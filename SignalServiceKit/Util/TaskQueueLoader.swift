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
    associatedtype Record: TaskRecord

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
        loader: TaskQueueLoader<Self>
    ) async -> TaskRecordResult

    /// Called by ``TaskQueueLoader`` when the task completes successfully,
    /// with the same write transaction used to delete the task's database record.
    ///
    /// Thrown errors WILL interrupt task processing; it's assumed anything that goes
    /// wrong here is a severe error affecting the queue itself.
    func didSucceed(
        record: Store.Record,
        tx: DBWriteTransaction
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
        tx: DBWriteTransaction
    ) throws

    /// Called by ``TaskQueueLoader`` when the task is cancelled,
    /// with the same write transaction used to delete the task's database record.
    ///
    /// Thrown errors WILL interrupt task processing; it's assumed anything that goes
    /// wrong here is a severe error affecting the queue itself.
    func didCancel(
        record: Store.Record,
        tx: DBWriteTransaction
    ) throws
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
public actor TaskQueueLoader<Runner: TaskRecordRunner> {

    typealias Store = Runner.Store
    typealias Record = Store.Record

    public let maxConcurrentTasks: UInt

    private nonisolated let dateProvider: DateProvider
    private let db: any DB
    private let runner: Runner
    private var store: Store { runner.store }

    /// WARNING: the runner (and therefore any of its strong references) is strongly
    /// captured by this class and will be retained for its lifetime.
    internal init(
        maxConcurrentTasks: UInt,
        dateProvider: @escaping DateProvider,
        db: any DB,
        runner: Runner,
        sleep: (_ nanoseconds: UInt64) async throws -> Void
    ) {
        self.maxConcurrentTasks = maxConcurrentTasks
        self.dateProvider = dateProvider
        self.db = db
        self.runner = runner
    }

    /// WARNING: the runner (and therefore any of its strong references) is strongly
    /// captured by this class and will be retained for its lifetime.
    public init(
        maxConcurrentTasks: UInt,
        dateProvider: @escaping DateProvider,
        db: any DB,
        runner: Runner
    ) {
        self.init(
            maxConcurrentTasks: maxConcurrentTasks,
            dateProvider: dateProvider,
            db: db,
            runner: runner,
            sleep: {
                try await Task.sleep(nanoseconds: $0)
            }
        )
    }

    private var runningTask: Task<Void, Error>?
    /// Error provided when the task was stopped; if not nil, throw it on callers of loadAndRunTasks.
    private var stoppedReason: Error?

    private var currentTaskIds = Set<Record.IDType>()

    /// Load tasks, N at a time, and begin running any that are not already running.
    /// (N = max concurrent tasks)
    /// Runs until cooperative parent Task cancellation, some task throws an error, or
    /// all tasks are finished (finished = table peek returns empty).
    ///
    /// Throws an error IFF some database operation relating to the queue or post-task cleanup fails;
    /// within-task failures are handled by the runner and do NOT interrupt processing of subsequent tasks.
    public func loadAndRunTasks() async throws {
        if let runningTask {
            do {
                return try await runningTask.value
            } catch let cancellationError as CancellationError {
                throw stoppedReason ?? cancellationError
            } catch let error {
                throw error
            }
        }
        let task = Task {
            try await self._loadAndRunTasks()
            self.runningTask = nil
        }
        self.runningTask = task
        try await withTaskCancellationHandler(
            operation: {
                do {
                    return try await task.value
                } catch let cancellationError as CancellationError {
                    throw stoppedReason ?? cancellationError
                } catch let error {
                    throw error
                }
            },
            onCancel: {
                task.cancel()
            }
        )
    }

    public func stop(reason: Error? = nil) async throws {
        guard let runningTask, !runningTask.isCancelled else {
            return
        }
        self.stoppedReason = reason
        runningTask.cancel()
        self.runningTask = nil
    }

    private func _loadAndRunTasks() async throws {
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
                        try await Task.sleep(nanoseconds: NSEC_PER_MSEC * (nextRetryTimestamp - nowMs))
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
                    try await self._loadAndRunTasks()
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
