//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import SignalServiceKit

// MARK: - Job Queue

public class SendGiftBadgeJobQueue {
    private let jobQueueRunner: JobQueueRunner<
        JobRecordFinderImpl<SendGiftBadgeJobRecord>,
        SendGiftBadgeJobRunnerFactory
    >
    private let jobRunnerFactory: SendGiftBadgeJobRunnerFactory

    public init(db: DB, reachabilityManager: SSKReachabilityManager) {
        self.jobRunnerFactory = SendGiftBadgeJobRunnerFactory()
        self.jobQueueRunner = JobQueueRunner(
            canExecuteJobsConcurrently: true,
            db: db,
            jobFinder: JobRecordFinderImpl(db: db),
            jobRunnerFactory: self.jobRunnerFactory
        )
        self.jobQueueRunner.listenForReachabilityChanges(reachabilityManager: reachabilityManager)
    }

    func start(appContext: AppContext) {
        guard appContext.isMainApp else {
            return
        }
        jobQueueRunner.start(shouldRestartExistingJobs: true)
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

    public func addJob(
        _ jobRecord: SendGiftBadgeJobRecord,
        tx: SDSAnyWriteTransaction
    ) -> (chargePromise: Promise<Void>, completionPromise: Promise<Void>) {
        let (chargePromise, chargeFuture) = Promise<Void>.pending()
        let (completionPromise, completionFuture) = Promise<Void>.pending()
        Logger.info("[Gifting] Adding a \"send gift badge\" job")
        jobRecord.anyInsert(transaction: tx)
        tx.addSyncCompletion {
            let runner = self.jobRunnerFactory.buildRunner(chargeFuture: chargeFuture, completionFuture: completionFuture)
            self.jobQueueRunner.addPersistedJob(jobRecord, runner: runner)
        }
        return (chargePromise, completionPromise)
    }

    public func alreadyHasJob(for thread: TSContactThread, transaction: SDSAnyReadTransaction) -> Bool {
        SendGiftBadgeJobFinder.jobExists(forThreadId: thread.uniqueId, transaction: transaction)
    }
}

// MARK: - Job Finder

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

// MARK: - Runner

private class SendGiftBadgeJobRunnerFactory: JobRunnerFactory {
    func buildRunner() -> SendGiftBadgeJobRunner { buildRunner(chargeFuture: nil, completionFuture: nil) }

    func buildRunner(chargeFuture: Future<Void>?, completionFuture: Future<Void>?) -> SendGiftBadgeJobRunner {
        return SendGiftBadgeJobRunner(chargeFuture: chargeFuture, completionFuture: completionFuture)
    }
}

private class SendGiftBadgeJobRunner: JobRunner, Dependencies {
    private enum Constants {
        static let maxRetries: UInt = 110
    }

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

    private let chargeFuture: Future<Void>?
    private let completionFuture: Future<Void>?

    init(chargeFuture: Future<Void>?, completionFuture: Future<Void>?) {
        self.chargeFuture = chargeFuture
        self.completionFuture = completionFuture
    }

    func runJobAttempt(_ jobRecord: SendGiftBadgeJobRecord) async -> JobAttemptResult {
        return await .executeBlockWithDefaultErrorHandler(
            jobRecord: jobRecord,
            retryLimit: Constants.maxRetries,
            db: DependenciesBridge.shared.db,
            block: { try await _runJobAttempt(jobRecord) }
        )
    }

    func didFinishJob(_ jobRecordId: JobRecord.RowId, result: JobResult) async {
        switch result.ranSuccessfullyOrError {
        case .success:
            Logger.info("[Gifting] Job succeeded!")
            completionFuture?.resolve(())
        case .failure(let error):
            chargeFuture?.reject(error)
            completionFuture?.reject(error)
        }
    }

    private func _runJobAttempt(_ jobRecord: SendGiftBadgeJobRecord) async throws {
        let payment: Payment = try {
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
                    throw OWSGenericError("Tried to use Stripe as payment processor but data was missing")
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
                    throw OWSGenericError("Tried to use Braintree as payment processor but data was missing")
                }
                return Payment.forBraintree(paypalApprovalParams: .init(
                    payerId: paypalPayerId,
                    paymentId: paypalPaymentId,
                    paymentToken: paypalPaymentToken
                ))
            }
        }()

        let receiptCredentialRequestContext = try ReceiptCredentialRequestContext(contents: [UInt8](jobRecord.receiptCredentialRequestContext))
        let receiptCredentialRequest = try ReceiptCredentialRequest(contents: [UInt8](jobRecord.receiptCredentialRequest))

        // We also do this check right before sending the message, but we might be able to prevent
        // charging the payment method (and some extra work) if we check now.
        Logger.info("[Gifting] Ensuring we can still message recipient...")
        try databaseStorage.read { tx in
            try ensureThatWeCanStillMessageRecipient(threadUniqueId: jobRecord.threadId, tx: tx)
        }

        Logger.info("[Gifting] Confirming payment...")
        let amount = FiatMoney(currencyCode: jobRecord.currencyCode, value: jobRecord.amount as Decimal)
        let paymentIntentId = try await confirmPayment(payment, amount: amount, idempotencyKey: jobRecord.uniqueId)
        chargeFuture?.resolve(())

        Logger.info("[Gifting] Charge succeeded! Getting receipt credential...")
        let receiptCredentialPresentation = try await getReceiptCredentialPresentation(
            payment: payment,
            paymentIntentId: paymentIntentId,
            receiptCredentialRequest: receiptCredentialRequest,
            receiptCredentialRequestContext: receiptCredentialRequestContext
        )

        Logger.info("[Gifting] Enqueueing messages & finishing up...")
        try await databaseStorage.awaitableWrite { tx in
            try self.enqueueMessages(
                threadUniqueId: jobRecord.threadId,
                messageText: jobRecord.messageText,
                receiptCredentialPresentation: receiptCredentialPresentation,
                tx: tx
            )
            DonationReceipt(receiptType: .gift, timestamp: Date(), amount: amount).anyInsert(transaction: tx)
            jobRecord.anyRemove(transaction: tx)
        }
    }

    private func getValidatedThread(threadUniqueId: String, tx: SDSAnyReadTransaction) throws -> TSContactThread {
        guard let thread = TSContactThread.anyFetchContactThread(uniqueId: threadUniqueId, transaction: tx) else {
            throw OWSGenericError("Thread for gift badge sending no longer exists")
        }
        guard !blockingManager.isThreadBlocked(thread, transaction: tx) else {
            throw OWSGenericError("Thread for gift badge sending is blocked")
        }
        return thread
    }

    private func ensureThatWeCanStillMessageRecipient(threadUniqueId: String, tx: SDSAnyReadTransaction) throws {
        _ = try getValidatedThread(threadUniqueId: threadUniqueId, tx: tx)
    }

    /// Confirm the payment. Return the payment intent ID.
    private func confirmPayment(_ payment: Payment, amount: FiatMoney, idempotencyKey: String) async throws -> String {
        switch payment {
        case let .forStripe(paymentIntentClientSecret, paymentIntentId, paymentMethodId):
            _ = try await Stripe.confirmPaymentIntent(
                // Bank transfers not supported on gift badges,
                // so the bank mandate can be left nil.
                mandate: nil,
                paymentIntentClientSecret: paymentIntentClientSecret,
                paymentIntentId: paymentIntentId,
                paymentMethodId: paymentMethodId,
                callbackURL: nil,
                idempotencyKey: idempotencyKey
            ).awaitable()
            return paymentIntentId
        case let .forBraintree(paypalApprovalParams):
            return try await Paypal.confirmOneTimePayment(
                amount: amount,
                level: .giftBadge(.signalGift),
                approvalParams: paypalApprovalParams
            ).awaitable()
        }
    }

    private func getReceiptCredentialPresentation(
        payment: Payment,
        paymentIntentId: String,
        receiptCredentialRequest: ReceiptCredentialRequest,
        receiptCredentialRequestContext: ReceiptCredentialRequestContext
    ) async throws -> ReceiptCredentialPresentation {
        try await SubscriptionManagerImpl.requestReceiptCredentialPresentation(
            boostPaymentIntentId: paymentIntentId,
            expectedBadgeLevel: .giftBadge(.signalGift),
            paymentProcessor: payment.processor,
            context: receiptCredentialRequestContext,
            request: receiptCredentialRequest
        ).awaitable()
    }

    private func enqueueMessages(
        threadUniqueId: String,
        messageText: String,
        receiptCredentialPresentation: ReceiptCredentialPresentation,
        tx: SDSAnyWriteTransaction
    ) throws {
        func send(_ preparer: OutgoingMessagePreparer) {
            preparer.insertMessage(transaction: tx)
            SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparer, transaction: tx)
        }

        let thread = try getValidatedThread(threadUniqueId: threadUniqueId, tx: tx)

        send(OutgoingMessagePreparer(
            giftBadgeReceiptCredentialPresentation: receiptCredentialPresentation,
            thread: thread,
            transaction: tx
        ))

        if !messageText.isEmpty {
            send(OutgoingMessagePreparer(messageBody: messageText, thread: thread, transaction: tx))
        }
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
