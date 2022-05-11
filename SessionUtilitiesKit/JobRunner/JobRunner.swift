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
    private class Trigger {
        private var timer: Timer?
        
        static func create(timestamp: TimeInterval) -> Trigger? {
            // Setup the trigger (wait at least 1 second before triggering)
            let trigger: Trigger = Trigger()
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
            JobRunner.start()
        }
    }
    
    // TODO: Could this be a bottleneck? (single serial queue to process all these jobs? Group by thread?).
    // TODO: Multi-thread support.
    private static let queueKey: DispatchSpecificKey = DispatchSpecificKey<String>()
    private static let queueContext: String = "JobRunner"
    private static let internalQueue: DispatchQueue = {
        let result: DispatchQueue = DispatchQueue(label: queueContext)
        result.setSpecific(key: queueKey, value: queueContext)
        
        return result
    }()
    
    internal static var executorMap: Atomic<[Job.Variant: JobExecutor.Type]> = Atomic([:])
    private static var nextTrigger: Atomic<Trigger?> = Atomic(nil)
    private static var isRunning: Atomic<Bool> = Atomic(false)
    private static var jobQueue: Atomic<[Job]> = Atomic([])
    
    private static var jobsCurrentlyRunning: Atomic<Set<Int64>> = Atomic([])
    private static var perSessionJobsCompleted: Atomic<Set<Int64>> = Atomic([])
    
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
        
        // Check if the job should be added to the queue
        guard
            canStartJob,
            updatedJob.behaviour != .runOnceNextLaunch,
            updatedJob.nextRunTimestamp <= Date().timeIntervalSince1970
        else { return }
        
        jobQueue.mutate { $0.append(updatedJob) }
        
        // Start the job runner if needed
        db.afterNextTransactionCommit { _ in
            if !isRunning.wrappedValue {
                start()
            }
        }
    }
    
    /// Upsert a job onto the queue, if the queue isn't currently running and 'canStartJob' is true then this will start
    /// the JobRunner
    ///
    /// **Note:** If the job has a `behaviour` of `runOnceNextLaunch` or the `nextRunTimestamp`
    /// is in the future then the job won't be started
    public static func upsert(_ db: Database, job: Job?, canStartJob: Bool = true) {
        guard let job: Job = job else { return }    // Ignore null jobs
        guard let jobId: Int64 = job.id else {
            add(db, job: job, canStartJob: canStartJob)
            return
        }
        
        // Lock the queue while checking the index and inserting to ensure we don't run into
        // any multi-threading shenanigans
        //
        // Note: currently running jobs are removed from the queue so we don't need to check
        // the 'jobsCurrentlyRunning' set
        var didUpdateExistingJob: Bool = false
        
        jobQueue.mutate { queue in
            if let jobIndex: Array<Job>.Index = queue.firstIndex(where: { $0.id == jobId }) {
                queue[jobIndex] = job
                didUpdateExistingJob = true
            }
        }
        
        // If we didn't update an existing job then we need to add it to the queue
        guard !didUpdateExistingJob else { return }
        
        add(db, job: job, canStartJob: canStartJob)
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
        
        // Insert the job before the current job (re-adding the current job to
        // the start of the queue if it's not in there) - this will mean the new
        // job will run and then the otherJob will run (or run again) once it's
        // done
        jobQueue.mutate {
            guard let otherJobIndex: Int = $0.firstIndex(of: otherJob) else {
                $0.insert(contentsOf: [updatedJob, otherJob], at: 0)
                return
            }
            
            $0.insert(updatedJob, at: otherJobIndex)
        }
        
        return updatedJob
    }
    
    public static func appDidFinishLaunching() {
        // Note: 'appDidBecomeActive' will run on first launch anyway so we can
        // leave those jobs out and can wait until then to start the JobRunner
        let maybeJobsToRun: [Job]? = GRDBStorage.shared.read { db in
            try Job
                .filter(
                    [
                        Job.Behaviour.recurringOnLaunch,
                        Job.Behaviour.recurringOnLaunchBlocking,
                        Job.Behaviour.recurringOnLaunchBlockingOncePerSession,
                        Job.Behaviour.runOnceNextLaunch
                    ].contains(Job.Columns.behaviour)
                )
                .order(Job.Columns.id)
                .fetchAll(db)
        }
        
        guard let jobsToRun: [Job] = maybeJobsToRun else { return }
        
        jobQueue.mutate {
            // Insert any blocking jobs after any existing blocking jobs then add
            // the remaining jobs to the end of the queue
            let lastBlockingIndex = $0.lastIndex(where: { $0.isBlocking })
                .defaulting(to: $0.startIndex.advanced(by: -1))
                .advanced(by: 1)
            
            $0.insert(
                contentsOf: jobsToRun.filter { $0.isBlocking },
                at: lastBlockingIndex
            )
            $0.append(
                contentsOf: jobsToRun.filter { !$0.isBlocking }
            )
        }
    }
    
    public static func appDidBecomeActive() {
        let maybeJobsToRun: [Job]? = GRDBStorage.shared.read { db in
            try Job
                .filter(
                    [
                        Job.Behaviour.recurringOnActive,
                        Job.Behaviour.recurringOnActiveBlocking
                    ].contains(Job.Columns.behaviour)
                )
                .order(Job.Columns.id)
                .fetchAll(db)
        }
        
        guard let jobsToRun: [Job] = maybeJobsToRun else { return }
        
        jobQueue.mutate {
            // Insert any blocking jobs after any existing blocking jobs then add
            // the remaining jobs to the end of the queue
            let lastBlockingIndex = $0.lastIndex(where: { $0.isBlocking })
                .defaulting(to: $0.startIndex.advanced(by: -1))
                .advanced(by: 1)
            
            $0.insert(
                contentsOf: jobsToRun.filter { $0.isBlocking },
                at: lastBlockingIndex
            )
            $0.append(
                contentsOf: jobsToRun.filter { !$0.isBlocking }
            )
        }
        
        // Start the job runner if needed
        if !isRunning.wrappedValue {
            start()
        }
    }
    
    public static func isCurrentlyRunning(_ job: Job?) -> Bool {
        guard let job: Job = job, let jobId: Int64 = job.id else { return false }
        
        return jobsCurrentlyRunning.wrappedValue.contains(jobId)
    }
    
    // MARK: - Job Running
    
    public static func start() {
        // We only want the JobRunner to run in the main app
        guard CurrentAppContext().isMainApp else { return }
        guard !isRunning.wrappedValue else { return }
        
        // The JobRunner runs synchronously we need to ensure this doesn't start
        // on the main thread (if it is on the main thread then swap to a different thread)
        guard DispatchQueue.getSpecific(key: queueKey) == queueContext else {
            internalQueue.async {
                start()
            }// TODO: Want to have multiple threads for this (attachment download should be separate - do we even use attachment upload anymore???)
            return
        }
        
        // Get any pending jobs
        let maybeJobsToRun: [Job]? = GRDBStorage.shared.read { db in
            try Job// TODO: Test this
                .filterPendingJobs()
                .fetchAll(db)
        }
        
        // Determine the number of jobs to run
        var jobCount: Int = 0
        
        jobQueue.mutate { queue in
            // Add the jobs to the queue
            if let jobsToRun: [Job] = maybeJobsToRun {
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
        SNLog("[JobRunner] Starting with (\(jobCount) job\(jobCount != 1 ? "s" : ""))")
        runNextJob()
    }
    
    private static func runNextJob() {
        // Ensure this is running on the correct queue
        guard DispatchQueue.getSpecific(key: queueKey) == queueContext else {
            internalQueue.async {
                runNextJob()
            }
            return
        }
        guard let (nextJob, numJobsRemaining): (Job, Int) = jobQueue.mutate({ queue in queue.popFirst().map { ($0, queue.count) } }) else {
            isRunning.mutate { $0 = false }
            scheduleNextSoonestJob()
            return
        }
        guard let jobExecutor: JobExecutor.Type = executorMap.wrappedValue[nextJob.variant] else {
            SNLog("[JobRunner] Unable to run \(nextJob.variant) job due to missing executor")
            handleJobFailed(nextJob, error: JobRunnerError.executorMissing, permanentFailure: true)
            return
        }
        guard !jobExecutor.requiresThreadId || nextJob.threadId != nil else {
            SNLog("[JobRunner] Unable to run \(nextJob.variant) job due to missing required threadId")
            handleJobFailed(nextJob, error: JobRunnerError.requiredThreadIdMissing, permanentFailure: true)
            return
        }
        guard !jobExecutor.requiresInteractionId || nextJob.interactionId != nil else {
            SNLog("[JobRunner] Unable to run \(nextJob.variant) job due to missing required interactionId")
            handleJobFailed(nextJob, error: JobRunnerError.requiredInteractionIdMissing, permanentFailure: true)
            return
        }
        
        // If the 'nextRunTimestamp' for the job is in the future then don't run it yet
        guard nextJob.nextRunTimestamp <= Date().timeIntervalSince1970 else {
            handleJobDeferred(nextJob)
            return
        }
        
        // Check if the next job has any dependencies
        let jobDependencies: [Job] = GRDBStorage.shared
            .read { db in try nextJob.dependencies.fetchAll(db) }
            .defaulting(to: [])
        
        guard jobDependencies.isEmpty else {
            SNLog("[JobRunner] Found job with \(jobDependencies.count) dependencies, running those first")
            
            let jobDependencyIds: [Int64] = jobDependencies
                .compactMap { $0.id }
            let jobIdsNotInQueue: Set<Int64> = jobDependencyIds
                .asSet()
                .subtracting(jobQueue.wrappedValue.compactMap { $0.id })
            
            // If there are dependencies which aren't in the queue we should just append them
            guard !jobIdsNotInQueue.isEmpty else {
                jobQueue.mutate { queue in
                    queue.append(
                        contentsOf: jobDependencies
                            .filter { jobIdsNotInQueue.contains($0.id ?? -1) }
                    )
                    queue.append(nextJob)
                }
                handleJobDeferred(nextJob)
                return
            }
            
            // Otherwise re-add the current job after it's dependencies
            jobQueue.mutate { queue in
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
        SNLog("[JobRunner] Start job (\(numJobsRemaining) remaining)")
        
        jobExecutor.run(
            nextJob,
            success: handleJobSucceeded,
            failure: handleJobFailed,
            deferred: handleJobDeferred
        )
    }
    
    private static func scheduleNextSoonestJob() {
        let nextJobTimestamp: TimeInterval? = GRDBStorage.shared
            .read { db in
                try TimeInterval
                    .fetchOne(
                        db,
                        Job
                            .filterPendingJobs(excludeFutureJobs: false)
                            .select(.nextRunTimestamp)
                    )
            }
        
        guard let nextJobTimestamp: TimeInterval = nextJobTimestamp else { return }
        
        // If the next job isn't scheduled in the future then just restart the JobRunner immediately
        let secondsUntilNextJob: TimeInterval = (nextJobTimestamp - Date().timeIntervalSince1970)
        
        guard secondsUntilNextJob > 0 else {
            SNLog("[JobRunner] Restarting immediately for job scheduled \(Int(ceil(abs(secondsUntilNextJob)))) second\(Int(ceil(abs(secondsUntilNextJob))) == 1 ? "" : "s")) ago")
            
            internalQueue.async {
                JobRunner.start()
            }
            return
        }
        
        // Setup a trigger
        SNLog("[JobRunner] Stopping until next job in \(Int(ceil(abs(secondsUntilNextJob)))) second\(Int(ceil(abs(secondsUntilNextJob))) == 1 ? "" : "s"))")
        nextTrigger.mutate { $0 = Trigger.create(timestamp: nextJobTimestamp) }
    }
    
    // MARK: - Handling Results

    /// This function is called when a job succeeds
    private static func handleJobSucceeded(_ job: Job, shouldStop: Bool) {
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
                
            case .recurringOnLaunchBlockingOncePerSession:
                perSessionJobsCompleted.mutate { $0 = $0.inserting(job.id) }
                
            default: break
        }
        
        // The job is removed from the queue before it runs so all we need to to is remove it
        // from the 'currentlyRunning' set and start the next one
        jobsCurrentlyRunning.mutate { $0 = $0.removing(job.id) }
        internalQueue.async {
            runNextJob()
        }
    }

    /// This function is called when a job fails, if it's wasn't a permanent failure then the 'failureCount' for the job will be incremented and it'll
    /// be re-run after a retry interval has passed
    private static func handleJobFailed(_ job: Job, error: Error?, permanentFailure: Bool) {
        guard GRDBStorage.shared.read({ db in try Job.exists(db, id: job.id ?? -1) }) == true else {
            SNLog("[JobRunner] \(job.variant) job canceled")
            jobsCurrentlyRunning.mutate { $0 = $0.removing(job.id) }
            
            internalQueue.async {
                runNextJob()
            }
            return
        }
        
        switch job.behaviour {
            // If a "blocking" job failed then rerun it immediately
            case .recurringOnLaunchBlocking, .recurringOnActiveBlocking:
                SNLog("[JobRunner] blocking \(job.variant) job failed; retrying immediately")
                jobQueue.mutate({ $0.insert(job, at: 0) })
                
                internalQueue.async {
                    runNextJob()
                }
                return
                
            // For "blocking once per session" jobs only rerun it immediately if it hasn't already
            // run this session
            case .recurringOnLaunchBlockingOncePerSession:
                guard !perSessionJobsCompleted.wrappedValue.contains(job.id ?? -1) else { break }
                
                SNLog("[JobRunner] blocking \(job.variant) job failed; retrying immediately")
                perSessionJobsCompleted.mutate { $0 = $0.inserting(job.id) }
                jobQueue.mutate({ $0.insert(job, at: 0) })
                
                internalQueue.async {
                    runNextJob()
                }
                return
                
            default: break
        }
        
        GRDBStorage.shared.write { db in
            // Get the max failure count for the job (a value of '-1' means it will retry indefinitely)
            let maxFailureCount: Int = (executorMap.wrappedValue[job.variant]?.maxFailureCount ?? 0)
            
            guard
                !permanentFailure &&
                maxFailureCount >= 0 &&
                job.failureCount + 1 < maxFailureCount
            else {
                // If the job permanently failed or we have performed all of our retry attempts
                // then delete the job (it'll probably never succeed)
                _ = try job.delete(db)
                return
            }
            
            SNLog("[JobRunner] \(job.variant) job failed; scheduling retry (failure count is \(job.failureCount + 1))")
            _ = try job
                .with(
                    failureCount: (job.failureCount + 1),
                    nextRunTimestamp: (Date().timeIntervalSince1970 + getRetryInterval(for: job))
                )
                .saved(db)
        }
        
        jobsCurrentlyRunning.mutate { $0 = $0.removing(job.id) }
        internalQueue.async {
            runNextJob()
        }
    }
    
    /// This function is called when a job neither succeeds or fails (this should only occur if the job has specific logic that makes it dependant
    /// on other jobs, and it should automatically manage those dependencies)
    private static func handleJobDeferred(_ job: Job) {
        jobsCurrentlyRunning.mutate { $0 = $0.removing(job.id) }
        internalQueue.async {
            runNextJob()
        }
    }
    
    // MARK: - Convenience

    private static func getRetryInterval(for job: Job) -> TimeInterval {
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
