//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

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
public class DonationReceiptCredentialRedemptionJobQueue {
    private let jobQueueRunner: JobQueueRunner<
        JobRecordFinderImpl<DonationReceiptCredentialRedemptionJobRecord>,
        DonationReceiptCredentialRedemptionJobRunnerFactory
    >
    private let jobRunnerFactory: DonationReceiptCredentialRedemptionJobRunnerFactory

    private let logger: PrefixedLogger = .donations

    public init(db: any DB, reachabilityManager: SSKReachabilityManager) {
        self.jobRunnerFactory = DonationReceiptCredentialRedemptionJobRunnerFactory()
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

    /// Persists and returns a `JobRecord` for redeeming a boost donation.
    ///
    /// - Important
    /// The returned job must be passed to ``runRedemptionJob(jobRecord:)``.
    func saveBoostRedemptionJob(
        amount: FiatMoney,
        paymentProcessor: DonationPaymentProcessor,
        paymentMethod: DonationPaymentMethod,
        receiptCredentialRequestContext: ReceiptCredentialRequestContext,
        receiptCredentialRequest: ReceiptCredentialRequest,
        boostPaymentIntentID: String,
        tx: DBWriteTransaction
    ) -> DonationReceiptCredentialRedemptionJobRecord {
        logger.info("Adding a boost redemption job.")

        let jobRecord = DonationReceiptCredentialRedemptionJobRecord(
            paymentProcessor: paymentProcessor.rawValue,
            paymentMethod: paymentMethod.rawValue,
            receiptCredentialRequestContext: receiptCredentialRequestContext.serialize().asData,
            receiptCredentialRequest: receiptCredentialRequest.serialize().asData,
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

        jobRecord.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))

        return jobRecord
    }

    /// Persists and returns a `JobRecord` for redeeming a boost donation.
    ///
    /// - Important
    /// The returned job must be passed to ``runRedemptionJob(jobRecord:)``.
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
    func saveSubscriptionRedemptionJob(
        paymentProcessor: DonationPaymentProcessor,
        paymentMethod: DonationPaymentMethod?,
        receiptCredentialRequestContext: ReceiptCredentialRequestContext,
        receiptCredentialRequest: ReceiptCredentialRequest,
        subscriberID: Data,
        targetSubscriptionLevel: UInt,
        priorSubscriptionLevel: UInt?,
        isNewSubscription: Bool,
        shouldSuppressPaymentAlreadyRedeemed: Bool,
        tx: DBWriteTransaction
    ) -> DonationReceiptCredentialRedemptionJobRecord {
        logger.info("Adding a subscription redemption job.")

        let jobRecord = DonationReceiptCredentialRedemptionJobRecord(
            paymentProcessor: paymentProcessor.rawValue,
            paymentMethod: paymentMethod?.rawValue,
            receiptCredentialRequestContext: receiptCredentialRequestContext.serialize().asData,
            receiptCredentialRequest: receiptCredentialRequest.serialize().asData,
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

        jobRecord.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))

        return jobRecord
    }

    public func runRedemptionJob(
        jobRecord: DonationReceiptCredentialRedemptionJobRecord
    ) async throws {
        logger.info("Running redemption job.")

        try await withCheckedThrowingContinuation { continuation in
            self.jobQueueRunner.addPersistedJob(
                jobRecord,
                runner: self.jobRunnerFactory.buildRunner(continuation: continuation)
            )
        }
    }
}

private class DonationReceiptCredentialRedemptionJobRunnerFactory: JobRunnerFactory {
    func buildRunner() -> DonationReceiptCredentialRedemptionJobRunner { buildRunner(continuation: nil) }

    func buildRunner(continuation: CheckedContinuation<Void, Error>?) -> DonationReceiptCredentialRedemptionJobRunner {
        return DonationReceiptCredentialRedemptionJobRunner(continuation: continuation)
    }
}

private class DonationReceiptCredentialRedemptionJobRunner: JobRunner {
    private let logger: PrefixedLogger = .donations

    private let continuation: CheckedContinuation<Void, Error>?

    init(continuation: CheckedContinuation<Void, Error>?) {
        self.continuation = continuation
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

        var receiptCredentialResultMode: DonationReceiptCredentialResultStore.Mode {
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

    private var donationReceiptCredentialResultStore: DonationReceiptCredentialResultStore {
        DependenciesBridge.shared.donationReceiptCredentialResultStore
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

        let priorError = SSKEnvironment.shared.databaseStorageRef.read(block: { tx -> DonationReceiptCredentialRequestError? in
            return donationReceiptCredentialResultStore.getRequestError(
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
        owsAssertDebug(
            priorError.paymentMethod == .sepa || priorError.paymentMethod == .ideal,
            logger: logger
        )
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

    private func parseJobRecord(_ jobRecord: DonationReceiptCredentialRedemptionJobRecord) throws -> Configuration {
        guard let paymentProcessor = DonationPaymentProcessor(rawValue: jobRecord.paymentProcessor) else {
            throw OWSGenericError("Unexpected payment processor in job record! \(jobRecord.paymentProcessor)")
        }

        let paymentMethod: DonationPaymentMethod? = try jobRecord.paymentMethod.map { paymentMethodString in
            guard let paymentMethod = DonationPaymentMethod(rawValue: paymentMethodString) else {
                throw OWSGenericError("Unexpected payment method in job record! \(paymentMethodString)")
            }
            return paymentMethod
        }

        let receiptCredentialRequestContext = try ReceiptCredentialRequestContext(
            contents: [UInt8](jobRecord.receiptCredentialRequestContext)
        )
        let receiptCredentialRequest = try ReceiptCredentialRequest(
            contents: [UInt8](jobRecord.receiptCredentialRequest)
        )

        let paymentType: PaymentType
        if jobRecord.isBoost {
            guard
                let value = jobRecord.amount.map({ $0 as Decimal }),
                let currencyCode = jobRecord.currencyCode
            else {
                throw OWSGenericError("Boost job record missing amount!")
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
            receiptCredentialPresentation: try jobRecord.getReceiptCredentialPresentation()
        )
    }

    // MARK: - Running

    func runJobAttempt(_ jobRecord: DonationReceiptCredentialRedemptionJobRecord) async -> JobAttemptResult {
        do {
            return try await _runJobAttempt(jobRecord)
        } catch {
            if error.isRetryable {
                // In practice, the only retryable errors are network failures.
                owsAssertDebug(
                    error.isNetworkFailureOrTimeout,
                    logger: logger
                )
                return .retryAfter(triggerExponentialRetry(jobRecord: jobRecord))
            }
            logger.warn("Job encountered unexpected terminal error")
            return await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                jobRecord.anyRemove(transaction: tx)
                return .finished(.failure(error))
            }
        }
    }

    func didFinishJob(_ jobRecordId: JobRecord.RowId, result: JobResult) async {
        switch result.ranSuccessfullyOrError {
        case .success:
            logger.info("Redemption job succeeded")
            DonationReceiptCredentialRedemptionJob.postNotification(name: DonationReceiptCredentialRedemptionJob.didSucceedNotification)
            continuation?.resume()
        case .failure(let error):
            DonationReceiptCredentialRedemptionJob.postNotification(name: DonationReceiptCredentialRedemptionJob.didFailNotification)
            continuation?.resume(throwing: error)
        }
    }

    private func _runJobAttempt(_ jobRecord: DonationReceiptCredentialRedemptionJobRecord) async throws -> JobAttemptResult {
        // First, load a bunch of state that *could* fail. If it does, the
        // operation can't ever succeed, so we throw it away.
        let configuration = try parseJobRecord(jobRecord)

        logger.info("Running job for \(configuration.paymentType).")

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
            logger.info("Using persisted receipt credential presentation")
            receiptCredentialPresentation = persistedReceiptCredentialPresentation
        } else {
            logger.info("Creating new receipt credential presentation")
            do {
                receiptCredentialPresentation = try await fetchReceiptCredentialPresentation(
                    jobRecord: jobRecord,
                    configuration: configuration,
                    badge: badge,
                    amount: amount
                )
            } catch let error as DonationSubscriptionManager.KnownReceiptCredentialRequestError {
                let errorCode = error.errorCode
                let chargeFailureCodeIfPaymentFailed = error.chargeFailureCodeIfPaymentFailed
                let paymentMethod = configuration.paymentMethod
                let paymentType = configuration.paymentType

                return await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                    if
                        errorCode == .paymentIntentRedeemed,
                        case .recurringSubscription(_, _, _, _, shouldSuppressPaymentAlreadyRedeemed: true) = paymentType
                    {
                        self.logger.warn("Suppressing payment-already-redeemed error.")
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
                            self.logger.warn("Payment still processing; scheduling retry…")
                            jobRecord.addFailure(tx: tx)
                            switch retryInterval {
                            case .exponential:
                                return .retryAfter(self.triggerExponentialRetry(jobRecord: jobRecord))
                            case .sepa:
                                return .retryAfter(Constants.sepaRetryInterval, canRetryEarly: false)
                            }
                        }
                    }

                    self.logger.warn("Couldn't fetch credential; aborting: \(errorCode)")
                    jobRecord.anyRemove(transaction: tx)
                    return .finished(.failure(error))
                }
            }
        }

        try await DonationSubscriptionManager.redeemReceiptCredentialPresentation(
            receiptCredentialPresentation: receiptCredentialPresentation
        ).awaitable()

        return await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            self.donationReceiptCredentialResultStore.clearRequestError(
                errorMode: configuration.paymentType.receiptCredentialResultMode,
                tx: tx.asV2Write
            )
            self.donationReceiptCredentialResultStore.setRedemptionSuccess(
                success: DonationReceiptCredentialRedemptionSuccess(
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
            return try await DonationSubscriptionManager.getBoostBadge().awaitable()
        case let .recurringSubscription(_, targetSubscriptionLevel, _, _, _):
            return try await DonationSubscriptionManager.getSubscriptionBadge(
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
            let subscription = try await DonationSubscriptionManager.getCurrentSubscriptionStatus(for: subscriberId).awaitable()
            guard let subscription else {
                throw OWSAssertionError("Missing subscription", logger: logger)
            }
            logger.info("Fetched current subscription. \(subscription.debugDescription)")
            return subscription.amount
        }
    }

    private func fetchReceiptCredentialPresentation(
        jobRecord: DonationReceiptCredentialRedemptionJobRecord,
        configuration: Configuration,
        badge: ProfileBadge,
        amount: FiatMoney
    ) async throws -> ReceiptCredentialPresentation {
        let receiptCredential: ReceiptCredential
        switch configuration.paymentType {
        case let .oneTimeBoost(paymentIntentId: paymentIntentId, amount: _):
            logger.info("Durable job requesting receipt for boost")
            receiptCredential = try await DonationSubscriptionManager.requestReceiptCredential(
                boostPaymentIntentId: paymentIntentId,
                expectedBadgeLevel: .boostBadge,
                paymentProcessor: configuration.paymentProcessor,
                context: configuration.receiptCredentialRequestContext,
                request: configuration.receiptCredentialRequest,
                logger: logger
            ).awaitable()

        case let .recurringSubscription(subscriberId, targetSubscriptionLevel, priorSubscriptionLevel, _, _):
            logger.info("Durable job requesting receipt for subscription")
            receiptCredential = try await DonationSubscriptionManager.requestReceiptCredential(
                subscriberId: subscriberId,
                isValidReceiptLevelPredicate: { receiptLevel -> Bool in
                    // Validate that receipt credential level matches requested
                    // level, or prior subscription level.
                    if receiptLevel == targetSubscriptionLevel {
                        return true
                    } else if priorSubscriptionLevel != 0 {
                        return receiptLevel == priorSubscriptionLevel
                    }

                    return false
                },
                context: configuration.receiptCredentialRequestContext,
                request: configuration.receiptCredentialRequest,
                logger: logger
            ).awaitable()
        }

        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            jobRecord.setReceiptCredential(receiptCredential, tx: tx)
        }

        return try DonationSubscriptionManager.generateReceiptCredentialPresentation(
            receiptCredential: receiptCredential
        )
    }

    private func persistErrorCode(
        errorCode: DonationReceiptCredentialRequestError.ErrorCode,
        chargeFailureCodeIfPaymentFailed: String?,
        configuration: Configuration,
        badge: ProfileBadge,
        amount: FiatMoney,
        tx: DBWriteTransaction
    ) {
        let receiptCredentialRequestError: DonationReceiptCredentialRequestError = {
            if let paymentMethod = configuration.paymentMethod {
                return DonationReceiptCredentialRequestError(
                    errorCode: errorCode,
                    chargeFailureCodeIfPaymentFailed: chargeFailureCodeIfPaymentFailed,
                    badge: badge,
                    amount: amount,
                    paymentMethod: paymentMethod
                )
            } else {
                logger.warn("Building legacy error, job record missing fields!")
                return DonationReceiptCredentialRequestError(legacyErrorCode: errorCode)
            }
        }()

        donationReceiptCredentialResultStore.setRequestError(
            error: receiptCredentialRequestError,
            errorMode: configuration.paymentType.receiptCredentialResultMode,
            tx: tx
        )
    }
}

// MARK: - Notifications

public enum DonationReceiptCredentialRedemptionJob {
    public static let didSucceedNotification = NSNotification.Name("DonationReceiptCredentialRedemptionJob.DidSucceed")
    public static let didFailNotification = NSNotification.Name("DonationReceiptCredentialRedemptionJob.DidFail")

    fileprivate static func postNotification(name: NSNotification.Name) {
        NotificationCenter.default.postNotificationNameAsync(name, object: nil, userInfo: nil)
    }
}

// MARK: -

private extension PrefixedLogger {
    static let donations = PrefixedLogger(prefix: "[Donations]")
}
