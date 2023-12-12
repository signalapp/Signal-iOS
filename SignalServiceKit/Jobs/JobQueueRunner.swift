//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

public enum JobAttemptResult {
    /// The Job has succeeded or reached a terminal error. A retryable error may
    /// become terminal if too many failures occur.
    case finished(Result<Void, Error>)

    /// The Job encountered a transient, retryable error. If `canRetryEarly` is
    /// true, the job may be attempted again before the time interval has
    /// elapsed (eg, when Reachability reports that we've reconnected).
    case retryAfter(TimeInterval, canRetryEarly: Bool = true)

    /// Invokes `block` and handles retryable errors.
    ///
    /// If `block()` succeeds, a terminal success result is returned. In this
    /// case, the caller (or, more typically, `block`) is responsible for
    /// removing the job from the database.
    ///
    /// If `block()` throws an error, calls `performDefaultErrorHandler`.
    public static func executeBlockWithDefaultErrorHandler(
        jobRecord: JobRecord,
        retryLimit: UInt,
        db: DB,
        block: () async throws -> Void
    ) async -> JobAttemptResult {
        do {
            try await block()
            return .finished(.success(()))
        } catch {
            return await db.awaitableWrite { tx in
                return performDefaultErrorHandler(error: error, jobRecord: jobRecord, retryLimit: retryLimit, tx: tx)
            }
        }
    }

    /// Performs default error handling for an error.
    ///
    /// If the job throws a retryable error, `jobRecord.failureCount` is
    /// incremented (assuming it's less than `retryLimit`) and this method
    /// returns a `.retryAfter` value with exponential backoff.
    ///
    /// If the job throws a terminal error (or retryable error with no retries
    /// remaining), the job is removed and a terminal error is returned.
    public static func performDefaultErrorHandler(
        error: Error,
        jobRecord: JobRecord,
        retryLimit: UInt,
        tx: DBWriteTransaction
    ) -> JobAttemptResult {
        if jobRecord.failureCount < retryLimit, error.isRetryable {
            jobRecord.addFailure(tx: SDSDB.shimOnlyBridge(tx))
            let delay = OWSOperation.retryIntervalForExponentialBackoff(failureCount: jobRecord.failureCount)
            return .retryAfter(delay, canRetryEarly: true)
        } else {
            jobRecord.anyRemove(transaction: SDSDB.shimOnlyBridge(tx))
            return .finished(.failure(error))
        }
    }
}

public enum JobResult {
    /// The Job ran to completion and returned a Result.
    case ranJob(Result<Void, Error>)
    /// The Job couldn't be found, so it wasn't executed.
    case notFound
    /// The Job couldn't be fetched because of an Error.
    case fetchError(Error)

    public var ranSuccessfullyOrError: Result<Void, Error> {
        switch self {
        case .ranJob(.success(())):
            return .success(())
        case .ranJob(.failure(let error)), .fetchError(let error):
            return .failure(error)
        case .notFound:
            return .failure(OWSGenericError("JobRecord not found."))
        }
    }
}

/// A `JobRunner` is responsible for running a `JobRecord`.
///
/// A single JobRunner is used for all attempts of a `JobRecord` (within a
/// single app launch/process). Therefore, a `JobRunner` is a good place to
/// store mutable, transient state (eg a per-job error counter).
///
/// When a job is initially scheduled, the caller can provide its own
/// `JobRunner`. This can be useful for registering completion callbacks.
/// However, it's important to note that those completion callbacks will be
/// lost if the app is relaunched and a new `JobRunner` is created. In
/// practice, this doesn't cause problems because the UX that's waiting for
/// the completion callback is also dismissed if the app is relaunched.
public protocol JobRunner<JobRecordType> {
    associatedtype JobRecordType: JobRecord

    /// Runs a single attempt of the job.
    ///
    /// Each attempt can return one of two results: `.finished` (eg, "success",
    /// "terminal error", "out of retries") or `.retryAfter` (ie "network error;
    /// try again in 2 minutes").
    ///
    /// If this method `.finished`, then it's also responsible for removing
    /// `jobRecord` from the database. Passing this responsibility to
    /// `runJobAttempt` ensures that removing `jobRecord` can be performed
    /// atomically with other database operations. (In DEBUG builds, the caller
    /// will try to ensure this invariant remains true.)
    func runJobAttempt(_ jobRecord: JobRecordType) async -> JobAttemptResult

    /// Invoked when a job reaches a terminal result.
    ///
    /// This method is guaranteed to be invoked exactly once for every
    /// `JobRunner` provided to `JobQueueRunner.addPersistedJob(...)` (assuming
    /// the app doesn't crash just before or during its execution).
    ///
    /// If a `JobRecord` is removed from the database before it's run (or if
    /// fetching it throws an error), then `runJobAttempt` won't be invoked, but
    /// this method will still be invoked. This method is therefore an excellent
    /// place to invoke "exactly once", in-memory completion handlers.
    func didFinishJob(_ jobRecordId: JobRecord.RowId, result: JobResult) async
}

/// A `JobRunnerFactory` creates `JobRunner` instances.
///
/// Most `JobRunner` types currently use `Dependencies`, but when they
/// don't, these factories will be responsible for passing dependencies into
/// `JobRunner` instances.
public protocol JobRunnerFactory<JobRunnerType> {
    associatedtype JobRunnerType: JobRunner

    /// Creates a `JobRunner` for a `JobRecord` loaded from the database.
    func buildRunner() -> JobRunnerType
}

public class JobQueueRunner<
    JobFinderType: JobRecordFinder,
    JobRunnerFactoryType: JobRunnerFactory
> where JobFinderType.JobRecordType == JobRunnerFactoryType.JobRunnerType.JobRecordType {
    private let db: DB
    private let jobFinder: JobFinderType
    private let jobRunnerFactory: JobRunnerFactoryType
    private var observers = [NSObjectProtocol]()

    private enum Mode {
        /// The runner hasn't been started yet, or the runner is in the process of
        /// starting. In both of these states, new jobs are held until persisted
        /// jobs have been loaded. (This ensures new jobs execute after old jobs.)
        case loading(canExecuteJobsConcurrently: Bool, jobsToEnqueueAfterLoading: [QueuedJob])

        /// The runner is operating concurrently. New jobs are started immediately.
        case concurrent

        /// The runner is operating serially. No jobs are running, so a new job can
        /// be started immediately.
        case serialPaused

        /// The runner is operating serially. A job is being executed, so any new
        /// jobs will be added to `nextJobs`. When the current job finishes, it will
        /// start the first job in `nextJobs`.
        case serialRunning(nextJobs: [QueuedJob])
    }

    private struct QueuedJob {
        var rowId: JobRecord.RowId
        var runner: JobRunnerFactoryType.JobRunnerType
    }

    private struct State {
        var mode: Mode

        /// If a job encounters a transient failure, it can request to be run again
        /// after a delay. While it's waiting, it will store a reference to its
        /// waiting Task here. On certain external triggers (eg we reconnect to the
        /// Internet), these waiting Tasks can be canceled to trigger the next
        /// attempt immediately.
        var waitingTasks = [JobRecord.RowId: Task<Void, Never>]()
    }

    private let state: AtomicValue<State>

    public init(canExecuteJobsConcurrently: Bool, db: DB, jobFinder: JobFinderType, jobRunnerFactory: JobRunnerFactoryType) {
        let mode: Mode = .loading(canExecuteJobsConcurrently: canExecuteJobsConcurrently, jobsToEnqueueAfterLoading: [])
        self.state = AtomicValue<State>(State(mode: mode), lock: AtomicLock())
        self.db = db
        self.jobFinder = jobFinder
        self.jobRunnerFactory = jobRunnerFactory
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    public func start(shouldRestartExistingJobs: Bool) {
        Task { await self._start(shouldRestartExistingJobs: shouldRestartExistingJobs) }
    }

    private func _start(shouldRestartExistingJobs: Bool) async {
        var oldJobs = [JobFinderType.JobRecordType]()
        if shouldRestartExistingJobs {
            do {
                oldJobs.append(contentsOf: try await jobFinder.loadRunnableJobs())
            } catch {
                Logger.error("Couldn't start existing jobs, so no new jobs will start: \(error)")
                return
            }
        }
        state.update { state in
            let newMode: Mode
            switch state.mode {
            case .loading(let canExecuteJobsConcurrently, let jobsToEnqueueAfterLoading):
                // Every runner must be started before it can execute jobs. When a runner
                // is started, it may optionally fetch all previously-persisted jobs to
                // execute. Any jobs that are scheduled while previously-persisted jobs are
                // being loaded from disk must be scheduled after those
                // previously-persisted jobs. If a new job is persisted while
                // previously-persisted jobs are being loaded, then it may or may not be
                // considered a previously-persisted job (depending on db race conditions).
                // If it is present in the previously-persisted jobs, we want to ignore it
                // since the new job might have a custom `JobRunner`.
                let newRowIds = Set(jobsToEnqueueAfterLoading.map { $0.rowId })
                var queuedJobs = [QueuedJob]()
                queuedJobs.append(
                    contentsOf: oldJobs.filter { !newRowIds.contains($0.id!) }.map {
                        QueuedJob(rowId: $0.id!, runner: jobRunnerFactory.buildRunner())
                    }
                )
                queuedJobs.append(contentsOf: jobsToEnqueueAfterLoading)
                if canExecuteJobsConcurrently {
                    queuedJobs.forEach(runJob(_:))
                    newMode = .concurrent
                } else if queuedJobs.isEmpty {
                    newMode = .serialPaused
                } else {
                    var serialJobs = queuedJobs
                    runJob(serialJobs.removeFirst())
                    newMode = .serialRunning(nextJobs: serialJobs)
                }
            case .concurrent, .serialPaused, .serialRunning:
                owsFail("Can't start a JobQueueRunner more than once.")
            }
            state.mode = newMode
        }
    }

    // MARK: - Reachability Changes

    public func listenForReachabilityChanges(reachabilityManager: SSKReachabilityManager) {
        observers.append(NotificationCenter.default.addObserver(
            forName: SSKReachability.owsReachabilityDidChange,
            object: reachabilityManager,
            queue: nil,
            using: { [weak self] _ in
                if reachabilityManager.isReachable {
                    self?.retryWaitingJobs()
                }
            }
        ))
    }

    func retryWaitingJobs() {
        // Cancel each waiting task so that the next retry can commence.
        state.update { state in
            state.waitingTasks.forEach { (_, waitingTask) in waitingTask.cancel() }
        }
    }

    // MARK: - Queuing Jobs

    public func addPersistedJob(_ jobRecord: JobFinderType.JobRecordType, runner: JobRunnerFactoryType.JobRunnerType? = nil) {
        enqueueAndStartJob(QueuedJob(rowId: jobRecord.id!, runner: runner ?? jobRunnerFactory.buildRunner()))
    }

    private func enqueueAndStartJob(_ job: QueuedJob) {
        state.update { state in
            switch state.mode {
            case .loading(let canExecuteJobsConcurrently, let jobsToEnqueueAfterLoading):
                state.mode = .loading(
                    canExecuteJobsConcurrently: canExecuteJobsConcurrently,
                    jobsToEnqueueAfterLoading: jobsToEnqueueAfterLoading + [job]
                )
            case .concurrent:
                runJob(job)
            case .serialPaused:
                runJob(job)
                state.mode = .serialRunning(nextJobs: [])
            case .serialRunning(nextJobs: let nextJobs):
                state.mode = .serialRunning(nextJobs: nextJobs + [job])
            }
        }
    }

    // MARK: - Running Jobs

    private func runJob(_ queuedJob: QueuedJob) {
        Task {
            let jobResult = await _runJob(queuedJob)
            await queuedJob.runner.didFinishJob(queuedJob.rowId, result: jobResult)
            state.update { state in startNextJob(state: &state) }
        }
    }

    private func _runJob(_ queuedJob: QueuedJob) async -> JobResult {
        while true {
            switch await runJobAttempt(queuedJob) {
            case .runAgain:
                continue
            case .notFound:
                return .notFound
            case .finished(let result):
                return .ranJob(result)
            case .fetchError(let error):
                Logger.warn("Couldn't fetch a job; skipping just that job: \(error)")
                return .fetchError(error)
            }
        }
    }

    private enum JobAttemptResult {
        case runAgain
        case finished(Result<Void, Error>)
        case notFound
        case fetchError(Error)
    }

    private func runJobAttempt(_ queuedJob: QueuedJob) async -> JobAttemptResult {
        let jobRecord: JobFinderType.JobRecordType?
        do {
            jobRecord = try db.read(block: { tx in try jobFinder.fetchJob(rowId: queuedJob.rowId, tx: tx) })
        } catch {
            return .fetchError(error)
        }
        guard let jobRecord else {
            // The job no longer exists, so we can start the next one.
            return .notFound
        }

        let result = await queuedJob.runner.runJobAttempt(jobRecord)
        switch result {
        case .finished(let result):
            // In DEBUG builds, make sure that .finished jobs were deleted.
            assert(db.read(block: { tx in (try? jobFinder.fetchJob(rowId: queuedJob.rowId, tx: tx)) == nil }))
            return .finished(result)
        case .retryAfter(let retryAfter, let canRetryEarly):
            // Create a Task that waits for `retryAfter`. If `retryWaitingJobs` is
            // called, this Task will be canceled, starting the next retry immediately.
            let waitingTask = Task { _ = try? await Task.sleep(nanoseconds: UInt64(retryAfter*Double(NSEC_PER_SEC))) }
            if canRetryEarly {
                state.update { state in state.waitingTasks[queuedJob.rowId] = waitingTask }
            }
            await waitingTask.value
            if canRetryEarly {
                state.update { state in state.waitingTasks[queuedJob.rowId] = nil }
            }
            return .runAgain
        }
    }

    private func startNextJob(state: inout State) {
        switch state.mode {
        case .loading, .serialPaused:
            owsFailBeta("Can't start the next job.")
        case .concurrent:
            return  // All of these are started immediately.
        case .serialRunning(nextJobs: var nextJobs):
            state.mode = {
                if nextJobs.isEmpty {
                    // There's no more jobs to run, so pause the runner.
                    return .serialPaused
                } else {
                    let jobToRun = nextJobs.removeFirst()
                    runJob(jobToRun)
                    return .serialRunning(nextJobs: nextJobs)
                }
            }()
        }
    }
}
