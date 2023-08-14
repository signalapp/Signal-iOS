//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

public final class LocalUserLeaveGroupOperation: OWSOperation, DurableOperation {
    public typealias JobRecordType = LocalUserLeaveGroupJobRecord
    public typealias DurableOperationDelegateType = LocalUserLeaveGroupJobQueue

    public let jobRecord: JobRecordType
    public weak var durableOperationDelegate: DurableOperationDelegateType?

    public var operation: OWSOperation { self }

    private var groupThreadAfterSuccessfulUpdate: TSGroupThread?
    private let future: Future<TSGroupThread>?

    fileprivate init(
        jobRecord: LocalUserLeaveGroupJobRecord,
        future: Future<TSGroupThread>?
    ) {
        self.jobRecord = jobRecord
        self.future = future
    }

    public override func run() {
        firstly(on: DispatchQueue.global()) { () throws -> Promise<Void> in
            guard self.jobRecord.waitForMessageProcessing else {
                return Promise.value(())
            }

            let groupModel = try self.getGroupModelWithSneakyTransaction()

            return GroupManager.messageProcessingPromise(
                for: groupModel,
                description: "Leave group or decline invite"
            )
        }.then { () throws -> Promise<TSGroupThread> in
            // Read the group model again from the DB to ensure we have the
            // latest before we try and update the group
            let groupModel = try self.getGroupModelWithSneakyTransaction()

            let replacementAdminAci: Aci? = try self.jobRecord.replacementAdminAciString.map { aciString in
                guard let aci = Aci.parseFrom(aciString: aciString) else {
                    throw OWSAssertionError("Unable to convert replacement admin UUID string to UUID")
                }
                return aci
            }

            return GroupManager.updateGroupV2(
                groupModel: groupModel,
                description: "Leave group or decline invite"
            ) { groupChangeSet in
                groupChangeSet.setShouldLeaveGroupDeclineInvite()

                // Sometimes when we leave a group we take care to assign a new admin.
                if let replacementAdminAci {
                    groupChangeSet.changeRoleForMember(replacementAdminAci, role: .administrator)
                }
            }
        }.map { groupThread in
            self.groupThreadAfterSuccessfulUpdate = groupThread
            self.reportSuccess()
        }.catch { error in
            self.reportError(withUndefinedRetry: error)
        }
    }

    public override func didSucceed() {
        Logger.info("Succeeded!")

        databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperationDidSucceed(self, transaction: transaction)
        }

        guard let groupThread = groupThreadAfterSuccessfulUpdate else {
            owsFailDebug("Unexpectedly missing group thread")
            future?.reject(OWSAssertionError("Unexpectedly missing group thread"))
            return
        }

        future?.resolve(groupThread)
    }

    public override func didReportError(_ error: Error) {
        Logger.warn("Reported error: \(error). Remaining retries: \(remainingRetries)")

        databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperation(self, didReportError: error, transaction: transaction)
        }
    }

    public override func didFail(error: Error) {
        Logger.error("Failed with error: \(error)")

        databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperation(self, didFailWithError: error, transaction: transaction)
        }

        future?.reject(error)
    }

    public override func retryInterval() -> TimeInterval {
        OWSOperation.retryIntervalForExponentialBackoff(failureCount: jobRecord.failureCount)
    }

    private func getGroupModelWithSneakyTransaction() throws -> TSGroupModelV2 {
        guard
            let groupThread = self.databaseStorage.read(block: { transaction in
                TSGroupThread.anyFetchGroupThread(
                    uniqueId: self.jobRecord.threadId,
                    transaction: transaction
                )
            }),
            let groupModel = groupThread.groupModel as? TSGroupModelV2
        else {
            throw OWSAssertionError("Missing V2 group thread for operation")
        }

        return groupModel
    }
}

@objc
public class LocalUserLeaveGroupJobQueue: NSObject, JobQueue {
    public typealias DurableOperationType = LocalUserLeaveGroupOperation

    /// 110 retries corresponds to approximately ~24hr of retry when using
    /// `OWSOperation.retryIntervalForExponentialBackoff(failureCount:)`.
    public static var maxRetries: UInt { 110 }

    public var runningOperations = AtomicArray<LocalUserLeaveGroupOperation>()
    public var isSetup = AtomicBool(false)

    public var requiresInternet: Bool { true }
    public var isEnabled: Bool { true }
    public var jobRecordLabel: String { "LocalUserLeaveGroup" }

    private let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "LocalUserLeaveGroupJobQueue"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private var jobFutures = AtomicDictionary<String, Future<TSGroupThread>>()

    public override init() {
        super.init()

        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            self.setup()
        }
    }

    public func setup() {
        defaultSetup()
    }

    public func buildOperation(jobRecord: JobRecordType, transaction _: SDSAnyReadTransaction) throws -> DurableOperationType {
        LocalUserLeaveGroupOperation(
            jobRecord: jobRecord,
            future: jobFutures.pop(jobRecord.uniqueId)
        )
    }

    public func operationQueue(jobRecord: JobRecordType) -> OperationQueue {
        operationQueue
    }

    public func didMarkAsReady(oldJobRecord: JobRecordType, transaction: SDSAnyWriteTransaction) {
        // No special handling
    }

    // MARK: - Promises

    public func add(
        threadId: String,
        replacementAdminAci: Aci?,
        waitForMessageProcessing: Bool,
        transaction: SDSAnyWriteTransaction
    ) -> Promise<TSGroupThread> {
        Promise { future in
            self.add(
                threadId: threadId,
                replacementAdminAci: replacementAdminAci,
                waitForMessageProcessing: waitForMessageProcessing,
                future: future,
                transaction: transaction
            )
        }
    }

    private func add(
        threadId: String,
        replacementAdminAci: Aci?,
        waitForMessageProcessing: Bool,
        future: Future<TSGroupThread>,
        transaction: SDSAnyWriteTransaction
    ) {
        let jobRecord = LocalUserLeaveGroupJobRecord(
            threadId: threadId,
            replacementAdminAci: replacementAdminAci,
            waitForMessageProcessing: waitForMessageProcessing,
            label: jobRecordLabel
        )

        self.add(jobRecord: jobRecord, transaction: transaction)
        jobFutures[jobRecord.uniqueId] = future
    }
}
