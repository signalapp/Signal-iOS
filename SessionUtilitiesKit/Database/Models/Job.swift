// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

public struct Job: Codable, Equatable, Identifiable, FetchableRecord, MutablePersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "job" }
    internal static let dependencyForeignKey = ForeignKey([Columns.id], to: [JobDependencies.Columns.dependantId])
    public static let dependantJobDependency = hasMany(
        JobDependencies.self,
        using: JobDependencies.jobForeignKey
    )
    public static let dependancyJobDependency = hasMany(
        JobDependencies.self,
        using: JobDependencies.dependantForeignKey
    )
    internal static let jobsThisJobDependsOn = hasMany(
        Job.self,
        through: dependantJobDependency,
        using: JobDependencies.dependant
    )
    internal static let jobsThatDependOnThisJob = hasMany(
        Job.self,
        through: dependancyJobDependency,
        using: JobDependencies.job
    )
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case failureCount
        case variant
        case behaviour
        case shouldBlock
        case shouldSkipLaunchBecomeActive
        case nextRunTimestamp
        case threadId
        case interactionId
        case details
    }
    
    public enum Variant: Int, Codable, DatabaseValueConvertible, CaseIterable {
        /// This is a recurring job that handles the removal of disappearing messages and is triggered
        /// at the timestamp of the next disappearing message
        case disappearingMessages
        
        /// This is a recurring job that ensures the app retrieves a service node pool on become active
        ///
        /// **Note:** This is a blocking job so it will run before any other jobs and prevent them from
        /// running until it's complete
        case getSnodePool
        
        /// This is a recurring job that checks if the user needs to update their profile picture on launch, and if so
        /// attempt to download the latest
        case updateProfilePicture
        
        /// This is a recurring job that ensures the app fetches the default open group rooms on launch
        case retrieveDefaultOpenGroupRooms
        
        /// This is a recurring job that removes expired and orphaned data, it runs on launch and can also be triggered
        /// as 'runOnce' to avoid waiting until the next launch to clear data
        case garbageCollection
        
        /// This is a recurring job that runs on launch and flags any messages marked as 'sending' to
        /// be in their 'failed' state
        ///
        /// **Note:** This is a blocking job so it will run before any other jobs and prevent them from
        /// running until it's complete
        case failedMessageSends = 1000
        
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
    
    public enum Behaviour: Int, Codable, DatabaseValueConvertible, CaseIterable {
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
        
        /// This job will run once each whenever the app becomes active (launch and return from background) and
        /// may run again during the same session if `nextRunTimestamp` gets set
        case recurringOnActive
    }
    
    /// The `id` value is auto incremented by the database, if the `Job` hasn't been inserted into
    /// the database yet this value will be `nil`
    public var id: Int64? = nil
    
    /// A counter for the number of times this job has failed
    public let failureCount: UInt
    
    /// The type of job
    public let variant: Variant
    
    /// How the job should behave
    public let behaviour: Behaviour
    
    /// When the app starts this flag controls whether the job should prevent other jobs from starting until after it completes
    ///
    /// **Note:** This flag is only supported for jobs with an `OnLaunch` behaviour because there is no way to guarantee
    /// jobs with any other behaviours will be added to the JobRunner before all the `OnLaunch` blocking jobs are completed
    /// resulting in the JobRunner no longer blocking
    public let shouldBlock: Bool
    
    /// When the app starts it also triggers any `OnActive` jobs, this flag controls whether the job should skip this initial `OnActive`
    /// trigger (generally used for the same job registered with both `OnLaunch` and `OnActive` behaviours)
    public let shouldSkipLaunchBecomeActive: Bool
    
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
        request(for: Job.jobsThisJobDependsOn)
    }
    
    /// The other jobs which depend on this job
    ///
    /// **Note:** When completing a job the dependencies **MUST** be cleared before the job is
    /// deleted or it will automatically delete any dependant jobs
    public var dependantJobs: QueryInterfaceRequest<Job> {
        request(for: Job.jobsThatDependOnThisJob)
    }
    
    // MARK: - Initialization
    
    fileprivate init(
        id: Int64?,
        failureCount: UInt,
        variant: Variant,
        behaviour: Behaviour,
        shouldBlock: Bool,
        shouldSkipLaunchBecomeActive: Bool,
        nextRunTimestamp: TimeInterval,
        threadId: String?,
        interactionId: Int64?,
        details: Data?
    ) {
        Job.ensureValidBehaviour(
            behaviour: behaviour,
            shouldBlock: shouldBlock,
            shouldSkipLaunchBecomeActive: shouldSkipLaunchBecomeActive
        )
        
        self.id = id
        self.failureCount = failureCount
        self.variant = variant
        self.behaviour = behaviour
        self.shouldBlock = shouldBlock
        self.shouldSkipLaunchBecomeActive = shouldSkipLaunchBecomeActive
        self.nextRunTimestamp = nextRunTimestamp
        self.threadId = threadId
        self.interactionId = interactionId
        self.details = details
    }
    
    public init(
        failureCount: UInt = 0,
        variant: Variant,
        behaviour: Behaviour = .runOnce,
        shouldBlock: Bool = false,
        shouldSkipLaunchBecomeActive: Bool = false,
        nextRunTimestamp: TimeInterval = 0,
        threadId: String? = nil,
        interactionId: Int64? = nil
    ) {
        Job.ensureValidBehaviour(
            behaviour: behaviour,
            shouldBlock: shouldBlock,
            shouldSkipLaunchBecomeActive: shouldSkipLaunchBecomeActive
        )
        
        self.failureCount = failureCount
        self.variant = variant
        self.behaviour = behaviour
        self.shouldBlock = shouldBlock
        self.shouldSkipLaunchBecomeActive = shouldSkipLaunchBecomeActive
        self.nextRunTimestamp = nextRunTimestamp
        self.threadId = threadId
        self.interactionId = interactionId
        self.details = nil
    }
    
    public init?<T: Encodable>(
        failureCount: UInt = 0,
        variant: Variant,
        behaviour: Behaviour = .runOnce,
        shouldBlock: Bool = false,
        shouldSkipLaunchBecomeActive: Bool = false,
        nextRunTimestamp: TimeInterval = 0,
        threadId: String? = nil,
        interactionId: Int64? = nil,
        details: T?
    ) {
        precondition(T.self != Job.self, "[Job] Fatal error trying to create a Job with a Job as it's details")
        Job.ensureValidBehaviour(
            behaviour: behaviour,
            shouldBlock: shouldBlock,
            shouldSkipLaunchBecomeActive: shouldSkipLaunchBecomeActive
        )
        
        guard
            let details: T = details,
            let detailsData: Data = try? JSONEncoder().encode(details)
        else { return nil }
        
        self.failureCount = failureCount
        self.variant = variant
        self.behaviour = behaviour
        self.shouldBlock = shouldBlock
        self.shouldSkipLaunchBecomeActive = shouldSkipLaunchBecomeActive
        self.nextRunTimestamp = nextRunTimestamp
        self.threadId = threadId
        self.interactionId = interactionId
        self.details = detailsData
    }
    
    fileprivate static func ensureValidBehaviour(
        behaviour: Behaviour,
        shouldBlock: Bool,
        shouldSkipLaunchBecomeActive: Bool
    ) {
        // Blocking jobs can only run on launch as we can't guarantee that any other behaviours will get added
        // to the JobRunner before any prior blocking jobs have completed (resulting in them being non-blocking)
        precondition(
            !shouldBlock || behaviour == .recurringOnLaunch || behaviour == .runOnceNextLaunch,
            "[Job] Fatal error trying to create a blocking job which doesn't run on launch"
        )
        precondition(
            !shouldSkipLaunchBecomeActive || behaviour == .recurringOnActive,
            "[Job] Fatal error trying to create a job which skips on 'OnActive' triggered during launch with doesn't run on active"
        )
    }
    
    // MARK: - Custom Database Interaction
    
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        self.id = inserted.rowID
    }
}

// MARK: - GRDB Interactions

extension Job {
    internal static func filterPendingJobs(
        variants: [Variant],
        excludeFutureJobs: Bool = true,
        includeJobsWithDependencies: Bool = false
    ) -> QueryInterfaceRequest<Job> {
        var query: QueryInterfaceRequest<Job> = Job
            .filter(
                // Retrieve all 'runOnce' and 'recurring' jobs
                [
                    Job.Behaviour.runOnce,
                    Job.Behaviour.recurring
                ].contains(Job.Columns.behaviour) || (
                    // Retrieve any 'recurringOnLaunch' and 'recurringOnActive' jobs that have a
                    // 'nextRunTimestamp'
                    [
                        Job.Behaviour.recurringOnLaunch,
                        Job.Behaviour.recurringOnActive
                    ].contains(Job.Columns.behaviour) &&
                    Job.Columns.nextRunTimestamp > 0
                )
            )
            .filter(variants.contains(Job.Columns.variant))
            .order(Job.Columns.nextRunTimestamp)
            .order(Job.Columns.id)
        
        if excludeFutureJobs {
            query = query.filter(Job.Columns.nextRunTimestamp <= Date().timeIntervalSince1970)
        }
        
        if !includeJobsWithDependencies {
            query = query.having(Job.jobsThisJobDependsOn.isEmpty)
        }
        
        return query
    }
}

// MARK: - Convenience

public extension Job {
    func with(
        failureCount: UInt = 0,
        nextRunTimestamp: TimeInterval
    ) -> Job {
        return Job(
            id: self.id,
            failureCount: failureCount,
            variant: self.variant,
            behaviour: self.behaviour,
            shouldBlock: self.shouldBlock,
            shouldSkipLaunchBecomeActive: self.shouldSkipLaunchBecomeActive,
            nextRunTimestamp: nextRunTimestamp,
            threadId: self.threadId,
            interactionId: self.interactionId,
            details: self.details
        )
    }
    
    func with<T: Encodable>(details: T) -> Job? {
        guard let detailsData: Data = try? JSONEncoder().encode(details) else { return nil }
        
        return Job(
            id: self.id,
            failureCount: self.failureCount,
            variant: self.variant,
            behaviour: self.behaviour,
            shouldBlock: self.shouldBlock,
            shouldSkipLaunchBecomeActive: self.shouldSkipLaunchBecomeActive,
            nextRunTimestamp: self.nextRunTimestamp,
            threadId: self.threadId,
            interactionId: self.interactionId,
            details: detailsData
        )
    }
}
