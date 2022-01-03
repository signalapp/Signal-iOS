//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalClient

@objc(OWSSubscriptionReceiptCredentialJobQueue)
public class SubscriptionReceiptCredentialJobQueue: NSObject, JobQueue {

    // Add optional paymentIntentID / isBoost

    public func add(
        isBoost: Bool,
        receiptCredentialRequestContext: Data,
        receiptCredentailRequest: Data,
        subscriberID: Data,
        targetSubscriptionLevel: UInt,
        priorSubscriptionLevel: UInt,
        boostPaymentIntentID: String,
        transaction: SDSAnyWriteTransaction
    ) {
        let jobRecord = OWSReceiptCredentialRedemptionJobRecord(
            receiptCredentialRequestContext: receiptCredentialRequestContext,
            receiptCredentailRequest: receiptCredentailRequest,
            subscriberID: subscriberID,
            targetSubscriptionLevel: targetSubscriptionLevel,
            priorSubscriptionLevel: priorSubscriptionLevel,
            isBoost: isBoost,
            boostPaymentIntentID: boostPaymentIntentID,
            label: self.jobRecordLabel)
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

    @objc public required init(_ jobRecord: OWSReceiptCredentialRedemptionJobRecord) throws {
        self.jobRecord = jobRecord
        self.isBoost = jobRecord.isBoost
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

        firstly(on: .global()) { () -> Promise<ReceiptCredentialPresentation> in
            // We already have a receiptCredentialPresentation, lets use it
            if let receiptCredentialPresentation = self.receiptCredentialPresentation {
                Logger.info("[Subscriptions] Using persisted receipt credential presentation")
                return Promise.value(receiptCredentialPresentation)
            }

            Logger.info("[Subscriptions] Creating new receipt credential presentation")

            // Create a new receipt credential presentation
            return firstly(on: .global()) { () -> Promise<ReceiptCredentialPresentation> in
                if self.isBoost {
                    Logger.info("[Subscriptions] Durable job requesting receipt for boost")
                    return try SubscriptionManager.requestBoostReceiptCredentialPresentation(
                        for: self.boostPaymentIntentID,
                           context: self.receiptCredentialRequestContext,
                           request: self.receiptCredentialRequest
                    )
                } else {
                    Logger.info("[Subscriptions] Durable job requesting receipt for subscription")
                    return try SubscriptionManager.requestReceiptCredentialPresentation(
                        for: self.subscriberID,
                           context: self.receiptCredentialRequestContext,
                           request: self.receiptCredentialRequest,
                           targetSubscriptionLevel: self.targetSubscriptionLevel,
                           priorSubscriptionLevel: self.priorSubscriptionLevel
                    )
                }
            }.then(on: .global()) { newReceiptCredentialPresentation in
                // Store the receipt credential presentation, in case the job fails.
                self.databaseStorage.writePromise { transaction in
                    self.jobRecord.update(
                        withReceiptCredentialPresentation: newReceiptCredentialPresentation.serialize().asData,
                        transaction: transaction
                    )
                }.map { _ in newReceiptCredentialPresentation }
            }
        }.then(on: .global()) { newReceiptCredentialPresentation in
            return try SubscriptionManager.redeemReceiptCredentialPresentation(
                receiptCredentialPresentation: newReceiptCredentialPresentation
            )
        }.done(on: .global()) {
            Logger.info("[Subscriptions] Successfully redeemed receipt credential presentation")
            self.didSucceed()
        }.catch(on: .global()) { error in
            self.reportError(error)
        }
    }

    override public func didSucceed() {
        self.databaseStorage.write { transaction in
            if !self.isBoost {
                SubscriptionManager.setLastReceiptRedemptionFailed(failureReason: .none, transaction: transaction)
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
        Logger.error("failed to redeem receipt credential with error: \(error.userErrorDescription)")
        self.databaseStorage.write { transaction in
            NotificationCenter.default.postNotificationNameAsync(
                SubscriptionManager.SubscriptionJobQueueDidFailJobNotification,
                object: nil
            )
            self.durableOperationDelegate?.durableOperation(self, didFailWithError: error, transaction: transaction)
        }
    }
}
