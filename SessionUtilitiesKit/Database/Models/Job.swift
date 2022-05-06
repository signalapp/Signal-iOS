// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

public struct Job: Codable, Equatable, Identifiable, FetchableRecord, MutablePersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "job" }
    internal static let dependencyForeignKey = ForeignKey([Columns.id], to: [JobDependencies.Columns.dependantId])
    internal static let dependencies = hasMany(Job.self, using: dependencyForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case failureCount
        case variant
        case behaviour
        case nextRunTimestamp
        case threadId
        case interactionId
        case details
    }
    
    public enum Variant: Int, Codable, DatabaseValueConvertible {
        /// This is a recurring job that handles the removal of disappearing messages and is triggered
        /// at the timestamp of the next disappearing message
        case disappearingMessages
        
        /// This is a recurring job that ensures the app retrieves a service node pool on active
        ///
        /// **Note:** This is a blocking job so it will run before any other jobs and prevent them from
        /// running until it's complete
        case getSnodePool
        
        /// This is a recurring job that checks if the user needs to update their profile picture on launch, and if so
        /// attempt to download the latest
        case updateProfilePicture
        
        /// This is a recurring job that ensures the app fetches the default open group rooms on launch
        case retrieveDefaultOpenGroupRooms
        
        /// This is a recurring job that runs on launch and flags any messages marked as 'sending' to
        /// be in their 'failed' state
        ///
        /// **Note:** This is a blocking job so it will run before any other jobs and prevent them from
        /// running until it's complete
        case failedMessages = 1000
        
        /// This is a recurring job that runs on launch and flags any attachments marked as 'uploading' to
        /// be in their 'failed' state
        ///
        /// **Note:** This is a blocking job so it will run before any other jobs and prevent them from
        /// running until it's complete
        case failedAttachmentDownloads
        
        /// This is a recurring job that runs on return from background and registeres and uploads the
        /// latest device push tokens
        case syncPushTokens = 2000
        
        /// This is a job that runs once whenever a message is sent to notify the push notification server
        /// about the message
        case notifyPushServer
        
        /// This is a job that runs once at most every 3 seconds per thread whenever a message is marked as read
        /// (if read receipts are enabled) to notify other members in a conversation that their message was read
        case sendReadReceipts
        
        /// This is a job that runs once whenever a message is received to attempt to decode and properly
        /// process the message
        case messageReceive = 3000
        
        /// This is a job that runs once whenever a message is sent to attempt to encode and properly
        /// send the message
        case messageSend
        
        /// This is a job that runs once whenever an attachment is uploaded to attempt to encode and properly
        /// upload the attachment
        case attachmentUpload
        
        /// This is a job that runs once whenever an attachment is downloaded to attempt to decode and properly
        /// download the attachment
        case attachmentDownload
    }
    
    public enum Behaviour: Int, Codable, DatabaseValueConvertible {
        /// This job will run once and then be removed from the jobs table
        case runOnce
        
        /// This job will run once the next time the app launches and then be removed from the jobs table
        case runOnceNextLaunch
        
        /// This job will run and then will be updated with a new `nextRunTimestamp` (at least 1 second in
        /// the future) in order to be run again
        case recurring
        
        /// This job will run once each launch and may run again during the same session if `nextRunTimestamp`
        /// gets set
        case recurringOnLaunch
        
        /// This job will run once each launch and may run again during the same session if `nextRunTimestamp`
        /// gets set, it also must complete before any other jobs can run
        case recurringOnLaunchBlocking
        
        /// This job will run once each launch and may run again during the same session if `nextRunTimestamp`
        /// gets set, it also must complete before any other jobs can run
        case recurringOnLaunchBlockingOncePerSession
        
        /// This job will run once each whenever the app becomes active (launch and return from background) and
        /// may run again during the same session if `nextRunTimestamp` gets set
        case recurringOnActive
        
        /// This job will run once each whenever the app becomes active (launch and return from background) and
        /// may run again during the same session if `nextRunTimestamp` gets set, it also must complete before
        /// any other jobs can run
        case recurringOnActiveBlocking
    }
    
    /// The `id` value is auto incremented by the database, if the `Job` hasn't been inserted into
    /// the database yet this value will be `nil`
    public var id: Int64? = nil
    
    /// A counter for the number of times this job has failed
    public let failureCount: UInt
    
    /// The type of job
    public let variant: Variant
    
    /// The type of job
    public let behaviour: Behaviour
    
    /// Seconds since epoch to indicate the next datetime that this job should run
    public let nextRunTimestamp: TimeInterval
    
    /// The id of the thread this job is associated with, if the associated thread is deleted this job will
    /// also be deleted
    ///
    /// **Note:** This will only be populated for Jobs associated to threads
    public let threadId: String?
    
    /// The id of the interaction this job is associated with, if the associated interaction is deleted this
    /// job will also be deleted
    ///
    /// **Note:** This will only be populated for Jobs associated to interactions
    public let interactionId: Int64?
    
    /// JSON encoded data required for the job
    public let details: Data?
    
    /// The other jobs which this job is dependant on
    ///
    /// **Note:** When completing a job the dependencies **MUST** be cleared before the job is
    /// deleted or it will automatically delete any dependant jobs
    public var dependencies: QueryInterfaceRequest<Job> {
        request(for: Job.dependencies)
    }
    
    // MARK: - Initialization
    
    fileprivate init(
        id: Int64?,
        failureCount: UInt,
        variant: Variant,
        behaviour: Behaviour,
        nextRunTimestamp: TimeInterval,
        threadId: String?,
        interactionId: Int64?,
        details: Data?
    ) {
        self.id = id
        self.failureCount = failureCount
        self.variant = variant
        self.behaviour = behaviour
        self.nextRunTimestamp = nextRunTimestamp
        self.threadId = threadId
        self.interactionId = interactionId
        self.details = details
    }
    
    public init(
        failureCount: UInt = 0,
        variant: Variant,
        behaviour: Behaviour = .runOnce,
        nextRunTimestamp: TimeInterval = 0,
        threadId: String? = nil,
        interactionId: Int64? = nil
    ) {
        self.failureCount = failureCount
        self.variant = variant
        self.behaviour = behaviour
        self.nextRunTimestamp = nextRunTimestamp
        self.threadId = threadId
        self.interactionId = interactionId
        self.details = nil
    }
    
    public init?<T: Encodable>(
        failureCount: UInt = 0,
        variant: Variant,
        behaviour: Behaviour = .runOnce,
        nextRunTimestamp: TimeInterval = 0,
        threadId: String? = nil,
        interactionId: Int64? = nil,
        details: T?
    ) {
        precondition(T.self != Job.self, "[Job] Fatal error trying to create a Job with a Job as it's details")
        
        guard
            let details: T = details,
            let detailsData: Data = try? JSONEncoder().encode(details)
        else { return nil }
        
        self.failureCount = failureCount
        self.variant = variant
        self.behaviour = behaviour
        self.nextRunTimestamp = nextRunTimestamp
        self.threadId = threadId
        self.interactionId = interactionId
        self.details = detailsData
    }
    
    // MARK: - Custom Database Interaction
    
    public mutating func didInsert(with rowID: Int64, for column: String?) {
        self.id = rowID
    }
    
    public func delete(_ db: Database) throws -> Bool {
        // Delete any dependencies
        try dependencies
            .deleteAll(db)
        
        return try performDelete(db)
    }
}

// MARK: - GRDB Interactions

extension Job {
    internal static func filterPendingJobs(excludeFutureJobs: Bool = true) -> QueryInterfaceRequest<Job> {
        let query: QueryInterfaceRequest<Job> = Job
            .filter(
                // TODO: Should this include other behaviours? (what happens if one of the other types fails???? Just leave it until the next launch/active???) Set a 'failureCount' and use that to determine if it should run? (reset on success)
                // Retrieve all 'runOnce' and 'recurring' jobs
                [
                    Job.Behaviour.runOnce,
                    Job.Behaviour.recurring
                ].contains(Job.Columns.behaviour) || (
                    // Retrieve any 'recurringOnLaunch' and 'recurringOnActive' jobs that have a
                    // 'nextRunTimestamp'
                    [
                        Job.Behaviour.recurringOnLaunch,
                        Job.Behaviour.recurringOnLaunchBlocking,
                        Job.Behaviour.recurringOnActive,
                        Job.Behaviour.recurringOnActiveBlocking
                    ].contains(Job.Columns.behaviour) &&
                    Job.Columns.nextRunTimestamp > 0
                )
            )
            .order(Job.Columns.nextRunTimestamp)
            .order(Job.Columns.id)
        
        guard excludeFutureJobs else {
            return query
        }
        
        return query
            .filter(Job.Columns.nextRunTimestamp <= Date().timeIntervalSince1970)
    }
}

// MARK: - Convenience

public extension Job {
    var isBlocking: Bool {
        switch self.behaviour {
            case .recurringOnLaunchBlocking,
                .recurringOnLaunchBlockingOncePerSession,
                .recurringOnActiveBlocking:
                return true
                
            default: return false
        }
    }
    
    func with(
        failureCount: UInt = 0,
        nextRunTimestamp: TimeInterval
    ) -> Job {
        return Job(
            id: id,
            failureCount: failureCount,
            variant: variant,
            behaviour: behaviour,
            nextRunTimestamp: nextRunTimestamp,
            threadId: threadId,
            interactionId: interactionId,
            details: details
        )
    }
    
    func with<T: Encodable>(details: T) -> Job? {
        guard let detailsData: Data = try? JSONEncoder().encode(details) else { return nil }
        
        return Job(
            id: id,
            failureCount: failureCount,
            variant: variant,
            behaviour: behaviour,
            nextRunTimestamp: nextRunTimestamp,
            threadId: threadId,
            interactionId: interactionId,
            details: detailsData
        )
    }
}
