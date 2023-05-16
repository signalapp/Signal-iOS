//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit

public class SubscriptionReceiptCredentialJobQueue: JobQueue {

    // Add optional paymentIntentID / isBoost

    public func addBoostJob(
        amount: FiatMoney,
        paymentProcessor: PaymentProcessor,
        receiptCredentialRequestContext: Data,
        receiptCredentialRequest: Data,
        boostPaymentIntentID: String,
        transaction: SDSAnyWriteTransaction
    ) {
        Logger.info("[Donations] Adding a boost job")
        let jobRecord = ReceiptCredentialRedemptionJobRecord(
            paymentProcessor: paymentProcessor.rawValue,
            receiptCredentialRequestContext: receiptCredentialRequestContext,
            receiptCredentialRequest: receiptCredentialRequest,
            subscriberID: Data(),
            targetSubscriptionLevel: 0,
            priorSubscriptionLevel: 0,
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
        boostPaymentIntentID: String,
        transaction: SDSAnyWriteTransaction
    ) {
        Logger.info("[Donations] Adding a subscription job")
        let jobRecord = ReceiptCredentialRedemptionJobRecord(
            paymentProcessor: paymentProcessor.rawValue,
            receiptCredentialRequestContext: receiptCredentialRequestContext,
            receiptCredentialRequest: receiptCredentialRequest,
            subscriberID: subscriberID,
            targetSubscriptionLevel: targetSubscriptionLevel,
            priorSubscriptionLevel: priorSubscriptionLevel ?? 0,
            isBoost: false,
            amount: nil,
            currencyCode: nil,
            boostPaymentIntentID: boostPaymentIntentID,
            label: self.jobRecordLabel
        )
        self.add(jobRecord: jobRecord, transaction: transaction)
    }

    public typealias DurableOperationType = SubscriptionReceiptCredentailRedemptionOperation
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
        operationQueue.name = "SubscriptionReceiptCredentialJobQueue"
        return operationQueue
    }()

    public func operationQueue(jobRecord: ReceiptCredentialRedemptionJobRecord) -> OperationQueue {
        return self.operationQueue
    }

    public func buildOperation(jobRecord: ReceiptCredentialRedemptionJobRecord, transaction: SDSAnyReadTransaction) throws -> SubscriptionReceiptCredentailRedemptionOperation {
        return try SubscriptionReceiptCredentailRedemptionOperation(jobRecord)
    }
}

public class SubscriptionReceiptCredentailRedemptionOperation: OWSOperation, DurableOperation {

    // MARK: DurableOperation

    public let jobRecord: ReceiptCredentialRedemptionJobRecord

    weak public var durableOperationDelegate: SubscriptionReceiptCredentialJobQueue?

    public var operation: OWSOperation {
        return self
    }

    let paymentProcessor: PaymentProcessor
    let isBoost: Bool
    let subscriberID: Data
    var receiptCredentialRequestContext: ReceiptCredentialRequestContext
    var receiptCredentialRequest: ReceiptCredentialRequest
    var receiptCredentialPresentation: ReceiptCredentialPresentation?
    let targetSubscriptionLevel: UInt
    let priorSubscriptionLevel: UInt
    let boostPaymentIntentID: String

    // For boosts, these should always be present.
    // For subscriptions, these will be absent until the job runs, which should populate them.
    var amount: FiatMoney?

    public required init(_ jobRecord: ReceiptCredentialRedemptionJobRecord) throws {
        self.jobRecord = jobRecord
        self.paymentProcessor = {
            guard let paymentProcessor = PaymentProcessor(rawValue: jobRecord.paymentProcessor) else {
                owsFailDebug("Failed to deserialize payment processor from record with value: \(jobRecord.paymentProcessor)")
                return .stripe
            }

            return paymentProcessor
        }()
        self.isBoost = jobRecord.isBoost
        self.amount = {
            if
                let value = jobRecord.amount.map({ $0 as Decimal }),
                let currencyCode = jobRecord.currencyCode {
                return FiatMoney(currencyCode: currencyCode, value: value)
            } else {
                return nil
            }
        }()
        self.subscriberID = jobRecord.subscriberID
        self.targetSubscriptionLevel = jobRecord.targetSubscriptionLevel
        self.priorSubscriptionLevel = jobRecord.priorSubscriptionLevel
        self.boostPaymentIntentID = jobRecord.boostPaymentIntentID
        self.receiptCredentialRequestContext = try ReceiptCredentialRequestContext(
            contents: [UInt8](jobRecord.receiptCredentialRequestContext))
        self.receiptCredentialRequest = try ReceiptCredentialRequest(
            contents: [UInt8](jobRecord.receiptCredentialRequest))
        if let receiptCredentialPresentation = jobRecord.receiptCredentialPresentation {
            self.receiptCredentialPresentation = try ReceiptCredentialPresentation(
                contents: [UInt8](receiptCredentialPresentation))
        }
    }

    override public func run() {
        assert(self.durableOperationDelegate != nil)

        Logger.info("[Donations] Running job for \(isBoost ? "boost" : "subscription")")

        let getMoneyPromise: Promise<Void>
        if isBoost {
            getMoneyPromise = Promise.value(())
        } else {
            getMoneyPromise = SubscriptionManagerImpl.getCurrentSubscriptionStatus(for: subscriberID).done { subscription in
                guard let subscription = subscription else {
                    throw OWSAssertionError("Missing subscription")
                }

                Logger.info("[Donations] Fetched current subscription. \(subscription.debugDescription)")

                self.amount = subscription.amount
            }
        }

        let getReceiptCredentialPresentationPromise: Promise<ReceiptCredentialPresentation> = firstly(on: DispatchQueue.global()) { () -> Promise<ReceiptCredentialPresentation> in
            // We already have a receiptCredentialPresentation, lets use it
            if let receiptCredentialPresentation = self.receiptCredentialPresentation {
                Logger.info("[Donations] Using persisted receipt credential presentation")
                return Promise.value(receiptCredentialPresentation)
            }

            Logger.info("[Donations] Creating new receipt credential presentation")

            // Create a new receipt credential presentation
            return firstly(on: DispatchQueue.global()) { () -> Promise<ReceiptCredentialPresentation> in
                if self.isBoost {
                    Logger.info("[Donations] Durable job requesting receipt for boost")
                    return try SubscriptionManagerImpl.requestBoostReceiptCredentialPresentation(
                        for: self.boostPaymentIntentID,
                        context: self.receiptCredentialRequestContext,
                        request: self.receiptCredentialRequest,
                        expectedBadgeLevel: .boostBadge,
                        paymentProcessor: self.paymentProcessor
                    )
                } else {
                    Logger.info("[Donations] Durable job requesting receipt for subscription")
                    return try SubscriptionManagerImpl.requestReceiptCredentialPresentation(
                        for: self.subscriberID,
                           context: self.receiptCredentialRequestContext,
                           request: self.receiptCredentialRequest,
                           targetSubscriptionLevel: self.targetSubscriptionLevel,
                           priorSubscriptionLevel: self.priorSubscriptionLevel
                    )
                }
            }.then(on: DispatchQueue.global()) { newReceiptCredentialPresentation -> Promise<ReceiptCredentialPresentation> in
                Logger.info("[Donations] Storing receipt credential presentation in case the job fails")
                return self.databaseStorage.writePromise { transaction in
                    self.jobRecord.update(
                        withReceiptCredentialPresentation: newReceiptCredentialPresentation.serialize().asData,
                        transaction: transaction
                    )
                }.map { _ in newReceiptCredentialPresentation }
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
            if !self.isBoost {
                SubscriptionManagerImpl.setLastReceiptRedemptionFailed(failureReason: .none, transaction: transaction)
            }

            if let amount = amount {
                DonationReceipt(
                    receiptType: self.isBoost ? .boost : .subscription(subscriptionLevel: targetSubscriptionLevel),
                    timestamp: Date(),
                    amount: amount
                ).anyInsert(transaction: transaction)
            } else {
                Logger.warn("[Donations] amount was missing. Is this an old job?")
            }

            self.durableOperationDelegate?.durableOperationDidSucceed(self, transaction: transaction)

            NotificationCenter.default.postNotificationNameAsync(
                SubscriptionManagerImpl.SubscriptionJobQueueDidFinishJobNotification,
                object: nil
            )
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
