// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public enum DisappearingMessagesJob: JobExecutor {
    public static let maxFailureCount: UInt = 0
    public static let requiresThreadId: Bool = false
    
    public static func run(
        _ job: Job,
        success: @escaping (Job, Bool) -> (),
        failure: @escaping (Job, Error?, Bool) -> (),
        deferred: @escaping (Job) -> ()
    ) {
        // The 'backgroundTask' gets captured and cleared within the 'completion' block
        let timestampNowMs: TimeInterval = (Date().timeIntervalSince1970 * 1000)
        var backgroundTask: OWSBackgroundTask? = OWSBackgroundTask(label: #function)
        
        let updatedJob: Job? = GRDBStorage.shared.write { db in
            _ = try Interaction
                .filter(Interaction.Columns.expiresStartedAtMs != nil)
                .filter(sql: "(\(Interaction.Columns.expiresStartedAtMs) + (\(Interaction.Columns.expiresInSeconds) * 1000) <= \(timestampNowMs)")
                .deleteAll(db)
            
            // Update the next run timestamp for the DisappearingMessagesJob
            return updateNextRunIfNeeded(db)
        }
        
        success(updatedJob ?? job, false)
        
        // The 'if' is only there to prevent the "variable never read" warning from showing
        if backgroundTask != nil { backgroundTask = nil }
    }
}

// MARK: - Convenience

public extension DisappearingMessagesJob {
    @discardableResult static func updateNextRunIfNeeded(_ db: Database) -> Job? {
        // Don't schedule run when inactive or not in main app
        var isMainAppActive = false
        if let sharedUserDefaults = UserDefaults(suiteName: "group.com.loki-project.loki-messenger") {
            isMainAppActive = sharedUserDefaults[.isMainAppActive]
        }
        guard isMainAppActive else { return nil }
        
        // If there is another expiring message then update the job to run 1 second after it's meant to expire
        let nextExpirationTimestampMs: Double? = try? Double
            .fetchOne(
                db,
                Interaction
                    .select(sql: "(\(Interaction.Columns.expiresStartedAtMs) + (\(Interaction.Columns.expiresInSeconds) * 1000)")
                    .order(sql: "(\(Interaction.Columns.expiresStartedAtMs) + (\(Interaction.Columns.expiresInSeconds) * 1000) asc")
            )
        
        guard let nextExpirationTimestampMs: Double = nextExpirationTimestampMs else { return nil }
        
        return try? Job
            .filter(Job.Columns.variant == Job.Variant.disappearingMessages)
            .fetchOne(db)?
            .with(nextRunTimestamp: ((nextExpirationTimestampMs / 1000) + 1))
            .saved(db)
    }
    
    @discardableResult static func updateNextRunIfNeeded(_ db: Database, interactionIds: [Int64], startedAtMs: Double) -> Bool {
        // Update the expiring messages expiresStartedAtMs value
        let changeCount: Int? = try? Interaction
            .filter(interactionIds.contains(Interaction.Columns.id))
            .filter(Interaction.Columns.expiresInSeconds != nil && Interaction.Columns.expiresStartedAtMs == nil)
            .updateAll(db, Interaction.Columns.expiresStartedAtMs.set(to: startedAtMs))
        
        // If there were no changes then none of the provided `interactionIds` are expiring messages
        guard (changeCount ?? 0) > 0 else { return false }
        
        return (updateNextRunIfNeeded(db) != nil)
    }
    
    @discardableResult static func updateNextRunIfNeeded(_ db: Database, interaction: Interaction, startedAtMs: Double) -> Bool {
        guard interaction.isExpiringMessage else { return false }
        
        // Don't clobber if multiple actions simultaneously triggered expiration
        guard interaction.expiresStartedAtMs == nil || (interaction.expiresStartedAtMs ?? 0) > startedAtMs else {
            return false
        }
        
        do {
            guard let interactionId: Int64 = try? (interaction.id ?? interaction.inserted(db).id) else {
                throw GRDBStorageError.objectNotFound
            }
            
            return updateNextRunIfNeeded(db, interactionIds: [interactionId], startedAtMs: startedAtMs)
        }
        catch {
            SNLog("Failed to update the expiring messages timer on an interaction")
            return false
        }
    }
}
