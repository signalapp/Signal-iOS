//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit

@objc(OWSSessionResetJobQueue)
public class SessionResetJobQueue: NSObject, JobQueue {

    @objc(addContactThread:transaction:)
    public func add(contactThread: TSContactThread, transaction: YapDatabaseReadWriteTransaction) {
        let jobRecord = OWSSessionResetJobRecord(contactThread: contactThread, label: self.jobRecordLabel)
        self.add(jobRecord: jobRecord, transaction: transaction.asAnyWrite)
    }

    // MARK: JobQueue

    public typealias DurableOperationType = SessionResetOperation
    public let jobRecordLabel: String = "SessionReset"
    public static let maxRetries: UInt = 10
    public let requiresInternet: Bool = true
    public var runningOperations: [SessionResetOperation] = []

    @objc
    public override init() {
        super.init()

        AppReadiness.runNowOrWhenAppWillBecomeReady {
            self.setup()
        }
    }

    @objc
    public func setup() {
        defaultSetup()
    }

    public var isSetup: Bool = false

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
    var recipientId: String {
        return contactThread.contactIdentifier()
    }

    @objc public required init(contactThread: TSContactThread, jobRecord: OWSSessionResetJobRecord) {
        self.contactThread = contactThread
        self.jobRecord = jobRecord
    }

    // MARK: Dependencies

    var dbConnection: YapDatabaseConnection {
        return SSKEnvironment.shared.primaryStorage.dbReadWriteConnection
    }

    var sessionStore: SSKSessionStore {
        return SSKEnvironment.shared.sessionStore
    }

    var messageSender: MessageSender {
        return SSKEnvironment.shared.messageSender
    }

    // MARK: 

    var firstAttempt = true

    override public func run() {
        assert(self.durableOperationDelegate != nil)

        if firstAttempt {
            self.dbConnection.readWrite { transaction in
                Logger.info("deleting sessions for recipient: \(self.recipientId)")
                self.sessionStore.deleteAllSessions(forContact: self.recipientId, transaction: transaction.asAnyWrite)
            }
            firstAttempt = false
        }

        let endSessionMessage = EndSessionMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: self.contactThread)

        firstly {
            return self.messageSender.sendPromise(message: endSessionMessage)
        }.done {
            Logger.info("successfully sent EndSessionMessage.")
            self.dbConnection.readWrite { transaction in
                // Archive the just-created session since the recipient should delete their corresponding
                // session upon receiving and decrypting our EndSession message.
                // Otherwise if we send another message before them, they wont have the session to decrypt it.
                self.sessionStore.archiveAllSessions(forContact: self.recipientId, transaction: transaction.asAnyWrite)

                let message = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(),
                                            in: self.contactThread,
                                            messageType: TSInfoMessageType.typeSessionDidEnd)
                message.save(with: transaction)
            }
            self.reportSuccess()
        }.catch { error in
            Logger.error("sending error: \(error.localizedDescription)")
            self.reportError(error)
        }.retainUntilComplete()
    }

    override public func didSucceed() {
        self.dbConnection.readWrite { transaction in
            self.durableOperationDelegate?.durableOperationDidSucceed(self, transaction: transaction.asAnyWrite)
        }
    }

    override public func didReportError(_ error: Error) {
        Logger.debug("remainingRetries: \(self.remainingRetries)")

        self.dbConnection.readWrite { transaction in
            self.durableOperationDelegate?.durableOperation(self, didReportError: error, transaction: transaction.asAnyWrite)
        }
    }

    override public func retryInterval() -> TimeInterval {
        // Arbitrary backoff factor...
        // With backOffFactor of 1.9
        // try  1 delay:  0.00s
        // try  2 delay:  0.19s
        // ...
        // try  5 delay:  1.30s
        // ...
        // try 11 delay: 61.31s
        let backoffFactor = 1.9
        let maxBackoff = kHourInterval

        let seconds = 0.1 * min(maxBackoff, pow(backoffFactor, Double(self.jobRecord.failureCount)))

        return seconds
    }

    override public func didFail(error: Error) {
        Logger.error("failed to send EndSessionMessage with error: \(error.localizedDescription)")
        self.dbConnection.readWrite { transaction in
            self.durableOperationDelegate?.durableOperation(self, didFailWithError: error, transaction: transaction.asAnyWrite)

            // Even though this is the failure handler - which means probably the recipient didn't receive the message
            // there's a chance that our send did succeed and the server just timed out our repsonse or something.
            // Since the cost of sending a future message using a session the recipient doesn't have is so high,
            // we archive the session just in case.
            //
            // Archive the just-created session since the recipient should delete their corresponding
            // session upon receiving and decrypting our EndSession message.
            // Otherwise if we send another message before them, they wont have the session to decrypt it.
            self.sessionStore.archiveAllSessions(forContact: self.recipientId, transaction: transaction.asAnyWrite)
        }
    }
}
