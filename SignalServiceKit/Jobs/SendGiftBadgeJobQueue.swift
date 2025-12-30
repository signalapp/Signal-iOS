//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
public import LibSignalClient

// MARK: - Job Queue

public class SendGiftBadgeJobQueue {
    private let jobQueueRunner: JobQueueRunner<
        JobRecordFinderImpl<SendGiftBadgeJobRecord>,
        SendGiftBadgeJobRunnerFactory,
    >
    private let jobRunnerFactory: SendGiftBadgeJobRunnerFactory

    public init(db: any DB, reachabilityManager: SSKReachabilityManager) {
        self.jobRunnerFactory = SendGiftBadgeJobRunnerFactory()
        self.jobQueueRunner = JobQueueRunner(
            canExecuteJobsConcurrently: true,
            db: db,
            jobFinder: JobRecordFinderImpl(db: db),
            jobRunnerFactory: self.jobRunnerFactory,
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
        messageText: String,
    ) -> SendGiftBadgeJobRecord {
        let paymentProcessor: DonationPaymentProcessor
        var stripePaymentIntent: Stripe.PaymentIntent?
        var stripePaymentMethodId: String?
        var paypalApprovalParams: Paypal.OneTimePaymentWebAuthApprovalParams?
        var paypalPaymentId: String?

        switch preparedPayment {
        case let .forStripe(paymentIntent, paymentMethodId):
            paymentProcessor = .stripe
            stripePaymentIntent = paymentIntent
            stripePaymentMethodId = paymentMethodId
        case let .forPaypal(approvalParams, paymentId):
            paymentProcessor = .braintree
            paypalApprovalParams = approvalParams
            paypalPaymentId = paymentId
        }

        return SendGiftBadgeJobRecord(
            paymentProcessor: paymentProcessor.rawValue,
            receiptCredentialRequestContext: receiptRequest.context.serialize(),
            receiptCredentialRequest: receiptRequest.request.serialize(),
            amount: amount.value,
            currencyCode: amount.currencyCode,
            paymentIntentClientSecret: stripePaymentIntent?.clientSecret,
            paymentIntentId: stripePaymentIntent?.id,
            paymentMethodId: stripePaymentMethodId,
            paypalPayerId: paypalApprovalParams?.payerId,
            paypalPaymentId: paypalPaymentId,
            paypalPaymentToken: paypalApprovalParams?.paymentToken,
            threadId: thread.uniqueId,
            messageText: messageText,
        )
    }

    public func addJob(
        _ jobRecord: SendGiftBadgeJobRecord,
        tx: DBWriteTransaction,
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

    public func alreadyHasJob(threadId: String, transaction: DBReadTransaction) -> Bool {
        jobExists(threadId: threadId, transaction: transaction)
    }
}

// MARK: - Job Finder

private func jobExists(threadId: String, transaction: DBReadTransaction) -> Bool {
    assert(!threadId.isEmpty)

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
        SendGiftBadgeJobRecord.Status.obsolete.rawValue,
    ]
    return failIfThrows {
        return try Bool.fetchOne(transaction.database, sql: sql, arguments: arguments) ?? false
    }
}

// MARK: - Runner

private class SendGiftBadgeJobRunnerFactory: JobRunnerFactory {
    func buildRunner() -> SendGiftBadgeJobRunner { buildRunner(chargeFuture: nil, completionFuture: nil) }

    func buildRunner(chargeFuture: Future<Void>?, completionFuture: Future<Void>?) -> SendGiftBadgeJobRunner {
        return SendGiftBadgeJobRunner(chargeFuture: chargeFuture, completionFuture: completionFuture)
    }
}

private class SendGiftBadgeJobRunner: JobRunner {
    private enum Constants {
        static let maxRetries: UInt = 110
    }

    private enum Payment {
        case forStripe(
            paymentIntentClientSecret: String,
            paymentIntentId: String,
            paymentMethodId: String,
        )
        case forBraintree(
            paypalApprovalParams: Paypal.OneTimePaymentWebAuthApprovalParams,
            paymentId: String,
        )

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

    func runJobAttempt(_ jobRecord: SendGiftBadgeJobRecord) async -> JobAttemptResult<Void> {
        return await .executeBlockWithDefaultErrorHandler(
            jobRecord: jobRecord,
            retryLimit: Constants.maxRetries,
            db: DependenciesBridge.shared.db,
            block: { try await _runJobAttempt(jobRecord) },
        )
    }

    func didFinishJob(_ jobRecordId: JobRecord.RowId, result: JobResult<Void>) async {
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
                    paymentMethodId: paymentMethodId,
                )
            case .braintree:
                guard
                    let paypalPayerId = jobRecord.paypalPayerId,
                    let paypalPaymentId = jobRecord.paypalPaymentId,
                    let paypalPaymentToken = jobRecord.paypalPaymentToken
                else {
                    throw OWSGenericError("Tried to use Braintree as payment processor but data was missing")
                }
                return Payment.forBraintree(
                    paypalApprovalParams: .init(payerId: paypalPayerId, paymentToken: paypalPaymentToken),
                    paymentId: paypalPaymentId,
                )
            }
        }()

        let receiptCredentialRequestContext = try ReceiptCredentialRequestContext(contents: jobRecord.receiptCredentialRequestContext)
        let receiptCredentialRequest = try ReceiptCredentialRequest(contents: jobRecord.receiptCredentialRequest)

        // We also do this check right before sending the message, but we might be able to prevent
        // charging the payment method (and some extra work) if we check now.
        Logger.info("[Gifting] Ensuring we can still message recipient...")
        try SSKEnvironment.shared.databaseStorageRef.read { tx in
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
            receiptCredentialRequestContext: receiptCredentialRequestContext,
        )

        let messageBody: ValidatedMessageBody?
        if let text = jobRecord.messageText.nilIfEmpty {
            messageBody = try await DependenciesBridge.shared.attachmentContentValidator
                .prepareOversizeTextIfNeeded(MessageBody(text: text, ranges: .empty))
        } else {
            messageBody = nil
        }

        Logger.info("[Gifting] Enqueueing messages & finishing up...")
        try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            try self.enqueueMessages(
                threadUniqueId: jobRecord.threadId,
                messageBody: messageBody,
                receiptCredentialPresentation: receiptCredentialPresentation,
                tx: tx,
            )
            DonationReceipt(receiptType: .gift, timestamp: Date(), amount: amount).anyInsert(transaction: tx)
            jobRecord.anyRemove(transaction: tx)
        }
    }

    private func getValidatedThread(threadUniqueId: String, tx: DBReadTransaction) throws -> TSContactThread {
        guard let thread = TSContactThread.anyFetchContactThread(uniqueId: threadUniqueId, transaction: tx) else {
            throw OWSGenericError("Thread for gift badge sending no longer exists")
        }
        guard !SSKEnvironment.shared.blockingManagerRef.isThreadBlocked(thread, transaction: tx) else {
            throw OWSGenericError("Thread for gift badge sending is blocked")
        }
        return thread
    }

    private func ensureThatWeCanStillMessageRecipient(threadUniqueId: String, tx: DBReadTransaction) throws {
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
                idempotencyKey: idempotencyKey,
            )
            return paymentIntentId
        case let .forBraintree(paypalApprovalParams, paymentId):
            return try await Paypal.confirmOneTimePayment(
                amount: amount,
                level: .giftBadge(.signalGift),
                paymentId: paymentId,
                approvalParams: paypalApprovalParams,
            )
        }
    }

    private func getReceiptCredentialPresentation(
        payment: Payment,
        paymentIntentId: String,
        receiptCredentialRequest: ReceiptCredentialRequest,
        receiptCredentialRequestContext: ReceiptCredentialRequestContext,
    ) async throws -> ReceiptCredentialPresentation {
        let receiptCredential = try await ReceiptCredentialManager(
            dateProvider: { Date() },
            logger: PrefixedLogger(prefix: "[Donations]"),
            networkManager: SSKEnvironment.shared.networkManagerRef,
        ).requestReceiptCredential(
            via: OWSRequestFactory.boostReceiptCredentials(
                paymentIntentID: paymentIntentId,
                paymentProcessor: payment.processor,
                receiptCredentialRequest: receiptCredentialRequest,
            ),
            isValidReceiptLevelPredicate: { receiptLevel in
                return receiptLevel == OneTimeBadgeLevel.giftBadge(.signalGift).rawValue
            },
            context: receiptCredentialRequestContext,
        )

        return try ReceiptCredentialManager.generateReceiptCredentialPresentation(
            receiptCredential: receiptCredential,
        )
    }

    private func enqueueMessages(
        threadUniqueId: String,
        messageBody: ValidatedMessageBody?,
        receiptCredentialPresentation: ReceiptCredentialPresentation,
        tx: DBWriteTransaction,
    ) throws {
        func send(_ unpreparedMessage: UnpreparedOutgoingMessage) throws {
            let preparedMessage = try unpreparedMessage.prepare(tx: tx)
            SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: tx)
        }

        let thread = try getValidatedThread(threadUniqueId: threadUniqueId, tx: tx)

        try send(UnpreparedOutgoingMessage.build(
            giftBadgeReceiptCredentialPresentation: receiptCredentialPresentation,
            thread: thread,
            tx: tx,
        ))

        if let messageBody {
            try send(UnpreparedOutgoingMessage.build(messageBody: messageBody, thread: thread, tx: tx))
        }
    }
}

// MARK: - Outgoing message preparer

extension UnpreparedOutgoingMessage {
    fileprivate static func build(
        giftBadgeReceiptCredentialPresentation: ReceiptCredentialPresentation,
        thread: TSThread,
        tx: DBReadTransaction,
    ) -> UnpreparedOutgoingMessage {
        let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
        let dmConfig = dmConfigurationStore.fetchOrBuildDefault(for: .thread(thread), tx: tx)
        let builder: TSOutgoingMessageBuilder = .withDefaultValues(
            thread: thread,
            expiresInSeconds: dmConfig.durationSeconds,
            expireTimerVersion: dmConfig.timerVersion,
            giftBadge: OWSGiftBadge(redemptionCredential: giftBadgeReceiptCredentialPresentation.serialize()),
        )
        return .forMessage(builder.build(transaction: tx), body: nil)
    }

    fileprivate static func build(
        messageBody: ValidatedMessageBody,
        thread: TSThread,
        tx: DBReadTransaction,
    ) -> UnpreparedOutgoingMessage {
        let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
        let dmConfig = dmConfigurationStore.fetchOrBuildDefault(for: .thread(thread), tx: tx)
        let builder: TSOutgoingMessageBuilder = .withDefaultValues(
            thread: thread,
            messageBody: messageBody,
            expiresInSeconds: dmConfig.durationSeconds,
            expireTimerVersion: dmConfig.timerVersion,
        )
        return .forMessage(builder.build(transaction: tx), body: messageBody)
    }
}
