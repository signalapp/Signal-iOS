//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
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
/// fail with a "still processing" error.
public class DonationReceiptCredentialRedemptionJobQueue {
    private let jobQueueRunner: JobQueueRunner<
        JobRecordFinderImpl<DonationReceiptCredentialRedemptionJobRecord>,
        DonationReceiptCredentialRedemptionJobRunnerFactory,
    >
    private let jobRunnerFactory: DonationReceiptCredentialRedemptionJobRunnerFactory
    private let logger: PrefixedLogger

    public init(
        dateProvider: @escaping DateProvider,
        db: any DB,
        donationReceiptCredentialResultStore: DonationReceiptCredentialResultStore,
        networkManager: NetworkManager,
        profileManager: ProfileManager,
        reachabilityManager: SSKReachabilityManager,
        tsAccountManager: TSAccountManager,
    ) {
        self.jobRunnerFactory = DonationReceiptCredentialRedemptionJobRunnerFactory(
            dateProvider: dateProvider,
            db: db,
            donationReceiptCredentialResultStore: donationReceiptCredentialResultStore,
            logger: .donations,
            networkManager: networkManager,
            profileManager: profileManager,
            tsAccountManager: tsAccountManager,
        )
        self.jobQueueRunner = JobQueueRunner(
            canExecuteJobsConcurrently: true,
            db: db,
            jobFinder: JobRecordFinderImpl(db: db),
            jobRunnerFactory: self.jobRunnerFactory,
        )
        self.logger = .donations

        self.jobQueueRunner.listenForReachabilityChanges(reachabilityManager: reachabilityManager)
    }

    func start(appContext: AppContext) {
        guard appContext.isMainApp else { return }
        jobQueueRunner.start(shouldRestartExistingJobs: true)
    }

    // MARK: -

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
        tx: DBWriteTransaction,
    ) -> DonationReceiptCredentialRedemptionJobRecord {
        logger.info("Adding a boost redemption job.")

        let jobRecord = DonationReceiptCredentialRedemptionJobRecord(
            paymentProcessor: paymentProcessor.rawValue,
            paymentMethod: paymentMethod.rawValue,
            receiptCredentialRequestContext: receiptCredentialRequestContext.serialize(),
            receiptCredentialRequest: receiptCredentialRequest.serialize(),
            subscriberID: Data(), // Unused
            targetSubscriptionLevel: 0, // Unused
            priorSubscriptionLevel: 0, // Unused
            isNewSubscription: true, // Unused
            isBoost: true,
            amount: amount.value,
            currencyCode: amount.currencyCode,
            boostPaymentIntentID: boostPaymentIntentID,
        )

        jobRecord.anyInsert(transaction: tx)

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
    func saveSubscriptionRedemptionJob(
        paymentProcessor: DonationPaymentProcessor,
        paymentMethod: DonationPaymentMethod?,
        receiptCredentialRequestContext: ReceiptCredentialRequestContext,
        receiptCredentialRequest: ReceiptCredentialRequest,
        subscriberID: Data,
        targetSubscriptionLevel: UInt,
        priorSubscriptionLevel: UInt?,
        isNewSubscription: Bool,
        tx: DBWriteTransaction,
    ) -> DonationReceiptCredentialRedemptionJobRecord {
        logger.info("Adding a subscription redemption job.")

        let jobRecord = DonationReceiptCredentialRedemptionJobRecord(
            paymentProcessor: paymentProcessor.rawValue,
            paymentMethod: paymentMethod?.rawValue,
            receiptCredentialRequestContext: receiptCredentialRequestContext.serialize(),
            receiptCredentialRequest: receiptCredentialRequest.serialize(),
            subscriberID: subscriberID,
            targetSubscriptionLevel: targetSubscriptionLevel,
            priorSubscriptionLevel: priorSubscriptionLevel ?? 0,
            isNewSubscription: isNewSubscription,
            isBoost: false,
            amount: nil,
            currencyCode: nil,
            boostPaymentIntentID: String(), // Unused
        )

        jobRecord.anyInsert(transaction: tx)

        return jobRecord
    }

    public func runRedemptionJob(
        jobRecord: DonationReceiptCredentialRedemptionJobRecord,
    ) async throws {
        logger.info("Running redemption job.")

        try await withCheckedThrowingContinuation { continuation in
            self.jobQueueRunner.addPersistedJob(
                jobRecord,
                runner: self.jobRunnerFactory.buildRunner(continuation: continuation),
            )
        }
    }
}

// MARK: -

extension DonationReceiptCredentialRedemptionJobQueue {
    func subscriptionJobExists(
        subscriberID: Data,
        tx: DBReadTransaction,
    ) -> Bool {
        return DonationReceiptCredentialRedemptionJobFinder()
            .subscriptionJobExists(subscriberID: subscriberID, tx: tx)
    }
}

struct DonationReceiptCredentialRedemptionJobFinder {
    init() {}

    func subscriptionJobExists(
        subscriberID: Data,
        tx: DBReadTransaction,
    ) -> Bool {
        let sql = """
            SELECT EXISTS (
                SELECT 1 FROM \(DonationReceiptCredentialRedemptionJobRecord.databaseTableName)
                WHERE \(DonationReceiptCredentialRedemptionJobRecord.columnName(.recordType)) IS ?
                AND \(DonationReceiptCredentialRedemptionJobRecord.columnName(.subscriberID)) IS ?
            )
        """
        let arguments: StatementArguments = [
            SDSRecordType.receiptCredentialRedemptionJobRecord.rawValue,
            subscriberID,
        ]

        return failIfThrows {
            return try Bool.fetchOne(tx.database, sql: sql, arguments: arguments) ?? false
        }
    }
}

// MARK: -

private class DonationReceiptCredentialRedemptionJobRunnerFactory: JobRunnerFactory {
    private let dateProvider: DateProvider
    private let db: DB
    private let donationReceiptCredentialResultStore: DonationReceiptCredentialResultStore
    private let logger: PrefixedLogger
    private let networkManager: NetworkManager
    private let profileManager: ProfileManager
    private let tsAccountManager: TSAccountManager

    init(
        dateProvider: @escaping DateProvider,
        db: DB,
        donationReceiptCredentialResultStore: DonationReceiptCredentialResultStore,
        logger: PrefixedLogger,
        networkManager: NetworkManager,
        profileManager: ProfileManager,
        tsAccountManager: TSAccountManager,
    ) {
        self.dateProvider = dateProvider
        self.db = db
        self.donationReceiptCredentialResultStore = donationReceiptCredentialResultStore
        self.logger = logger
        self.networkManager = networkManager
        self.profileManager = profileManager
        self.tsAccountManager = tsAccountManager
    }

    func buildRunner() -> DonationReceiptCredentialRedemptionJobRunner { buildRunner(continuation: nil) }

    func buildRunner(continuation: CheckedContinuation<Void, Error>?) -> DonationReceiptCredentialRedemptionJobRunner {
        return DonationReceiptCredentialRedemptionJobRunner(
            continuation: continuation,
            dateProvider: dateProvider,
            db: db,
            donationReceiptCredentialResultStore: donationReceiptCredentialResultStore,
            networkManager: networkManager,
            profileManager: profileManager,
            tsAccountManager: tsAccountManager,
        )
    }
}

// MARK: -

private class DonationReceiptCredentialRedemptionJobRunner: JobRunner {
    private let continuation: CheckedContinuation<Void, Error>?

    private let dateProvider: DateProvider
    private let db: DB
    private let donationReceiptCredentialResultStore: DonationReceiptCredentialResultStore
    private let networkManager: NetworkManager
    private let profileManager: ProfileManager
    private let receiptCredentialManager: ReceiptCredentialManager
    private let tsAccountManager: TSAccountManager

    private var logger: PrefixedLogger = .donations
    private var transientFailureCount: UInt = 0

    init(
        continuation: CheckedContinuation<Void, Error>?,
        dateProvider: @escaping DateProvider,
        db: DB,
        donationReceiptCredentialResultStore: DonationReceiptCredentialResultStore,
        networkManager: NetworkManager,
        profileManager: ProfileManager,
        tsAccountManager: TSAccountManager,
    ) {
        self.continuation = continuation

        self.dateProvider = dateProvider
        self.db = db
        self.donationReceiptCredentialResultStore = donationReceiptCredentialResultStore
        self.networkManager = networkManager
        self.profileManager = profileManager
        self.receiptCredentialManager = ReceiptCredentialManager(
            dateProvider: dateProvider,
            logger: logger,
            networkManager: networkManager,
        )
        self.tsAccountManager = tsAccountManager
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
        )

        var receiptCredentialResultMode: DonationReceiptCredentialResultStore.Mode {
            switch self {
            case .oneTimeBoost: return .oneTimeBoost
            case .recurringSubscription(_, _, _, isNewSubscription: true): return .recurringSubscriptionInitiation
            case .recurringSubscription(_, _, _, isNewSubscription: false): return .recurringSubscriptionRenewal
            }
        }

        var donationReceiptType: DonationReceipt.DonationReceiptType {
            switch self {
            case .oneTimeBoost:
                return .boost
            case let .recurringSubscription(_, targetSubscriptionLevel, _, _):
                return .subscription(subscriptionLevel: targetSubscriptionLevel)
            }
        }

        var description: String {
            switch self {
            case .oneTimeBoost: return "one-time"
            case .recurringSubscription(_, _, _, isNewSubscription: true): return "recurring-initiation"
            case .recurringSubscription(_, _, _, isNewSubscription: false): return "recurring-renewal"
            }
        }
    }

    // MARK: - Retries

    private enum Constants {
        /// Defines the time between retries for SEPA and recurring iDEAL transactions.
        static let sepaRetryInterval: TimeInterval = TSConstants.isUsingProductionService ? .day : .minute
    }

    private enum RetryMode {
        case exponential
        case sepa
    }

    private func retryModeIfStillProcessing(
        paymentType: PaymentType,
        paymentMethod: DonationPaymentMethod?,
    ) -> RetryMode {
        switch paymentMethod {
        case nil, .applePay, .creditOrDebitCard, .paypal:
            return .exponential
        case .sepa:
            return .sepa
        case .ideal:
            switch paymentType {
            case .oneTimeBoost:
                return .exponential
            case .recurringSubscription:
                return .sepa
            }
        }
    }

    /// Returns an exponential-backoff retry delay that increases with each
    /// subsequent call to this method.
    private func incrementExponentialRetryDelay() -> TimeInterval {
        transientFailureCount += 1

        return OWSOperation.retryIntervalForExponentialBackoff(
            failureCount: transientFailureCount,
            maxAverageBackoff: .day,
        )
    }

    private func sepaRetryDelay(configuration: Configuration) -> TimeInterval? {
        switch retryModeIfStillProcessing(
            paymentType: configuration.paymentType,
            paymentMethod: configuration.paymentMethod,
        ) {
        case .exponential:
            return nil
        case .sepa:
            break
        }

        let priorError = db.read(block: { tx -> DonationReceiptCredentialRequestError? in
            return donationReceiptCredentialResultStore.getRequestError(
                errorMode: configuration.paymentType.receiptCredentialResultMode,
                tx: tx,
            )
        })
        guard let priorError, priorError.errorCode == .paymentStillProcessing else {
            return nil
        }

        let nextAttemptDate = priorError.creationDate.addingTimeInterval(Constants.sepaRetryInterval)
        let delay = nextAttemptDate.timeIntervalSince(dateProvider())
        guard delay > 0 else {
            return nil
        }

        owsAssertDebug(
            priorError.paymentMethod == .sepa || priorError.paymentMethod == .ideal,
            logger: logger,
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
            contents: jobRecord.receiptCredentialRequestContext,
        )
        let receiptCredentialRequest = try ReceiptCredentialRequest(
            contents: jobRecord.receiptCredentialRequest,
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
                amount: FiatMoney(currencyCode: currencyCode, value: value),
            )
        } else {
            paymentType = .recurringSubscription(
                subscriberId: jobRecord.subscriberID,
                targetSubscriptionLevel: jobRecord.targetSubscriptionLevel,
                priorSubscriptionLevel: jobRecord.priorSubscriptionLevel,
                isNewSubscription: jobRecord.isNewSubscription,
            )
        }

        return Configuration(
            paymentMethod: paymentMethod,
            paymentProcessor: paymentProcessor,
            paymentType: paymentType,
            receiptCredentialRequest: receiptCredentialRequest,
            receiptCredentialRequestContext: receiptCredentialRequestContext,
            receiptCredentialPresentation: try jobRecord.getReceiptCredentialPresentation(),
        )
    }

    // MARK: - Running

    func runJobAttempt(_ jobRecord: DonationReceiptCredentialRedemptionJobRecord) async -> JobAttemptResult<Void> {
        do {
            return try await _runJobAttempt(jobRecord)
        } catch {
            if error.isRetryable {
                // In practice, the only retryable errors are network failures.
                owsAssertDebug(
                    error.isNetworkFailureOrTimeout,
                    logger: logger,
                )
                return .retryAfter(incrementExponentialRetryDelay())
            }
            logger.warn("Job encountered unexpected terminal error")
            return await db.awaitableWrite { tx in
                jobRecord.anyRemove(transaction: tx)
                return .finished(.failure(error))
            }
        }
    }

    func didFinishJob(_ jobRecordId: JobRecord.RowId, result: JobResult<Void>) async {
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

    private func _runJobAttempt(_ jobRecord: DonationReceiptCredentialRedemptionJobRecord) async throws -> JobAttemptResult<Void> {
        // First, load a bunch of state that *could* fail. If it does, the
        // operation can't ever succeed, so we throw it away.
        let configuration = try parseJobRecord(jobRecord)

        // Now that we know what type of job we are, suffix the logger.
        logger = logger.suffixed(with: "[\(configuration.paymentType)]")

        _ = try tsAccountManager.registeredStateWithMaybeSneakyTransaction()
        let badgesSnapshotBeforeJob = db.read { tx in
            // In order to properly show the "you have a new badge" UI after this job
            // succeeds, we need to know what badges we had beforehand.
            return ProfileBadgesSnapshot.forLocalProfile(profileManager: profileManager, tx: tx)
        }

        logger.info("Running job.")

        // When the app relaunches, we'll try to restart all pending redemption
        // jobs. If one is for SEPA, and if that job hit a "still processing" error
        // in the past 24 hours, don't check again until 24 hours after the error.
        if let retryDelay = sepaRetryDelay(configuration: configuration) {
            logger.info("Skipping SEPA job: in SEPA retry-delay period!")
            return .retryAfter(retryDelay, canRetryEarly: false)
        }

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
                    amount: amount,
                )
            } catch let error as ReceiptCredentialRequestError {
                let errorCode = error.errorCode
                let chargeFailureCodeIfPaymentFailed = error.chargeFailureCodeIfPaymentFailed
                let paymentMethod = configuration.paymentMethod
                let paymentType = configuration.paymentType

                return await db.awaitableWrite { tx in
                    if errorCode == .paymentIntentRedeemed {
                        /// This error indicates that the user has gotten their
                        /// badge via another redemption from another job. No
                        /// harm done, so we'll treat these like a success.
                        logger.warn("Suppressing payment-already-redeemed error.")
                        jobRecord.anyRemove(transaction: tx)
                        return .finished(.success(()))
                    }

                    persistErrorCode(
                        errorCode: errorCode,
                        chargeFailureCodeIfPaymentFailed: chargeFailureCodeIfPaymentFailed,
                        configuration: configuration,
                        badge: badge,
                        amount: amount,
                        tx: tx,
                    )

                    switch errorCode {
                    case .paymentStillProcessing:
                        logger.warn("Payment still processing; scheduling retry…")

                        switch retryModeIfStillProcessing(
                            paymentType: paymentType,
                            paymentMethod: paymentMethod,
                        ) {
                        case .exponential:
                            return .retryAfter(incrementExponentialRetryDelay())
                        case .sepa:
                            return .retryAfter(Constants.sepaRetryInterval, canRetryEarly: false)
                        }
                    case .paymentFailed,
                         .localValidationFailed,
                         .serverValidationFailed,
                         .paymentNotFound,
                         .paymentIntentRedeemed:
                        logger.warn("Couldn't fetch credential; aborting: \(errorCode)")
                        jobRecord.anyRemove(transaction: tx)
                        return .finished(.failure(error))
                    }
                }
            }
        }

        try await DonationSubscriptionManager.redeemReceiptCredentialPresentation(
            receiptCredentialPresentation: receiptCredentialPresentation,
        )

        return await db.awaitableWrite { tx in
            switch configuration.paymentType.receiptCredentialResultMode {
            case .oneTimeBoost:
                donationReceiptCredentialResultStore
                    .clearRequestError(errorMode: .oneTimeBoost, tx: tx)
            case .recurringSubscriptionInitiation, .recurringSubscriptionRenewal:
                // For a time, we might have enqueued both the "initiation" job
                // and one or more "renewal" jobs for the same subscription
                // period; for example, if a SEPA initiation job was processing
                // for several days, we might have later enqueued a redundant
                // renewal job. If the initiation job persisted an error (such
                // as "still processing", and the renewal job later succeeded,
                // then the initiation job may never have gotten to clear its
                // error.
                //
                // This shouldn't happen anymore, but we can clear all errors
                // (including any orphaned errors) now that we've succeeded.
                donationReceiptCredentialResultStore
                    .clearRequestErrorForAnyRecurringSubscription(tx: tx)
            }

            self.donationReceiptCredentialResultStore.clearRequestError(
                errorMode: configuration.paymentType.receiptCredentialResultMode,
                tx: tx,
            )
            self.donationReceiptCredentialResultStore.setRedemptionSuccess(
                success: DonationReceiptCredentialRedemptionSuccess(
                    badgesSnapshotBeforeJob: badgesSnapshotBeforeJob,
                    badge: badge,
                    paymentMethod: configuration.paymentMethod,
                ),
                successMode: configuration.paymentType.receiptCredentialResultMode,
                tx: tx,
            )

            DonationReceipt(
                receiptType: configuration.paymentType.donationReceiptType,
                timestamp: Date(),
                amount: amount,
            ).anyInsert(transaction: tx)

            jobRecord.anyRemove(transaction: tx)
            return .finished(.success(()))
        }
    }

    var cachedBadge: ProfileBadge?

    private func loadBadge(paymentType: PaymentType) async throws -> ProfileBadge {
        switch paymentType {
        case .oneTimeBoost:
            return try await DonationSubscriptionManager.getBoostBadge()
        case let .recurringSubscription(_, targetSubscriptionLevel, _, _):
            return try await DonationSubscriptionManager.getSubscriptionBadge(subscriptionLevel: targetSubscriptionLevel)
        }
    }

    var cachedAmount: FiatMoney?

    private func loadAmount(paymentType: PaymentType) async throws -> FiatMoney {
        switch paymentType {
        case .oneTimeBoost(paymentIntentId: _, amount: let amount):
            return amount
        case let .recurringSubscription(subscriberId, _, _, _):
            let subscription = try await SubscriptionFetcher(networkManager: networkManager)
                .fetch(subscriberID: subscriberId)
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
        amount: FiatMoney,
    ) async throws -> ReceiptCredentialPresentation {
        let receiptCredential: ReceiptCredential
        switch configuration.paymentType {
        case let .oneTimeBoost(paymentIntentId: paymentIntentId, amount: _):
            logger.info("Durable job requesting receipt for boost")
            receiptCredential = try await receiptCredentialManager.requestReceiptCredential(
                via: OWSRequestFactory.boostReceiptCredentials(
                    paymentIntentID: paymentIntentId,
                    paymentProcessor: configuration.paymentProcessor,
                    receiptCredentialRequest: configuration.receiptCredentialRequest,
                ),
                isValidReceiptLevelPredicate: { receiptLevel in
                    return receiptLevel == OneTimeBadgeLevel.boostBadge.rawValue
                },
                context: configuration.receiptCredentialRequestContext,
            )

        case let .recurringSubscription(subscriberId, targetSubscriptionLevel, priorSubscriptionLevel, _):
            logger.info("Durable job requesting receipt for subscription")
            receiptCredential = try await receiptCredentialManager.requestReceiptCredential(
                via: OWSRequestFactory.subscriptionReceiptCredentialsRequest(
                    subscriberID: subscriberId,
                    receiptCredentialRequest: configuration.receiptCredentialRequest,
                ),
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
            )
        }

        await db.awaitableWrite { tx in
            jobRecord.setReceiptCredential(receiptCredential, tx: tx)
        }

        return try ReceiptCredentialManager.generateReceiptCredentialPresentation(
            receiptCredential: receiptCredential,
        )
    }

    private func persistErrorCode(
        errorCode: ReceiptCredentialRequestError.ErrorCode,
        chargeFailureCodeIfPaymentFailed: String?,
        configuration: Configuration,
        badge: ProfileBadge,
        amount: FiatMoney,
        tx: DBWriteTransaction,
    ) {
        let receiptCredentialRequestError = DonationReceiptCredentialRequestError(
            errorCode: errorCode,
            chargeFailureCodeIfPaymentFailed: chargeFailureCodeIfPaymentFailed,
            badge: badge,
            amount: amount,
            paymentMethod: configuration.paymentMethod,
            now: dateProvider(),
        )

        donationReceiptCredentialResultStore.setRequestError(
            error: receiptCredentialRequestError,
            errorMode: configuration.paymentType.receiptCredentialResultMode,
            tx: tx,
        )
    }
}

// MARK: - Notifications

public enum DonationReceiptCredentialRedemptionJob {
    public static let didSucceedNotification = NSNotification.Name("DonationReceiptCredentialRedemptionJob.DidSucceed")
    public static let didFailNotification = NSNotification.Name("DonationReceiptCredentialRedemptionJob.DidFail")

    fileprivate static func postNotification(name: NSNotification.Name) {
        NotificationCenter.default.postOnMainThread(name: name, object: nil, userInfo: nil)
    }
}

// MARK: -

private extension PrefixedLogger {
    static let donations = PrefixedLogger(prefix: "[Donations]")
}
