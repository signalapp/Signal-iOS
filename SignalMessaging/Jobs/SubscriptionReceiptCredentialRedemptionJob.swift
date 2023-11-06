//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalCoreKit
import SignalServiceKit

/// Manages "donation receipt credential" redemption.
///
/// Donation payments are handled differently depending on the payment method.
/// Ultimately, however, all payments are "confirmed" – this means the user has
/// authorized the payment. Once that happens, we end up with a "payment intent
/// ID" as well as a "receipt credential request/context".
///
/// At this point, we're in a zero-knowledge world – neither the payment intent
/// ID nor the receipt credential request are associated with our account.
///
/// We take the payment intent ID and receipt credential request, and send them
/// (unauthenticated) to Signal servers. If the payment in question has been
/// "processed" (per the relevant payment processor, such as Stripe), the server
/// returns us a value that we can combine with our receipt credential request
/// context to create a zero-knowledge "receipt credential".
///
/// Note that if the payment has not processed successfully we instead receive
/// an error, which can tell us the status of the payment and how to proceed.
/// For example, the payment may have failed to process, or may still be pending
/// but not have affirmatively failed – we want to respond differently to those
/// scenarios.
///
/// *Finally*, we make an authenticated request to send a presentation for the
/// ZK receipt credential to the service – thereby proving that we have made a
/// donation – which assigns a badge to our account.
///
/// - Note
/// Some payment types (such as credit cards) usually process immediately, but
/// others (such as SEPA debit transfers) can take days/weeks to process. During
/// that time, receipt credential request redemption will fail.
///
/// - Note
/// The term "subscription" is overloaded. It can either refer to a donation,
/// either one-time or recurring, as in the context of this class name. It can
/// also refer to a recurring donation, as in "subscriber ID", which is only
/// relevant for recurring donations. Good luck.
public class SubscriptionReceiptCredentialRedemptionJobQueue: JobQueue {

    public func addBoostJob(
        amount: FiatMoney,
        paymentProcessor: DonationPaymentProcessor,
        paymentMethod: DonationPaymentMethod,
        receiptCredentialRequestContext: Data,
        receiptCredentialRequest: Data,
        boostPaymentIntentID: String,
        transaction: SDSAnyWriteTransaction
    ) {
        Logger.info("[Donations] Adding a boost job")

        let jobRecord = SubscriptionReceiptCredentialRedemptionJobRecord(
            paymentProcessor: paymentProcessor.rawValue,
            paymentMethod: paymentMethod.rawValue,
            receiptCredentialRequestContext: receiptCredentialRequestContext,
            receiptCredentialRequest: receiptCredentialRequest,
            subscriberID: Data(), // Unused
            targetSubscriptionLevel: 0, // Unused
            priorSubscriptionLevel: 0, // Unused
            isBoost: true,
            amount: amount.value,
            currencyCode: amount.currencyCode,
            boostPaymentIntentID: boostPaymentIntentID,
            label: jobRecordLabel
        )
        self.add(jobRecord: jobRecord, transaction: transaction)
    }

    /// Add a new redemption job for a recurring payment.
    ///
    /// - Parameter paymentMethod
    /// The payment method for this subscription. In practice, should not be
    /// `nil`! However, we fetch this from the service, which cannot guarantee a
    /// recognized value (as it is in turn fetched from an external service,
    /// such as Stripe).
    public func addSubscriptionJob(
        paymentProcessor: DonationPaymentProcessor,
        paymentMethod: DonationPaymentMethod?,
        receiptCredentialRequestContext: Data,
        receiptCredentialRequest: Data,
        subscriberID: Data,
        targetSubscriptionLevel: UInt,
        priorSubscriptionLevel: UInt?,
        transaction: SDSAnyWriteTransaction
    ) {
        Logger.info("[Donations] Adding a subscription job")

        let jobRecord = SubscriptionReceiptCredentialRedemptionJobRecord(
            paymentProcessor: paymentProcessor.rawValue,
            paymentMethod: paymentMethod?.rawValue,
            receiptCredentialRequestContext: receiptCredentialRequestContext,
            receiptCredentialRequest: receiptCredentialRequest,
            subscriberID: subscriberID,
            targetSubscriptionLevel: targetSubscriptionLevel,
            priorSubscriptionLevel: priorSubscriptionLevel ?? 0,
            isBoost: false,
            amount: nil,
            currencyCode: nil,
            boostPaymentIntentID: String(), // Unused
            label: self.jobRecordLabel
        )
        self.add(jobRecord: jobRecord, transaction: transaction)
    }

    public typealias DurableOperationType = SubscriptionReceiptCredentialRedemptionOperation

    /// The value of this string is persisted, and must not change.
    public static let jobRecordLabel: String = "SubscriptionReceiptCredentailRedemption"
    public var jobRecordLabel: String {
        return type(of: self).jobRecordLabel
    }

    public let requiresInternet: Bool = true
    public var isEnabled: Bool { CurrentAppContext().isMainApp }
    public var runningOperations = AtomicArray<SubscriptionReceiptCredentialRedemptionOperation>()

    public init() {
        AppReadiness.runNowOrWhenAppDidBecomeReadySync {
            self.setup()
        }
    }

    public func setup() {
        defaultSetup()
    }

    public var isSetup = AtomicBool(false)

    public func didMarkAsReady(oldJobRecord: JobRecordType, transaction: SDSAnyWriteTransaction) {
        // no special handling
    }

    let operationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "SubscriptionReceiptCredentialRedemptionJobQueue"
        return operationQueue
    }()

    public func operationQueue(jobRecord: SubscriptionReceiptCredentialRedemptionJobRecord) -> OperationQueue {
        return self.operationQueue
    }

    public func buildOperation(jobRecord: SubscriptionReceiptCredentialRedemptionJobRecord, transaction: SDSAnyReadTransaction) throws -> SubscriptionReceiptCredentialRedemptionOperation {
        return try SubscriptionReceiptCredentialRedemptionOperation(jobRecord)
    }
}

public class SubscriptionReceiptCredentialRedemptionOperation: OWSOperation, DurableOperation {
    /// Represents the type of payment that resulted in this receipt credential
    /// redemption.
    fileprivate enum PaymentType: CustomStringConvertible {
        /// A one-time payment, or "boost".
        case oneTimeBoost(paymentIntentId: String)
        /// A recurring payment, or (an overloaded term) "subscription".
        case recurringSubscription(
            subscriberId: Data,
            targetSubscriptionLevel: UInt,
            priorSubscriptionLevel: UInt
        )

        var receiptCredentialResultMode: SubscriptionReceiptCredentialResultStore.Mode {
            switch self {
            case .oneTimeBoost: return .oneTimeBoost
            case .recurringSubscription: return .recurringSubscription
            }
        }

        var donationReceiptType: DonationReceipt.DonationReceiptType {
            switch self {
            case .oneTimeBoost:
                return .boost
            case let .recurringSubscription(_, targetSubscriptionLevel, _):
                return .subscription(subscriptionLevel: targetSubscriptionLevel)
            }
        }

        var description: String {
            switch self {
            case .oneTimeBoost: return "one-time"
            case .recurringSubscription: return "recurring"
            }
        }
    }

    private enum ReceiptCredentialOperationError: Error, IsRetryableProvider {
        /// The source that told us a payment was still processing.
        enum PaymentStillProcessingSource {
            case localState
            case remoteService
        }

        /// A SEPA payment is still processing.
        ///
        /// We want to separate out this case to facilitate a bespoke retry
        /// behavior. Normally, durable job operations run on launch, and then
        /// have a delayed retry queued in-memory. However, we instead want SEPA
        /// payment retries to occur once per *absolute* duration, rather than
        /// duration since app launch.
        case sepaPaymentStillProcessing(source: PaymentStillProcessingSource)
        case nonSepaPaymentStillProcessing
        case other(errorCode: SubscriptionReceiptCredentialRequestError.ErrorCode)

        var isRetryableProvider: Bool {
            switch self {
            case .nonSepaPaymentStillProcessing:
                // We want to retry these because we believe the payment will
                // process quickly.
                return true
            case  .sepaPaymentStillProcessing:
                // We don't want to retry these because we don't believe the
                // payment will process quickly, so there's no point.
                return false
            case .other:
                // Any remaining error cases here are fatal.
                return false
            }
        }
    }

    private var receiptCredentialResultStore: SubscriptionReceiptCredentialResultStore {
        DependenciesBridge.shared.subscriptionReceiptCredentialResultStore
    }

    // MARK: DurableOperation

    public let jobRecord: SubscriptionReceiptCredentialRedemptionJobRecord
    weak public var durableOperationDelegate: SubscriptionReceiptCredentialRedemptionJobQueue?
    public var operation: OWSOperation { self }

    public var maxRetries: UInt {
        switch paymentMethod {
        case nil, .applePay, .creditOrDebitCard, .paypal:
            // We'll retry operations for these payment types fairly
            // aggressively, so we need a large retry buffer.
            return 110
        case .sepa:
            // We'll only retry operations for SEPA 1x/day, so we limit the
            // retry buffer. They should always complete within 14 business
            // days, so this is generous compared to what we should need, but
            // prevents us from having an indefinite job if for whatever reason
            // a payment never processes.
            return 30
        }
    }

    // MARK: Job state

    private let paymentProcessor: DonationPaymentProcessor
    private let paymentMethod: DonationPaymentMethod?
    private let receiptCredentialRequest: ReceiptCredentialRequest
    private let receiptCredentialRequestContext: ReceiptCredentialRequestContext
    private var receiptCredentialPresentation: ReceiptCredentialPresentation?

    private let paymentType: PaymentType

    /// For one-time payments, this should always be present.
    ///
    /// For recurring payments, this will be absent until the job runs, which
    /// should populate it.
    private var amount: FiatMoney?

    /// In order to properly show the "you have a new badge" UI after this job
    /// succeeds, we need to know what badges we had beforehand.
    private let badgesSnapshotBeforeJob: ProfileBadgesSnapshot

    /// In order to show UI after this job completes, we need to know what badge
    /// we were trying to redeem.
    ///
    /// - Important
    /// This property starts `nil`, and is populated when the job runs. It is
    /// guaranteed to be present when the job completes with either success or
    /// a known operation error.
    private var badge: ProfileBadge?

    // MARK: Init

    fileprivate init(_ jobRecord: SubscriptionReceiptCredentialRedemptionJobRecord) throws {
        self.jobRecord = jobRecord

        self.paymentProcessor = try {
            guard let paymentProcessor = DonationPaymentProcessor(rawValue: jobRecord.paymentProcessor) else {
                throw JobError.permanentFailure(description: "Unexpected payment processor in job record! \(jobRecord.paymentProcessor)")
            }

            return paymentProcessor
        }()

        self.paymentMethod = try jobRecord.paymentMethod.map { paymentMethodString in
            guard let paymentMethod = DonationPaymentMethod(rawValue: paymentMethodString) else {
                throw JobError.permanentFailure(description: "[Donations] Unexpected payment method in job record! \(paymentMethodString)")
            }

            return paymentMethod
        }

        if jobRecord.isBoost {
            guard
                let value = jobRecord.amount.map({ $0 as Decimal }),
                let currencyCode = jobRecord.currencyCode
            else {
                throw JobError.permanentFailure(description: "[Donations] Boost job record missing amount!")
            }

            self.paymentType = .oneTimeBoost(paymentIntentId: jobRecord.boostPaymentIntentID)
            self.amount = FiatMoney(currencyCode: currencyCode, value: value)
        } else {
            self.paymentType = .recurringSubscription(
                subscriberId: jobRecord.subscriberID,
                targetSubscriptionLevel: jobRecord.targetSubscriptionLevel,
                priorSubscriptionLevel: jobRecord.priorSubscriptionLevel
            )
        }

        self.receiptCredentialRequestContext = try ReceiptCredentialRequestContext(
            contents: [UInt8](jobRecord.receiptCredentialRequestContext)
        )
        self.receiptCredentialRequest = try ReceiptCredentialRequest(
            contents: [UInt8](jobRecord.receiptCredentialRequest)
        )
        self.receiptCredentialPresentation = try jobRecord.receiptCredentialPresentation.map {
            try ReceiptCredentialPresentation(contents: [UInt8]($0))
        }

        self.badgesSnapshotBeforeJob = .current()
    }

    override public func run() {
        Logger.info("[Donations] Running job for \(paymentType).")

        firstly(on: DispatchQueue.global()) { () -> Promise<ProfileBadge> in
            return self.loadBadge()
        }.then(on: DispatchQueue.global()) { badge -> Promise<(ProfileBadge, FiatMoney)> in
            return self.getAmount().map(on: SyncScheduler()) { amount in
                (badge, amount)
            }
        }.then(on: DispatchQueue.global()) { (badge, amount) -> Promise<ReceiptCredentialPresentation> in
            return self.getReceiptCredentialPresentation(
                badge: badge,
                amount: amount
            )
        }.then(on: DispatchQueue.global()) { presentation -> Promise<Void> in
            return SubscriptionManagerImpl.redeemReceiptCredentialPresentation(
                receiptCredentialPresentation: presentation
            )
        }.done(on: DispatchQueue.global()) {
            Logger.info("[Donations] Successfully redeemed receipt credential presentation")
            self.reportSuccess()
        }.catch(on: DispatchQueue.global()) { error in
            self.reportError(error)
        }
    }

    /// Before running the operation, determine if we even need to.
    ///
    /// We should not bother retrying a SEPA job if we attempted within the last
    /// day and learned that the payment was, at the time, still processing.
    override public func checkForPreconditionError() -> Error? {
        func timeIntervalSince(_ timestampMs: UInt64) -> TimeInterval {
            return Date().timeIntervalSince(Date(millisecondsSince1970: timestampMs))
        }

        if
            paymentMethod == .sepa,
            let priorError = databaseStorage.read(block: { tx -> SubscriptionReceiptCredentialRequestError? in
                return receiptCredentialResultStore.getRequestError(
                    errorMode: paymentType.receiptCredentialResultMode,
                    tx: tx.asV2Read
                )
            }),
            priorError.errorCode == .paymentStillProcessing,
            timeIntervalSince(priorError.timestampMs) < kDayInterval
        {
            // If we are a SEPA job being retried, and we got a "still
            // processing" error less than a day ago, we should assume nothing
            // has changed and short-circuit.
            owsAssertDebug(priorError.paymentMethod == .sepa)

            return ReceiptCredentialOperationError.sepaPaymentStillProcessing(
                source: .localState
            )
        }

        return super.checkForPreconditionError()
    }

    /// Once this promise resolves, `self.badge` is guaranteed to be populated.
    private func loadBadge() -> Promise<ProfileBadge> {
        if let badge = self.badge {
            return .value(badge)
        }

        return firstly(on: DispatchQueue.global()) { () -> Promise<ProfileBadge> in
            switch self.paymentType {
            case .oneTimeBoost:
                return SubscriptionManagerImpl.getBoostBadge()
            case let .recurringSubscription(_, targetSubscriptionLevel, _):
                return SubscriptionManagerImpl.getSubscriptionBadge(
                    subscriptionLevel: targetSubscriptionLevel
                )
            }
        }.map(on: SyncScheduler()) { badge -> ProfileBadge in
            self.badge = badge
            return badge
        }
    }

    /// Once this promise resolves, `self.amount` is guaranteed to be populated.
    private func getAmount() -> Promise<FiatMoney> {
        if let amount = self.amount {
            return .value(amount)
        }

        switch paymentType {
        case .oneTimeBoost:
            guard let amount else { owsFail("How did we construct a boost job without an amount?") }

            return .value(amount)
        case let .recurringSubscription(subscriberId, _, _):
            return SubscriptionManagerImpl
                .getCurrentSubscriptionStatus(for: subscriberId)
                .map(on: DispatchQueue.global()) { subscription -> FiatMoney in
                    guard let subscription else {
                        throw OWSAssertionError("Missing subscription")
                    }

                    Logger.info("[Donations] Fetched current subscription. \(subscription.debugDescription)")

                    self.amount = subscription.amount
                    return subscription.amount
                }
        }
    }

    private func getReceiptCredentialPresentation(
        badge: ProfileBadge,
        amount: FiatMoney
    ) -> Promise<ReceiptCredentialPresentation> {
        // We already have a receiptCredentialPresentation, lets use it
        if let receiptCredentialPresentation = self.receiptCredentialPresentation {
            Logger.info("[Donations] Using persisted receipt credential presentation")
            return Promise.value(receiptCredentialPresentation)
        }

        return firstly(on: DispatchQueue.global()) { () -> Promise<ReceiptCredentialPresentation> in
            Logger.info("[Donations] Creating new receipt credential presentation")

            // Create a new receipt credential presentation
            switch self.paymentType {
            case let .oneTimeBoost(paymentIntentId):
                Logger.info("[Donations] Durable job requesting receipt for boost")
                return try SubscriptionManagerImpl.requestReceiptCredentialPresentation(
                    boostPaymentIntentId: paymentIntentId,
                    expectedBadgeLevel: .boostBadge,
                    paymentProcessor: self.paymentProcessor,
                    context: self.receiptCredentialRequestContext,
                    request: self.receiptCredentialRequest
                )
            case let .recurringSubscription(subscriberId, targetSubscriptionLevel, priorSubscriptionLevel):
                Logger.info("[Donations] Durable job requesting receipt for subscription")
                return try SubscriptionManagerImpl.requestReceiptCredentialPresentation(
                    subscriberId: subscriberId,
                    targetSubscriptionLevel: targetSubscriptionLevel,
                    priorSubscriptionLevel: priorSubscriptionLevel,
                    context: self.receiptCredentialRequestContext,
                    request: self.receiptCredentialRequest
                )
            }
        }.map(on: DispatchQueue.global()) { newReceiptCredentialPresentation -> ReceiptCredentialPresentation in
            Logger.info("[Donations] Storing receipt credential presentation in case the job fails")

            self.databaseStorage.write { tx in
                self.jobRecord.update(
                    withReceiptCredentialPresentation: newReceiptCredentialPresentation.serialize().asData,
                    transaction: tx
                )
            }

            return newReceiptCredentialPresentation
        }.recover(on: DispatchQueue.global()) { error -> Promise<ReceiptCredentialPresentation> in
            guard let receiptCredentialRequestErrorCode = error as? SubscriptionReceiptCredentialRequestError.ErrorCode else {
                throw error
            }

            self.databaseStorage.write { tx in
                self.persistErrorCode(
                    receiptCredentialRequestErrorCode: receiptCredentialRequestErrorCode,
                    badge: badge,
                    amount: amount,
                    tx: tx.asV2Write
                )
            }

            switch receiptCredentialRequestErrorCode {
            case .paymentStillProcessing where self.paymentMethod == .sepa:
                throw ReceiptCredentialOperationError.sepaPaymentStillProcessing(
                    source: .remoteService
                )
            case .paymentStillProcessing:
                throw ReceiptCredentialOperationError.nonSepaPaymentStillProcessing
            case
                    .paymentFailed,
                    .localValidationFailed,
                    .serverValidationFailed,
                    .paymentNotFound,
                    .paymentIntentRedeemed:
                throw ReceiptCredentialOperationError.other(
                    errorCode: receiptCredentialRequestErrorCode
                )
            }
        }
    }

    private func persistErrorCode(
        receiptCredentialRequestErrorCode: SubscriptionReceiptCredentialRequestError.ErrorCode,
        badge: ProfileBadge,
        amount: FiatMoney,
        tx: DBWriteTransaction
    ) {
        let receiptCredentialRequestError: SubscriptionReceiptCredentialRequestError = {
            if let paymentMethod = self.paymentMethod {
                return SubscriptionReceiptCredentialRequestError(
                    errorCode: receiptCredentialRequestErrorCode,
                    badge: badge,
                    amount: amount,
                    paymentMethod: paymentMethod
                )
            } else {
                Logger.warn("[Donations] Building legacy error, job record missing fields!")

                return SubscriptionReceiptCredentialRequestError(
                    legacyErrorCode: receiptCredentialRequestErrorCode
                )
            }
        }()

        receiptCredentialResultStore.setRequestError(
            error: receiptCredentialRequestError,
            errorMode: self.paymentType.receiptCredentialResultMode,
            tx: tx
        )
    }

    override public func didSucceed() {
        Logger.info("[Donations] Redemption job succeeded")

        self.databaseStorage.write { tx in
            defer {
                self.durableOperationDelegate?.durableOperationDidSucceed(self, transaction: tx)
            }

            tx.addAsyncCompletionOffMain {
                self.postNotification(name: Self.DidSucceedNotification)
            }

            guard
                let amount = self.amount,
                let badge = self.badge
            else {
                owsFail("[Donations] How did we succeed a job without learning the amount and badge?")
            }

            switch paymentType {
            case .oneTimeBoost: break
            case .recurringSubscription:
                SubscriptionManagerImpl.setHasEverRedeemedRecurringSubscriptionBadge(tx: tx)
            }

            self.receiptCredentialResultStore.clearRequestError(
                errorMode: paymentType.receiptCredentialResultMode,
                tx: tx.asV2Write
            )
            self.receiptCredentialResultStore.setRedemptionSuccess(
                success: SubscriptionReceiptCredentialRedemptionSuccess(
                    badgesSnapshotBeforeJob: badgesSnapshotBeforeJob,
                    badge: badge,
                    paymentMethod: paymentMethod
                ),
                successMode: paymentType.receiptCredentialResultMode,
                tx: tx.asV2Write
            )

            DonationReceipt(
                receiptType: paymentType.donationReceiptType,
                timestamp: Date(),
                amount: amount
            ).anyInsert(transaction: tx)
        }
    }

    /// The interval to wait between operation-level retries.
    ///
    /// In practice, the only errors that are retryable at the operation level
    /// are network errors and "payment processing" for non-bank payments.
    ///
    /// The former do not increment our job record's failure count, but will
    /// increment the operation-local error count. Correspondingly, to prevent
    /// network errors from causing infinitely-instantly-retrying requests,
    /// we'll use both the operation-local error count and job record failure
    /// count to determine our retry interval.
    override public func retryInterval() -> TimeInterval {
        /// If this operation just started, but we've tried in the past and have
        /// persisted failures on the job record, we'll respect those and start
        /// with a longer retry. Otherwise, as this operation continues to retry
        /// it'll get a longer retry from its local error count.
        let failureCountForRetry = max(jobRecord.failureCount, self.errorCount)

        return OWSOperation.retryIntervalForExponentialBackoff(
            failureCount: failureCountForRetry
        )
    }

    override public func didReportError(_ error: Error) {
        guard let operationError = error as? ReceiptCredentialOperationError else {
            owsAssertDebug(error.isNetworkFailureOrTimeout)
            Logger.warn("[Donations] Silently ignoring non-operation error.")
            return
        }

        switch operationError {
        case .sepaPaymentStillProcessing(.localState):
            // We shouldn't be coming through this codepath, because the only
            // place we create local still-processing errors should go straight
            // to `didFail`. If we do get here, because something changed, we
            // shouldn't count these against our failure count.
            owsFailDebug("We shouldn't be sending local-state short-circuits through this codepath!")
            return
        case
                .sepaPaymentStillProcessing(source: .remoteService),
                .nonSepaPaymentStillProcessing,
                .other:
            break
        }

        self.databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperation(
                self, didReportError: operationError, transaction: transaction
            )
        }
    }

    /// We get here if we have a non-retryable error, or if we've run out of
    /// retries.
    override public func didFail(error: Error) {
        guard let operationError = error as? ReceiptCredentialOperationError else {
            owsAssertDebug(error.isNetworkFailureOrTimeout)
            Logger.warn("[Donations] Silently ignoring non-operation error.")
            return
        }

        let persistArtificialPaymentFailure: Bool

        switch operationError {
        case .sepaPaymentStillProcessing(.localState):
            Logger.warn("[Donations] Silently ignoring SEPA payment still processing short-circuit.")
            return
        case .sepaPaymentStillProcessing(.remoteService) where remainingRetries > 0:
            Logger.warn("[Donations] Silently ignoring SEPA payment still processing error, we have retries remaining.")
            return
        case .sepaPaymentStillProcessing(.remoteService):
            Logger.error("[Donations] SEPA payment still processing on the service, but we're out of retries!")
            persistArtificialPaymentFailure = true
        case .nonSepaPaymentStillProcessing:
            Logger.error("[Donations] Non-SEPA payment still processing, but we're out of retries!")
            persistArtificialPaymentFailure = true
        case let .other(errorCode):
            Logger.error("[Donations] Failed to redeem receipt credential! \(errorCode)")
            persistArtificialPaymentFailure = false
        }

        guard
            let amount = self.amount,
            let badge = self.badge
        else {
            owsFail("How did we get a operation error by interacting with the service, without an amount and badge?")
        }

        self.databaseStorage.write { tx in
            tx.addAsyncCompletionOffMain {
                self.postNotification(name: Self.DidFailNotification)
            }

            if persistArtificialPaymentFailure {
                self.persistErrorCode(
                    receiptCredentialRequestErrorCode: .paymentFailed,
                    badge: badge,
                    amount: amount,
                    tx: tx.asV2Write
                )
            }

            self.durableOperationDelegate?.durableOperation(
                self, didFailWithError: operationError, transaction: tx
            )
        }
    }
}

// MARK: - Notifications

public extension SubscriptionReceiptCredentialRedemptionOperation {
    static let DidSucceedNotification = NSNotification.Name("SubscriptionReceiptCredentialRedemptionOperation.DidSucceed")
    static let DidFailNotification = NSNotification.Name("SubscriptionReceiptCredentialRedemptionOperation.DidFail")

    func postNotification(name: NSNotification.Name) {
        NotificationCenter.default.postNotificationNameAsync(
            name, object: nil, userInfo: nil
        )
    }
}
