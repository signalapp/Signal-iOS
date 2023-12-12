//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import SignalCoreKit

/// JobQueue - A durable work queue
///
/// When work needs to be done, add it to the JobQueue.
/// The JobQueue will persist a JobRecord to be sure that work can be restarted if the app is killed.
///
/// The actual work, is carried out in a DurableOperation which the JobQueue spins off, based on the contents
/// of a JobRecord.
///
/// For a concrete example, take message sending.
/// Add an outgoing message to the MessageSenderJobQueue, which first records a SSKMessageSenderJobRecord.
/// The MessageSenderJobQueue then uses that SSKMessageSenderJobRecord to create a MessageSenderOperation which
/// takes care of the actual business of communicating with the service.
///
/// DurableOperations are retryable - via their `remainingRetries` logic. However, if the operation encounters
/// an error where `error.isRetryable == false`, the operation will fail, regardless of available retries.

public enum JobError: Error {
    case permanentFailure(description: String)
    case obsolete(description: String)
}

public protocol DurableOperation: AnyObject, Equatable {
    associatedtype JobRecordType: JobRecord
    associatedtype DurableOperationDelegateType: DurableOperationDelegate

    var jobRecord: JobRecordType { get }
    var durableOperationDelegate: DurableOperationDelegateType? { get set }
    var operation: OWSOperation { get }

    var maxRetries: UInt { get }

    /// This could be computed using ``maxRetries`` and ``JobRecord/failureCount``,
    /// but because in practice these are ``OWSOperation``s we make it a mutable
    /// stored property instead for compatibility.
    var remainingRetries: UInt { get set }
}

public protocol DurableOperationDelegate: AnyObject {
    associatedtype DurableOperationType: DurableOperation

    func durableOperationDidSucceed(_ operation: DurableOperationType, transaction: SDSAnyWriteTransaction)
    func durableOperation(_ operation: DurableOperationType, didReportError: Error, transaction: SDSAnyWriteTransaction)
    func durableOperation(_ operation: DurableOperationType, didFailWithError error: Error, transaction: SDSAnyWriteTransaction)
}

public protocol JobQueue: DurableOperationDelegate, Dependencies {
    typealias JobRecordType = DurableOperationType.JobRecordType

    var runningOperations: AtomicArray<DurableOperationType> { get set }

    var isSetup: AtomicBool { get }
    func setup()
    func didMarkAsReady(oldJobRecord: JobRecordType, transaction: SDSAnyWriteTransaction)

    func operationQueue(jobRecord: JobRecordType) -> OperationQueue
    func buildOperation(jobRecord: JobRecordType, transaction: SDSAnyReadTransaction) throws -> DurableOperationType

    /// When `requiresInternet` is true, we immediately run any jobs which are waiting for retry upon detecting Reachability.
    ///
    /// Because `Reachability` isn't 100% reliable, the jobs will be attempted regardless of what we think our current Reachability is.
    /// However, because these jobs will likely fail many times in succession, their `retryInterval` could be quite long by the time we
    /// are back online.
    var requiresInternet: Bool { get }

    var isEnabled: Bool { get }
}

// MARK: -

public extension JobQueue {

    func add(
        jobRecord: JobRecordType,
        transaction: SDSAnyWriteTransaction
    ) {
        owsAssertDebug(jobRecord.status == .ready)

        jobRecord.anyInsert(transaction: transaction)

        transaction.addTransactionFinalizationBlock(
            forKey: "jobQueue.\(JobRecordType.jobRecordType.jobRecordLabel).startWorkImmediatelyIfAppIsReady"
        ) { transaction in
            self.startWorkImmediatelyIfAppIsReady(transaction: transaction)
        }

        transaction.addAsyncCompletion(queue: .global()) {
            self.startWorkWhenAppIsReady()
        }
    }

    func startWorkImmediatelyIfAppIsReady(transaction: SDSAnyWriteTransaction) {
        guard isEnabled else { return }
        guard !CurrentAppContext().isRunningTests else { return }
        guard AppReadiness.isAppReady else { return }
        guard isSetup.get() else { return }
        workStep(transaction: transaction)
    }

    func startWorkWhenAppIsReady() {
        guard isEnabled else { return }

        guard !CurrentAppContext().isRunningTests else {
            DispatchQueue.global().async {
                self.workStep()
            }
            return
        }

        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            guard self.isSetup.get() else {
                return
            }
            DispatchQueue.global().async {
                self.workStep()
            }
        }
    }

    func workStep() {
        guard isEnabled else { return }

        guard isSetup.get() else {
            if !CurrentAppContext().isRunningTests {
                owsFailDebug("not setup")
            }

            return
        }

        databaseStorage.write { self.workStep(transaction: $0) }
    }

    func workStep(transaction: SDSAnyWriteTransaction) {
        let nextJob: JobRecordType?

        do {
            nextJob = try JobRecordFinderImpl(db: DependenciesBridge.shared.db).getNextReady(transaction: transaction.asV2Write)
        } catch let error {
            Logger.error("Couldn't start next job: \(error)")
            return
        }

        guard let nextJob else {
            return
        }

        do {
            try nextJob.saveReadyAsRunning(transaction: transaction)

            let operationQueue = operationQueue(jobRecord: nextJob)
            let durableOperation = try buildOperation(jobRecord: nextJob, transaction: transaction)

            durableOperation.durableOperationDelegate = self as? Self.DurableOperationType.DurableOperationDelegateType
            owsAssertDebug(durableOperation.durableOperationDelegate != nil)

            let remainingRetries = remainingRetries(durableOperation: durableOperation)
            durableOperation.remainingRetries = remainingRetries

            transaction.addSyncCompletion {
                self.runningOperations.append(durableOperation)
                operationQueue.addOperation(durableOperation.operation)
            }
        } catch JobError.permanentFailure(let description) {
            owsFailDebug("permanent failure: \(description)")
            nextJob.saveAsPermanentlyFailed(transaction: transaction)
        } catch JobError.obsolete(let description) {
            // TODO is this even worthwhile to have obsolete state? Should we just delete the task outright?
            nextJob.saveAsObsolete(transaction: transaction)
        } catch {
            owsFailDebug("unexpected error")
        }

        transaction.addAsyncCompletionOffMain { self.workStep() }
    }

    func restartOldJobs() {
        guard CurrentAppContext().isMainApp else { return }
        guard isEnabled else { return }

        databaseStorage.write { transaction in
            let runningRecords: [JobRecordType]
            do {
                runningRecords = try JobRecordFinderImpl(db: DependenciesBridge.shared.db).allRecords(
                    status: JobRecord.Status.running,
                    transaction: transaction.asV2Write
                )
            } catch {
                Logger.error("Couldn't restart old jobs: \(error)")
                return
            }
            Logger.info("marking old `running` \(JobRecordType.jobRecordType.jobRecordLabel) JobRecords as ready: \(runningRecords.count)")
            for jobRecord in runningRecords {
                do {
                    try jobRecord.saveRunningAsReady(transaction: transaction)
                    self.didMarkAsReady(oldJobRecord: jobRecord, transaction: transaction)
                } catch {
                    owsFailDebug("failed to mark old running records as ready error: \(error)")
                    jobRecord.saveAsPermanentlyFailed(transaction: transaction)
                }
            }
        }
    }

    func pruneStaleJobs() {
        guard CurrentAppContext().isMainApp else { return }
        guard isEnabled else { return }

        databaseStorage.write { transaction in
            let staleRecords: [JobRecordType]
            do {
                staleRecords = try JobRecordFinderImpl(db: DependenciesBridge.shared.db).staleRecords(transaction: transaction.asV2Write)
            } catch {
                Logger.error("Failed to prune stale jobs! \(error)")
                return
            }

            Logger.info("Pruning stale \(JobRecordType.jobRecordType.jobRecordLabel) job records: \(staleRecords.count).")

            for jobRecord in staleRecords {
                jobRecord.anyRemove(transaction: transaction)
            }
        }
    }

    /// Unless you need special handling, your setup method can be as simple as
    ///
    ///     func setup() {
    ///         defaultSetup()
    ///     }
    ///
    /// So you might ask, why not just rename this method to `setup`? Because
    /// `setup` is called from objc, and default implementations from a protocol
    /// cannot be marked as @objc.
    func defaultSetup() {
        guard isEnabled else { return }

        guard !isSetup.get() else {
            owsFailDebug("already ready already")
            return
        }

        DispatchQueue.global().async(.promise) {
            self.restartOldJobs()
            self.pruneStaleJobs()
        }.done { [weak self] in
            guard let self = self else {
                return
            }
            if self.requiresInternet {
                // FIXME: The returned observer token is never unregistered.
                // In practice all our JobQueues live forever, so this isn't a problem.
                NotificationCenter.default.addObserver(
                    forName: SSKReachability.owsReachabilityDidChange,
                    object: nil,
                    queue: nil
                ) { _ in
                    if self.reachabilityManager.isReachable {
                        self.becameReachable()
                    }
                }
            }

            self.isSetup.set(true)
            self.startWorkWhenAppIsReady()
        }
    }

    func remainingRetries(durableOperation: DurableOperationType) -> UInt {
        let maxRetries = durableOperation.maxRetries
        let failureCount = durableOperation.jobRecord.failureCount

        guard maxRetries > failureCount else {
            return 0
        }

        return maxRetries - failureCount
    }

    func becameReachable() {
        guard requiresInternet else {
            owsFailDebug("should only be called if `requiresInternet` is true")
            return
        }

        _ = self.runAnyQueuedRetry()
    }

    func runAnyQueuedRetry() -> DurableOperationType? {
        guard let runningDurableOperation = self.runningOperations.first else {
            return nil
        }
        runningDurableOperation.operation.runAnyQueuedRetry()

        return runningDurableOperation
    }

    // MARK: DurableOperationDelegate

    func durableOperationDidSucceed(_ operation: DurableOperationType, transaction: SDSAnyWriteTransaction) {
        runningOperations.remove(operation)
        operation.jobRecord.anyRemove(transaction: transaction)
    }

    func durableOperation(_ operation: DurableOperationType, didReportError: Error, transaction: SDSAnyWriteTransaction) {
        do {
            try operation.jobRecord.addFailure(transaction: transaction)
        } catch {
            owsFailDebug("error while addingFailure: \(error)")
            operation.jobRecord.saveAsPermanentlyFailed(transaction: transaction)
        }
    }

    func durableOperation(_ operation: DurableOperationType, didFailWithError error: Error, transaction: SDSAnyWriteTransaction) {
        runningOperations.remove(operation)
        operation.jobRecord.saveAsPermanentlyFailed(transaction: transaction)
    }
}

public protocol JobRecordFinder<JobRecordType> {
    associatedtype JobRecordType: JobRecord

    /// Fetches a single JobRecord from the database.
    ///
    /// Returns `nil` a JobRecord doesn't exist for `rowId`.
    func fetchJob(rowId: JobRecord.RowId, tx: DBReadTransaction) throws -> JobRecordType?

    /// Removes a single JobRecord from the database.
    func removeJob(_ jobRecord: JobRecordType, tx: DBWriteTransaction)

    /// Fetches all runnable jobs.
    ///
    /// This method may use multiple transactions, may use write transactions,
    /// may delete jobs that can't ever be run, etc.
    ///
    /// It returns all jobs that can be run.
    ///
    /// Conforming types should avoid long-running write transactions.
    func loadRunnableJobs() async throws -> [JobRecordType]

    func enumerateJobRecords(
        transaction: DBReadTransaction,
        block: (JobRecordType, inout Bool) -> Void
    ) throws

    func enumerateJobRecords(
        status: JobRecord.Status,
        transaction: DBReadTransaction,
        block: (JobRecordType, inout Bool) -> Void
    ) throws
}

public extension JobRecordFinder {
    func getNextReady(transaction: DBReadTransaction) throws -> JobRecordType? {
        var result: JobRecordType?
        try enumerateJobRecords(status: .ready, transaction: transaction) { jobRecord, stop in
            // Skip job records that aren't for the current process, we can't run these.
            guard jobRecord.canBeRunByCurrentProcess else {
                return
            }
            result = jobRecord
            stop = true
        }
        return result
    }

    func allRecords(status: JobRecord.Status, transaction: DBReadTransaction) throws -> [JobRecordType] {
        var result: [JobRecordType] = []
        try enumerateJobRecords(status: status, transaction: transaction) { jobRecord, _ in
            result.append(jobRecord)
        }
        return result
    }

    func staleRecords(transaction: DBReadTransaction) throws -> [JobRecordType] {
        var result: [JobRecordType] = []

        try enumerateJobRecords(transaction: transaction) { jobRecord, _ in
            let isStale: Bool = {
                switch jobRecord.status {
                case .running:
                    return false
                case .ready:
                    return !jobRecord.canBeRunByCurrentProcess
                case
                        .obsolete,
                        .permanentlyFailed,
                        .unknown:
                    return true
                }
            }()

            if isStale {
                result.append(jobRecord)
            }
        }

        return result
    }
}

private extension JobRecord {
    var canBeRunByCurrentProcess: Bool {
        if let exclusiveProcessIdentifier, exclusiveProcessIdentifier != JobRecord.currentProcessIdentifier {
            return false
        }
        return true
    }
}

private enum Constants {
    /// The number of JobRecords to fetch in a batch.
    ///
    /// Most job queues won't ever have more than a few records at the same
    /// time. Other times, a job queue may build up a huge backlog, and this
    /// value can help prune it efficiently.
    static let batchSize = 400
}

public class JobRecordFinderImpl<JobRecordType>: JobRecordFinder where JobRecordType: JobRecord {
    private let db: DB

    public init(db: DB) {
        self.db = db
    }

    private func iterateJobsWith(
        sql: String,
        arguments: StatementArguments,
        database: Database,
        block: (JobRecordType, inout Bool) -> Void
    ) throws {
        let cursor = try JobRecordType.fetchCursor(
            database,
            sql: sql,
            arguments: arguments
        )

        var stop = false
        while let nextJobRecord = try cursor.next() {
            block(nextJobRecord, &stop)

            if stop {
                return
            }
        }
    }

    public func enumerateJobRecords(
        transaction: DBReadTransaction,
        block: (JobRecordType, inout Bool) -> Void
    ) throws {
        let transaction = SDSDB.shimOnlyBridge(transaction)

        let sql = """
            SELECT * FROM \(JobRecord.databaseTableName)
            WHERE \(JobRecord.columnName(.label)) = ?
            ORDER BY \(JobRecord.columnName(.id))
        """

        try iterateJobsWith(
            sql: sql,
            arguments: [JobRecordType.jobRecordType.jobRecordLabel],
            database: transaction.unwrapGrdbRead.database,
            block: block
        )
    }

    public func enumerateJobRecords(
        status: JobRecord.Status,
        transaction: DBReadTransaction,
        block: (JobRecordType, inout Bool) -> Void
    ) throws {
        let transaction = SDSDB.shimOnlyBridge(transaction)

        let sql = """
            SELECT * FROM \(JobRecord.databaseTableName)
            WHERE \(JobRecord.columnName(.status)) = ?
              AND \(JobRecord.columnName(.label)) = ?
            ORDER BY \(JobRecord.columnName(.id))
        """

        try iterateJobsWith(
            sql: sql,
            arguments: [status.rawValue, JobRecordType.jobRecordType.jobRecordLabel],
            database: transaction.unwrapGrdbRead.database,
            block: block
        )
    }

    public func fetchJob(rowId: JobRecord.RowId, tx: DBReadTransaction) throws -> JobRecordType? {
        do {
            let db = SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database
            return try JobRecordType.fetchOne(db, key: rowId)
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    public func removeJob(_ jobRecord: JobRecordType, tx: DBWriteTransaction) {
        jobRecord.anyRemove(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func loadRunnableJobs() async throws -> [JobRecordType] {
        var allRunnableJobs = [JobRecordType]()
        var afterRowId: JobRecord.RowId?
        while true {
            let (runnableJobs, hasMoreAfterRowId) = try await db.awaitableWrite { tx in
                try self.fetchAndPruneSomePersistedJobs(afterRowId: afterRowId, tx: tx)
            }
            allRunnableJobs.append(contentsOf: runnableJobs)
            guard let hasMoreAfterRowId else {
                break
            }
            afterRowId = hasMoreAfterRowId
        }
        return allRunnableJobs
    }

    private func fetchAndPruneSomePersistedJobs(
        afterRowId: JobRecord.RowId?,
        tx: DBWriteTransaction
    ) throws -> ([JobRecordType], hasMoreAfterRowId: JobRecord.RowId?) {
        let (jobs, hasMore) = try fetchSomeJobs(afterRowId: afterRowId, tx: tx)
        var runnableJobs = [JobRecordType]()
        for job in jobs {
            let canRunJob: Bool = {
                // This property is deprecated. If it's set, it means the job was created
                // for a prior version of the application, and that version definitely
                // can't be the current process.
                guard job.exclusiveProcessIdentifier == nil else {
                    return false
                }
                // If a job has failed or is obsolete, we can remove it. We previously
                // distinguished `.ready` from `.running`, but now they're treated exactly
                // the same when we restart existing jobs.
                switch job.status {
                case .unknown, .permanentlyFailed, .obsolete:
                    return false
                case .ready, .running:
                    break
                }
                return true
            }()
            if canRunJob {
                runnableJobs.append(job)
            } else {
                removeJob(job, tx: tx)
            }
        }
        return (runnableJobs, hasMore ? jobs.last!.id! : nil)
    }

    private func fetchSomeJobs(
        afterRowId: JobRecord.RowId?,
        tx: DBReadTransaction
    ) throws -> ([JobRecordType], hasMore: Bool) {
        var sql = """
            SELECT * FROM \(JobRecordType.databaseTableName)
            WHERE "\(JobRecordType.columnName(.label))" = ?
        """
        var arguments: StatementArguments = [JobRecordType.jobRecordType.jobRecordLabel]
        if let afterRowId {
            sql += """
                AND \(JobRecordType.columnName(.id)) > ?
            """
            arguments += [afterRowId]
        }
        sql += """
            ORDER BY "\(JobRecordType.columnName(.id))"
            LIMIT \(Constants.batchSize)
        """
        do {
            let db = SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database
            let results = try JobRecordType.fetchAll(db, sql: sql, arguments: arguments)
            return (results, results.count == Constants.batchSize)
        } catch {
            throw error.grdbErrorForLogging
        }
    }
}
