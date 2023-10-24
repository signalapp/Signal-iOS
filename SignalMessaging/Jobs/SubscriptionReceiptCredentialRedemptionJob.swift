//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
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
/// others (such as SEPA debit transfers) can take days/weeks to process.
///
/// - Note
/// The term "subscription" is overloaded. It can either refer to a donation,
/// either one-time or recurring, as in the context of this class name. It can
/// also refer to a recurring donation, as in "subscriber ID", which is only
/// relevant for recurring donations. Good luck.
public class SubscriptionReceiptCredentialRedemptionJobQueue: JobQueue {

    public func addBoostJob(
        amount: FiatMoney,
        paymentProcessor: PaymentProcessor,
        receiptCredentialRequestContext: Data,
        receiptCredentialRequest: Data,
        boostPaymentIntentID: String,
        transaction: SDSAnyWriteTransaction
    ) {
        Logger.info("[Donations] Adding a boost job")
        let jobRecord = SubscriptionReceiptCredentialRedemptionJobRecord(
            paymentProcessor: paymentProcessor.rawValue,
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

    public func addSubscriptionJob(
        paymentProcessor: PaymentProcessor,
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

    public typealias DurableOperationType = SubscriptionReceiptCredentailRedemptionOperation

    /// The value of this string is persisted, and must not change.
    public static let jobRecordLabel: String = "SubscriptionReceiptCredentailRedemption"
    public var jobRecordLabel: String {
        return type(of: self).jobRecordLabel
    }

    // per OWSOperation.retryIntervalForExponentialBackoff(failureCount:),
    // 110 retries will yield ~24 hours of retry.
    public static let maxRetries: UInt = 110
    public let requiresInternet: Bool = true
    public var isEnabled: Bool { CurrentAppContext().isMainApp }
    public var runningOperations = AtomicArray<SubscriptionReceiptCredentailRedemptionOperation>()

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

    public func buildOperation(jobRecord: SubscriptionReceiptCredentialRedemptionJobRecord, transaction: SDSAnyReadTransaction) throws -> SubscriptionReceiptCredentailRedemptionOperation {
        return try SubscriptionReceiptCredentailRedemptionOperation(jobRecord)
    }
}

public class SubscriptionReceiptCredentailRedemptionOperation: OWSOperation, DurableOperation {
    /// Represents the type of payment that resulted in this receipt credential
    /// redemption.
    private enum PaymentType: CustomStringConvertible {
        /// A one-time payment, or "boost".
        case oneTime(paymentIntentId: String)

        /// A recurring payment, or (an overloaded term) "subscription".
        case recurring(
            subscriberId: Data,
            targetSubscriptionLevel: UInt,
            priorSubscriptionLevel: UInt
        )

        var description: String {
            switch self {
            case .oneTime: return "one-time"
            case .recurring: return "recurring"
            }
        }
    }

    public let jobRecord: SubscriptionReceiptCredentialRedemptionJobRecord
    weak public var durableOperationDelegate: SubscriptionReceiptCredentialRedemptionJobQueue?
    public var operation: OWSOperation { self }

    private let paymentProcessor: PaymentProcessor
    private let receiptCredentialRequest: ReceiptCredentialRequest
    private let receiptCredentialRequestContext: ReceiptCredentialRequestContext
    private var receiptCredentialPresentation: ReceiptCredentialPresentation?

    private let paymentType: PaymentType

    var isBoost: Bool {
        switch paymentType {
        case .oneTime: return true
        case .recurring: return false
        }
    }

    /// For one-time payments, this should always be present.
    ///
    /// For recurring payments, this will be absent until the job runs, which
    /// should populate it.
    private var amount: FiatMoney?

    fileprivate init(_ jobRecord: SubscriptionReceiptCredentialRedemptionJobRecord) throws {
        self.jobRecord = jobRecord
        self.paymentProcessor = {
            guard let paymentProcessor = PaymentProcessor(rawValue: jobRecord.paymentProcessor) else {
                owsFailDebug("Failed to deserialize payment processor from record with value: \(jobRecord.paymentProcessor)")
                return .stripe
            }

            return paymentProcessor
        }()

        self.amount = {
            if
                let value = jobRecord.amount.map({ $0 as Decimal }),
                let currencyCode = jobRecord.currencyCode {
                return FiatMoney(currencyCode: currencyCode, value: value)
            } else {
                return nil
            }
        }()

        if jobRecord.isBoost {
            self.paymentType = .oneTime(paymentIntentId: jobRecord.boostPaymentIntentID)
        } else {
            self.paymentType = .recurring(
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

        if let receiptCredentialPresentation = jobRecord.receiptCredentialPresentation {
            self.receiptCredentialPresentation = try ReceiptCredentialPresentation(
                contents: [UInt8](receiptCredentialPresentation)
            )
        }
    }

    override public func run() {
        Logger.info("[Donations] Running job for \(paymentType).")

        let getMoneyPromise: Promise<Void> = {
            switch paymentType {
            case .oneTime:
                return .value(())
            case let .recurring(subscriberId, _, _):
                return SubscriptionManagerImpl
                    .getCurrentSubscriptionStatus(for: subscriberId)
                    .done(on: DispatchQueue.global()) { subscription in
                        guard let subscription else {
                            throw OWSAssertionError("Missing subscription")
                        }

                        Logger.info("[Donations] Fetched current subscription. \(subscription.debugDescription)")

                        self.amount = subscription.amount
                    }
            }
        }()

        let getReceiptCredentialPresentationPromise: Promise<ReceiptCredentialPresentation> = firstly(on: DispatchQueue.global()) { () -> Promise<ReceiptCredentialPresentation> in
            // We already have a receiptCredentialPresentation, lets use it
            if let receiptCredentialPresentation = self.receiptCredentialPresentation {
                Logger.info("[Donations] Using persisted receipt credential presentation")
                return Promise.value(receiptCredentialPresentation)
            }

            Logger.info("[Donations] Creating new receipt credential presentation")

            // Create a new receipt credential presentation
            return firstly(on: DispatchQueue.global()) { () -> Promise<ReceiptCredentialPresentation> in
                switch self.paymentType {
                case let .oneTime(paymentIntentId):
                    Logger.info("[Donations] Durable job requesting receipt for boost")
                    return try SubscriptionManagerImpl.requestBoostReceiptCredentialPresentation(
                        for: paymentIntentId,
                        context: self.receiptCredentialRequestContext,
                        request: self.receiptCredentialRequest,
                        expectedBadgeLevel: .boostBadge,
                        paymentProcessor: self.paymentProcessor
                    )
                case let .recurring(subscriberId, targetSubscriptionLevel, priorSubscriptionLevel):
                    Logger.info("[Donations] Durable job requesting receipt for subscription")
                    return try SubscriptionManagerImpl.requestReceiptCredentialPresentation(
                        for: subscriberId,
                        context: self.receiptCredentialRequestContext,
                        request: self.receiptCredentialRequest,
                        targetSubscriptionLevel: targetSubscriptionLevel,
                        priorSubscriptionLevel: priorSubscriptionLevel
                    )
                }
            }.then(on: DispatchQueue.global()) { newReceiptCredentialPresentation -> Promise<ReceiptCredentialPresentation> in
                Logger.info("[Donations] Storing receipt credential presentation in case the job fails")
                return self.databaseStorage.writePromise { transaction in
                    self.jobRecord.update(
                        withReceiptCredentialPresentation: newReceiptCredentialPresentation.serialize().asData,
                        transaction: transaction
                    )
                }.map(on: DispatchQueue.global()) { _ in newReceiptCredentialPresentation }
            }
        }

        getMoneyPromise.then(on: DispatchQueue.global()) {
            getReceiptCredentialPresentationPromise.then(on: DispatchQueue.global()) {
                SubscriptionManagerImpl.redeemReceiptCredentialPresentation(receiptCredentialPresentation: $0)
            }
        }.done(on: DispatchQueue.global()) {
            Logger.info("[Donations] Successfully redeemed receipt credential presentation")
            self.didSucceed()
        }.catch(on: DispatchQueue.global()) { error in
            self.reportError(error)
        }
    }

    override public func didSucceed() {
        Logger.info("[Donations] Redemption job succeeded")
        self.databaseStorage.write { transaction in
            defer {
                self.durableOperationDelegate?.durableOperationDidSucceed(self, transaction: transaction)

                NotificationCenter.default.postNotificationNameAsync(
                    SubscriptionManagerImpl.SubscriptionJobQueueDidFinishJobNotification,
                    object: nil
                )
            }

            guard let amount = self.amount else {
                owsFailDebug("[Donations] Amount was missing. Is this an old job?")
                return
            }

            let receiptType: DonationReceipt.DonationReceiptType

            switch paymentType {
            case .oneTime:
                receiptType = .boost
            case let .recurring(_, targetSubscriptionLevel, _):
                SubscriptionManagerImpl.setLastReceiptRedemptionFailed(failureReason: .none, transaction: transaction)

                receiptType = .subscription(subscriptionLevel: targetSubscriptionLevel)
            }

            DonationReceipt(
                receiptType: receiptType,
                timestamp: Date(),
                amount: amount
            ).anyInsert(transaction: transaction)
        }
    }

    override public func didReportError(_ error: Error) {
        Logger.debug("remainingRetries: \(self.remainingRetries)")

        self.databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperation(self, didReportError: error, transaction: transaction)
        }
    }

    override public func retryInterval() -> TimeInterval {
        let timeInterval = OWSOperation.retryIntervalForExponentialBackoff(failureCount: jobRecord.failureCount)
        return timeInterval
    }

    override public func didFail(error: Error) {
        Logger.error("[Donations] failed to redeem receipt credential with error: \(error.userErrorDescription)")
        self.databaseStorage.write { transaction in
            NotificationCenter.default.postNotificationNameAsync(
                SubscriptionManagerImpl.SubscriptionJobQueueDidFailJobNotification,
                object: nil
            )
            self.durableOperationDelegate?.durableOperation(self, didFailWithError: error, transaction: transaction)
        }
    }
}
