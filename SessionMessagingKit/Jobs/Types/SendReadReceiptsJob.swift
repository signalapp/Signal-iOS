// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import PromiseKit
import SessionUtilitiesKit

public enum SendReadReceiptsJob: JobExecutor {
    public static let maxFailureCount: Int = -1
    public static let requiresThreadId: Bool = false
    public static let requiresInteractionId: Bool = false
    private static let minRunFrequency: TimeInterval = 3
    
    public static func run(
        _ job: Job,
        success: @escaping (Job, Bool) -> (),
        failure: @escaping (Job, Error?, Bool) -> (),
        deferred: @escaping (Job) -> ()
    ) {
        guard
            let threadId: String = job.threadId,
            let detailsData: Data = job.details,
            let details: Details = try? JSONDecoder().decode(Details.self, from: detailsData)
        else {
            failure(job, JobRunnerError.missingRequiredDetails, false)
            return
        }
        
        // If there are no timestampMs values then the job can just complete (next time
        // something is marked as read we want to try and run immediately so don't scuedule
        // another run in this case)
        guard !details.timestampMsValues.isEmpty else {
            success(job, true)
            return
        }
        
        GRDBStorage.shared
            .write { db in
                try MessageSender.send(
                    db,
                    message: ReadReceipt(
                        timestamps: details.timestampMsValues.map { UInt64($0) }
                    ),
                    to: details.destination,
                    interactionId: nil
                )
            }
            .done {
                // When we complete the 'SendReadReceiptsJob' we want to immediately schedule
                // another one for the same thread but with a 'nextRunTimestamp' set to the
                // 'minRunFrequency' value to throttle the read receipt requests
                GRDBStorage.shared.write { db in
                    _ = try createOrUpdateIfNeeded(db, threadId: threadId, interactionIds: [])?
                        .with(nextRunTimestamp: (Date().timeIntervalSince1970 + minRunFrequency))
                        .saved(db)
                }
                
                success(job, false)
            }
            .catch { error in failure(job, error, false) }
            .retainUntilComplete()
    }
}


// MARK: - SendReadReceiptsJob.Details

extension SendReadReceiptsJob {
    public struct Details: Codable {
        public let destination: Message.Destination
        public let timestampMsValues: Set<Int64>
    }
}

// MARK: - Convenience

public extension SendReadReceiptsJob {
    @discardableResult static func createOrUpdateIfNeeded(_ db: Database, threadId: String, interactionIds: [Int64]) -> Job? {
        guard db[.areReadReceiptsEnabled] == true else { return nil }
        
        // Retrieve the timestampMs values for the specified interactions
        let maybeTimestampMsValues: [Int64]? = try? Int64.fetchAll(
            db,
            Interaction
                .select(Interaction.Columns.timestampMs)
                .filter(interactionIds.contains(Interaction.Columns.id))
                // Only `standardIncoming` incoming interactions should have read receipts sent
                .filter(Interaction.Columns.variant == Interaction.Variant.standardIncoming)
                .joining(
                    // Don't send read receipts in group threads
                    required: Interaction.thread
                        .filter(SessionThread.Columns.variant != SessionThread.Variant.closedGroup)
                        .filter(SessionThread.Columns.variant != SessionThread.Variant.openGroup)
                )
                .distinct()
        )
        
        // If there are no timestamp values then do nothing
        guard let timestampMsValues: [Int64] = maybeTimestampMsValues else { return nil }
        
        // Try to get an existing job (if there is one that's not running)
        if
            let existingJob: Job = try? Job
                .filter(Job.Columns.variant == Job.Variant.sendReadReceipts)
                .filter(Job.Columns.threadId == threadId)
                .fetchOne(db),
            !JobRunner.isCurrentlyRunning(existingJob),
            let existingDetailsData: Data = existingJob.details,
            let existingDetails: Details = try? JSONDecoder().decode(Details.self, from: existingDetailsData)
        {
            let maybeUpdatedJob: Job? = existingJob
                .with(
                    details: Details(
                        destination: existingDetails.destination,
                        timestampMsValues: existingDetails.timestampMsValues
                            .union(timestampMsValues)
                    )
                )
            
            guard let updatedJob: Job = maybeUpdatedJob else { return nil }
            
            return try? updatedJob
                .saved(db)
        }
        
        // Otherwise create a new job
        return Job(
            variant: .sendReadReceipts,
            behaviour: .recurring,
            threadId: threadId,
            details: Details(
                destination: .contact(publicKey: threadId),
                timestampMsValues: timestampMsValues.asSet()
            )
        )
    }
}
