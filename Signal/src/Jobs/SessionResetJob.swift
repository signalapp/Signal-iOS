//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit

@objc(OWSSessionResetJobQueue)
public class SessionResetJobQueue: NSObject, JobQueue {

    @objc(addContactThread:transaction:)
    public func add(contactThread: TSContactThread, transaction: SDSAnyWriteTransaction) {
        let jobRecord = OWSSessionResetJobRecord(contactThread: contactThread, label: self.jobRecordLabel)
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
    public var runningOperations = AtomicArray<SessionResetOperation>()

    @objc
    public override init() {
        super.init()

        AppReadiness.runNowOrWhenAppDidBecomeReady {
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
        operationQueue.name = "SessionReset.OperationQueue"
        return operationQueue
    }()

    public func operationQueue(jobRecord: OWSSessionResetJobRecord) -> OperationQueue {
        return self.operationQueue
    }

    public func buildOperation(jobRecord: OWSSessionResetJobRecord, transaction: SDSAnyReadTransaction) throws -> SessionResetOperation {
        guard let contactThread = TSThread.anyFetch(uniqueId: jobRecord.contactThreadId, transaction: transaction) as? TSContactThread else {
            throw JobError.obsolete(description: "thread for session reset no longer exists")
        }

        return SessionResetOperation(contactThread: contactThread, jobRecord: jobRecord)
    }
}

public class SessionResetOperation: OWSOperation, DurableOperation {

    // MARK: DurableOperation

    public let jobRecord: OWSSessionResetJobRecord

    weak public var durableOperationDelegate: SessionResetJobQueue?

    public var operation: OWSOperation {
        return self
    }

    // MARK: 

    let contactThread: TSContactThread
    var recipientAddress: SignalServiceAddress {
        return contactThread.contactAddress
    }

    @objc public required init(contactThread: TSContactThread, jobRecord: OWSSessionResetJobRecord) {
        self.contactThread = contactThread
        self.jobRecord = jobRecord
    }

    // MARK: Dependencies

    var sessionStore: SSKSessionStore {
        return SSKEnvironment.shared.sessionStore
    }

    var messageSender: MessageSender {
        return SSKEnvironment.shared.messageSender
    }

    var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: 

    var firstAttempt = true

    override public func run() {
        assert(self.durableOperationDelegate != nil)

        if firstAttempt {
            self.databaseStorage.write { transaction in
                Logger.info("archiving sessions for recipient: \(self.recipientAddress)")
                self.sessionStore.archiveAllSessions(for: self.recipientAddress, transaction: transaction)
            }
            firstAttempt = false
        }

        let endSessionMessage = EndSessionMessage(thread: self.contactThread)

        firstly {
            return self.messageSender.sendMessage(.promise, endSessionMessage.asPreparer)
        }.done {
            Logger.info("successfully sent EndSessionMessage.")
            self.databaseStorage.write { transaction in
                // Archive the just-created session since the recipient should delete their corresponding
                // session upon receiving and decrypting our EndSession message.
                // Otherwise if we send another message before them, they wont have the session to decrypt it.
                self.sessionStore.archiveAllSessions(for: self.recipientAddress, transaction: transaction)

                let message = TSInfoMessage(thread: self.contactThread,
                                            messageType: TSInfoMessageType.typeSessionDidEnd)
                message.anyInsert(transaction: transaction)
            }
            self.reportSuccess()
        }.catch { error in
            Logger.error("sending error: \(error.localizedDescription)")
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
        Logger.error("failed to send EndSessionMessage with error: \(error.localizedDescription)")
        self.databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperation(self, didFailWithError: error, transaction: transaction)

            // Even though this is the failure handler - which means probably the recipient didn't receive the message
            // there's a chance that our send did succeed and the server just timed out our repsonse or something.
            // Since the cost of sending a future message using a session the recipient doesn't have is so high,
            // we archive the session just in case.
            //
            // Archive the just-created session since the recipient should delete their corresponding
            // session upon receiving and decrypting our EndSession message.
            // Otherwise if we send another message before them, they wont have the session to decrypt it.
            self.sessionStore.archiveAllSessions(for: self.recipientAddress, transaction: transaction)
        }
    }
}
