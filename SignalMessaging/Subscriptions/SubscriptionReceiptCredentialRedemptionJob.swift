//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalServiceKit

@objc(OWSSubscriptionReceiptCredentialJobQueue)
public class SubscriptionReceiptCredentialJobQueue: NSObject, JobQueue {

    // Add optional paymentIntentID / isBoost

    public func addBoostJob(
        amount: Decimal,
        currencyCode: Currency.Code,
        receiptCredentialRequestContext: Data,
        receiptCredentailRequest: Data,
        boostPaymentIntentID: String,
        transaction: SDSAnyWriteTransaction
    ) {
        Logger.info("[Donations] Adding a boost job")
        let jobRecord = OWSReceiptCredentialRedemptionJobRecord(
            receiptCredentialRequestContext: receiptCredentialRequestContext,
            receiptCredentailRequest: receiptCredentailRequest,
            subscriberID: Data(),
            targetSubscriptionLevel: 0,
            priorSubscriptionLevel: 0,
            isBoost: true,
            amount: amount as NSDecimalNumber,
            currencyCode: currencyCode,
            boostPaymentIntentID: boostPaymentIntentID,
            label: self.jobRecordLabel
        )
        self.add(jobRecord: jobRecord, transaction: transaction)
    }

    public func addSubscriptionJob(
        receiptCredentialRequestContext: Data,
        receiptCredentailRequest: Data,
        subscriberID: Data,
        targetSubscriptionLevel: UInt,
        priorSubscriptionLevel: UInt,
        boostPaymentIntentID: String,
        transaction: SDSAnyWriteTransaction
    ) {
        Logger.info("[Donations] Adding a subscription job")
        let jobRecord = OWSReceiptCredentialRedemptionJobRecord(
            receiptCredentialRequestContext: receiptCredentialRequestContext,
            receiptCredentailRequest: receiptCredentailRequest,
            subscriberID: subscriberID,
            targetSubscriptionLevel: targetSubscriptionLevel,
            priorSubscriptionLevel: priorSubscriptionLevel,
            isBoost: false,
            amount: nil,
            currencyCode: nil,
            boostPaymentIntentID: boostPaymentIntentID,
            label: self.jobRecordLabel
        )
        self.add(jobRecord: jobRecord, transaction: transaction)
    }

    public typealias DurableOperationType = SubscriptionReceiptCredentailRedemptionOperation
    @objc
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

    public var isSetup = AtomicBool(false)

    public func didMarkAsReady(oldJobRecord: JobRecordType, transaction: SDSAnyWriteTransaction) {
        // no special handling
    }

    let operationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "SubscriptionReceiptCredential.OperationQueue"
        return operationQueue
    }()

    public func operationQueue(jobRecord: OWSReceiptCredentialRedemptionJobRecord) -> OperationQueue {
        return self.operationQueue
    }

    public func buildOperation(jobRecord: OWSReceiptCredentialRedemptionJobRecord, transaction: SDSAnyReadTransaction) throws -> SubscriptionReceiptCredentailRedemptionOperation {
        return try SubscriptionReceiptCredentailRedemptionOperation(jobRecord)
    }
}

public class SubscriptionReceiptCredentailRedemptionOperation: OWSOperation, DurableOperation {

    // MARK: DurableOperation

    public let jobRecord: OWSReceiptCredentialRedemptionJobRecord

    weak public var durableOperationDelegate: SubscriptionReceiptCredentialJobQueue?

    public var operation: OWSOperation {
        return self
    }

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
    var amount: Decimal?
    var currencyCode: Currency.Code?

    @objc
    public required init(_ jobRecord: OWSReceiptCredentialRedemptionJobRecord) throws {
        self.jobRecord = jobRecord
        self.isBoost = jobRecord.isBoost
        self.amount = jobRecord.amount.map { $0 as Decimal }
        self.currencyCode = jobRecord.currencyCode
        self.subscriberID = jobRecord.subscriberID
        self.targetSubscriptionLevel = jobRecord.targetSubscriptionLevel
        self.priorSubscriptionLevel = jobRecord.priorSubscriptionLevel
        self.boostPaymentIntentID = jobRecord.boostPaymentIntentID
        self.receiptCredentialRequestContext = try ReceiptCredentialRequestContext(
            contents: [UInt8](jobRecord.receiptCredentailRequestContext))
        self.receiptCredentialRequest = try ReceiptCredentialRequest(
            contents: [UInt8](jobRecord.receiptCredentailRequest))
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
            getMoneyPromise = SubscriptionManager.getCurrentSubscriptionStatus(for: subscriberID).done { subscription in
                guard let subscription = subscription else {
                    throw OWSAssertionError("Missing subscription")
                }

                Logger.info("[Donations] Fetched current subscription. \(subscription.debugDescription)")

                // Subscriptions represent $12.34 as `1234`, unlike most other code.
                var amount = subscription.amount as Decimal
                if !Stripe.zeroDecimalCurrencyCodes.contains(subscription.currency) {
                    amount /= 100
                }

                self.amount = amount
                self.currencyCode = subscription.currency
            }
        }

        let getReceiptCredentialPresentationPromise: Promise<ReceiptCredentialPresentation> = firstly(on: .global()) { () -> Promise<ReceiptCredentialPresentation> in
            // We already have a receiptCredentialPresentation, lets use it
            if let receiptCredentialPresentation = self.receiptCredentialPresentation {
                Logger.info("[Donations] Using persisted receipt credential presentation")
                return Promise.value(receiptCredentialPresentation)
            }

            Logger.info("[Donations] Creating new receipt credential presentation")

            // Create a new receipt credential presentation
            return firstly(on: .global()) { () -> Promise<ReceiptCredentialPresentation> in
                if self.isBoost {
                    Logger.info("[Donations] Durable job requesting receipt for boost")
                    return try SubscriptionManager.requestBoostReceiptCredentialPresentation(
                        for: self.boostPaymentIntentID,
                        context: self.receiptCredentialRequestContext,
                        request: self.receiptCredentialRequest,
                        expectedBadgeLevel: .boostBadge
                    )
                } else {
                    Logger.info("[Donations] Durable job requesting receipt for subscription")
                    return try SubscriptionManager.requestReceiptCredentialPresentation(
                        for: self.subscriberID,
                           context: self.receiptCredentialRequestContext,
                           request: self.receiptCredentialRequest,
                           targetSubscriptionLevel: self.targetSubscriptionLevel,
                           priorSubscriptionLevel: self.priorSubscriptionLevel
                    )
                }
            }.then(on: .global()) { newReceiptCredentialPresentation -> Promise<ReceiptCredentialPresentation> in
                Logger.info("[Donations] Storing receipt credential presentation in case the job fails")
                return self.databaseStorage.writePromise { transaction in
                    self.jobRecord.update(
                        withReceiptCredentialPresentation: newReceiptCredentialPresentation.serialize().asData,
                        transaction: transaction
                    )
                }.map { _ in newReceiptCredentialPresentation }
            }
        }

        getMoneyPromise.then(on: .global()) {
            getReceiptCredentialPresentationPromise.then(on: .global()) {
                try SubscriptionManager.redeemReceiptCredentialPresentation(receiptCredentialPresentation: $0)
            }
        }.done(on: .global()) {
            Logger.info("[Donations] Successfully redeemed receipt credential presentation")
            self.didSucceed()
        }.catch(on: .global()) { error in
            self.reportError(error)
        }
    }

    override public func didSucceed() {
        Logger.info("[Donations] Redemption job succeeded")
        self.databaseStorage.write { transaction in
            if !self.isBoost {
                SubscriptionManager.setLastReceiptRedemptionFailed(failureReason: .none, transaction: transaction)
            }

            if let amount = amount, let currencyCode = currencyCode {
                DonationReceipt(
                    receiptType: self.isBoost ? .boost : .subscription(subscriptionLevel: targetSubscriptionLevel),
                    timestamp: Date(),
                    amount: amount,
                    currencyCode: currencyCode
                ).anyInsert(transaction: transaction)
            } else {
                Logger.warn("[Donations] amount and/or currencyCode was missing. Is this an old job?")
            }

            self.durableOperationDelegate?.durableOperationDidSucceed(self, transaction: transaction)

            NotificationCenter.default.postNotificationNameAsync(
                SubscriptionManager.SubscriptionJobQueueDidFinishJobNotification,
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
                SubscriptionManager.SubscriptionJobQueueDidFailJobNotification,
                object: nil
            )
            self.durableOperationDelegate?.durableOperation(self, didFailWithError: error, transaction: transaction)
        }
    }
}
