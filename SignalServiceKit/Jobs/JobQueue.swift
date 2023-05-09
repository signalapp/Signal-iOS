//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

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
    var remainingRetries: UInt { get set }
}

public protocol DurableOperationDelegate: AnyObject {
    associatedtype DurableOperationType: DurableOperation

    func durableOperationDidSucceed(_ operation: DurableOperationType, transaction: SDSAnyWriteTransaction)
    func durableOperation(_ operation: DurableOperationType, didReportError: Error, transaction: SDSAnyWriteTransaction)
    func durableOperation(_ operation: DurableOperationType, didFailWithError error: Error, transaction: SDSAnyWriteTransaction)
}

public protocol JobQueue: DurableOperationDelegate, Dependencies {
    typealias DurableOperationDelegateType = Self
    typealias JobRecordType = DurableOperationType.JobRecordType

    var runningOperations: AtomicArray<DurableOperationType> { get set }
    var jobRecordLabel: String { get }

    var isSetup: AtomicBool { get set }
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
    static var maxRetries: UInt { get }

    var isEnabled: Bool { get }
}

// MARK: -

public extension JobQueue {

    // MARK: - Dependencies

    var finder: AnyJobRecordFinder<JobRecordType> {
        return AnyJobRecordFinder<JobRecordType>()
    }

    // MARK: Default Implementations

    func add(
        jobRecord: JobRecordType,
        transaction: SDSAnyWriteTransaction
    ) {
        owsAssertDebug(jobRecord.status == .ready)

        jobRecord.anyInsert(transaction: transaction)

        transaction.addTransactionFinalizationBlock(
            forKey: "jobQueue.\(jobRecordLabel).startWorkImmediatelyIfAppIsReady"
        ) { transaction in
            self.startWorkImmediatelyIfAppIsReady(transaction: transaction)
        }

        transaction.addAsyncCompletion(queue: .global()) {
            self.startWorkWhenAppIsReady()
        }
    }

    func hasPendingJobs(transaction: SDSAnyReadTransaction) -> Bool {
        do {
            return try finder.getNextReady(label: self.jobRecordLabel, transaction: transaction) != nil
        } catch let error {
            Logger.error("Couldn't fetch pending job: \(error)")
            return false
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
        Logger.debug("")

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
        let nextJob: JobRecordType
        switch Result(catching: { try finder.getNextReady(label: jobRecordLabel, transaction: transaction) }) {
        case .success(nil):
            Logger.verbose("nothing left to enqueue")
            return
        case .failure(let error):
            Logger.error("Couldn't start next job: \(error)")
            return
        case .success(.some(let someJob)):
            nextJob = someJob
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

                Logger.debug("adding operation: \(durableOperation) with remainingRetries: \(remainingRetries)")
                operationQueue.addOperation(durableOperation.operation)
            }
        } catch JobError.permanentFailure(let description) {
            owsFailDebug("permanent failure: \(description)")
            nextJob.saveAsPermanentlyFailed(transaction: transaction)
        } catch JobError.obsolete(let description) {
            // TODO is this even worthwhile to have obsolete state? Should we just delete the task outright?
            Logger.verbose("marking obsolete task as such. description:\(description)")
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
                runningRecords = try finder.allRecords(label: self.jobRecordLabel, status: .running, transaction: transaction)
            } catch {
                Logger.error("Couldn't restart old jobs: \(error)")
                return
            }
            Logger.info("marking old `running` \(self.jobRecordLabel) JobRecords as ready: \(runningRecords.count)")
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
                staleRecords = try finder.staleReadyRecords(label: self.jobRecordLabel, transaction: transaction)
            } catch {
                Logger.error("Couldn't prune stale jobs: \(error)")
                return
            }
            Logger.info("Pruning stale \(self.jobRecordLabel) JobRecords exclusively for previous process: \(staleRecords.count)")
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
                NotificationCenter.default.addObserver(forName: SSKReachability.owsReachabilityDidChange,
                                                       object: nil,
                                                       queue: nil) { _ in

                                                        if self.reachabilityManager.isReachable {
                                                            Logger.verbose("isReachable: true")
                                                            self.becameReachable()
                                                        } else {
                                                            Logger.verbose("isReachable: false")
                                                        }
                }
            }

            self.isSetup.set(true)
            self.startWorkWhenAppIsReady()
        }
    }

    func remainingRetries(durableOperation: DurableOperationType) -> UInt {
        let maxRetries = type(of: self).maxRetries
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

public protocol JobRecordFinder {
    associatedtype ReadTransaction
    associatedtype JobRecordType: JobRecord

    func getNextReady(label: String, transaction: ReadTransaction) throws -> JobRecordType?
    func allRecords(label: String, status: JobRecord.Status, transaction: ReadTransaction) throws -> [JobRecordType]
    func staleReadyRecords(label: String, transaction: ReadTransaction) throws -> [JobRecordType]
    func enumerateJobRecords(label: String, transaction: ReadTransaction, block: (JobRecordType, inout Bool) -> Void) throws
    func enumerateJobRecords(label: String, status: JobRecord.Status, transaction: ReadTransaction, block: (JobRecordType, inout Bool) -> Void) throws
}

extension JobRecordFinder {
    public func getNextReady(label: String, transaction: ReadTransaction) throws -> JobRecordType? {
        var result: JobRecordType?
        try enumerateJobRecords(label: label, status: .ready, transaction: transaction) { jobRecord, stop in
            // Skip job records that aren't for the current process, we can't run these.
            guard jobRecord.canBeRunByCurrentProcess else {
                return
            }
            result = jobRecord
            stop = true
        }
        return result
    }

    public func allRecords(label: String, status: JobRecord.Status, transaction: ReadTransaction) throws -> [JobRecordType] {
        var result: [JobRecordType] = []
        try enumerateJobRecords(label: label, status: status, transaction: transaction) { jobRecord, _ in
            result.append(jobRecord)
        }
        return result
    }

    public func staleReadyRecords(label: String, transaction: ReadTransaction) throws -> [JobRecordType] {
        var result: [JobRecordType] = []
        try enumerateJobRecords(label: label, status: .ready, transaction: transaction) { jobRecord, _ in
            guard !jobRecord.canBeRunByCurrentProcess else {
                return
            }
            result.append(jobRecord)
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

public class AnyJobRecordFinder<JobRecordType> where JobRecordType: JobRecord {
    lazy var grdbAdapter = GRDBJobRecordFinder<JobRecordType>()

    public init() {}
}

extension AnyJobRecordFinder: JobRecordFinder {
    public func enumerateJobRecords(label: String, transaction: SDSAnyReadTransaction, block: (JobRecordType, inout Bool) -> Void) throws {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            try grdbAdapter.enumerateJobRecords(label: label, transaction: grdbRead, block: block)
        }
    }

    public func enumerateJobRecords(label: String, status: JobRecord.Status, transaction: SDSAnyReadTransaction, block: (JobRecordType, inout Bool) -> Void) throws {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            try grdbAdapter.enumerateJobRecords(label: label, status: status, transaction: grdbRead, block: block)
        }
    }
}

class GRDBJobRecordFinder<JobRecordType> where JobRecordType: JobRecord {

}

extension GRDBJobRecordFinder: JobRecordFinder {
    private func iterateJobsWith(
        sql: String,
        arguments: StatementArguments,
        transaction: GRDBReadTransaction,
        block: (JobRecordType, inout Bool) -> Void
    ) throws {
        let cursor = try JobRecordType.fetchCursor(
            transaction.database,
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

    func enumerateJobRecords(
        label: String,
        transaction: GRDBReadTransaction,
        block: (JobRecordType, inout Bool) -> Void
    ) throws {
        let sql = """
            SELECT * FROM \(JobRecord.databaseTableName)
            WHERE \(JobRecord.columnName(.label)) = ?
            ORDER BY \(JobRecord.columnName(.id))
        """

        try iterateJobsWith(
            sql: sql,
            arguments: [label],
            transaction: transaction,
            block: block
        )
    }

    func enumerateJobRecords(
        label: String,
        status: JobRecord.Status,
        transaction: GRDBReadTransaction,
        block: (JobRecordType, inout Bool) -> Void
    ) throws {
        let sql = """
            SELECT * FROM \(JobRecord.databaseTableName)
            WHERE \(JobRecord.columnName(.status)) = ?
              AND \(JobRecord.columnName(.label)) = ?
            ORDER BY \(JobRecord.columnName(.id))
        """

        try iterateJobsWith(
            sql: sql,
            arguments: [status.rawValue, label],
            transaction: transaction,
            block: block
        )
    }
}
