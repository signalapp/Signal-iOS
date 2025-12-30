//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A database record (or wrapper around one) representing an enqueued task
/// to be run. Contains whatever ``TaskRecordRunner`` needs to run the
/// task; all the generic ``TaskQueueLoader`` needs from it is some id
/// for uniqueing purposes.
public protocol TaskRecord {
    associatedtype IDType: Hashable

    var id: IDType { get }

    /// If non-nil, tasks will wait until this timestamp before running.
    /// Default to nil.
    var nextRetryTimestamp: UInt64? { get }
}

extension TaskRecord {
    var nextRetryTimestamp: UInt64? { return nil }
}

/// Intermediary between the ``TaskQueueLoader`` and the queue table in the database.
/// Used to peek (get next tasks to do) and remove tasks once complete.
public protocol TaskRecordStore {
    associatedtype Record: TaskRecord, Sendable

    /// Fetch the next `count` records to run, in priority order.
    ///
    /// Repeated results across peek calls is allowed; it is NOT expected that each peek call
    /// will retain an offset and return the N results _after_ the last peek.
    ///
    /// For example, the ``TaskQueueLoader`` might peek 4 and start running those 4 tasks.
    /// When the 1st task finishes, it will delete that record, then call peek 4 again.
    /// Tasks 2, 3, and 4 are still running and therefore not deleted from the database, so its
    /// expected that peek could return the same 3 plus the next record (e.g. returns [2,3,4,5].)
    /// Or it could return a totally new set of higher priority that were inserted since the last peek.
    func peek(count: UInt, tx: DBReadTransaction) throws -> [Record]

    /// Remove a record from the database table queue.
    ///
    /// Called by the ``TaskQueueLoader`` when the task either succeeds or fails with
    /// an unretryable error. Outside callers may remove queued records as they see fit.
    /// Removing a record that is currently running will not stop it from completing.
    func removeRecord(_ record: Record, tx: DBWriteTransaction) throws
}

/// The result of a ``TaskRecordRunner`` run.
public enum TaskRecordResult {
    /// Sucess! The task will be cleared from the queue by the loader (via the store).
    case success
    /// A retryable failure. The task will not be cleared from the queue by default; the
    /// runner gets an opportunity to respond to the error, including making any
    /// updates it desires to the record (including clearing it and reinserting if desired).
    case retryableError(Error)
    /// A non-retryable failure. The task will be cleared from the queue by the loader.
    /// Only return this result if it's expected that no retry will ever happen within
    /// the queue mechanism.
    case unretryableError(Error)
    /// Something happened between when the task was queued and when it was run
    /// that invalidated the need for any work (the task was "cancelled"). For example,
    /// perhaps the user deleted the owning thread, or whatever.
    /// Like a success, the row is removed and no error is assumed, but it's not
    /// _strictly_ a success so the result type and callback are differentiated.
    case cancelled
}

/// Used with a ``TaskQueueLoader``; this actually runs the task for each record
/// and performs any necessary cleanup on success or failure within the same write
/// transaction that clears the task record from the queue.
public protocol TaskRecordRunner {
    associatedtype Store: TaskRecordStore

    var store: Store { get }

    /// Run the task for a single record.
    /// Returned errors do NOT interrupt task processing; the loader will continue
    /// to process tasks until there are none left.
    ///
    /// - parameter loader: Provided so that runners can choose to call
    /// ``TaskQueueLoader/stop(reason:)`` if some error they encounter
    /// should stop all future tasks, not just the current one.
    func runTask(
        record: Store.Record,
        loader: TaskQueueLoader<Self>,
    ) async -> TaskRecordResult

    /// Called by ``TaskQueueLoader`` when the task completes successfully,
    /// with the same write transaction used to delete the task's database record.
    ///
    /// Thrown errors WILL interrupt task processing; it's assumed anything that goes
    /// wrong here is a severe error affecting the queue itself.
    func didSucceed(
        record: Store.Record,
        tx: DBWriteTransaction,
    ) throws

    /// Called by ``TaskQueueLoader`` when the task fails.
    /// If the error is non-retryable, the record is deleted from the databse in the
    /// same transaction.
    /// Otherwise the record is left alone and it is up to the runner to modify it as
    /// needed. However it is modified, it will be retried by the loader the next time
    /// it is returned as a result of the store's `peek` method.
    ///
    /// Thrown errors WILL interrupt task processing; it's assumed anything that goes
    /// wrong here is a severe error affecting the queue itself.
    func didFail(
        record: Store.Record,
        error: Error,
        isRetryable: Bool,
        tx: DBWriteTransaction,
    ) throws

    /// Called by ``TaskQueueLoader`` when the task is cancelled,
    /// with the same write transaction used to delete the task's database record.
    ///
    /// Thrown errors WILL interrupt task processing; it's assumed anything that goes
    /// wrong here is a severe error affecting the queue itself.
    func didCancel(
        record: Store.Record,
        tx: DBWriteTransaction,
    ) throws

    /// Called by ``TaskQueueLoader`` when all tasks have finished.
    /// In other words, when ``TaskRecordStore`` peek returns an empty array.
    func didDrainQueue() async
}

extension TaskRecordRunner {
    public func didDrainQueue() async {}
}

/// Utility class that helps working with serialized queues for which each needs to run
/// an async task and then remove itself from the queue.
///
/// Works with a ``TaskRecordStore`` and ``TaskRecordRunner`` to load
/// ``TaskRecord``s from the database N at a time and run their associated async
/// tasks in parallel. When each task completes or fails, it then removes the task from
/// the queue (unless it fails with a retryable error) and moves on to the next task(s).
///
/// When should you use this type as opposed to ``JobRunner`` and ``JobRecord``?
/// This type is bring-your-own database table (or in memory queue), thus granting flexibility particularly
/// if you want to enforce ORDER BYs when querying the next row to run, which allows for more options
/// than just the FIFO ordering offered by ``JobRunner``.
/// On the other hand, ``JobRunner`` gives you more in-built functionality, particularly with
/// respect to error handling and retries. Callers of this class are left to do that on their own as well
/// as left the task of actually starting up the loader and managing the queue table.
public actor TaskQueueLoader<Runner: TaskRecordRunner & Sendable> {

    typealias Store = Runner.Store
    typealias Record = Store.Record

    public let maxConcurrentTasks: UInt

    public var isRunning: Bool {
        switch state {
        case .notRunning, .cleaningUp, .cancelled:
            return false
        case .running:
            return true
        }
    }

    private nonisolated let dateProvider: DateProvider
    private let db: any DB
    private let runner: Runner
    private var store: Store { runner.store }
    private let sleep: (_ nanoseconds: UInt64) async throws -> Void

    /// WARNING: the runner (and therefore any of its strong references) is strongly
    /// captured by this class and will be retained for its lifetime.
    init(
        maxConcurrentTasks: UInt,
        dateProvider: @escaping DateProvider,
        db: any DB,
        runner: Runner,
        sleep: @escaping (_ nanoseconds: UInt64) async throws -> Void,
    ) {
        self.maxConcurrentTasks = maxConcurrentTasks
        self.dateProvider = dateProvider
        self.db = db
        self.runner = runner
        self.sleep = sleep
    }

    /// WARNING: the runner (and therefore any of its strong references) is strongly
    /// captured by this class and will be retained for its lifetime.
    public init(
        maxConcurrentTasks: UInt,
        dateProvider: @escaping DateProvider,
        db: any DB,
        runner: Runner,
    ) {
        self.init(
            maxConcurrentTasks: maxConcurrentTasks,
            dateProvider: dateProvider,
            db: db,
            runner: runner,
            sleep: {
                try await Task.sleep(nanoseconds: $0)
            },
        )
    }

    private enum State {
        case notRunning
        case running(UUID, Task<Void, Error>)
        case cleaningUp(UUID, Task<Void, Error>)
        case cancelled(UUID, Task<Void, Error>)

        func isUnchanged(from oldState: State) -> Bool {
            switch (oldState, self) {
            case (.notRunning, .notRunning):
                return true
            case (.notRunning, _):
                return false
            case (.running(let oldId, _), .running(let newId, _)):
                return oldId == newId
            case (.running, _):
                return false
            case (.cleaningUp(let oldId, _), .cleaningUp(let newId, _)):
                return oldId == newId
            case (.cleaningUp, _):
                return false
            case (.cancelled(let oldId, _), .cancelled(let newId, _)):
                return oldId == newId
            case (.cancelled, _):
                return false
            }
        }
    }

    private var state = State.notRunning
    /// Random IDs of un-cancelled observers of the currently running task.
    private var runningTaskObservers = Set<UUID>()
    /// Error provided when the task was stopped; if not nil, throw it on callers of loadAndRunTasks.
    private var stoppedReason: Error?

    private var currentTaskIds = Set<Record.IDType>()

    /// Load tasks, N at a time, and begin running any that are not already running.
    /// (N = max concurrent tasks)
    /// Runs until all tasks are finished (finished = table peek returns empty).
    ///
    /// Throws an error IFF some database operation relating to the queue or post-task cleanup fails;
    /// within-task failures are handled by the runner and do NOT interrupt processing of subsequent tasks.
    ///
    /// Cancellation causes code execution to be returned to the caller but does not _necessarily_ cancel
    /// the execution of subsequent tasks. All callers of `loadAndRunTasks()` await a single runner.
    /// As long as some uncancelled task context is awaiting the result, the runner will continue to execute
    /// subsequent tasks. A single caller cancelling simply releases that caller from waiting on the runner
    /// to finish; the runner isn't cancelled until _all_ callers cancel.
    /// If some caller wishes to _force_ the runner to stop, call `stop()` instead of cancelling the task.
    public func loadAndRunTasks() async throws {
        let task: Task<Void, Error>
        let state = self.state
        switch state {
        case .notRunning:
            // Start a new task.
            let taskId = UUID()
            task = Task {
                try await self._loadAndRunTasks(taskId: taskId)
            }
            self.state = .running(taskId, task)
            self.runningTaskObservers = Set()
        case .running(_, let _task):
            task = _task
        case .cancelled(_, let cancelledTask):
            // We want to wait for cancellation to finish
            // applying, and then try again.
            try? await cancelledTask.value
            // We expect that state will have been cleaned
            // up by the time runningTask finishes, but
            // just in case do cleanup here.
            if self.state.isUnchanged(from: state) {
                self.state = .notRunning
            }
            return try await loadAndRunTasks()
        case .cleaningUp(_, let runningTask):
            // We want to wait for cleanup to finish
            // applying, and then try again.
            try? await runningTask.value
            // We expect that state will have been cleaned
            // up by the time runningTask finishes, but
            // just in case do cleanup here.
            if self.state.isUnchanged(from: state) {
                self.state = .notRunning
            }
            return try await loadAndRunTasks()
        }

        let observerId = UUID()
        runningTaskObservers.insert(observerId)
        // The cancellable continuation means if the calling context cancels
        // it will immediately resume while the inner task keeps running.
        // In addition, we use `withTaskCancellationHandler` to get the
        // onCancel callback so that we can track when _all_ observers
        // have cancelled and then we pass along the cancellation to
        // the actual running task.
        let continuation = CancellableContinuation<Void>()
        Task {
            do {
                try await task.value
                continuation.resume(with: .success(()))
            } catch let cancellationError as CancellationError {
                let error = self.stoppedReason ?? cancellationError
                continuation.resume(with: .failure(error))
            } catch let error {
                continuation.resume(with: .failure(error))
            }
        }

        try await withTaskCancellationHandler(
            operation: {
                try await continuation.wait()
            },
            onCancel: {
                continuation.cancel()
                Task {
                    try await observerDidCancel(observerId)
                }
            },
        )
    }

    private func observerDidCancel(_ id: UUID) throws {
        guard runningTaskObservers.contains(id) else {
            return
        }
        self.runningTaskObservers.remove(id)
        if runningTaskObservers.isEmpty {
            // We can stop and cancel the running task.
            try self.stop()
        }
    }

    public func stop(reason: Error? = nil) throws {
        switch state {
        case .notRunning:
            break
        case .cancelled:
            // Already cancelled; prefer the initial
            // reason (if any) and let it finish cancelling.
            return
        case .running(let taskId, let runningTask), .cleaningUp(let taskId, let runningTask):
            self.stoppedReason = reason
            runningTask.cancel()
            self.state = .cancelled(taskId, runningTask)
        }
    }

    private func _loadAndRunTasks(taskId: UUID) async throws {
        // Check cancellation at the start of each attempt.
        // This method is called recursively, so now is a good time to check.
        try Task.checkCancellation()

        if currentTaskIds.count >= maxConcurrentTasks {
            return
        }

        // _Always_ read as many tasks as we can run; afterwards we can
        // dedupe against the tasks already running and keep as many as
        // needed to fill up the max concurrent count.
        let recordCandidates = try db.read { tx in
            try store.peek(count: self.maxConcurrentTasks, tx: tx)
        }

        let records = recordCandidates.filter { record in
            !currentTaskIds.contains(record.id)
        }
        guard !records.isEmpty else {
            if currentTaskIds.isEmpty {
                switch self.state {
                case .notRunning:
                    return
                case .cancelled:
                    owsFailDebug("Cancel should have applied to the task context")
                    return
                case .cleaningUp:
                    return
                case .running(let stateTaskId, let runningTask):
                    if stateTaskId == taskId {
                        state = .cleaningUp(taskId, runningTask)
                        await self.runner.didDrainQueue()
                        switch self.state {
                        case .notRunning:
                            owsFailDebug("State is not running but we are, in fact, running")
                            return
                        case .running(let stateTaskId, _):
                            owsFailDebug("Not cleaning up? How?")
                            fallthrough
                        case .cancelled(let stateTaskId, _):
                            // Cancellation might've applied while running didDrainQueue;
                            // We're done now so just finish.
                            fallthrough
                        case .cleaningUp(let stateTaskId, _):
                            if stateTaskId == taskId {
                                state = .notRunning
                            }
                        }
                    }
                }
            }
            return
        }
        records.forEach { currentTaskIds.insert($0.id) }

        let runner = self.runner
        try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            records.forEach { record in
                taskGroup.addTask {
                    let nowMs = self.dateProvider().ows_millisecondsSince1970
                    if
                        let nextRetryTimestamp = record.nextRetryTimestamp,
                        nowMs < nextRetryTimestamp
                    {
                        try await self.sleep(NSEC_PER_MSEC * (nextRetryTimestamp - nowMs))
                    }
                    let taskResult = await runner.runTask(record: record, loader: self)
                    switch taskResult {
                    case .success:
                        try await self.didSucceed(record: record)
                    case .retryableError(let error):
                        try await self.didFail(record: record, error: error, isRetryable: true)
                    case .unretryableError(let error):
                        try await self.didFail(record: record, error: error, isRetryable: false)
                    case .cancelled:
                        try await self.didCancel(record: record)
                    }
                    // As soon as we finish any task, start loading more tasks to run.
                    try await self._loadAndRunTasks(taskId: taskId)
                }
            }
            try await taskGroup.waitForAll()
        }
    }

    private func didSucceed(record: Store.Record) async throws {
        try await db.awaitableWrite { tx in
            try self.store.removeRecord(record, tx: tx)
            try self.runner.didSucceed(record: record, tx: tx)
        }
        self.currentTaskIds.remove(record.id)
    }

    private func didFail(record: Store.Record, error: Error, isRetryable: Bool) async throws {
        try await db.awaitableWrite { tx in
            if !isRetryable {
                // Remove the record for non-retryable errors.
                try self.store.removeRecord(record, tx: tx)
            }
            try self.runner.didFail(record: record, error: error, isRetryable: isRetryable, tx: tx)
        }
        self.currentTaskIds.remove(record.id)
    }

    private func didCancel(record: Store.Record) async throws {
        try await db.awaitableWrite { tx in
            try self.store.removeRecord(record, tx: tx)
            try self.runner.didCancel(record: record, tx: tx)
        }
        self.currentTaskIds.remove(record.id)
    }
}
