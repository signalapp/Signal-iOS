//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

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

extension SSKJobRecordStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .ready:
            return "ready"
        case .unknown:
            return "unknown"
        case .running:
            return "running"
        case .permanentlyFailed:
            return "permanentlyFailed"
        case .obsolete:
            return "obsolete"
        }
    }
}

public enum JobError: Error {
    case assertionFailure(description: String)
    case obsolete(description: String)
}

public protocol DurableOperation: class, Equatable {
    associatedtype JobRecordType: SSKJobRecord
    associatedtype DurableOperationDelegateType: DurableOperationDelegate

    var jobRecord: JobRecordType { get }
    var durableOperationDelegate: DurableOperationDelegateType? { get set }
    var operation: OWSOperation { get }
    var remainingRetries: UInt { get set }
}

public protocol DurableOperationDelegate: class {
    associatedtype DurableOperationType: DurableOperation

    func durableOperationDidSucceed(_ operation: DurableOperationType, transaction: SDSAnyWriteTransaction)
    func durableOperation(_ operation: DurableOperationType, didReportError: Error, transaction: SDSAnyWriteTransaction)
    func durableOperation(_ operation: DurableOperationType, didFailWithError error: Error, transaction: SDSAnyWriteTransaction)
}

public protocol JobQueue: DurableOperationDelegate {
    typealias DurableOperationDelegateType = Self
    typealias JobRecordType = DurableOperationType.JobRecordType

    // MARK: Dependencies

    var databaseStorage: SDSDatabaseStorage { get }
    var finder: AnyJobRecordFinder<JobRecordType> { get }

    // MARK: Default Implementations

    func add(jobRecord: JobRecordType, transaction: SDSAnyWriteTransaction)
    func restartOldJobs()
    func workStep()
    func defaultSetup()

    // MARK: Required

    var runningOperations: AtomicArray<DurableOperationType> { get set }
    var jobRecordLabel: String { get }

    var isSetup: AtomicBool { get set }
    func setup()
    func didMarkAsReady(oldJobRecord: JobRecordType, transaction: SDSAnyWriteTransaction)
    func didFlushQueue(transaction: SDSAnyWriteTransaction)

    func operationQueue(jobRecord: JobRecordType) -> OperationQueue
    func buildOperation(jobRecord: JobRecordType, transaction: SDSAnyReadTransaction) throws -> DurableOperationType

    /// When `requiresInternet` is true, we immediately run any jobs which are waiting for retry upon detecting Reachability.
    ///
    /// Because `Reachability` isn't 100% reliable, the jobs will be attempted regardless of what we think our current Reachability is.
    /// However, because these jobs will likely fail many times in succession, their `retryInterval` could be quite long by the time we
    /// are back online.
    var requiresInternet: Bool { get }
    static var maxRetries: UInt { get }
}

public extension JobQueue {

    // MARK: Dependencies

    var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    var finder: AnyJobRecordFinder<JobRecordType> {
        return AnyJobRecordFinder<JobRecordType>()
    }

    var reachabilityManager: SSKReachabilityManager {
        return SSKEnvironment.shared.reachabilityManager
    }

    // MARK: 

    func add(jobRecord: JobRecordType, transaction: SDSAnyWriteTransaction) {
        assert(jobRecord.status == .ready)

        jobRecord.anyInsert(transaction: transaction)

        transaction.addAsyncCompletion(queue: .global()) {
            self.startWorkWhenAppIsReady()
        }
    }

    func hasPendingJobs(transaction: SDSAnyReadTransaction) -> Bool {
        return nil != finder.getNextReady(label: self.jobRecordLabel, transaction: transaction)
    }

    func startWorkWhenAppIsReady() {
        guard !CurrentAppContext().isRunningTests else {
            DispatchQueue.global().async {
                self.workStep()
            }
            return
        }

        AppReadiness.runNowOrWhenAppDidBecomeReadyPolite {
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

        guard !DebugFlags.suppressBackgroundActivity else {
            // Don't process queues.
            return
        }

        guard isSetup.get() else {
            if !CurrentAppContext().isRunningTests {
                owsFailDebug("not setup")
            }

            return
        }

        self.databaseStorage.write { transaction in
            guard let nextJob: JobRecordType = self.finder.getNextReady(label: self.jobRecordLabel, transaction: transaction) else {
                Logger.verbose("nothing left to enqueue")
                self.didFlushQueue(transaction: transaction)
                return
            }

            do {
                try nextJob.saveAsStarted(transaction: transaction)

                let operationQueue = self.operationQueue(jobRecord: nextJob)
                let durableOperation = try self.buildOperation(jobRecord: nextJob, transaction: transaction)

                durableOperation.durableOperationDelegate = self as? Self.DurableOperationType.DurableOperationDelegateType
                assert(durableOperation.durableOperationDelegate != nil)

                let remainingRetries = self.remainingRetries(durableOperation: durableOperation)
                durableOperation.remainingRetries = remainingRetries

                self.runningOperations.append(durableOperation)

                Logger.debug("adding operation: \(durableOperation) with remainingRetries: \(remainingRetries)")
                operationQueue.addOperation(durableOperation.operation)
            } catch JobError.assertionFailure(let description) {
                owsFailDebug("assertion failure: \(description)")
                nextJob.saveAsPermanentlyFailed(transaction: transaction)
            } catch JobError.obsolete(let description) {
                // TODO is this even worthwhile to have obsolete state? Should we just delete the task outright?
                Logger.verbose("marking obsolete task as such. description:\(description)")
                nextJob.saveAsObsolete(transaction: transaction)
            } catch {
                owsFailDebug("unexpected error")
            }

            DispatchQueue.global().async {
                self.workStep()
            }
        }
    }

    func restartOldJobs() {
        guard !DebugFlags.suppressBackgroundActivity else {
            // Don't process queues.
            return
        }
        databaseStorage.write { transaction in
            let runningRecords = self.finder.allRecords(label: self.jobRecordLabel, status: .running, transaction: transaction)
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
        guard !isSetup.get() else {
            owsFailDebug("already ready already")
            return
        }

        DispatchQueue.global().async(.promise) {
            self.restartOldJobs()
        }.done { [weak self] in
            guard let self = self else {
                return
            }
            if self.requiresInternet {
                NotificationCenter.default.addObserver(forName: SSKReachability.owsReachabilityDidChange,
                                                       object: self.reachabilityManager.observationContext,
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

        notifyFlushQueueIfPossible(transaction: transaction)
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

        notifyFlushQueueIfPossible(transaction: transaction)
    }

    func notifyFlushQueueIfPossible(transaction: SDSAnyWriteTransaction) {
        guard nil == finder.getNextReady(label: jobRecordLabel, transaction: transaction) else {
            return
        }
        self.didFlushQueue(transaction: transaction)
    }

    func didFlushQueue(transaction: SDSAnyWriteTransaction) {
        // Do nothing.
    }
}

public protocol JobRecordFinder {
    associatedtype ReadTransaction
    associatedtype JobRecordType: SSKJobRecord

    func getNextReady(label: String, transaction: ReadTransaction) -> JobRecordType?
    func allRecords(label: String, status: SSKJobRecordStatus, transaction: ReadTransaction) -> [JobRecordType]
    func enumerateJobRecords(label: String, transaction: ReadTransaction, block: @escaping (JobRecordType, UnsafeMutablePointer<ObjCBool>) -> Void)
    func enumerateJobRecords(label: String, status: SSKJobRecordStatus, transaction: ReadTransaction, block: @escaping (JobRecordType, UnsafeMutablePointer<ObjCBool>) -> Void)
}

extension JobRecordFinder {
    public func getNextReady(label: String, transaction: ReadTransaction) -> JobRecordType? {
        var result: JobRecordType?
        self.enumerateJobRecords(label: label, status: .ready, transaction: transaction) { jobRecord, stopPointer in
            result = jobRecord
            stopPointer.pointee = true
        }
        return result
    }

    public func allRecords(label: String, status: SSKJobRecordStatus, transaction: ReadTransaction) -> [JobRecordType] {
        var result: [JobRecordType] = []
        self.enumerateJobRecords(label: label, status: status, transaction: transaction) { jobRecord, _ in
            result.append(jobRecord)
        }
        return result
    }
}

@objc
public class JobRecordFinderObjC: NSObject {
    private let jobRecordFinder = AnyJobRecordFinder<SSKJobRecord>()

    @objc
    public func enumerateJobRecords(label: String, transaction: SDSAnyReadTransaction, block: @escaping (SSKJobRecord, UnsafeMutablePointer<ObjCBool>) -> Void) {
        jobRecordFinder.enumerateJobRecords(label: label, transaction: transaction, block: block)
    }

    @objc
    public func enumerateJobRecords(label: String, status: SSKJobRecordStatus, transaction: SDSAnyReadTransaction, block: @escaping (SSKJobRecord, UnsafeMutablePointer<ObjCBool>) -> Void) {
        jobRecordFinder.enumerateJobRecords(label: label, status: status, transaction: transaction, block: block)
    }
}

public class AnyJobRecordFinder<JobRecordType> where JobRecordType: SSKJobRecord {
    lazy var grdbAdapter = GRDBJobRecordFinder<JobRecordType>()
    lazy var yapAdapter = YAPDBJobRecordFinder<JobRecordType>()

    public init() {}
}

extension AnyJobRecordFinder: JobRecordFinder {
    public func enumerateJobRecords(label: String, transaction: SDSAnyReadTransaction, block: @escaping (JobRecordType, UnsafeMutablePointer<ObjCBool>) -> Void) {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            grdbAdapter.enumerateJobRecords(label: label, transaction: grdbRead, block: block)
        case .yapRead(let yapRead):
            yapAdapter.enumerateJobRecords(label: label, transaction: yapRead, block: block)
        }
    }

    public func enumerateJobRecords(label: String, status: SSKJobRecordStatus, transaction: SDSAnyReadTransaction, block: @escaping (JobRecordType, UnsafeMutablePointer<ObjCBool>) -> Void) {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            grdbAdapter.enumerateJobRecords(label: label, status: status, transaction: grdbRead, block: block)
        case .yapRead(let yapRead):
            yapAdapter.enumerateJobRecords(label: label, status: status, transaction: yapRead, block: block)
        }
    }
}

class GRDBJobRecordFinder<JobRecordType> where JobRecordType: SSKJobRecord {

}

extension GRDBJobRecordFinder: JobRecordFinder {
    func enumerateJobRecords(label: String, transaction: GRDBReadTransaction, block: @escaping (JobRecordType, UnsafeMutablePointer<ObjCBool>) -> Void) {

        let sql = """
        SELECT * FROM \(JobRecordRecord.databaseTableName)
        WHERE \(jobRecordColumn: .label) = ?
        ORDER BY \(jobRecordColumn: .id)
        """

        let cursor = JobRecordType.grdbFetchCursor(sql: sql,
                                                   arguments: [label],
                                                   transaction: transaction)
        var stop: ObjCBool = false
        // GRDB TODO make cursor.next fail hard to remove this `try!`
        while let next = try! cursor.next() {
            guard let jobRecord = next as? JobRecordType else {
                owsFailDebug("expecting jobRecord but found: \(next)")
                return
            }
            block(jobRecord, &stop)
            if stop.boolValue {
                return
            }
        }
    }

    func enumerateJobRecords(label: String, status: SSKJobRecordStatus, transaction: GRDBReadTransaction, block: @escaping (JobRecordType, UnsafeMutablePointer<ObjCBool>) -> Void) {

        let sql = """
            SELECT * FROM \(JobRecordRecord.databaseTableName)
            WHERE \(jobRecordColumn: .status) = ?
              AND \(jobRecordColumn: .label) = ?
            ORDER BY \(jobRecordColumn: .id)
        """

        let cursor = JobRecordType.grdbFetchCursor(sql: sql,
                                                   arguments: [status.rawValue, label],
                                                   transaction: transaction)
        var stop: ObjCBool = false
        // GRDB TODO make cursor.next fail hard to remove this `try!`
        while let next = try! cursor.next() {
            guard let jobRecord = next as? JobRecordType else {
                owsFailDebug("expecting jobRecord but found: \(next)")
                return
            }
            block(jobRecord, &stop)
            if stop.boolValue {
                return
            }
        }
    }
}

@objc
public class YAPDBJobRecordFinderSetup: NSObject {
    @objc
    public class func asyncRegisterDatabaseExtensionObjC(storage: OWSStorage) {
        YAPDBJobRecordFinder.asyncRegisterDatabaseExtension(storage: storage)
    }
}

public class YAPDBJobRecordFinder<JobRecordType> where JobRecordType: SSKJobRecord {
    public static var dbExtensionName: String {
        return "SecondaryIndexJobRecord"
    }

    func ext(transaction: YapDatabaseReadTransaction) -> YapDatabaseSecondaryIndexTransaction? {
        return transaction.safeSecondaryIndexTransaction(type(of: self).dbExtensionName)
    }

    static func asyncRegisterDatabaseExtension(storage: OWSStorage) {
        storage.asyncRegister(dbExtensionConfig, withName: dbExtensionName)
    }

    enum JobRecordField: String {
        case status, label, sortId
    }

    static var dbExtensionConfig: YapDatabaseSecondaryIndex {
        let setup = YapDatabaseSecondaryIndexSetup()
        setup.addColumn(JobRecordField.sortId.rawValue, with: .integer)
        setup.addColumn(JobRecordField.status.rawValue, with: .integer)
        setup.addColumn(JobRecordField.label.rawValue, with: .text)

        let block: YapDatabaseSecondaryIndexWithObjectBlock = { transaction, dict, collection, key, object in
            guard let jobRecord = object as? SSKJobRecord else {
                return
            }

            dict[JobRecordField.sortId.rawValue] = jobRecord.sortId
            dict[JobRecordField.status.rawValue] = jobRecord.status.rawValue
            dict[JobRecordField.label.rawValue] = jobRecord.label
        }

        let handler = YapDatabaseSecondaryIndexHandler.withObjectBlock(block)

        let options = YapDatabaseSecondaryIndexOptions()
        let whitelist = YapWhitelistBlacklist(whitelist: Set([SSKJobRecord.collection()]))
        options.allowedCollections = whitelist

        return YapDatabaseSecondaryIndex.init(setup: setup, handler: handler, versionTag: "2", options: options)
    }
}

extension YAPDBJobRecordFinder: JobRecordFinder {
    public func enumerateJobRecords(label: String, transaction: YapDatabaseReadTransaction, block: @escaping (JobRecordType, UnsafeMutablePointer<ObjCBool>) -> Void) {
        let queryFormat = String(format: "WHERE %@ = ? ORDER BY %@", JobRecordField.label.rawValue, JobRecordField.sortId.rawValue)
        let query = YapDatabaseQuery(string: queryFormat, parameters: [label])

        guard let ext = self.ext(transaction: transaction) else {
            return
        }
        ext.enumerateKeysAndObjects(matching: query) { _, _, object, stopPointer in
            guard let jobRecord = object as? JobRecordType else {
                owsFailDebug("expecting jobRecord but found: \(object)")
                return
            }
            block(jobRecord, stopPointer)
        }
    }

    public func enumerateJobRecords(label: String, status: SSKJobRecordStatus, transaction: YapDatabaseReadTransaction, block: @escaping (JobRecordType, UnsafeMutablePointer<ObjCBool>) -> Void) {
        let queryFormat = String(format: "WHERE %@ = ? AND %@ = ? ORDER BY %@", JobRecordField.status.rawValue, JobRecordField.label.rawValue, JobRecordField.sortId.rawValue)
        let query = YapDatabaseQuery(string: queryFormat, parameters: [status.rawValue, label])

        guard let ext = self.ext(transaction: transaction) else {
            return
        }
        ext.enumerateKeysAndObjects(matching: query) { _, _, object, stopPointer in
            guard let jobRecord = object as? JobRecordType else {
                owsFailDebug("expecting jobRecord but found: \(object)")
                return
            }
            block(jobRecord, stopPointer)
        }
    }
}
