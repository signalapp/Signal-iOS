//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import SignalServiceKit

// MARK: - Job queue

public class SendGiftBadgeJobQueue: JobQueue {
    public typealias DurableOperationType = SendGiftBadgeOperation

    public let requiresInternet: Bool = true
    public var isEnabled: Bool { CurrentAppContext().isMainApp }
    public var runningOperations = AtomicArray<SendGiftBadgeOperation>()
    public let isSetup = AtomicBool(false)

    public enum JobEvent: Int {
        case chargeSucceeded
        case jobFailed
        case jobSucceeded
    }

    public static let JobEventNotification = NSNotification.Name("SendGiftBadgeJobQueueJobEventNotification")

    public init() {
        AppReadiness.runNowOrWhenAppDidBecomeReadySync {
            self.setup()
        }
    }

    public func setup() {
        defaultSetup()
    }

    public func didMarkAsReady(oldJobRecord: JobRecordType, transaction: SDSAnyWriteTransaction) {
        // no special handling
    }

    let operationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "SendGiftBadgeJobQueue"
        return operationQueue
    }()

    public func operationQueue(jobRecord: SendGiftBadgeJobRecord) -> OperationQueue {
        return self.operationQueue
    }

    public func buildOperation(jobRecord: SendGiftBadgeJobRecord, transaction: SDSAnyReadTransaction) throws -> SendGiftBadgeOperation {
        return try SendGiftBadgeOperation(jobRecord)
    }

    public static func createJob(
        preparedPayment: PreparedGiftPayment,
        receiptRequest: (context: ReceiptCredentialRequestContext, request: ReceiptCredentialRequest),
        amount: FiatMoney,
        thread: TSContactThread,
        messageText: String
    ) -> SendGiftBadgeJobRecord {
        let paymentProcessor: DonationPaymentProcessor
        var stripePaymentIntent: Stripe.PaymentIntent?
        var stripePaymentMethodId: String?
        var paypalApprovalParams: Paypal.OneTimePaymentWebAuthApprovalParams?

        switch preparedPayment {
        case let .forStripe(paymentIntent, paymentMethodId):
            paymentProcessor = .stripe
            stripePaymentIntent = paymentIntent
            stripePaymentMethodId = paymentMethodId
        case let .forPaypal(approvalParams):
            paymentProcessor = .braintree
            paypalApprovalParams = approvalParams
        }

        return SendGiftBadgeJobRecord(
            paymentProcessor: paymentProcessor.rawValue,
            receiptCredentialRequestContext: receiptRequest.context.serialize().asData,
            receiptCredentialRequest: receiptRequest.request.serialize().asData,
            amount: amount.value,
            currencyCode: amount.currencyCode,
            paymentIntentClientSecret: stripePaymentIntent?.clientSecret,
            paymentIntentId: stripePaymentIntent?.id,
            paymentMethodId: stripePaymentMethodId,
            paypalPayerId: paypalApprovalParams?.payerId,
            paypalPaymentId: paypalApprovalParams?.paymentId,
            paypalPaymentToken: paypalApprovalParams?.paymentToken,
            threadId: thread.uniqueId,
            messageText: messageText
        )
    }

    public func addJob(_ jobRecord: SendGiftBadgeJobRecord, transaction: SDSAnyWriteTransaction) {
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
                    SELECT 1 FROM \(SendGiftBadgeJobRecord.databaseTableName)
                    WHERE \(SendGiftBadgeJobRecord.columnName(.threadId)) IS ?
                    AND \(SendGiftBadgeJobRecord.columnName(.recordType)) IS ?
                    AND \(SendGiftBadgeJobRecord.columnName(.status)) NOT IN (?, ?)
                )
            """
            let arguments: StatementArguments = [
                threadId,
                SDSRecordType.sendGiftBadgeJobRecord.rawValue,
                SendGiftBadgeJobRecord.Status.permanentlyFailed.rawValue,
                SendGiftBadgeJobRecord.Status.obsolete.rawValue
            ]
            do {
                return try Bool.fetchOne(grdbTransaction.database, sql: sql, arguments: arguments) ?? false
            } catch {
                DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                    userDefaults: CurrentAppContext().appUserDefaults(),
                    error: error
                )
                owsFail("Unable to find job")
            }
        }
    }
}

// MARK: - Operation

public final class SendGiftBadgeOperation: OWSOperation, DurableOperation {
    private enum Payment {
        case forStripe(
            paymentIntentClientSecret: String,
            paymentIntentId: String,
            paymentMethodId: String
        )
        case forBraintree(paypalApprovalParams: Paypal.OneTimePaymentWebAuthApprovalParams)

        var processor: DonationPaymentProcessor {
            switch self {
            case .forStripe: return .stripe
            case .forBraintree: return .braintree
            }
        }
    }

    public typealias JobRecordType = SendGiftBadgeJobRecord
    public typealias DurableOperationDelegateType = SendGiftBadgeJobQueue

    public var jobRecord: SendGiftBadgeJobRecord
    weak public var durableOperationDelegate: SendGiftBadgeJobQueue?

    public var operation: OWSOperation { self }

    /// 110 retries corresponds to approximately ~24hr of retry when using
    /// ``OWSOperation/retryIntervalForExponentialBackoff(failureCount:maxBackoff:)``.
    public let maxRetries: UInt = 110

    private let payment: Payment
    private let receiptCredentialRequestContext: ReceiptCredentialRequestContext
    private let receiptCredentialRequest: ReceiptCredentialRequest
    private let amount: FiatMoney
    private let threadId: String
    private let messageText: String

    public required init(_ jobRecord: SendGiftBadgeJobRecord) throws {
        self.jobRecord = jobRecord

        payment = try {
            switch DonationPaymentProcessor(rawValue: jobRecord.paymentProcessor) {
            case nil:
                owsFailDebug("Failed to deserialize payment processor from record with value: \(jobRecord.paymentProcessor)")
                fallthrough
            case .stripe:
                guard
                    let paymentIntentClientSecret = jobRecord.paymentIntentClientSecret,
                    let paymentIntentId = jobRecord.paymentIntentId,
                    let paymentMethodId = jobRecord.paymentMethodId
                else {
                    throw JobError.permanentFailure(description: "Tried to use Stripe as payment processor but data was missing")
                }
                return Payment.forStripe(
                    paymentIntentClientSecret: paymentIntentClientSecret,
                    paymentIntentId: paymentIntentId,
                    paymentMethodId: paymentMethodId
                )
            case .braintree:
                guard
                    let paypalPayerId = jobRecord.paypalPayerId,
                    let paypalPaymentId = jobRecord.paypalPaymentId,
                    let paypalPaymentToken = jobRecord.paypalPaymentToken
                else {
                    throw JobError.permanentFailure(description: "Tried to use Braintree as payment processor but data was missing")
                }
                return Payment.forBraintree(paypalApprovalParams: .init(
                    payerId: paypalPayerId,
                    paymentId: paypalPaymentId,
                    paymentToken: paypalPaymentToken
                ))
            }
        }()

        receiptCredentialRequestContext = try ReceiptCredentialRequestContext(contents: [UInt8](jobRecord.receiptCredentialRequestContext))
        receiptCredentialRequest = try ReceiptCredentialRequest(contents: [UInt8](jobRecord.receiptCredentialRequest))
        amount = FiatMoney(
            currencyCode: jobRecord.currencyCode,
            value: jobRecord.amount as Decimal
        )
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

    /// Confirm the payment. Return the payment intent ID.
    private func confirmPayment() -> Promise<String> {
        switch payment {
        case let .forStripe(paymentIntentClientSecret, paymentIntentId, paymentMethodId):
            return Stripe.confirmPaymentIntent(
                // Bank transfers not supported on gift badges,
                // so the bank mandate can be left nil.
                mandate: nil,
                paymentIntentClientSecret: paymentIntentClientSecret,
                paymentIntentId: paymentIntentId,
                paymentMethodId: paymentMethodId,
                callbackURL: nil,
                idempotencyKey: jobRecord.uniqueId
            ).map { _ in paymentIntentId }
        case let .forBraintree(paypalApprovalParams):
            return Paypal.confirmOneTimePayment(
                amount: amount,
                level: .giftBadge(.signalGift),
                approvalParams: paypalApprovalParams
            )
        }
    }

    private func getReceiptCredentialPresentation(
        paymentIntentId: String
    ) throws -> Promise<ReceiptCredentialPresentation> {
        try SubscriptionManagerImpl.requestReceiptCredentialPresentation(
            boostPaymentIntentId: paymentIntentId,
            expectedBadgeLevel: .giftBadge(.signalGift),
            paymentProcessor: payment.processor,
            context: receiptCredentialRequestContext,
            request: receiptCredentialRequest
        )
    }

    private func enqueueMessages(receiptCredentialPresentation: ReceiptCredentialPresentation,
                                 transaction: SDSAnyWriteTransaction) throws {
        func send(_ preparer: OutgoingMessagePreparer) {
            preparer.insertMessage(transaction: transaction)
            SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparer, transaction: transaction)
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

        firstly(on: DispatchQueue.global()) { () -> Promise<Void> in
            Logger.info("[Gifting] Ensuring we can still message recipient...")
            // We also do this check right before sending the message, but we might be able to prevent
            // charging the payment method (and some extra work) if we check now.
            try self.databaseStorage.read { try self.ensureThatWeCanStillMessageRecipient(transaction: $0) }
            return Promise.value(())
        }.then { () -> Promise<String> in
            Logger.info("[Gifting] Confirming payment...")
            return self.confirmPayment()
        }.then { (paymentIntentId: String) -> Promise<ReceiptCredentialPresentation> in
            self.postJobEventNotification(.chargeSucceeded)
            Logger.info("[Gifting] Charge succeeded! Getting receipt credential...")
            return try self.getReceiptCredentialPresentation(paymentIntentId: paymentIntentId)
        }.done(on: DispatchQueue.global()) { receiptCredentialPresentation in
            Logger.info("[Gifting] Enqueueing messages...")
            try self.databaseStorage.write { transaction in
                try self.enqueueMessages(receiptCredentialPresentation: receiptCredentialPresentation,
                                         transaction: transaction)
            }
            self.didSucceed()
        }.catch(on: DispatchQueue.global()) { error in
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
                amount: amount
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
    fileprivate convenience init(
        giftBadgeReceiptCredentialPresentation: ReceiptCredentialPresentation,
        thread: TSThread,
        transaction tx: SDSAnyReadTransaction
    ) {
        let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
        self.init(
            builder: TSOutgoingMessageBuilder(
                thread: thread,
                expiresInSeconds: dmConfigurationStore.durationSeconds(for: thread, tx: tx.asV2Read),
                giftBadge: OWSGiftBadge(redemptionCredential: Data(giftBadgeReceiptCredentialPresentation.serialize()))
            ),
            transaction: tx
        )
    }

    fileprivate convenience init(
        messageBody: String,
        thread: TSThread,
        transaction tx: SDSAnyReadTransaction
    ) {
        let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
        self.init(
            builder: TSOutgoingMessageBuilder(
                thread: thread,
                messageBody: messageBody,
                expiresInSeconds: dmConfigurationStore.durationSeconds(for: thread, tx: tx.asV2Read)
            ),
            transaction: tx
        )
    }

    private convenience init(builder: TSOutgoingMessageBuilder, transaction: SDSAnyReadTransaction) {
        self.init(builder.build(transaction: transaction))
    }
}
