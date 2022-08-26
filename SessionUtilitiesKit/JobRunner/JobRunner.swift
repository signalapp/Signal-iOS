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
        queue: DispatchQueue,
        success: @escaping (Job, Bool) -> (),
        failure: @escaping (Job, Error?, Bool) -> (),
        deferred: @escaping (Job) -> ()
    )
}

public final class JobRunner {
    public enum JobResult {
        case succeeded
        case failed
        case deferred
        case notFound
    }
    
    private static let blockingQueue: Atomic<JobQueue?> = Atomic(
        JobQueue(
            type: .blocking,
            qos: .default,
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
            executionType: .concurrent, // Allow as many jobs to run at once as supported by the device
            qos: .default,
            jobVariants: [
                jobVariants.remove(.attachmentUpload),
                jobVariants.remove(.messageSend),
                jobVariants.remove(.notifyPushServer),
                jobVariants.remove(.sendReadReceipts)
            ].compactMap { $0 }
        )
        let messageReceiveQueue: JobQueue = JobQueue(
            type: .messageReceive,
            // Explicitly serial as executing concurrently means message receives getting processed at
            // different speeds which can result in:
            // • Small batches of messages appearing in the UI before larger batches
            // • Closed group messages encrypted with updated keys could start parsing before it's key
            //   update message has been processed (ie. guaranteed to fail)
            executionType: .serial,
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
    private static var hasCompletedInitialBecomeActive: Atomic<Bool> = Atomic(false)
    private static var shutdownBackgroundTask: Atomic<OWSBackgroundTask?> = Atomic(nil)
    
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
        
        // Don't start the queue if the job can't be started
        guard canStartJob else { return }
        
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
        
        // Start the job runner if needed
        db.afterNextTransactionCommit { _ in
            queues.wrappedValue[job.variant]?.start()
        }
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
        
        // Start the job runner if needed
        db.afterNextTransactionCommit { _ in
            queues.wrappedValue[updatedJob.variant]?.start()
        }
        
        return updatedJob
    }
    
    public static func appDidFinishLaunching() {
        // Note: 'appDidBecomeActive' will run on first launch anyway so we can
        // leave those jobs out and can wait until then to start the JobRunner
        let jobsToRun: (blocking: [Job], nonBlocking: [Job]) = Storage.shared
            .read { db in
                let blockingJobs: [Job] = try Job
                    .filter(
                        [
                            Job.Behaviour.recurringOnLaunch,
                            Job.Behaviour.runOnceNextLaunch
                        ].contains(Job.Columns.behaviour)
                    )
                    .filter(Job.Columns.shouldBlock == true)
                    .order(Job.Columns.id)
                    .fetchAll(db)
                let nonblockingJobs: [Job] = try Job
                    .filter(
                        [
                            Job.Behaviour.recurringOnLaunch,
                            Job.Behaviour.runOnceNextLaunch
                        ].contains(Job.Columns.behaviour)
                    )
                    .filter(Job.Columns.shouldBlock == false)
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
        // If we have a running "sutdownBackgroundTask" then we want to cancel it as otherwise it
        // can result in the database being suspended and us being unable to interact with it at all
        shutdownBackgroundTask.mutate {
            $0?.cancel()
            $0 = nil
        }
        
        // Retrieve any jobs which should run when becoming active
        let hasCompletedInitialBecomeActive: Bool = JobRunner.hasCompletedInitialBecomeActive.wrappedValue
        let jobsToRun: [Job] = Storage.shared
            .read { db in
                return try Job
                    .filter(Job.Columns.behaviour == Job.Behaviour.recurringOnActive)
                    .order(Job.Columns.id)
                    .fetchAll(db)
            }
            .defaulting(to: [])
            .filter { hasCompletedInitialBecomeActive || !$0.shouldSkipLaunchBecomeActive }
        
        // Store the current queue state locally to avoid multiple atomic retrievals
        let jobQueues: [Job.Variant: JobQueue] = queues.wrappedValue
        let blockingQueueIsRunning: Bool = (blockingQueue.wrappedValue?.isRunning.wrappedValue == true)
        
        guard !jobsToRun.isEmpty else {
            if !blockingQueueIsRunning {
                jobQueues.forEach { _, queue in queue.start() }
            }
            return
        }
        
        // Add and start any non-blocking jobs (if there are no blocking jobs)
        let jobsByVariant: [Job.Variant: [Job]] = jobsToRun.grouped(by: \.variant)
        
        jobQueues.forEach { variant, queue in
            queue.appDidBecomeActive(
                with: (jobsByVariant[variant] ?? []),
                canStart: !blockingQueueIsRunning
            )
        }
        JobRunner.hasCompletedInitialBecomeActive.mutate { $0 = true }
    }
    
    /// Calling this will clear the JobRunner queues and stop it from running new jobs, any currently executing jobs will continue to run
    /// though (this means if we suspend the database it's likely that any currently running jobs will fail to complete and fail to record their
    /// failure - they _should_ be picked up again the next time the app is launched)
    public static func stopAndClearPendingJobs(
        exceptForVariant: Job.Variant? = nil,
        onComplete: (() -> ())? = nil
    ) {
        // Stop all queues except for the one containing the `exceptForVariant`
        queues.wrappedValue
            .values
            .filter { queue -> Bool in
                guard let exceptForVariant: Job.Variant = exceptForVariant else { return true }
                
                return !queue.jobVariants.contains(exceptForVariant)
            }
            .forEach { $0.stopAndClearPendingJobs() }
        
        // Ensure the queue is actually running (if not the trigger the callback immediately)
        guard
            let exceptForVariant: Job.Variant = exceptForVariant,
            let queue: JobQueue = queues.wrappedValue[exceptForVariant],
            queue.isRunning.wrappedValue == true
        else {
            onComplete?()
            return
        }
        
        let oldQueueDrained: (() -> ())? = queue.onQueueDrained
        
        // Create a backgroundTask to give the queue the chance to properly be drained
        shutdownBackgroundTask.mutate {
            $0 = OWSBackgroundTask(labelStr: #function) { [weak queue] state in
                // If the background task didn't succeed then trigger the onComplete (and hope we have
                // enough time to complete it's logic)
                guard state != .cancelled else {
                    queue?.onQueueDrained = oldQueueDrained
                    return
                }
                guard state != .success else { return }
                
                onComplete?()
                queue?.onQueueDrained = oldQueueDrained
                queue?.stopAndClearPendingJobs()
            }
        }
        
        // Add a callback to be triggered once the queue is drained
        queue.onQueueDrained = { [weak queue] in
            oldQueueDrained?()
            queue?.onQueueDrained = oldQueueDrained
            onComplete?()
            
            shutdownBackgroundTask.mutate { $0 = nil }
        }
    }
    
    public static func isCurrentlyRunning(_ job: Job?) -> Bool {
        guard let job: Job = job, let jobId: Int64 = job.id else { return false }
        
        return (queues.wrappedValue[job.variant]?.isCurrentlyRunning(jobId) == true)
    }
    
    public static func defailsForCurrentlyRunningJobs(of variant: Job.Variant) -> [Int64: Data?] {
        return (queues.wrappedValue[variant]?.detailsForAllCurrentlyRunningJobs())
            .defaulting(to: [:])
    }
    
    public static func afterCurrentlyRunningJob(_ job: Job?, callback: @escaping (JobResult) -> ()) {
        guard let job: Job = job, let jobId: Int64 = job.id, let queue: JobQueue = queues.wrappedValue[job.variant] else {
            callback(.notFound)
            return
        }
        
        queue.afterCurrentlyRunningJob(jobId, callback: callback)
    }
    
    public static func hasPendingOrRunningJob<T: Encodable>(with variant: Job.Variant, details: T) -> Bool {
        guard let targetQueue: JobQueue = queues.wrappedValue[variant] else { return false }
        guard let detailsData: Data = try? JSONEncoder().encode(details) else { return false }
        
        return targetQueue.hasPendingOrRunningJob(with: detailsData)
    }
    
    public static func removePendingJob(_ job: Job?) {
        guard let job: Job = job, let jobId: Int64 = job.id else { return }
        
        queues.wrappedValue[job.variant]?.removePendingJob(jobId)
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
    
    fileprivate enum ExecutionType {
        /// A serial queue will execute one job at a time until the queue is empty, then will load any new/deferred
        /// jobs and run those one at a time
        case serial
        
        /// A concurrent queue will execute as many jobs as the device supports at once until the queue is empty,
        /// then will load any new/deferred jobs and try to start them all
        case concurrent
    }
    
    private class Trigger {
        private var timer: Timer?
        fileprivate var fireTimestamp: TimeInterval = 0
        
        static func create(queue: JobQueue, timestamp: TimeInterval) -> Trigger? {
            /// Setup the trigger (wait at least 1 second before triggering)
            ///
            /// **Note:** We use the `Timer.scheduledTimerOnMainThread` method because running a timer
            /// on our random queue threads results in the timer never firing, the `start` method will redirect itself to
            /// the correct thread
            let trigger: Trigger = Trigger()
            trigger.fireTimestamp = max(1, (timestamp - Date().timeIntervalSince1970))
            trigger.timer = Timer.scheduledTimerOnMainThread(
                withTimeInterval: trigger.fireTimestamp,
                repeats: false,
                block: { [weak queue] _ in
                    queue?.start()
                }
            )
            
            return trigger
        }
        
        func invalidate() {
            // Need to do this to prevent a strong reference cycle
            timer?.invalidate()
            timer = nil
        }
    }
    
    private static let deferralLoopThreshold: Int = 3
    
    private let type: QueueType
    private let executionType: ExecutionType
    private let qosClass: DispatchQoS
    private let queueKey: DispatchSpecificKey = DispatchSpecificKey<String>()
    private let queueContext: String
    
    /// The specific types of jobs this queue manages, if this is left empty it will handle all jobs not handled by other queues
    fileprivate let jobVariants: [Job.Variant]
    
    fileprivate var onQueueDrained: (() -> ())?
    
    private lazy var internalQueue: DispatchQueue = {
        let result: DispatchQueue = DispatchQueue(
            label: self.queueContext,
            qos: self.qosClass,
            attributes: (self.executionType == .concurrent ? [.concurrent] : []),
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
    private var jobCallbacks: Atomic<[Int64: [(JobRunner.JobResult) -> ()]]> = Atomic([:])
    private var detailsForCurrentlyRunningJobs: Atomic<[Int64: Data?]> = Atomic([:])
    private var deferLoopTracker: Atomic<[Int64: (count: Int, times: [TimeInterval])]> = Atomic([:])
    
    fileprivate var hasPendingJobs: Bool { !queue.wrappedValue.isEmpty }
    
    // MARK: - Initialization
    
    init(
        type: QueueType,
        executionType: ExecutionType = .serial,
        qos: DispatchQoS,
        jobVariants: [Job.Variant],
        onQueueDrained: (() -> ())? = nil
    ) {
        self.type = type
        self.executionType = executionType
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
    
    fileprivate func detailsForAllCurrentlyRunningJobs() -> [Int64: Data?] {
        return detailsForCurrentlyRunningJobs.wrappedValue
    }
    
    fileprivate func afterCurrentlyRunningJob(_ jobId: Int64, callback: @escaping (JobRunner.JobResult) -> ()) {
        guard isCurrentlyRunning(jobId) else {
            callback(.notFound)
            return
        }
        
        jobCallbacks.mutate { jobCallbacks in
            jobCallbacks[jobId] = (jobCallbacks[jobId] ?? []).appending(callback)
        }
    }
    
    fileprivate func hasPendingOrRunningJob(with detailsData: Data?) -> Bool {
        let pendingJobs: [Job] = queue.wrappedValue
        
        return pendingJobs.contains { job in job.details == detailsData }
    }
    
    fileprivate func removePendingJob(_ jobId: Int64) {
        queue.mutate { queue in
            queue = queue.filter { $0.id != jobId }
        }
    }
    
    // MARK: - Job Running
    
    fileprivate func start(force: Bool = false) {
        // We only want the JobRunner to run in the main app
        guard CurrentAppContext().isMainApp else { return }
        guard force || !isRunning.wrappedValue else { return }
        
        // The JobRunner runs synchronously we need to ensure this doesn't start
        // on the main thread (if it is on the main thread then swap to a different thread)
        guard DispatchQueue.getSpecific(key: queueKey) == queueContext else {
            internalQueue.async { [weak self] in
                self?.start()
            }
            return
        }
        
        // Flag the JobRunner as running (to prevent something else from trying to start it
        // and messing with the execution behaviour)
        var wasAlreadyRunning: Bool = false
        isRunning.mutate { isRunning in
            wasAlreadyRunning = isRunning
            isRunning = true
        }
        
        // Get any pending jobs
        let jobIdsAlreadyRunning: Set<Int64> = jobsCurrentlyRunning.wrappedValue
        let jobsAlreadyInQueue: Set<Int64> = queue.wrappedValue.compactMap { $0.id }.asSet()
        let jobsToRun: [Job] = Storage.shared.read { db in
            try Job.filterPendingJobs(variants: jobVariants)
                .filter(!jobIdsAlreadyRunning.contains(Job.Columns.id)) // Exclude jobs already running
                .filter(!jobsAlreadyInQueue.contains(Job.Columns.id))   // Exclude jobs already in the queue
                .fetchAll(db)
        }
        .defaulting(to: [])
        
        // Determine the number of jobs to run
        var jobCount: Int = 0
        
        queue.mutate { queue in
            queue.append(contentsOf: jobsToRun)
            jobCount = queue.count
        }
        
        // If there are no pending jobs and nothing in the queue then schedule the JobRunner
        // to start again when the next scheduled job should start
        guard jobCount > 0 else {
            if jobIdsAlreadyRunning.isEmpty {
                isRunning.mutate { $0 = false }
                scheduleNextSoonestJob()
            }
            return
        }
        
        // Run the first job in the queue
        if !wasAlreadyRunning {
            SNLog("[JobRunner] Starting \(queueContext) with (\(jobCount) job\(jobCount != 1 ? "s" : ""))")
        }
        runNextJob()
    }
    
    fileprivate func stopAndClearPendingJobs() {
        isRunning.mutate { $0 = false }
        queue.mutate { $0 = [] }
        deferLoopTracker.mutate { $0 = [:] }
    }
    
    private func runNextJob() {
        // Ensure the queue is running (if we've stopped the queue then we shouldn't start the next job)
        guard isRunning.wrappedValue else { return }
        
        // Ensure this is running on the correct queue
        guard DispatchQueue.getSpecific(key: queueKey) == queueContext else {
            internalQueue.async { [weak self] in
                self?.runNextJob()
            }
            return
        }
        guard let (nextJob, numJobsRemaining): (Job, Int) = queue.mutate({ queue in queue.popFirst().map { ($0, queue.count) } }) else {
            // If it's a serial queue, or there are no more jobs running then update the 'isRunning' flag
            if executionType != .concurrent || jobsCurrentlyRunning.wrappedValue.isEmpty {
                isRunning.mutate { $0 = false }
            }
            
            // Always attempt to schedule the next soonest job (otherwise if enough jobs get started in rapid
            // succession then pending/failed jobs in the database may never get re-started in a concurrent queue)
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
        let dependencyInfo: (expectedCount: Int, jobs: [Job]) = Storage.shared.read { db in
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
            
            // Otherwise re-add the current job after it's dependencies (if this isn't a concurrent
            // queue - don't want to immediately try to start the job again only for it to end up back
            // in here)
            if executionType != .concurrent {
                queue.mutate { queue in
                    guard let lastDependencyIndex: Int = queue.lastIndex(where: { jobDependencyIds.contains($0.id ?? -1) }) else {
                        queue.append(nextJob)
                        return
                    }
                    
                    queue.insert(nextJob, at: lastDependencyIndex + 1)
                }
            }
            
            handleJobDeferred(nextJob)
            return
        }
        
        // Update the state to indicate the particular job is running
        //
        // Note: We need to store 'numJobsRemaining' in it's own variable because
        // the 'SNLog' seems to dispatch to it's own queue which ends up getting
        // blocked by the JobRunner's queue becuase 'jobQueue' is Atomic
        var numJobsRunning: Int = 0
        nextTrigger.mutate { trigger in
            trigger?.invalidate()   // Need to invalidate to prevent a memory leak
            trigger = nil
        }
        jobsCurrentlyRunning.mutate { jobsCurrentlyRunning in
            jobsCurrentlyRunning = jobsCurrentlyRunning.inserting(nextJob.id)
            numJobsRunning = jobsCurrentlyRunning.count
        }
        detailsForCurrentlyRunningJobs.mutate { $0 = $0.setting(nextJob.id, nextJob.details) }
        SNLog("[JobRunner] \(queueContext) started job (\(executionType == .concurrent ? "\(numJobsRunning) currently running, " : "")\(numJobsRemaining) remaining)")
        
        jobExecutor.run(
            nextJob,
            queue: internalQueue,
            success: handleJobSucceeded,
            failure: handleJobFailed,
            deferred: handleJobDeferred
        )
        
        // If this queue executes concurrently and there are still jobs remaining then immediately attempt
        // to start the next job
        if executionType == .concurrent && numJobsRemaining > 0 {
            internalQueue.async { [weak self] in
                self?.runNextJob()
            }
        }
    }
    
    private func scheduleNextSoonestJob() {
        let jobIdsAlreadyRunning: Set<Int64> = jobsCurrentlyRunning.wrappedValue
        let nextJobTimestamp: TimeInterval? = Storage.shared.read { db in
            try Job.filterPendingJobs(variants: jobVariants, excludeFutureJobs: false)
                .select(.nextRunTimestamp)
                .filter(!jobIdsAlreadyRunning.contains(Job.Columns.id)) // Exclude jobs already running
                .asRequest(of: TimeInterval.self)
                .fetchOne(db)
        }
        
        // If there are no remaining jobs the trigger the 'onQueueDrained' callback and stop
        guard let nextJobTimestamp: TimeInterval = nextJobTimestamp else {
            if executionType != .concurrent || jobsCurrentlyRunning.wrappedValue.isEmpty {
                self.onQueueDrained?()
            }
            return
        }
        
        // If the next job isn't scheduled in the future then just restart the JobRunner immediately
        let secondsUntilNextJob: TimeInterval = (nextJobTimestamp - Date().timeIntervalSince1970)
        
        guard secondsUntilNextJob > 0 else {
            // Only log that the queue is getting restarted if this queue had actually been about to stop
            if executionType != .concurrent || jobsCurrentlyRunning.wrappedValue.isEmpty {
                let timingString: String = (nextJobTimestamp == 0 ?
                    "that should be in the queue" :
                    "scheduled \(Int(ceil(abs(secondsUntilNextJob)))) second\(Int(ceil(abs(secondsUntilNextJob))) == 1 ? "" : "s") ago"
                )
                SNLog("[JobRunner] Restarting \(queueContext) immediately for job \(timingString)")
            }
            
            // Trigger the 'start' function to load in any pending jobs that aren't already in the
            // queue (for concurrent queues we want to force them to load in pending jobs and add
            // them to the queue regardless of whether the queue is already running)
            internalQueue.async { [weak self] in
                self?.start(force: (self?.executionType == .concurrent))
            }
            return
        }
        
        // Only schedule a trigger if this queue has actually completed
        guard executionType != .concurrent || jobsCurrentlyRunning.wrappedValue.isEmpty else { return }
        
        // Setup a trigger
        SNLog("[JobRunner] Stopping \(queueContext) until next job in \(Int(ceil(abs(secondsUntilNextJob)))) second\(Int(ceil(abs(secondsUntilNextJob))) == 1 ? "" : "s")")
        nextTrigger.mutate { trigger in
            trigger?.invalidate()   // Need to invalidate the old trigger to prevent a memory leak
            trigger = Trigger.create(queue: self, timestamp: nextJobTimestamp)
        }
    }
    
    // MARK: - Handling Results

    /// This function is called when a job succeeds
    private func handleJobSucceeded(_ job: Job, shouldStop: Bool) {
        switch job.behaviour {
            case .runOnce, .runOnceNextLaunch:
                Storage.shared.write { db in
                    // First remove any JobDependencies requiring this job to be completed (if
                    // we don't then the dependant jobs will automatically be deleted)
                    _ = try JobDependencies
                        .filter(JobDependencies.Columns.dependantId == job.id)
                        .deleteAll(db)
                    
                    _ = try job.delete(db)
                }
                
            case .recurring where shouldStop == true:
                Storage.shared.write { db in
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
                Storage.shared.write { db in
                    _ = try job
                        .with(nextRunTimestamp: (Date().timeIntervalSince1970 + 1))
                        .saved(db)
                }
                
            // For `recurringOnLaunch/Active` jobs which have already run, we want to clear their
            // `failureCount` and `nextRunTimestamp` to prevent them from endlessly running over
            // and over and reset their retry backoff in case they fail next time
            case .recurringOnLaunch, .recurringOnActive:
                if
                    let jobId: Int64 = job.id,
                    job.failureCount != 0 &&
                    job.nextRunTimestamp > TimeInterval.leastNonzeroMagnitude
                {
                    Storage.shared.write { db in
                        _ = try Job
                            .filter(id: jobId)
                            .updateAll(
                                db,
                                Job.Columns.failureCount.set(to: 0),
                                Job.Columns.nextRunTimestamp.set(to: 0)
                            )
                    }
                }
            
            default: break
        }
        
        // For concurrent queues retrieve any 'dependant' jobs and re-add them here (if they have other
        // dependencies they will be removed again when they try to execute)
        if executionType == .concurrent {
            let dependantJobs: [Job] = Storage.shared
                .read { db in try job.dependantJobs.fetchAll(db) }
                .defaulting(to: [])
            let dependantJobIds: [Int64] = dependantJobs
                .compactMap { $0.id }
            let jobIdsNotInQueue: Set<Int64> = dependantJobIds
                .asSet()
                .subtracting(queue.wrappedValue.compactMap { $0.id })
            
            // If there are dependant jobs which aren't in the queue we should just append them
            if !jobIdsNotInQueue.isEmpty {
                queue.mutate { queue in
                    queue.append(
                        contentsOf: dependantJobs
                            .filter { jobIdsNotInQueue.contains($0.id ?? -1) }
                    )
                }
            }
        }
        
        // Perform job cleanup and start the next job
        performCleanUp(for: job, result: .succeeded)
        internalQueue.async { [weak self] in
            self?.runNextJob()
        }
    }

    /// This function is called when a job fails, if it's wasn't a permanent failure then the 'failureCount' for the job will be incremented and it'll
    /// be re-run after a retry interval has passed
    private func handleJobFailed(_ job: Job, error: Error?, permanentFailure: Bool) {
        guard Storage.shared.read({ db in try Job.exists(db, id: job.id ?? -1) }) == true else {
            SNLog("[JobRunner] \(queueContext) \(job.variant) job canceled")
            performCleanUp(for: job, result: .failed)
            
            internalQueue.async { [weak self] in
                self?.runNextJob()
            }
            return
        }
        
        // If this is the blocking queue and a "blocking" job failed then rerun it
        // immediately (in this case we don't trigger any job callbacks because the
        // job isn't actually done, it's going to try again immediately)
        if self.type == .blocking && job.shouldBlock {
            SNLog("[JobRunner] \(queueContext) \(job.variant) job failed; retrying immediately")
            
            // If it was a possible deferral loop then we don't actually want to
            // retry the job (even if it's a blocking one, this gives a small chance
            // that the app could continue to function)
            let wasPossibleDeferralLoop: Bool = {
                if let error = error, case JobRunnerError.possibleDeferralLoop = error { return true }
                
                return false
            }()
            performCleanUp(
                for: job,
                result: .failed,
                shouldTriggerCallbacks: wasPossibleDeferralLoop
            )
            
            // Only add it back to the queue if it wasn't a deferral loop
            if !wasPossibleDeferralLoop {
                queue.mutate { $0.insert(job, at: 0) }
            }
            
            internalQueue.async { [weak self] in
                self?.runNextJob()
            }
            return
        }
        
        // Get the max failure count for the job (a value of '-1' means it will retry indefinitely)
        let maxFailureCount: Int = (JobRunner.executorMap.wrappedValue[job.variant]?.maxFailureCount ?? 0)
        let nextRunTimestamp: TimeInterval = (Date().timeIntervalSince1970 + JobRunner.getRetryInterval(for: job))
        
        Storage.shared.write { db in
            guard
                !permanentFailure && (
                    maxFailureCount < 0 ||
                    job.failureCount + 1 < maxFailureCount
                )
            else {
                SNLog("[JobRunner] \(queueContext) \(job.variant) failed permanently\(maxFailureCount >= 0 ? "; too many retries" : "")")
                
                let dependantJobIds: [Int64] = try job.dependantJobs
                    .select(.id)
                    .asRequest(of: Int64.self)
                    .fetchAll(db)

                // If the job permanently failed or we have performed all of our retry attempts
                // then delete the job and all of it's dependant jobs (it'll probably never succeed)
                _ = try job.dependantJobs
                    .deleteAll(db)

                _ = try job.delete(db)
                
                // Remove the dependant jobs from the queue (so we don't try to run a deleted job)
                if !dependantJobIds.isEmpty {
                    queue.mutate { queue in
                        queue = queue.filter { !dependantJobIds.contains($0.id ?? -1) }
                    }
                }
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
            // to run dependecies indefinitely)
            if !dependantJobIds.isEmpty {
                queue.mutate { queue in
                    queue = queue.filter { !dependantJobIds.contains($0.id ?? -1) }
                }
            }
        }
        
        performCleanUp(for: job, result: .failed)
        internalQueue.async { [weak self] in
            self?.runNextJob()
        }
    }
    
    /// This function is called when a job neither succeeds or fails (this should only occur if the job has specific logic that makes it dependant
    /// on other jobs, and it should automatically manage those dependencies)
    private func handleJobDeferred(_ job: Job) {
        var stuckInDeferLoop: Bool = false
        
        deferLoopTracker.mutate {
            guard let lastRecord: (count: Int, times: [TimeInterval]) = $0[job.id] else {
                $0 = $0.setting(
                    job.id,
                    (1, [Date().timeIntervalSince1970])
                )
                return
            }
            
            let timeNow: TimeInterval = Date().timeIntervalSince1970
            stuckInDeferLoop = (
                lastRecord.count >= JobQueue.deferralLoopThreshold &&
                (timeNow - lastRecord.times[0]) < CGFloat(lastRecord.count)
            )
            
            $0 = $0.setting(
                job.id,
                (
                    lastRecord.count + 1,
                    // Only store the last 'deferralLoopThreshold' times to ensure we aren't running faster
                    // than one loop per second
                    lastRecord.times.suffix(JobQueue.deferralLoopThreshold - 1) + [timeNow]
                )
            )
        }
        
        // It's possible (by introducing bugs) to create a loop where a Job tries to run and immediately
        // defers itself but then attempts to run again (resulting in an infinite loop); this won't block
        // the app since it's on a background thread but can result in 100% of a CPU being used (and a
        // battery drain)
        //
        // This code will maintain an in-memory store for any jobs which are deferred too quickly (ie.
        // more than 'deferralLoopThreshold' times within 'deferralLoopThreshold' seconds)
        guard !stuckInDeferLoop else {
            deferLoopTracker.mutate { $0 = $0.removingValue(forKey: job.id) }
            handleJobFailed(job, error: JobRunnerError.possibleDeferralLoop, permanentFailure: false)
            return
        }
        
        performCleanUp(for: job, result: .deferred)
        internalQueue.async { [weak self] in
            self?.runNextJob()
        }
    }
    
    private func performCleanUp(for job: Job, result: JobRunner.JobResult, shouldTriggerCallbacks: Bool = true) {
        // The job is removed from the queue before it runs so all we need to to is remove it
        // from the 'currentlyRunning' set
        jobsCurrentlyRunning.mutate { $0 = $0.removing(job.id) }
        detailsForCurrentlyRunningJobs.mutate { $0 = $0.removingValue(forKey: job.id) }
        
        guard shouldTriggerCallbacks else { return }
        
        // Run any job callbacks now that it's done
        var jobCallbacksToRun: [(JobRunner.JobResult) -> ()] = []
        jobCallbacks.mutate { jobCallbacks in
            jobCallbacksToRun = (jobCallbacks[job.id] ?? [])
            jobCallbacks = jobCallbacks.removingValue(forKey: job.id)
        }
        
        DispatchQueue.global(qos: .default).async {
            jobCallbacksToRun.forEach { $0(result) }
        }
    }
}
