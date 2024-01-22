//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalCoreKit
import SignalServiceKit

/// Manages "donation receipt credential" redemption.
///
/// Donation payments are handled differently depending on the payment
/// method. Ultimately, however, all payments are "confirmed" – this means
/// the user has authorized the payment. Once that happens, we end up with a
/// "payment intent ID" as well as a "receipt credential request/context".
///
/// At this point, we're in a zero-knowledge world – neither the payment
/// intent ID nor the receipt credential request are associated with our
/// account.
///
/// We take the payment intent ID and receipt credential request, and send
/// them (unauthenticated) to Signal servers. If the payment in question has
/// been "processed" (per the relevant payment processor, such as Stripe),
/// the server returns us a value that we can combine with our receipt
/// credential request context to create a zero-knowledge "receipt
/// credential".
///
/// Note that if the payment has not processed successfully, we instead
/// receive an error which can tell us the status of the payment and how to
/// proceed. For example, the payment may have failed to process, or may
/// still be pending but not have affirmatively failed – we want to respond
/// differently to those scenarios.
///
/// *Finally*, we make an authenticated request to send a presentation for
/// the ZK receipt credential to the service – thereby proving that we have
/// made a donation – which assigns a badge to our account.
///
/// - Note
/// Some payment types (such as credit cards) usually process immediately,
/// but others (such as SEPA debit transfers) can take days/weeks to
/// process. During that time, receipt credential request redemption will
/// fail.
public class ReceiptCredentialRedemptionJobQueue {
    private let jobQueueRunner: JobQueueRunner<
        JobRecordFinderImpl<ReceiptCredentialRedemptionJobRecord>,
        ReceiptCredentialRedemptionJobRunnerFactory
    >
    private let jobRunnerFactory: ReceiptCredentialRedemptionJobRunnerFactory

    public init(db: DB, reachabilityManager: SSKReachabilityManager) {
        self.jobRunnerFactory = ReceiptCredentialRedemptionJobRunnerFactory()
        self.jobQueueRunner = JobQueueRunner(
            canExecuteJobsConcurrently: true,
            db: db,
            jobFinder: JobRecordFinderImpl(db: db),
            jobRunnerFactory: self.jobRunnerFactory
        )
        self.jobQueueRunner.listenForReachabilityChanges(reachabilityManager: reachabilityManager)
    }

    func start(appContext: AppContext) {
        guard appContext.isMainApp else { return }
        jobQueueRunner.start(shouldRestartExistingJobs: true)
    }

    public func addBoostJob(
        amount: FiatMoney,
        paymentProcessor: DonationPaymentProcessor,
        paymentMethod: DonationPaymentMethod,
        receiptCredentialRequestContext: Data,
        receiptCredentialRequest: Data,
        boostPaymentIntentID: String,
        future: Future<Void>,
        transaction: SDSAnyWriteTransaction
    ) {
        Logger.info("[Donations] Adding a boost job")

        let jobRecord = ReceiptCredentialRedemptionJobRecord(
            paymentProcessor: paymentProcessor.rawValue,
            paymentMethod: paymentMethod.rawValue,
            receiptCredentialRequestContext: receiptCredentialRequestContext,
            receiptCredentialRequest: receiptCredentialRequest,
            subscriberID: Data(), // Unused
            targetSubscriptionLevel: 0, // Unused
            priorSubscriptionLevel: 0, // Unused
            isNewSubscription: true, // Unused
            shouldSuppressPaymentAlreadyRedeemed: false, // Unused
            isBoost: true,
            amount: amount.value,
            currencyCode: amount.currencyCode,
            boostPaymentIntentID: boostPaymentIntentID
        )
        add(jobRecord: jobRecord, future: future, tx: transaction)
    }

    /// Add a new redemption job for a recurring payment.
    ///
    /// - Parameter paymentMethod
    /// The payment method for this subscription. In practice, should not be
    /// `nil`! However, we fetch this from the service, which cannot guarantee a
    /// recognized value (as it is in turn fetched from an external service,
    /// such as Stripe).
    ///
    /// - Parameter isNewSubscription
    /// `true` if this job represents a new or updated subscription. `false` if
    /// this job is associated with the renewal of an existing subscription.
    ///
    /// - Parameter shouldSuppressPaymentAlreadyRedeemed
    /// Whether this job should suppress "payment already redeemed" errors.
    public func addSubscriptionJob(
        paymentProcessor: DonationPaymentProcessor,
        paymentMethod: DonationPaymentMethod?,
        receiptCredentialRequestContext: Data,
        receiptCredentialRequest: Data,
        subscriberID: Data,
        targetSubscriptionLevel: UInt,
        priorSubscriptionLevel: UInt?,
        isNewSubscription: Bool,
        shouldSuppressPaymentAlreadyRedeemed: Bool,
        future: Future<Void>,
        transaction: SDSAnyWriteTransaction
    ) {
        Logger.info("[Donations] Adding a subscription job")

        let jobRecord = ReceiptCredentialRedemptionJobRecord(
            paymentProcessor: paymentProcessor.rawValue,
            paymentMethod: paymentMethod?.rawValue,
            receiptCredentialRequestContext: receiptCredentialRequestContext,
            receiptCredentialRequest: receiptCredentialRequest,
            subscriberID: subscriberID,
            targetSubscriptionLevel: targetSubscriptionLevel,
            priorSubscriptionLevel: priorSubscriptionLevel ?? 0,
            isNewSubscription: isNewSubscription,
            shouldSuppressPaymentAlreadyRedeemed: shouldSuppressPaymentAlreadyRedeemed,
            isBoost: false,
            amount: nil,
            currencyCode: nil,
            boostPaymentIntentID: String() // Unused
        )
        add(jobRecord: jobRecord, future: future, tx: transaction)
    }

    private func add(jobRecord: ReceiptCredentialRedemptionJobRecord, future: Future<Void>, tx: SDSAnyWriteTransaction) {
        jobRecord.anyInsert(transaction: tx)
        tx.addSyncCompletion {
            self.jobQueueRunner.addPersistedJob(jobRecord, runner: self.jobRunnerFactory.buildRunner(future: future))
        }
    }
}

private class ReceiptCredentialRedemptionJobRunnerFactory: JobRunnerFactory {
    func buildRunner() -> ReceiptCredentialRedemptionJobRunner { buildRunner(future: nil) }

    func buildRunner(future: Future<Void>?) -> ReceiptCredentialRedemptionJobRunner {
        return ReceiptCredentialRedemptionJobRunner(future: future)
    }
}

private class ReceiptCredentialRedemptionJobRunner: JobRunner, Dependencies {
    private let future: Future<Void>?

    init(future: Future<Void>?) {
        self.future = future
    }

    /// Represents the type of payment that resulted in this receipt credential
    /// redemption.
    enum PaymentType: CustomStringConvertible {
        /// A one-time payment, or "boost".
        case oneTimeBoost(paymentIntentId: String, amount: FiatMoney)

        /// A recurring payment, or (an overloaded term) "subscription".
        case recurringSubscription(
            subscriberId: Data,
            targetSubscriptionLevel: UInt,
            priorSubscriptionLevel: UInt,
            isNewSubscription: Bool,
            shouldSuppressPaymentAlreadyRedeemed: Bool
        )

        var receiptCredentialResultMode: ReceiptCredentialResultStore.Mode {
            switch self {
            case .oneTimeBoost: return .oneTimeBoost
            case .recurringSubscription(_, _, _, isNewSubscription: true, _): return .recurringSubscriptionInitiation
            case .recurringSubscription(_, _, _, isNewSubscription: false, _): return .recurringSubscriptionRenewal
            }
        }

        var donationReceiptType: DonationReceipt.DonationReceiptType {
            switch self {
            case .oneTimeBoost:
                return .boost
            case let .recurringSubscription(_, targetSubscriptionLevel, _, _, _):
                return .subscription(subscriptionLevel: targetSubscriptionLevel)
            }
        }

        var description: String {
            switch self {
            case .oneTimeBoost: return "one-time"
            case .recurringSubscription(_, _, _, isNewSubscription: true, _): return "recurring-initiation"
            case .recurringSubscription(_, _, _, isNewSubscription: false, _): return "recurring-renewal"
            }
        }
    }

    private var receiptCredentialResultStore: ReceiptCredentialResultStore {
        DependenciesBridge.shared.receiptCredentialResultStore
    }

    // MARK: - Retries

    private enum Constants {
        /// Defines the time between retries for SEPA and recurring iDEAL transactions.
        static let sepaRetryInterval = TSConstants.isUsingProductionService ? kDayInterval : kMinuteInterval
    }

    private enum RetryInterval {
        case exponential
        case sepa
    }

    private func stillProcessingRetryParameters(
        paymentType: PaymentType,
        paymentMethod: DonationPaymentMethod?
    ) -> (RetryInterval, maxRetries: UInt) {
        switch paymentMethod {
        case nil, .applePay, .creditOrDebitCard, .paypal:
            // We'll retry operations for these payment types fairly aggressively, so
            // we need a large retry buffer.
            return (.exponential, 110)
        case .sepa:
            // We'll only retry operations for SEPA 1x/day (including those fronted by
            // iDEAL), so we limit the retry buffer. They should always complete within
            // 14 business days, so this is generous compared to what we should need,
            // but prevents us from having an indefinite job if for whatever reason a
            // payment never processes.
            return (.sepa, 30)
        case .ideal:
            switch paymentType {
            case .oneTimeBoost:
                return (.exponential, 110)
            case .recurringSubscription:
                return (.sepa, 30)
            }
        }
    }

    var transientFailureCount: UInt = 0

    private func triggerExponentialRetry(jobRecord: JobRecord) -> TimeInterval {
        // If this operation just started, but we've tried in the past and have
        // persisted failures on the job record, we'll respect those and start with
        // a longer retry. Otherwise, as this operation continues to retry it'll
        // get a longer retry from its local error count.
        transientFailureCount += 1
        return OWSOperation.retryIntervalForExponentialBackoff(
            failureCount: max(jobRecord.failureCount, transientFailureCount)
        )
    }

    private func timeIntervalSince(_ timestampMs: UInt64) -> TimeInterval {
        return Date().timeIntervalSince(Date(millisecondsSince1970: timestampMs))
    }

    private func sepaRetryDelay(configuration: Configuration) -> TimeInterval? {
        let (retryInterval, _) = stillProcessingRetryParameters(
            paymentType: configuration.paymentType,
            paymentMethod: configuration.paymentMethod
        )
        guard retryInterval == .sepa else { return nil }

        let priorError = databaseStorage.read(block: { tx -> ReceiptCredentialRequestError? in
            return receiptCredentialResultStore.getRequestError(
                errorMode: configuration.paymentType.receiptCredentialResultMode,
                tx: tx.asV2Read
            )
        })
        guard let priorError, priorError.errorCode == .paymentStillProcessing else {
            return nil
        }
        let delay = Constants.sepaRetryInterval - timeIntervalSince(priorError.timestampMs)
        guard delay > 0 else {
            return nil
        }
        owsAssertDebug(priorError.paymentMethod == .sepa || priorError.paymentMethod == .ideal)
        return delay
    }

    // MARK: - Parsing

    private struct Configuration {
        var paymentMethod: DonationPaymentMethod?
        var paymentProcessor: DonationPaymentProcessor
        var paymentType: PaymentType
        var receiptCredentialRequest: ReceiptCredentialRequest
        var receiptCredentialRequestContext: ReceiptCredentialRequestContext
        var receiptCredentialPresentation: ReceiptCredentialPresentation?
    }

    private func parseJobRecord(_ jobRecord: ReceiptCredentialRedemptionJobRecord) throws -> Configuration {
        guard let paymentProcessor = DonationPaymentProcessor(rawValue: jobRecord.paymentProcessor) else {
            throw OWSGenericError("Unexpected payment processor in job record! \(jobRecord.paymentProcessor)")
        }

        let paymentMethod: DonationPaymentMethod? = try jobRecord.paymentMethod.map { paymentMethodString in
            guard let paymentMethod = DonationPaymentMethod(rawValue: paymentMethodString) else {
                throw OWSGenericError("[Donations] Unexpected payment method in job record! \(paymentMethodString)")
            }
            return paymentMethod
        }

        let receiptCredentialRequestContext = try ReceiptCredentialRequestContext(
            contents: [UInt8](jobRecord.receiptCredentialRequestContext)
        )
        let receiptCredentialRequest = try ReceiptCredentialRequest(
            contents: [UInt8](jobRecord.receiptCredentialRequest)
        )
        let receiptCredentialPresentation = try jobRecord.receiptCredentialPresentation.map {
            try ReceiptCredentialPresentation(contents: [UInt8]($0))
        }

        let paymentType: PaymentType
        if jobRecord.isBoost {
            guard
                let value = jobRecord.amount.map({ $0 as Decimal }),
                let currencyCode = jobRecord.currencyCode
            else {
                throw OWSGenericError("[Donations] Boost job record missing amount!")
            }
            paymentType = .oneTimeBoost(
                paymentIntentId: jobRecord.boostPaymentIntentID,
                amount: FiatMoney(currencyCode: currencyCode, value: value)
            )
        } else {
            paymentType = .recurringSubscription(
                subscriberId: jobRecord.subscriberID,
                targetSubscriptionLevel: jobRecord.targetSubscriptionLevel,
                priorSubscriptionLevel: jobRecord.priorSubscriptionLevel,
                isNewSubscription: jobRecord.isNewSubscription,
                shouldSuppressPaymentAlreadyRedeemed: jobRecord.shouldSuppressPaymentAlreadyRedeemed
            )
        }

        return Configuration(
            paymentMethod: paymentMethod,
            paymentProcessor: paymentProcessor,
            paymentType: paymentType,
            receiptCredentialRequest: receiptCredentialRequest,
            receiptCredentialRequestContext: receiptCredentialRequestContext,
            receiptCredentialPresentation: receiptCredentialPresentation
        )
    }

    // MARK: - Running

    func runJobAttempt(_ jobRecord: ReceiptCredentialRedemptionJobRecord) async -> JobAttemptResult {
        do {
            return try await _runJobAttempt(jobRecord)
        } catch {
            if error.isRetryable {
                // In practice, the only retryable errors are network failures.
                owsAssertDebug(error.isNetworkFailureOrTimeout)
                return .retryAfter(triggerExponentialRetry(jobRecord: jobRecord))
            }
            Logger.warn("[Donations] Job encountered unexpected terminal error")
            return await databaseStorage.awaitableWrite { tx in
                jobRecord.anyRemove(transaction: tx)
                return .finished(.failure(error))
            }
        }
    }

    func didFinishJob(_ jobRecordId: JobRecord.RowId, result: JobResult) async {
        switch result.ranSuccessfullyOrError {
        case .success:
            Logger.info("[Donations] Redemption job succeeded")
            ReceiptCredentialRedemptionJob.postNotification(name: ReceiptCredentialRedemptionJob.didSucceedNotification)
            future?.resolve(())
        case .failure(let error):
            ReceiptCredentialRedemptionJob.postNotification(name: ReceiptCredentialRedemptionJob.didFailNotification)
            future?.reject(error)
        }
    }

    private func _runJobAttempt(_ jobRecord: ReceiptCredentialRedemptionJobRecord) async throws -> JobAttemptResult {
        // First, load a bunch of state that *could* fail. If it does, the
        // operation can't ever succeed, so we throw it away.
        let configuration = try parseJobRecord(jobRecord)

        Logger.info("[Donations] Running job for \(configuration.paymentType).")

        // When the app relaunches, we'll try to restart all pending redemption
        // jobs. If one is for SEPA, and if that job hit a "still processing" error
        // in the past 24 hours, don't check again until 24 hours after the error.
        if let retryDelay = sepaRetryDelay(configuration: configuration) {
            return .retryAfter(retryDelay, canRetryEarly: false)
        }

        // In order to properly show the "you have a new badge" UI after this job
        // succeeds, we need to know what badges we had beforehand.
        let badgesSnapshotBeforeJob: ProfileBadgesSnapshot = .current()

        let badge: ProfileBadge
        if let cachedBadge {
            badge = cachedBadge
        } else {
            badge = try await loadBadge(paymentType: configuration.paymentType)
            cachedBadge = badge
        }

        let amount: FiatMoney
        if let cachedAmount {
            amount = cachedAmount
        } else {
            amount = try await loadAmount(paymentType: configuration.paymentType)
            cachedAmount = amount
        }

        let receiptCredentialPresentation: ReceiptCredentialPresentation
        if let persistedReceiptCredentialPresentation = configuration.receiptCredentialPresentation {
            Logger.info("[Donations] Using persisted receipt credential presentation")
            receiptCredentialPresentation = persistedReceiptCredentialPresentation
        } else {
            Logger.info("[Donations] Creating new receipt credential presentation")
            do {
                receiptCredentialPresentation = try await fetchReceiptCredentialPresentation(
                    jobRecord: jobRecord,
                    configuration: configuration,
                    badge: badge,
                    amount: amount
                )
            } catch let error as SubscriptionManagerImpl.KnownReceiptCredentialRequestError {
                let errorCode = error.errorCode
                let chargeFailureCodeIfPaymentFailed = error.chargeFailureCodeIfPaymentFailed
                let paymentMethod = configuration.paymentMethod
                let paymentType = configuration.paymentType

                return await databaseStorage.awaitableWrite { tx in
                    if
                        errorCode == .paymentIntentRedeemed,
                        case .recurringSubscription(_, _, _, _, shouldSuppressPaymentAlreadyRedeemed: true) = paymentType
                    {
                        Logger.warn("[Donations] Suppressing payment-already-redeemed error.")
                        jobRecord.anyRemove(transaction: tx)
                        return .finished(.success(()))
                    }

                    self.persistErrorCode(
                        errorCode: errorCode,
                        chargeFailureCodeIfPaymentFailed: chargeFailureCodeIfPaymentFailed,
                        configuration: configuration,
                        badge: badge,
                        amount: amount,
                        tx: tx.asV2Write
                    )

                    if errorCode == .paymentStillProcessing {
                        let (retryInterval, maxRetries) = self.stillProcessingRetryParameters(
                            paymentType: paymentType,
                            paymentMethod: paymentMethod
                        )
                        if jobRecord.failureCount < maxRetries {
                            Logger.warn("[Donations] Payment still processing; scheduling retry…")
                            jobRecord.addFailure(tx: tx)
                            switch retryInterval {
                            case .exponential:
                                return .retryAfter(self.triggerExponentialRetry(jobRecord: jobRecord))
                            case .sepa:
                                return .retryAfter(Constants.sepaRetryInterval, canRetryEarly: false)
                            }
                        }
                    }

                    Logger.warn("[Donations] Couldn't fetch credential; aborting: \(errorCode)")
                    jobRecord.anyRemove(transaction: tx)
                    return .finished(.failure(error))
                }
            }
        }

        try await SubscriptionManagerImpl.redeemReceiptCredentialPresentation(
            receiptCredentialPresentation: receiptCredentialPresentation
        ).awaitable()

        return await databaseStorage.awaitableWrite { tx in
            self.receiptCredentialResultStore.clearRequestError(
                errorMode: configuration.paymentType.receiptCredentialResultMode,
                tx: tx.asV2Write
            )
            self.receiptCredentialResultStore.setRedemptionSuccess(
                success: ReceiptCredentialRedemptionSuccess(
                    badgesSnapshotBeforeJob: badgesSnapshotBeforeJob,
                    badge: badge,
                    paymentMethod: configuration.paymentMethod
                ),
                successMode: configuration.paymentType.receiptCredentialResultMode,
                tx: tx.asV2Write
            )

            DonationReceipt(
                receiptType: configuration.paymentType.donationReceiptType,
                timestamp: Date(),
                amount: amount
            ).anyInsert(transaction: tx)

            jobRecord.anyRemove(transaction: tx)
            return .finished(.success(()))
        }
    }

    var cachedBadge: ProfileBadge?

    private func loadBadge(paymentType: PaymentType) async throws -> ProfileBadge {
        switch paymentType {
        case .oneTimeBoost:
            return try await SubscriptionManagerImpl.getBoostBadge().awaitable()
        case let .recurringSubscription(_, targetSubscriptionLevel, _, _, _):
            return try await SubscriptionManagerImpl.getSubscriptionBadge(
                subscriptionLevel: targetSubscriptionLevel
            ).awaitable()
        }
    }

    var cachedAmount: FiatMoney?

    private func loadAmount(paymentType: PaymentType) async throws -> FiatMoney {
        switch paymentType {
        case .oneTimeBoost(paymentIntentId: _, amount: let amount):
            return amount
        case let .recurringSubscription(subscriberId, _, _, _, _):
            let subscription = try await SubscriptionManagerImpl.getCurrentSubscriptionStatus(for: subscriberId).awaitable()
            guard let subscription else {
                throw OWSAssertionError("Missing subscription")
            }
            Logger.info("[Donations] Fetched current subscription. \(subscription.debugDescription)")
            return subscription.amount
        }
    }

    private func fetchReceiptCredentialPresentation(
        jobRecord: ReceiptCredentialRedemptionJobRecord,
        configuration: Configuration,
        badge: ProfileBadge,
        amount: FiatMoney
    ) async throws -> ReceiptCredentialPresentation {
        let receiptCredentialPresentation: ReceiptCredentialPresentation
        switch configuration.paymentType {
        case let .oneTimeBoost(paymentIntentId: paymentIntentId, amount: _):
            Logger.info("[Donations] Durable job requesting receipt for boost")
            receiptCredentialPresentation = try await SubscriptionManagerImpl.requestReceiptCredentialPresentation(
                boostPaymentIntentId: paymentIntentId,
                expectedBadgeLevel: .boostBadge,
                paymentProcessor: configuration.paymentProcessor,
                context: configuration.receiptCredentialRequestContext,
                request: configuration.receiptCredentialRequest
            ).awaitable()

        case let .recurringSubscription(subscriberId, targetSubscriptionLevel, priorSubscriptionLevel, _, _):
            Logger.info("[Donations] Durable job requesting receipt for subscription")
            receiptCredentialPresentation = try await SubscriptionManagerImpl.requestReceiptCredentialPresentation(
                subscriberId: subscriberId,
                targetSubscriptionLevel: targetSubscriptionLevel,
                priorSubscriptionLevel: priorSubscriptionLevel,
                context: configuration.receiptCredentialRequestContext,
                request: configuration.receiptCredentialRequest
            ).awaitable()
        }
        await databaseStorage.awaitableWrite { tx in
            jobRecord.setReceiptCredentialPresentation(receiptCredentialPresentation.serialize().asData, tx: tx)
        }
        return receiptCredentialPresentation
    }

    private func persistErrorCode(
        errorCode: ReceiptCredentialRequestError.ErrorCode,
        chargeFailureCodeIfPaymentFailed: String?,
        configuration: Configuration,
        badge: ProfileBadge,
        amount: FiatMoney,
        tx: DBWriteTransaction
    ) {
        let receiptCredentialRequestError: ReceiptCredentialRequestError = {
            if let paymentMethod = configuration.paymentMethod {
                return ReceiptCredentialRequestError(
                    errorCode: errorCode,
                    chargeFailureCodeIfPaymentFailed: chargeFailureCodeIfPaymentFailed,
                    badge: badge,
                    amount: amount,
                    paymentMethod: paymentMethod
                )
            } else {
                Logger.warn("[Donations] Building legacy error, job record missing fields!")
                return ReceiptCredentialRequestError(legacyErrorCode: errorCode)
            }
        }()

        receiptCredentialResultStore.setRequestError(
            error: receiptCredentialRequestError,
            errorMode: configuration.paymentType.receiptCredentialResultMode,
            tx: tx
        )
    }
}

// MARK: - Notifications

public enum ReceiptCredentialRedemptionJob {
    public static let didSucceedNotification = NSNotification.Name("ReceiptCredentialRedemptionJob.DidSucceed")
    public static let didFailNotification = NSNotification.Name("ReceiptCredentialRedemptionJob.DidFail")

    fileprivate static func postNotification(name: NSNotification.Name) {
        NotificationCenter.default.postNotificationNameAsync(name, object: nil, userInfo: nil)
    }
}
