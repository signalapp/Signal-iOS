//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

@objc(OWSSessionResetJobQueue)
public class SessionResetJobQueue: NSObject, JobQueue {

    @objc(addContactThread:transaction:)
    public func add(contactThread: TSContactThread, transaction: SDSAnyWriteTransaction) {
        let jobRecord = SessionResetJobRecord(contactThread: contactThread, label: self.jobRecordLabel)
        self.add(jobRecord: jobRecord, transaction: transaction)
    }

    // MARK: JobQueue

    public typealias DurableOperationType = SessionResetOperation
    @objc
    public static let jobRecordLabel: String = "SessionReset"
    public var jobRecordLabel: String {
        return type(of: self).jobRecordLabel
    }
    public static let maxRetries: UInt = 10
    public let requiresInternet: Bool = true
    public var isEnabled: Bool { CurrentAppContext().isMainApp }
    public var runningOperations = AtomicArray<SessionResetOperation>()

    @objc
    public override init() {
        super.init()

        AppReadiness.runNowOrWhenAppDidBecomeReadySync {
            self.setup()
        }
    }

    @objc
    public func setup() {
        defaultSetup()
    }

    public var isSetup = AtomicBool(false)

    public func didMarkAsReady(oldJobRecord: JobRecordType, transaction: SDSAnyWriteTransaction) {
        // no special handling
    }

    let operationQueue: OperationQueue = {
        // no need to serialize the operation queuing, since sending will ultimately be serialized by MessageSender
        let operationQueue = OperationQueue()
        operationQueue.name = "SessionResetJobQueue"
        return operationQueue
    }()

    public func operationQueue(jobRecord: SessionResetJobRecord) -> OperationQueue {
        return self.operationQueue
    }

    public func buildOperation(jobRecord: SessionResetJobRecord, transaction: SDSAnyReadTransaction) throws -> SessionResetOperation {
        guard let contactThread = TSThread.anyFetch(uniqueId: jobRecord.contactThreadId, transaction: transaction) as? TSContactThread else {
            throw JobError.obsolete(description: "thread for session reset no longer exists")
        }

        return SessionResetOperation(contactThread: contactThread, jobRecord: jobRecord)
    }
}

public class SessionResetOperation: OWSOperation, DurableOperation {

    // MARK: DurableOperation

    public let jobRecord: SessionResetJobRecord

    weak public var durableOperationDelegate: SessionResetJobQueue?

    public var operation: OWSOperation {
        return self
    }

    // MARK: 

    let contactThread: TSContactThread
    var recipientAddress: SignalServiceAddress {
        return contactThread.contactAddress
    }

    public required init(contactThread: TSContactThread, jobRecord: SessionResetJobRecord) {
        self.contactThread = contactThread
        self.jobRecord = jobRecord
    }

    // MARK: 

    var firstAttempt = true

    override public func run() {
        assert(self.durableOperationDelegate != nil)

        if firstAttempt {
            self.databaseStorage.write { transaction in
                Logger.info("archiving sessions for recipient: \(self.recipientAddress)")
                // PNI TODO: should this archive PNI sessions as well, or should that be a parameter of the job?
                // Do we ever need a SessionResetJob for a PNI session?
                self.signalProtocolStore(for: .aci).sessionStore.archiveAllSessions(for: self.recipientAddress,
                                                                                    transaction: transaction)
            }
            firstAttempt = false
        }

        firstly(on: DispatchQueue.global()) {
            self.databaseStorage.write { transaction -> Promise<Void> in
                let endSessionMessage = EndSessionMessage(thread: self.contactThread, transaction: transaction)

                return ThreadUtil.enqueueMessagePromise(
                    message: endSessionMessage,
                    isHighPriority: true,
                    transaction: transaction
                )
            }
        }.done(on: DispatchQueue.global()) {
            Logger.info("successfully sent EndSessionMessage.")
            self.databaseStorage.write { transaction in
                // Archive the just-created session since the recipient should delete their corresponding
                // session upon receiving and decrypting our EndSession message.
                // Otherwise if we send another message before them, they won't have the session to decrypt it.
                // PNI TODO: same as above
                self.signalProtocolStore(for: .aci).sessionStore.archiveAllSessions(for: self.recipientAddress,
                                                                                    transaction: transaction)

                let message = TSInfoMessage(thread: self.contactThread,
                                            messageType: TSInfoMessageType.typeSessionDidEnd)
                message.anyInsert(transaction: transaction)
            }
            self.reportSuccess()
        }.catch { error in
            Logger.error("sending error: \(error.userErrorDescription)")
            self.reportError(withUndefinedRetry: error)
        }
    }

    override public func didSucceed() {
        self.databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperationDidSucceed(self, transaction: transaction)
        }
    }

    override public func didReportError(_ error: Error) {
        Logger.debug("remainingRetries: \(self.remainingRetries)")

        self.databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperation(self, didReportError: error, transaction: transaction)
        }
    }

    override public func retryInterval() -> TimeInterval {
        return OWSOperation.retryIntervalForExponentialBackoff(failureCount: jobRecord.failureCount)
    }

    override public func didFail(error: Error) {
        Logger.error("failed to send EndSessionMessage with error: \(error.userErrorDescription)")
        self.databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperation(self, didFailWithError: error, transaction: transaction)

            // Even though this is the failure handler - which means probably the recipient didn't receive the message
            // there's a chance that our send did succeed and the server just timed out our response or something.
            // Since the cost of sending a future message using a session the recipient doesn't have is so high,
            // we archive the session just in case.
            //
            // Archive the just-created session since the recipient should delete their corresponding
            // session upon receiving and decrypting our EndSession message.
            // Otherwise if we send another message before them, they won't have the session to decrypt it.
            // PNI TODO: same as above
            self.signalProtocolStore(for: .aci).sessionStore.archiveAllSessions(for: self.recipientAddress,
                                                                                transaction: transaction)
        }
    }
}
