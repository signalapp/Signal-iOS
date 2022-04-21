// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SignalCoreKit
import SessionUtilitiesKit

public protocol JobExecutor {
    static var maxFailureCount: UInt { get }
    static var requiresThreadId: Bool { get }

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
        
        static func create(timestamp: TimeInterval) -> Trigger {
            let trigger: Trigger = Trigger()
            trigger.timer = Timer.scheduledTimer(
                timeInterval: timestamp,
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
    
    // TODO: Could this be a bottleneck? (single serial queue to process all these jobs? Group by thread?)
    // TODO: Multi-thread support
    private static let minRetryInterval: TimeInterval = 1
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
    
    // MARK: - Configuration
    
    public static func add(executor: JobExecutor.Type, for variant: Job.Variant) {
        executorMap.mutate { $0[variant] = executor }
    }
    
    // MARK: - Execution
    
    public static func add(_ db: Database, job: Job?, canStartJob: Bool = true) {
        // Store the job into the database (getting an id for it)
        guard let updatedJob: Job = try? job?.inserted(db) else {
            SNLog("[JobRunner] Unable to add \(job.map { "\($0.variant)" } ?? "unknown") job")
            return
        }
        
        switch (canStartJob, updatedJob.behaviour) {
            case (false, _), (_, .runOnceNextLaunch): return
            default: break
        }
        
        jobQueue.mutate { $0.append(updatedJob) }
        
        // Start the job runner if needed
        db.afterNextTransactionCommit { _ in
            if !isRunning.wrappedValue {
                start()
            }
        }
    }
    
    public static func upsert(_ db: Database, job: Job?, canStartJob: Bool = true) {
        guard let job: Job = job else { return }    // Ignore null jobs
        guard let jobId: Int64 = job.id else {
            add(db, job: job, canStartJob: canStartJob)
            return
        }
        
        // Lock the queue while checking the index and inserting to ensure we don't run into
        // any multi-threading shenanigans
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
    
    public static func insert(_ db: Database, job: Job?, before otherJob: Job) {
        switch job?.behaviour {
            case .recurringOnActive, .recurringOnLaunch, .runOnceNextLaunch:
                SNLog("[JobRunner] Attempted to insert \(job.map { "\($0.variant)" } ?? "unknown") job before the current one even though it's behaviour is \(job.map { "\($0.behaviour)" } ?? "unknown")")
                return
                
            default: break
        }
        
        // Store the job into the database (getting an id for it)
        guard let updatedJob: Job = try? job?.inserted(db) else {
            SNLog("[JobRunner] Unable to add \(job.map { "\($0.variant)" } ?? "unknown") job")
            return
        }
        
        // Insert the job before the current job (re-adding the current job to
        // the start of the queue if it's not in there) - this will mean the new
        // job will run and then the otherJob will run (or run again) once it's
        // done
        jobQueue.mutate {
            if !$0.contains(otherJob) {
                $0.insert(otherJob, at: 0)
            }
            
            guard let otherJobIndex: Int = $0.firstIndex(of: otherJob) else { return }
            
            $0.insert(updatedJob, at: otherJobIndex)
        }
    }
    
    public static func appDidFinishLaunching() {
        // Note: 'appDidBecomeActive' will run on first launch anyway so we can
        // leave those jobs out and can wait until then to start the JobRunner
        let maybeJobsToRun: [Job]? = GRDBStorage.shared.read { db in
            try Job
                .filter(
                    [
                        Job.Behaviour.recurringOnLaunch,
                        Job.Behaviour.runOnceNextLaunch
                    ].contains(Job.Columns.behaviour)
                )
                .fetchAll(db)
        }
        
        guard let jobsToRun: [Job] = maybeJobsToRun else { return }
        
        jobQueue.mutate { $0.append(contentsOf: jobsToRun) }
    }
    
    public static func appDidBecomeActive() {
        let maybeJobsToRun: [Job]? = GRDBStorage.shared.read { db in
            try Job
                .filter(Job.Columns.behaviour == Job.Behaviour.recurringOnActive)
                .fetchAll(db)
        }
        
        guard let jobsToRun: [Job] = maybeJobsToRun else { return }
        
        jobQueue.mutate { $0.append(contentsOf: jobsToRun) }
        
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
            }
            return
        }
        
        // Get any pending jobs
        let maybeJobsToRun: [Job]? = GRDBStorage.shared.read { db in
            try Job
                .filter(
                    [
                        Job.Behaviour.runOnce,
                        Job.Behaviour.recurring
                    ].contains(Job.Columns.behaviour)
                )
                .filter(Job.Columns.nextRunTimestamp <= Date().timeIntervalSince1970)
                .order(Job.Columns.nextRunTimestamp)
                .fetchAll(db)
        }
        
        // If there are no pending jobs then schedule the JobRunner to start again
        // when the next scheduled job should start
        guard let jobsToRun: [Job] = maybeJobsToRun else {
            scheduleNextSoonestJob()
            return
        }
        
        // Add the jobs to the queue and run the first job in the queue
        jobQueue.mutate { $0.append(contentsOf: jobsToRun) }
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
        guard let nextJob: Job = jobQueue.mutate({ $0.popFirst() }) else {
            scheduleNextSoonestJob()
            isRunning.mutate { $0 = false }
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
        
        // Update the state to indicate it's running
        //
        // Note: We need to store 'numJobsRemaining' in it's own variable because
        // the 'SNLog' seems to dispatch to it's own queue which ends up getting
        // blocked by the JobRunner's queue becuase 'jobQueue' is Atomic
        let numJobsRemaining: Int = jobQueue.wrappedValue.count
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
        let maybeJob: Job? = GRDBStorage.shared.read { db in
            try Job
                .filter(
                    [
                        Job.Behaviour.runOnce,
                        Job.Behaviour.recurring
                    ].contains(Job.Columns.behaviour)
                )
                .order(Job.Columns.nextRunTimestamp)
                .fetchOne(db)
        }
        let targetTimestamp: TimeInterval = (maybeJob?.nextRunTimestamp ?? (Date().timeIntervalSince1970 + minRetryInterval))
        nextTrigger.mutate { $0 = Trigger.create(timestamp: targetTimestamp) }
    }
    
    // MARK: - Handling Results

    /// This function is called when a job succeeds
    private static func handleJobSucceeded(_ job: Job, shouldStop: Bool) {
        switch job.behaviour {
            case .runOnce, .runOnceNextLaunch:
                GRDBStorage.shared.write { db in
                    try job.delete(db)
                }
                
            case .recurring where shouldStop == true:
                GRDBStorage.shared.write { db in
                    try job.delete(db)
                }
                
            case .recurring where job.nextRunTimestamp <= Date().timeIntervalSince1970:
                // For `recurring` jobs we want the job to run again but want at least 1 second to pass
                GRDBStorage.shared.write { db in
                    var updatedJob: Job = job.with(
                        nextRunTimestamp: (Date().timeIntervalSince1970 + 1)
                    )
                    try updatedJob.save(db)
                }
                
            default: break
        }
        
        // The job is removed from the queue before it runs so all we need to to is remove it
        // from the 'currentlyRunning' set and start the next one
        jobsCurrentlyRunning.mutate { $0 = $0.removing(job.id) }
        runNextJob()
    }

    /// This function is called when a job fails, if it's wasn't a permanent failure then the 'failureCount' for the job will be incremented and it'll
    /// be re-run after a retry interval has passed
    private static func handleJobFailed(_ job: Job, error: Error?, permanentFailure: Bool) {
        guard GRDBStorage.shared.read({ db in try Job.exists(db, id: job.id ?? -1) }) == true else {
            SNLog("[JobRunner] \(job.variant) job canceled")
            jobsCurrentlyRunning.mutate { $0 = $0.removing(job.id) }
            runNextJob()
            return
        }
        
        GRDBStorage.shared.write { db in
            // Check if the job has a 'maxFailureCount' (a value of '0' means it will always retry)
            let maxFailureCount: UInt = (executorMap.wrappedValue[job.variant]?.maxFailureCount ?? 0)
            
            guard
                !permanentFailure &&
                maxFailureCount > 0 &&
                job.failureCount + 1 < maxFailureCount
            else {
                // If the job permanently failed or we have performed all of our retry attempts
                // then delete the job (it'll probably never succeed)
                try job.delete(db)
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
        runNextJob()
    }
    
    /// This function is called when a job neither succeeds or fails (this should only occur if the job has specific logic that makes it dependant
    /// on other jobs, and it should automatically manage those dependencies)
    private static func handleJobDeferred(_ job: Job) {
        jobsCurrentlyRunning.mutate { $0 = $0.removing(job.id) }
        runNextJob()
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
