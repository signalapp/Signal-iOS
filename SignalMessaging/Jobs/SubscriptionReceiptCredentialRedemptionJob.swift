//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import ZKGroup

@objc(OWSSubscriptionReceiptCredentialJobQueue)
public class SubscriptionReceiptCredentialJobQueue: NSObject, JobQueue {

    // Add optional paymentIntentID / isBoost

    public func add(isBoost: Bool, receiptCredentialRequestContext: Data, receiptCredentailRequest: Data, subscriberID: Data, targetSubscriptionLevel: UInt, priorSubscriptionLevel: UInt, boostPaymentIntentID: String, transaction: SDSAnyWriteTransaction) {
        let jobRecord = OWSReceiptCredentialRedemptionJobRecord(receiptCredentialRequestContext: receiptCredentialRequestContext,
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
    public static let maxRetries: UInt = 10
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
        return SubscriptionReceiptCredentailRedemptionOperation(jobRecord)
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
    var receiptCredentialRequestContext: ReceiptCredentialRequestContext?
    var receiptCredentialRequest: ReceiptCredentialRequest?
    let targetSubscriptionLevel: UInt
    let priorSubscriptionLevel: UInt
    let boostPaymentIntentID: String

    @objc public required init(_ jobRecord: OWSReceiptCredentialRedemptionJobRecord) {
        self.jobRecord = jobRecord
        self.isBoost = jobRecord.isBoost
        self.subscriberID = jobRecord.subscriberID
        self.targetSubscriptionLevel = jobRecord.targetSubscriptionLevel
        self.priorSubscriptionLevel = jobRecord.priorSubscriptionLevel
        self.boostPaymentIntentID = jobRecord.boostPaymentIntentID

        do {
            self.receiptCredentialRequestContext = try ReceiptCredentialRequestContext(contents: [UInt8](jobRecord.receiptCredentailRequestContext))
            self.receiptCredentialRequest = try ReceiptCredentialRequest(contents: [UInt8](jobRecord.receiptCredentailRequest))
        } catch {
            owsFailDebug("Failed to reconstitute request context, credential request \(error)")
            self.receiptCredentialRequestContext = nil
            self.receiptCredentialRequest = nil
        }
    }

    override public func run() {
        assert(self.durableOperationDelegate != nil)

        guard let context = receiptCredentialRequestContext, let request = receiptCredentialRequest else {
            let error = OWSAssertionError("Can't run an operation with invalid context and request")
            didFail(error: error)
            return
        }

        // First check to see if we have an existing presentation
        var serializedPresentation: Data?
        self.databaseStorage.read { transaction in
            serializedPresentation = SubscriptionManager.getPendingRecieptCredentialPresentation(transaction: transaction)
        }

        // We already have a receiptCredentialPresentation, lets redeem it
        if let serializedPresentation = serializedPresentation {

            var presentation: ReceiptCredentialPresentation?
            do {
                presentation = try ReceiptCredentialPresentation(contents: [UInt8](serializedPresentation))
            } catch {
                let error = OWSAssertionError("Failed to redeem persisted display credential")
                didFail(error: error)
                return
            }

            guard let presentation = presentation else {
                return
            }

            firstly(on: .global()) {
                return try SubscriptionManager.redeemReceiptCredentialPresentation(receiptCredentialPresentation: presentation)
            }.then(on: .global()) {
                self.profileManagerImpl.fetchLocalUsersProfilePromise().asVoid()
            }.done(on: .global()) {
                Logger.debug("Presentation completed successfully")
                self.didSucceed()
            }.catch(on: .global()) { error in
                self.reportError(error)
            }
        } else {
            // We do not have a receiptCredentialPresentation, lets go through the full flow

            firstly(on: .global()) {
                return try SubscriptionManager.requestReceiptCredentialPresentation(for: self.subscriberID,
                                                                                       context: context,
                                                                                       request: request,
                                                                                       targetSubscriptionLevel: self.targetSubscriptionLevel,
                                                                                       priorSubscriptionLevel: self.priorSubscriptionLevel)
            }.then { newReceiptCredentialPresentation in
                return try SubscriptionManager.redeemReceiptCredentialPresentation(receiptCredentialPresentation: newReceiptCredentialPresentation)
            }.then(on: .global()) {
                self.profileManagerImpl.fetchLocalUsersProfilePromise().asVoid()
            }.done(on: .global()) {
                Logger.debug("Presentation completed successfully")
                self.didSucceed()
            }.catch(on: .global()) { error in
                self.reportError(error)
            }
        }
    }

    override public func didSucceed() {
        self.databaseStorage.write { transaction in
            SubscriptionManager.setPendingRecieptCredentialPresentation(nil, transaction: transaction)
            SubscriptionManager.setLastReceiptRedemptionFailed(failed: false, transaction: transaction)
            self.durableOperationDelegate?.durableOperationDidSucceed(self, transaction: transaction)
            NotificationCenter.default.postNotificationNameAsync(SubscriptionManager.SubscriptionJobQueueDidFinishJobNotification, object: nil)
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
            SubscriptionManager.setPendingRecieptCredentialPresentation(nil, transaction: transaction)
            SubscriptionManager.setLastReceiptRedemptionFailed(failed: true, transaction: transaction)
            NotificationCenter.default.postNotificationNameAsync(SubscriptionManager.SubscriptionJobQueueDidFailJobNotification, object: nil)
            self.durableOperationDelegate?.durableOperation(self, didFailWithError: error, transaction: transaction)
        }
    }
}
