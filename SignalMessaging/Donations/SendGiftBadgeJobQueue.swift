//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB
import SignalServiceKit
import LibSignalClient

// MARK: - Job queue

public class SendGiftBadgeJobQueue: NSObject, JobQueue {
    public typealias DurableOperationType = SendGiftBadgeOperation

    @objc
    public static let jobRecordLabel: String = "SendGiftBadge"
    public var jobRecordLabel: String { Self.jobRecordLabel }

    public static let maxRetries: UInt = 110
    public let requiresInternet: Bool = true
    public var isEnabled: Bool { CurrentAppContext().isMainApp }
    public var runningOperations = AtomicArray<SendGiftBadgeOperation>()
    public var isSetup = AtomicBool(false)

    public enum JobEvent: Int {
        case chargeSucceeded
        case jobFailed
        case jobSucceeded
    }

    public static let JobEventNotification = NSNotification.Name("SendGiftBadgeJobQueueJobEventNotification")

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

    public func didMarkAsReady(oldJobRecord: JobRecordType, transaction: SDSAnyWriteTransaction) {
        // no special handling
    }

    let operationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "SendGiftBadge.OperationQueue"
        return operationQueue
    }()

    public func operationQueue(jobRecord: OWSSendGiftBadgeJobRecord) -> OperationQueue {
        return self.operationQueue
    }

    public func buildOperation(jobRecord: OWSSendGiftBadgeJobRecord, transaction: SDSAnyReadTransaction) throws -> SendGiftBadgeOperation {
        return try SendGiftBadgeOperation(jobRecord)
    }

    public static func createJob(receiptRequest: (context: ReceiptCredentialRequestContext, request: ReceiptCredentialRequest),
                                 amount: UInt,
                                 currencyCode: Currency.Code,
                                 paymentIntent: Stripe.PaymentIntent,
                                 paymentMethodId: String,
                                 thread: TSContactThread,
                                 messageText: String) -> OWSSendGiftBadgeJobRecord {
        OWSSendGiftBadgeJobRecord(
            receiptCredentialRequestContext: receiptRequest.context.serialize().asData,
            receiptCredentialRequest: receiptRequest.request.serialize().asData,
            amount: NSDecimalNumber(value: amount),
            currencyCode: currencyCode,
            paymentIntentClientSecret: paymentIntent.clientSecret,
            paymentIntentId: paymentIntent.id,
            paymentMethodId: paymentMethodId,
            threadId: thread.uniqueId,
            messageText: messageText,
            label: self.jobRecordLabel
        )
    }

    public func addJob(_ jobRecord: OWSSendGiftBadgeJobRecord, transaction: SDSAnyWriteTransaction) {
        Logger.info("[Gifting] Adding a \"send gift badge\" job")
        self.add(jobRecord: jobRecord, transaction: transaction)
    }

    public func alreadyHasJob(for thread: TSContactThread, transaction: SDSAnyReadTransaction) -> Bool {
        SendGiftBadgeJobFinder.jobExists(forThreadId: thread.uniqueId, transaction: transaction)
    }
}

// MARK: - Job finder

private class SendGiftBadgeJobFinder {
    public class func jobExists(forThreadId threadId: String, transaction: SDSAnyReadTransaction) -> Bool {
        assert(!threadId.isEmpty)

        switch transaction.readTransaction {
        case .grdbRead(let grdbTransaction):
            let sql = """
                SELECT EXISTS (
                    SELECT 1 FROM \(JobRecordRecord.databaseTableName)
                    WHERE \(jobRecordColumn: .threadId) IS ?
                    AND \(jobRecordColumn: .recordType) IS ?
                    AND \(jobRecordColumn: .status) NOT IN (?, ?)
                )
            """
            let arguments: StatementArguments = [
                threadId,
                SDSRecordType.sendGiftBadgeJobRecord.rawValue,
                SSKJobRecordStatus.permanentlyFailed,
                SSKJobRecordStatus.obsolete
            ]
            return try! Bool.fetchOne(grdbTransaction.database, sql: sql, arguments: arguments) ?? false
        }
    }
}

// MARK: - Operation

public final class SendGiftBadgeOperation: OWSOperation, DurableOperation {
    public var jobRecord: OWSSendGiftBadgeJobRecord

    public typealias JobRecordType = OWSSendGiftBadgeJobRecord

    public typealias DurableOperationDelegateType = SendGiftBadgeJobQueue

    weak public var durableOperationDelegate: SendGiftBadgeJobQueue?

    public var operation: OWSOperation { self }

    private let receiptCredentialRequestContext: ReceiptCredentialRequestContext
    private let receiptCredentialRequest: ReceiptCredentialRequest
    private let amount: Decimal
    private let currencyCode: Currency.Code
    private let paymentIntentClientSecret: String
    private let paymentIntentId: String
    private let paymentMethodId: String
    private let threadId: String
    private let messageText: String

    @objc
    public required init(_ jobRecord: OWSSendGiftBadgeJobRecord) throws {
        self.jobRecord = jobRecord
        receiptCredentialRequestContext = try ReceiptCredentialRequestContext(contents: [UInt8](jobRecord.receiptCredentailRequestContext))
        receiptCredentialRequest = try ReceiptCredentialRequest(contents: [UInt8](jobRecord.receiptCredentailRequest))
        amount = jobRecord.amount as Decimal
        currencyCode = jobRecord.currencyCode
        paymentIntentClientSecret = jobRecord.paymentIntentClientSecret
        paymentIntentId = jobRecord.boostPaymentIntentID
        paymentMethodId = jobRecord.paymentMethodId
        threadId = jobRecord.threadId
        messageText = jobRecord.messageText
    }

    private func getValidatedThread(transaction: SDSAnyReadTransaction) throws -> TSContactThread {
        guard let thread = TSThread.anyFetch(uniqueId: threadId, transaction: transaction) as? TSContactThread else {
            throw JobError.obsolete(description: "Thread for gift badge sending no longer exists")
        }
        guard !blockingManager.isThreadBlocked(thread, transaction: transaction) else {
            throw JobError.obsolete(description: "Thread for gift badge sending is blocked")
        }
        return thread
    }

    private func ensureThatWeCanStillMessageRecipient(transaction: SDSAnyReadTransaction) throws {
        _ = try getValidatedThread(transaction: transaction)
    }

    private func postJobEventNotification(_ jobEvent: SendGiftBadgeJobQueue.JobEvent) {
        NotificationCenter.default.postNotificationNameAsync(
            SendGiftBadgeJobQueue.JobEventNotification,
            object: nil,
            userInfo: ["jobId": jobRecord.uniqueId, "jobEvent": jobEvent.rawValue]
        )
    }

    private func confirmPaymentIntent() throws -> Promise<Void> {
        try Stripe.confirmPaymentIntent(paymentIntentClientSecret: self.paymentIntentClientSecret,
                                        paymentIntentId: self.paymentIntentId,
                                        paymentMethodId: self.paymentMethodId,
                                        idempotencyKey: self.jobRecord.uniqueId).asVoid()
    }

    private func getReceiptCredentialPresentation() throws -> Promise<ReceiptCredentialPresentation> {
        try SubscriptionManager.requestBoostReceiptCredentialPresentation(
            for: self.paymentIntentId,
            context: self.receiptCredentialRequestContext,
            request: self.receiptCredentialRequest,
            expectedBadgeLevel: .giftBadge(.signalGift)
        )
    }

    private func enqueueMessages(receiptCredentialPresentation: ReceiptCredentialPresentation,
                                 transaction: SDSAnyWriteTransaction) throws {
        func send(_ preparer: OutgoingMessagePreparer) {
            preparer.insertMessage(transaction: transaction)
            self.messageSenderJobQueue.add(message: preparer, transaction: transaction)
        }

        let thread = try getValidatedThread(transaction: transaction)

        send(OutgoingMessagePreparer(
            giftBadgeReceiptCredentialPresentation: receiptCredentialPresentation,
            thread: thread,
            transaction: transaction
        ))

        if !self.messageText.isEmpty {
            send(OutgoingMessagePreparer(
                messageBody: self.messageText,
                thread: thread,
                transaction: transaction
            ))
        }
    }

    override public func run() {
        assert(self.durableOperationDelegate != nil)

        firstly(on: .global()) { () -> Promise<Void> in
            Logger.info("[Gifting] Ensuring we can still message recipient...")
            // We also do this check right before sending the message, but we might be able to prevent
            // charging the payment method (and some extra work) if we check now.
            try self.databaseStorage.read { try self.ensureThatWeCanStillMessageRecipient(transaction: $0) }
            return Promise.value(())
        }.then { () -> Promise<Void> in
            Logger.info("[Gifting] Confirming payment intent...")
            return try self.confirmPaymentIntent()
        }.then { () -> Promise<ReceiptCredentialPresentation> in
            self.postJobEventNotification(.chargeSucceeded)
            Logger.info("[Gifting] Charge succeeded! Getting receipt credential...")
            return try self.getReceiptCredentialPresentation()
        }.done(on: .global()) { receiptCredentialPresentation in
            Logger.info("[Gifting] Enqueueing messages...")
            try self.databaseStorage.write { transaction in
                try self.enqueueMessages(receiptCredentialPresentation: receiptCredentialPresentation,
                                         transaction: transaction)
            }
            self.didSucceed()
        }.catch(on: .global()) { error in
            self.reportError(error)
        }
    }

    override public func didSucceed() {
        Logger.info("[Gifting] Gift sent! Finishing up...")
        databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperationDidSucceed(self, transaction: transaction)

            DonationReceipt(
                receiptType: .gift,
                timestamp: Date(),
                amount: amount,
                currencyCode: currencyCode
            ).anyInsert(transaction: transaction)
        }
        postJobEventNotification(.jobSucceeded)
    }

    override public func retryInterval() -> TimeInterval {
        OWSOperation.retryIntervalForExponentialBackoff(failureCount: jobRecord.failureCount)
    }

    override public func didFail(error: Error) {
        self.databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperation(self, didFailWithError: error, transaction: transaction)
        }
        postJobEventNotification(.jobFailed)
    }
}

// MARK: - Outgoing message preparer

extension OutgoingMessagePreparer {
    fileprivate convenience init(giftBadgeReceiptCredentialPresentation: ReceiptCredentialPresentation,
                                 thread: TSThread,
                                 transaction: SDSAnyReadTransaction) {
        self.init(
            builder: TSOutgoingMessageBuilder(
                thread: thread,
                expiresInSeconds: thread.disappearingMessagesDuration(with: transaction),
                giftBadge: OWSGiftBadge(redemptionCredential: Data(giftBadgeReceiptCredentialPresentation.serialize()))
            ),
            transaction: transaction
        )
    }

    fileprivate convenience init(messageBody: String,
                                 thread: TSThread,
                                 transaction: SDSAnyReadTransaction) {
        self.init(
            builder: TSOutgoingMessageBuilder(
                thread: thread,
                messageBody: messageBody,
                expiresInSeconds: thread.disappearingMessagesDuration(with: transaction)
            ),
            transaction: transaction
        )
    }

    private convenience init(builder: TSOutgoingMessageBuilder, transaction: SDSAnyReadTransaction) {
        self.init(builder.build(transaction: transaction))
    }
}
