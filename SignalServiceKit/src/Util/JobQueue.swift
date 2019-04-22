//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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

public extension Error {
    var isRetryable: Bool {
        get {
            return (self as NSError).isRetryable
        }
        set {
            (self as NSError).isRetryable = newValue
        }
    }
}

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

public protocol DurableOperation: class {
    associatedtype JobRecordType: SSKJobRecord
    associatedtype DurableOperationDelegateType: DurableOperationDelegate

    var jobRecord: JobRecordType { get }
    var durableOperationDelegate: DurableOperationDelegateType? { get set }
    var operation: OWSOperation { get }
    var remainingRetries: UInt { get set }
}

public protocol DurableOperationDelegate: class {
    associatedtype DurableOperationType: DurableOperation

    func durableOperationDidSucceed(_ operation: DurableOperationType, transaction: YapDatabaseReadWriteTransaction)
    func durableOperation(_ operation: DurableOperationType, didReportError: Error, transaction: YapDatabaseReadWriteTransaction)
    func durableOperation(_ operation: DurableOperationType, didFailWithError error: Error, transaction: YapDatabaseReadWriteTransaction)
}

public protocol JobQueue: DurableOperationDelegate {
    typealias DurableOperationDelegateType = Self
    typealias JobRecordType = DurableOperationType.JobRecordType

    // MARK: Dependencies

    var dbConnection: YapDatabaseConnection { get }
    var finder: JobRecordFinder { get }

    // MARK: Default Implementations

    func add(jobRecord: JobRecordType, transaction: YapDatabaseReadWriteTransaction)
    func restartOldJobs()
    func workStep()
    func defaultSetup()

    // MARK: Required

    var runningOperations: [DurableOperationType] { get set }
    var jobRecordLabel: String { get }

    var isSetup: Bool { get set }
    func setup()
    func didMarkAsReady(oldJobRecord: JobRecordType, transaction: YapDatabaseReadWriteTransaction)

    func operationQueue(jobRecord: JobRecordType) -> OperationQueue
    func buildOperation(jobRecord: JobRecordType, transaction: YapDatabaseReadTransaction) throws -> DurableOperationType

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

    var dbConnection: YapDatabaseConnection {
        return SSKEnvironment.shared.primaryStorage.dbReadWriteConnection
    }

    var finder: JobRecordFinder {
        return JobRecordFinder()
    }

    var reachabilityManager: SSKReachabilityManager {
        return SSKEnvironment.shared.reachabilityManager
    }

    // MARK: 

    func add(jobRecord: JobRecordType, transaction: YapDatabaseReadWriteTransaction) {
        assert(jobRecord.status == .ready)

        jobRecord.save(with: transaction)

        transaction.addCompletionQueue(.global()) {
            self.startWorkWhenAppIsReady()
        }
    }

    func startWorkWhenAppIsReady() {
        guard !CurrentAppContext().isRunningTests else {
            DispatchQueue.global().async {
                self.workStep()
            }
            return
        }

        AppReadiness.runNowOrWhenAppDidBecomeReady {
            DispatchQueue.global().async {
                self.workStep()
            }
        }
    }

    func workStep() {
        Logger.debug("")

        guard isSetup else {
            if !CurrentAppContext().isRunningTests {
                owsFailDebug("not setup")
            }

            return
        }

        self.dbConnection.readWrite { transaction in
            guard let nextJob: JobRecordType = self.finder.getNextReady(label: self.jobRecordLabel, transaction: transaction) as? JobRecordType else {
                Logger.verbose("nothing left to enqueue")
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

    public func restartOldJobs() {
        self.dbConnection.readWrite { transaction in
            let runningRecords = self.finder.allRecords(label: self.jobRecordLabel, status: .running, transaction: transaction)
            Logger.info("marking old `running` JobRecords as ready: \(runningRecords.count)")
            for record in runningRecords {
                guard let jobRecord = record as? JobRecordType else {
                    owsFailDebug("unexpectred jobRecord: \(record)")
                    continue
                }
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
        guard !isSetup else {
            owsFailDebug("already ready already")
            return
        }
        self.restartOldJobs()

        if self.requiresInternet {
            NotificationCenter.default.addObserver(forName: .reachabilityChanged,
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

        self.isSetup = true

        self.startWorkWhenAppIsReady()
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

    func durableOperationDidSucceed(_ operation: DurableOperationType, transaction: YapDatabaseReadWriteTransaction) {
        self.runningOperations = self.runningOperations.filter { $0 !== operation }
        operation.jobRecord.remove(with: transaction)
    }

    func durableOperation(_ operation: DurableOperationType, didReportError: Error, transaction: YapDatabaseReadWriteTransaction) {
        do {
            try operation.jobRecord.addFailure(transaction: transaction)
        } catch {
            owsFailDebug("error while addingFailure: \(error)")
            operation.jobRecord.saveAsPermanentlyFailed(transaction: transaction)
        }
    }

    func durableOperation(_ operation: DurableOperationType, didFailWithError error: Error, transaction: YapDatabaseReadWriteTransaction) {
        self.runningOperations = self.runningOperations.filter { $0 !== operation }
        operation.jobRecord.saveAsPermanentlyFailed(transaction: transaction)
    }
}

@objc(SSKJobRecordFinder)
public class JobRecordFinder: NSObject, Finder {

    typealias ExtensionType = YapDatabaseSecondaryIndex
    typealias TransactionType = YapDatabaseSecondaryIndexTransaction

    enum JobRecordField: String {
        case status, label, sortId
    }

    func getNextReady(label: String, transaction: YapDatabaseReadTransaction) -> SSKJobRecord? {
        var result: SSKJobRecord?
        self.enumerateJobRecords(label: label, status: .ready, transaction: transaction) { jobRecord, stopPointer in
            result = jobRecord
            stopPointer.pointee = true
        }
        return result
    }

    func allRecords(label: String, status: SSKJobRecordStatus, transaction: YapDatabaseReadTransaction) -> [SSKJobRecord] {
        var result: [SSKJobRecord] = []
        self.enumerateJobRecords(label: label, status: status, transaction: transaction) { jobRecord, _ in
            result.append(jobRecord)
        }
        return result
    }

    func enumerateJobRecords(label: String, status: SSKJobRecordStatus, transaction: YapDatabaseReadTransaction, block: @escaping (SSKJobRecord, UnsafeMutablePointer<ObjCBool>) -> Void) {
        let queryFormat = String(format: "WHERE %@ = ? AND %@ = ? ORDER BY %@", JobRecordField.status.rawValue, JobRecordField.label.rawValue, JobRecordField.sortId.rawValue)
        let query = YapDatabaseQuery(string: queryFormat, parameters: [status.rawValue, label])

        self.ext(transaction: transaction).enumerateKeysAndObjects(matching: query) { _, _, object, stopPointer in
            guard let jobRecord = object as? SSKJobRecord else {
                owsFailDebug("expecting jobRecord but found: \(object)")
                return
            }
            block(jobRecord, stopPointer)
        }
    }

    static var dbExtensionName: String {
        return "SecondaryIndexJobRecord"
    }

    @objc
    public class func asyncRegisterDatabaseExtensionObjC(storage: OWSStorage) {
        asyncRegisterDatabaseExtension(storage: storage)
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

protocol Finder {
    associatedtype ExtensionType: YapDatabaseExtension
    associatedtype TransactionType: YapDatabaseExtensionTransaction

    static var dbExtensionName: String { get }
    static var dbExtensionConfig: ExtensionType { get }

    func ext(transaction: YapDatabaseReadTransaction) -> TransactionType

    static func asyncRegisterDatabaseExtension(storage: OWSStorage)
    static func testingOnly_ensureDatabaseExtensionRegistered(storage: OWSStorage)
}

extension Finder {

    func ext(transaction: YapDatabaseReadTransaction) -> TransactionType {
        return transaction.ext(type(of: self).dbExtensionName) as! TransactionType
    }

    static func asyncRegisterDatabaseExtension(storage: OWSStorage) {
        storage.asyncRegister(dbExtensionConfig, withName: dbExtensionName)
    }

    // Only for testing.
    static func testingOnly_ensureDatabaseExtensionRegistered(storage: OWSStorage) {
        guard storage.registeredExtension(dbExtensionName) == nil else {
            return
        }

        storage.register(dbExtensionConfig, withName: dbExtensionName)
    }
}
