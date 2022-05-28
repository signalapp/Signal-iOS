// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SignalCoreKit

public protocol JobExecutor {
    /// The maximum number of times the job can fail before it fails permanently
    ///
    /// **Note:** A value of `-1` means it will retry indefinitely
    static var maxFailureCount: Int { get }
    static var requiresThreadId: Bool { get }
    static var requiresInteractionId: Bool { get }

    /// This method contains the logic needed to complete a job
    ///
    /// **Note:** The code in this method should run synchronously and the various
    /// "result" blocks should not be called within a database closure
    ///
    /// - Parameters:
    ///   - job: The job which is being run
    ///   - success: The closure which is called when the job succeeds (with an
    ///   updated `job` and a flag indicating whether the job should forcibly stop running)
    ///   - failure: The closure which is called when the job fails (with an updated
    ///   `job`, an `Error` (if applicable) and a flag indicating whether it was a permanent
    ///   failure)
    ///   - deferred: The closure which is called when the job is deferred (with an
    ///   updated `job`)
    static func run(
        _ job: Job,
        success: @escaping (Job, Bool) -> (),
        failure: @escaping (Job, Error?, Bool) -> (),
        deferred: @escaping (Job) -> ()
    )
}

public final class JobRunner {
    private static let blockingQueue: Atomic<JobQueue?> = Atomic(
        JobQueue(
            type: .blocking,
            qos: .userInitiated,
            jobVariants: [],
            onQueueDrained: {
                // Once all blocking jobs have been completed we want to start running
                // the remaining job queues
                queues.wrappedValue.forEach { _, queue in queue.start() }
            }
        )
    )
    private static let queues: Atomic<[Job.Variant: JobQueue]> = {
        var jobVariants: Set<Job.Variant> = Job.Variant.allCases.asSet()
        
        let messageSendQueue: JobQueue = JobQueue(
            type: .messageSend,
            qos: .default,
            jobVariants: [
                jobVariants.remove(.attachmentUpload),
                jobVariants.remove(.messageSend),
                jobVariants.remove(.notifyPushServer)// TODO: Read receipts
            ].compactMap { $0 }
        )
        let messageReceiveQueue: JobQueue = JobQueue(
            type: .messageReceive,
            qos: .default,
            jobVariants: [
                jobVariants.remove(.messageReceive)
            ].compactMap { $0 }
        )
        let attachmentDownloadQueue: JobQueue = JobQueue(
            type: .attachmentDownload,
            qos: .utility,
            jobVariants: [
                jobVariants.remove(.attachmentDownload)
            ].compactMap { $0 }
        )
        let generalQueue: JobQueue = JobQueue(
            type: .general(number: 0),
            qos: .utility,
            jobVariants: Array(jobVariants)
        )
        
        return Atomic([
            messageSendQueue,
            messageReceiveQueue,
            attachmentDownloadQueue,
            generalQueue
        ].reduce(into: [:]) { prev, next in
            next.jobVariants.forEach { variant in
                prev[variant] = next
            }
        })
    }()
    
    internal static var executorMap: Atomic<[Job.Variant: JobExecutor.Type]> = Atomic([:])
    fileprivate static var perSessionJobsCompleted: Atomic<Set<Int64>> = Atomic([])
    
    // MARK: - Configuration
    
    public static func add(executor: JobExecutor.Type, for variant: Job.Variant) {
        executorMap.mutate { $0[variant] = executor }
    }
    
    // MARK: - Execution
    
    /// Add a job onto the queue, if the queue isn't currently running and 'canStartJob' is true then this will start
    /// the JobRunner
    ///
    /// **Note:** If the job has a `behaviour` of `runOnceNextLaunch` or the `nextRunTimestamp`
    /// is in the future then the job won't be started
    public static func add(_ db: Database, job: Job?, canStartJob: Bool = true) {
        // Store the job into the database (getting an id for it)
        guard let updatedJob: Job = try? job?.inserted(db) else {
            SNLog("[JobRunner] Unable to add \(job.map { "\($0.variant)" } ?? "unknown") job")
            return
        }
        
        queues.mutate { $0[updatedJob.variant]?.add(updatedJob, canStartJob: canStartJob) }
        
        // Start the job runner if needed
        db.afterNextTransactionCommit { _ in
            queues.wrappedValue[updatedJob.variant]?.start()
        }
    }
    
    /// Upsert a job onto the queue, if the queue isn't currently running and 'canStartJob' is true then this will start
    /// the JobRunner
    ///
    /// **Note:** If the job has a `behaviour` of `runOnceNextLaunch` or the `nextRunTimestamp`
    /// is in the future then the job won't be started
    public static func upsert(_ db: Database, job: Job?, canStartJob: Bool = true) {
        guard let job: Job = job else { return }    // Ignore null jobs
        
        queues.wrappedValue[job.variant]?.upsert(job, canStartJob: canStartJob)
    }
    
    @discardableResult public static func insert(_ db: Database, job: Job?, before otherJob: Job) -> Job? {
        switch job?.behaviour {
            case .recurringOnActive, .recurringOnLaunch, .runOnceNextLaunch:
                SNLog("[JobRunner] Attempted to insert \(job.map { "\($0.variant)" } ?? "unknown") job before the current one even though it's behaviour is \(job.map { "\($0.behaviour)" } ?? "unknown")")
                return nil
                
            default: break
        }
        
        // Store the job into the database (getting an id for it)
        guard let updatedJob: Job = try? job?.inserted(db) else {
            SNLog("[JobRunner] Unable to add \(job.map { "\($0.variant)" } ?? "unknown") job")
            return nil
        }
        
        queues.wrappedValue[updatedJob.variant]?.insert(updatedJob, before: otherJob)
        
        return updatedJob
    }
    
    public static func appDidFinishLaunching() {
        // Note: 'appDidBecomeActive' will run on first launch anyway so we can
        // leave those jobs out and can wait until then to start the JobRunner
        let jobsToRun: (blocking: [Job], nonBlocking: [Job]) = GRDBStorage.shared
            .read { db in
                let blockingJobs: [Job] = try Job
                    .filter(
                        [
                            Job.Behaviour.recurringOnLaunch,
                            Job.Behaviour.runOnceNextLaunch
                        ].contains(Job.Columns.behaviour)
                    )
                    .filter(Job.Columns.shouldBlockFirstRunEachSession == true)
                    .order(Job.Columns.id)
                    .fetchAll(db)
                let nonblockingJobs: [Job] = try Job
                    .filter(
                        [
                            Job.Behaviour.recurringOnLaunch,
                            Job.Behaviour.runOnceNextLaunch
                        ].contains(Job.Columns.behaviour)
                    )
                    .filter(Job.Columns.shouldBlockFirstRunEachSession == false)
                    .order(Job.Columns.id)
                    .fetchAll(db)
                
                return (blockingJobs, nonblockingJobs)
            }
            .defaulting(to: ([], []))
        
        guard !jobsToRun.blocking.isEmpty || !jobsToRun.nonBlocking.isEmpty else { return }
        
        // Add and start any blocking jobs
        blockingQueue.wrappedValue?.appDidFinishLaunching(with: jobsToRun.blocking, canStart: true)
        
        // Add any non-blocking jobs (we don't start these incase there are blocking "on active"
        // jobs as well)
        let jobsByVariant: [Job.Variant: [Job]] = jobsToRun.nonBlocking.grouped(by: \.variant)
        let jobQueues: [Job.Variant: JobQueue] = queues.wrappedValue
        
        jobsByVariant.forEach { variant, jobs in
            jobQueues[variant]?.appDidFinishLaunching(with: jobs, canStart: false)
        }
    }
    
    public static func appDidBecomeActive() {
        // Note: When becoming active we want to start all non-on-launch blocking jobs as
        // long as there are no other jobs already running
        let alreadyRunningOtherJobs: Bool = queues.wrappedValue
            .contains(where: { _, queue -> Bool in queue.isRunning.wrappedValue })
        let jobsToRun: (blocking: [Job], nonBlocking: [Job]) = GRDBStorage.shared
            .read { db in
                guard !alreadyRunningOtherJobs else {
                    let onActiveJobs: [Job] = try Job
                        .filter(Job.Columns.behaviour == Job.Behaviour.recurringOnActive)
                        .order(Job.Columns.id)
                        .fetchAll(db)
                    
                    return ([], onActiveJobs)
                }
                
                let blockingJobs: [Job] = try Job
                    .filter(
                        Job.Behaviour.allCases
                            .filter {
                                $0 != .recurringOnLaunch &&
                                $0 != .runOnceNextLaunch
                            }
                            .contains(Job.Columns.behaviour)
                    )
                    .filter(Job.Columns.shouldBlockFirstRunEachSession == true)
                    .order(Job.Columns.id)
                    .fetchAll(db)
                let nonBlockingJobs: [Job] = try Job
                    .filter(Job.Columns.behaviour == Job.Behaviour.recurringOnActive)
                    .filter(Job.Columns.shouldBlockFirstRunEachSession == false)
                    .order(Job.Columns.id)
                    .fetchAll(db)
                
                return (blockingJobs, nonBlockingJobs)
            }
            .defaulting(to: ([], []))
        
        guard !jobsToRun.blocking.isEmpty || !jobsToRun.nonBlocking.isEmpty else { return }
        
        // Add and start any blocking jobs
        blockingQueue.wrappedValue?.appDidFinishLaunching(with: jobsToRun.blocking, canStart: true)
        
        let blockingQueueIsRunning: Bool = (blockingQueue.wrappedValue?.isRunning.wrappedValue == true)
        let jobsByVariant: [Job.Variant: [Job]] = jobsToRun.nonBlocking.grouped(by: \.variant)
        let jobQueues: [Job.Variant: JobQueue] = queues.wrappedValue
        
        jobsByVariant.forEach { variant, jobs in
            jobQueues[variant]?.appDidBecomeActive(
                with: jobs,
                canStart: !blockingQueueIsRunning
            )
        }
    }
    
    public static func isCurrentlyRunning(_ job: Job?) -> Bool {
        guard let job: Job = job, let jobId: Int64 = job.id else { return false }
        
        return (queues.wrappedValue[job.variant]?.isCurrentlyRunning(jobId) == true)
    }
    
    // MARK: - Convenience

    fileprivate static func getRetryInterval(for job: Job) -> TimeInterval {
        // Arbitrary backoff factor...
        // try  1 delay: 0.5s
        // try  2 delay: 1s
        // ...
        // try  5 delay: 16s
        // ...
        // try 11 delay: 512s
        let maxBackoff: Double = 10 * 60 // 10 minutes
        return 0.25 * min(maxBackoff, pow(2, Double(job.failureCount)))
    }
}

// MARK: - JobQueue

private final class JobQueue {
    fileprivate enum QueueType: Hashable {
        case blocking
        case general(number: Int)
        case messageSend
        case messageReceive
        case attachmentDownload
        
        var name: String {
            switch self {
                case .blocking: return "Blocking"
                case .general(let number): return "General-\(number)"
                case .messageSend: return "MessageSend"
                case .messageReceive: return "MessageReceive"
                case .attachmentDownload: return "AttachmentDownload"
            }
        }
    }
    
    private class Trigger {
        private weak var queue: JobQueue?
        private var timer: Timer?
        
        static func create(queue: JobQueue, timestamp: TimeInterval) -> Trigger? {
            // Setup the trigger (wait at least 1 second before triggering)
            let trigger: Trigger = Trigger()
            trigger.queue = queue
            trigger.timer = Timer.scheduledTimer(
                timeInterval: max(1, (timestamp - Date().timeIntervalSince1970)),
                target: self,
                selector: #selector(start),
                userInfo: nil,
                repeats: false
            )
            
            return trigger
        }
        
        deinit { timer?.invalidate() }
        
        @objc func start() {
            queue?.start()
        }
    }
    
    private let type: QueueType
    private let qosClass: DispatchQoS
    private let queueKey: DispatchSpecificKey = DispatchSpecificKey<String>()
    private let queueContext: String
    
    /// The specific types of jobs this queue manages, if this is left empty it will handle all jobs not handled by other queues
    fileprivate let jobVariants: [Job.Variant]
    
    private let onQueueDrained: (() -> ())?
    
    private lazy var internalQueue: DispatchQueue = {
        let result: DispatchQueue = DispatchQueue(
            label: self.queueContext,
            qos: self.qosClass,
            attributes: [],
            autoreleaseFrequency: .inherit,
            target: nil
        )
        result.setSpecific(key: queueKey, value: queueContext)
        
        return result
    }()
    
    private var nextTrigger: Atomic<Trigger?> = Atomic(nil)
    fileprivate var isRunning: Atomic<Bool> = Atomic(false)
    private var queue: Atomic<[Job]> = Atomic([])
    private var jobsCurrentlyRunning: Atomic<Set<Int64>> = Atomic([])
    
    fileprivate var hasPendingJobs: Bool { !queue.wrappedValue.isEmpty }
    
    // MARK: - Initialization
    
    init(type: QueueType, qos: DispatchQoS, jobVariants: [Job.Variant], onQueueDrained: (() -> ())? = nil) {
        self.type = type
        self.queueContext = "JobQueue-\(type.name)"
        self.qosClass = qos
        self.jobVariants = jobVariants
        self.onQueueDrained = onQueueDrained
    }
    
    // MARK: - Execution
    
    fileprivate func add(_ job: Job, canStartJob: Bool = true) {
        // Check if the job should be added to the queue
        guard
            canStartJob,
            job.behaviour != .runOnceNextLaunch,
            job.nextRunTimestamp <= Date().timeIntervalSince1970
        else { return }
        
        queue.mutate { $0.append(job) }
    }
    
    /// Upsert a job onto the queue, if the queue isn't currently running and 'canStartJob' is true then this will start
    /// the JobRunner
    ///
    /// **Note:** If the job has a `behaviour` of `runOnceNextLaunch` or the `nextRunTimestamp`
    /// is in the future then the job won't be started
    fileprivate func upsert(_ job: Job, canStartJob: Bool = true) {
        guard let jobId: Int64 = job.id else {
            add(job, canStartJob: canStartJob)
            return
        }
        
        // Lock the queue while checking the index and inserting to ensure we don't run into
        // any multi-threading shenanigans
        //
        // Note: currently running jobs are removed from the queue so we don't need to check
        // the 'jobsCurrentlyRunning' set
        var didUpdateExistingJob: Bool = false
        
        queue.mutate { queue in
            if let jobIndex: Array<Job>.Index = queue.firstIndex(where: { $0.id == jobId }) {
                queue[jobIndex] = job
                didUpdateExistingJob = true
            }
        }
        
        // If we didn't update an existing job then we need to add it to the queue
        guard !didUpdateExistingJob else { return }
        
        add(job, canStartJob: canStartJob)
    }
    
    fileprivate func insert(_ job: Job, before otherJob: Job) {
        // Insert the job before the current job (re-adding the current job to
        // the start of the queue if it's not in there) - this will mean the new
        // job will run and then the otherJob will run (or run again) once it's
        // done
        queue.mutate {
            guard let otherJobIndex: Int = $0.firstIndex(of: otherJob) else {
                $0.insert(contentsOf: [job, otherJob], at: 0)
                return
            }
            
            $0.insert(job, at: otherJobIndex)
        }
    }
    
    fileprivate func appDidFinishLaunching(with jobs: [Job], canStart: Bool) {
        queue.mutate { $0.append(contentsOf: jobs) }
        
        // Start the job runner if needed
        if canStart && !isRunning.wrappedValue {
            start()
        }
    }
    
    fileprivate func appDidBecomeActive(with jobs: [Job], canStart: Bool) {
        queue.mutate { queue in
            // Avoid re-adding jobs to the queue that are already in it (this can
            // happen if the user sends the app to the background before the 'onActive'
            // jobs and then brings it back to the foreground)
            let jobsNotAlreadyInQueue: [Job] = jobs
                .filter { job in !queue.contains(where: { $0.id == job.id }) }
            
            queue.append(contentsOf: jobsNotAlreadyInQueue)
        }
        
        // Start the job runner if needed
        if canStart && !isRunning.wrappedValue {
            start()
        }
    }
    
    fileprivate func isCurrentlyRunning(_ jobId: Int64) -> Bool {
        return jobsCurrentlyRunning.wrappedValue.contains(jobId)
    }
    
    // MARK: - Job Running
    
    fileprivate func start() {
        // We only want the JobRunner to run in the main app
        guard CurrentAppContext().isMainApp else { return }
        guard !isRunning.wrappedValue else { return }
        
        // The JobRunner runs synchronously we need to ensure this doesn't start
        // on the main thread (if it is on the main thread then swap to a different thread)
        guard DispatchQueue.getSpecific(key: queueKey) == queueContext else {
            internalQueue.async { [weak self] in
                self?.start()
            }
            return
        }
        
        // Get any pending jobs
        let jobsToRun: [Job] = GRDBStorage.shared.read { db in
            try Job.filterPendingJobs(variants: jobVariants)
                .fetchAll(db)
        }
        .defaulting(to: [])
        
        // Determine the number of jobs to run
        var jobCount: Int = 0
        
        queue.mutate { queue in
            // Avoid re-adding jobs to the queue that are already in it
            let jobsNotAlreadyInQueue: [Job] = jobsToRun
                .filter { job in !queue.contains(where: { $0.id == job.id }) }
            
            // Add the jobs to the queue
            if !jobsNotAlreadyInQueue.isEmpty {
                queue.append(contentsOf: jobsToRun)
            }
            
            jobCount = queue.count
        }
        
        // If there are no pending jobs then schedule the JobRunner to start again
        // when the next scheduled job should start
        guard jobCount > 0 else {
            isRunning.mutate { $0 = false }
            scheduleNextSoonestJob()
            return
        }
        
        // Run the first job in the queue
        SNLog("[JobRunner] Starting \(queueContext) with (\(jobCount) job\(jobCount != 1 ? "s" : ""))")
        runNextJob()
    }
    
    private func runNextJob() {
        // Ensure this is running on the correct queue
        guard DispatchQueue.getSpecific(key: queueKey) == queueContext else {
            internalQueue.async { [weak self] in
                self?.runNextJob()
            }
            return
        }
        guard let (nextJob, numJobsRemaining): (Job, Int) = queue.mutate({ queue in queue.popFirst().map { ($0, queue.count) } }) else {
            isRunning.mutate { $0 = false }
            scheduleNextSoonestJob()
            return
        }
        guard let jobExecutor: JobExecutor.Type = JobRunner.executorMap.wrappedValue[nextJob.variant] else {
            SNLog("[JobRunner] \(queueContext) Unable to run \(nextJob.variant) job due to missing executor")
            handleJobFailed(nextJob, error: JobRunnerError.executorMissing, permanentFailure: true)
            return
        }
        guard !jobExecutor.requiresThreadId || nextJob.threadId != nil else {
            SNLog("[JobRunner] \(queueContext) Unable to run \(nextJob.variant) job due to missing required threadId")
            handleJobFailed(nextJob, error: JobRunnerError.requiredThreadIdMissing, permanentFailure: true)
            return
        }
        guard !jobExecutor.requiresInteractionId || nextJob.interactionId != nil else {
            SNLog("[JobRunner] \(queueContext) Unable to run \(nextJob.variant) job due to missing required interactionId")
            handleJobFailed(nextJob, error: JobRunnerError.requiredInteractionIdMissing, permanentFailure: true)
            return
        }
        
        // If the 'nextRunTimestamp' for the job is in the future then don't run it yet
        guard nextJob.nextRunTimestamp <= Date().timeIntervalSince1970 else {
            handleJobDeferred(nextJob)
            return
        }
        
        // Check if the next job has any dependencies
        let dependencyInfo: (expectedCount: Int, jobs: [Job]) = GRDBStorage.shared.read { db in
            let numExpectedDependencies: Int = try JobDependencies
                .filter(JobDependencies.Columns.jobId == nextJob.id)
                .fetchCount(db)
            let jobDependencies: [Job] = try nextJob.dependencies.fetchAll(db)
            
            return (numExpectedDependencies, jobDependencies)
        }
        .defaulting(to: (0, []))
        
        guard dependencyInfo.jobs.count == dependencyInfo.expectedCount else {
            SNLog("[JobRunner] \(queueContext) found job with missing dependencies, removing the job")
            handleJobFailed(nextJob, error: JobRunnerError.missingDependencies, permanentFailure: true)
            return
        }
        guard dependencyInfo.jobs.isEmpty else {
            SNLog("[JobRunner] \(queueContext) found job with \(dependencyInfo.jobs.count) dependencies, running those first")
            
            let jobDependencyIds: [Int64] = dependencyInfo.jobs
                .compactMap { $0.id }
            let jobIdsNotInQueue: Set<Int64> = jobDependencyIds
                .asSet()
                .subtracting(queue.wrappedValue.compactMap { $0.id })
            
            // If there are dependencies which aren't in the queue we should just append them
            guard !jobIdsNotInQueue.isEmpty else {
                queue.mutate { queue in
                    queue.append(
                        contentsOf: dependencyInfo.jobs
                            .filter { jobIdsNotInQueue.contains($0.id ?? -1) }
                    )
                    queue.append(nextJob)
                }
                handleJobDeferred(nextJob)
                return
            }
            
            // Otherwise re-add the current job after it's dependencies
            queue.mutate { queue in
                guard let lastDependencyIndex: Int = queue.lastIndex(where: { jobDependencyIds.contains($0.id ?? -1) }) else {
                    queue.append(nextJob)
                    return
                }
                
                queue.insert(nextJob, at: lastDependencyIndex + 1)
            }
            handleJobDeferred(nextJob)
            return
        }
        
        // Update the state to indicate it's running
        //
        // Note: We need to store 'numJobsRemaining' in it's own variable because
        // the 'SNLog' seems to dispatch to it's own queue which ends up getting
        // blocked by the JobRunner's queue becuase 'jobQueue' is Atomic
        nextTrigger.mutate { $0 = nil }
        isRunning.mutate { $0 = true }
        jobsCurrentlyRunning.mutate { $0 = $0.inserting(nextJob.id) }
        SNLog("[JobRunner] \(queueContext) started job (\(numJobsRemaining) remaining)")
        
        jobExecutor.run(
            nextJob,
            success: handleJobSucceeded,
            failure: handleJobFailed,
            deferred: handleJobDeferred
        )
    }
    
    private func scheduleNextSoonestJob() {
        let nextJobTimestamp: TimeInterval? = GRDBStorage.shared.read { db in
            try Job.filterPendingJobs(variants: jobVariants, excludeFutureJobs: false)
                .select(.nextRunTimestamp)
                .asRequest(of: TimeInterval.self)
                .fetchOne(db)
        }
        
        // If there are no remaining jobs the trigger the 'onQueueDrained' callback and stop
        guard let nextJobTimestamp: TimeInterval = nextJobTimestamp else {
            self.onQueueDrained?()
            return
        }
        
        // If the next job isn't scheduled in the future then just restart the JobRunner immediately
        let secondsUntilNextJob: TimeInterval = (nextJobTimestamp - Date().timeIntervalSince1970)
        
        guard secondsUntilNextJob > 0 else {
            SNLog("[JobRunner] Restarting \(queueContext) immediately for job scheduled \(Int(ceil(abs(secondsUntilNextJob)))) second\(Int(ceil(abs(secondsUntilNextJob))) == 1 ? "" : "s")) ago")
            
            internalQueue.async { [weak self] in
                self?.start()
            }
            return
        }
        
        // Setup a trigger
        SNLog("[JobRunner] Stopping \(queueContext) until next job in \(Int(ceil(abs(secondsUntilNextJob)))) second\(Int(ceil(abs(secondsUntilNextJob))) == 1 ? "" : "s"))")
        nextTrigger.mutate { $0 = Trigger.create(queue: self, timestamp: nextJobTimestamp) }
    }
    
    // MARK: - Handling Results

    /// This function is called when a job succeeds
    private func handleJobSucceeded(_ job: Job, shouldStop: Bool) {
        switch job.behaviour {
            case .runOnce, .runOnceNextLaunch:
                GRDBStorage.shared.write { db in
                    // First remove any JobDependencies requiring this job to be completed (if
                    // we don't then the dependant jobs will automatically be deleted)
                    _ = try JobDependencies
                        .filter(JobDependencies.Columns.dependantId == job.id)
                        .deleteAll(db)
                    
                    _ = try job.delete(db)
                }
                
            case .recurring where shouldStop == true:
                GRDBStorage.shared.write { db in
                    // First remove any JobDependencies requiring this job to be completed (if
                    // we don't then the dependant jobs will automatically be deleted)
                    _ = try JobDependencies
                        .filter(JobDependencies.Columns.dependantId == job.id)
                        .deleteAll(db)
                    
                    _ = try job.delete(db)
                }
                
            // For `recurring` jobs which have already run, they should automatically run again
            // but we want at least 1 second to pass before doing so - the job itself should
            // really update it's own 'nextRunTimestamp' (this is just a safety net)
            case .recurring where job.nextRunTimestamp <= Date().timeIntervalSince1970:
                GRDBStorage.shared.write { db in
                    _ = try job
                        .with(nextRunTimestamp: (Date().timeIntervalSince1970 + 1))
                        .saved(db)
                }
            
            default: break
        }
        
        // The job is removed from the queue before it runs so all we need to to is remove it
        // from the 'currentlyRunning' set and start the next one
        jobsCurrentlyRunning.mutate { $0 = $0.removing(job.id) }
        internalQueue.async { [weak self] in
            self?.runNextJob()
        }
    }

    /// This function is called when a job fails, if it's wasn't a permanent failure then the 'failureCount' for the job will be incremented and it'll
    /// be re-run after a retry interval has passed
    private func handleJobFailed(_ job: Job, error: Error?, permanentFailure: Bool) {
        guard GRDBStorage.shared.read({ db in try Job.exists(db, id: job.id ?? -1) }) == true else {
            SNLog("[JobRunner] \(queueContext) \(job.variant) job canceled")
            jobsCurrentlyRunning.mutate { $0 = $0.removing(job.id) }
            
            internalQueue.async { [weak self] in
                self?.runNextJob()
            }
            return
        }
        
        // If this is the blocking queue and a "blocking" job failed then rerun it immediately
        if self.type == .blocking && job.shouldBlockFirstRunEachSession {
            SNLog("[JobRunner] \(queueContext) \(job.variant) job failed; retrying immediately")
            queue.mutate { $0.insert(job, at: 0) }
            
            internalQueue.async { [weak self] in
                self?.runNextJob()
            }
            return
        }
        
        // Get the max failure count for the job (a value of '-1' means it will retry indefinitely)
        let maxFailureCount: Int = (JobRunner.executorMap.wrappedValue[job.variant]?.maxFailureCount ?? 0)
        let nextRunTimestamp: TimeInterval = (Date().timeIntervalSince1970 + JobRunner.getRetryInterval(for: job))
        
        GRDBStorage.shared.write { db in
            guard
                !permanentFailure &&
                maxFailureCount >= 0 &&
                job.failureCount + 1 < maxFailureCount
            else {
                SNLog("[JobRunner] \(queueContext) \(job.variant) failed permanently\(maxFailureCount >= 0 ? "; too many retries" : "")")
                
                // If the job permanently failed or we have performed all of our retry attempts
                // then delete the job (it'll probably never succeed)
                _ = try job.delete(db)
                return
            }
            
            SNLog("[JobRunner] \(queueContext) \(job.variant) job failed; scheduling retry (failure count is \(job.failureCount + 1))")
            
            _ = try job
                .with(
                    failureCount: (job.failureCount + 1),
                    nextRunTimestamp: nextRunTimestamp
                )
                .saved(db)
            
            // Update the failureCount and nextRunTimestamp on dependant jobs as well (update the
            // 'nextRunTimestamp' value to be 1ms later so when the queue gets regenerated it'll
            // come after the dependency)
            try job.dependantJobs
                .updateAll(
                    db,
                    Job.Columns.failureCount.set(to: job.failureCount),
                    Job.Columns.nextRunTimestamp.set(to: (nextRunTimestamp + (1 / 1000)))
                )
            
            let dependantJobIds: [Int64] = try job.dependantJobs
                .select(.id)
                .asRequest(of: Int64.self)
                .fetchAll(db)
            
            // Remove the dependant jobs from the queue (so we don't get stuck in a loop of trying
            // to run dependecies indefinitely
            if !dependantJobIds.isEmpty {
                queue.mutate { queue in
                    queue = queue.filter { !dependantJobIds.contains($0.id ?? -1) }
                }
            }
        }
        
        jobsCurrentlyRunning.mutate { $0 = $0.removing(job.id) }
        internalQueue.async { [weak self] in
            self?.runNextJob()
        }
    }
    
    /// This function is called when a job neither succeeds or fails (this should only occur if the job has specific logic that makes it dependant
    /// on other jobs, and it should automatically manage those dependencies)
    private func handleJobDeferred(_ job: Job) {
        jobsCurrentlyRunning.mutate { $0 = $0.removing(job.id) }
        internalQueue.async { [weak self] in
            self?.runNextJob()
        }
    }
}
