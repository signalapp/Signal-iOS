//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

public final class SubscriptionReceiptCredentialRedemptionJobRecord: JobRecord, FactoryInitializableFromRecordType {
    override class var jobRecordType: JobRecordType { .subscriptionReceiptCredentialRedemption }

    public let paymentProcessor: String
    public let paymentMethod: String?
    public let receiptCredentialRequestContext: Data
    public let receiptCredentialRequest: Data
    public var receiptCredentialPresentation: Data?

    public let isBoost: Bool

    public let subscriberID: Data
    public let targetSubscriptionLevel: UInt
    public let priorSubscriptionLevel: UInt

    public let boostPaymentIntentID: String

    public let amount: Decimal?
    public let currencyCode: String?

    public init(
        paymentProcessor: String,
        paymentMethod: String?,
        receiptCredentialRequestContext: Data,
        receiptCredentialRequest: Data,
        receiptCredentialPresentation: Data? = nil,
        subscriberID: Data,
        targetSubscriptionLevel: UInt,
        priorSubscriptionLevel: UInt,
        isBoost: Bool,
        amount: Decimal?,
        currencyCode: String?,
        boostPaymentIntentID: String,
        label: String,
        exclusiveProcessIdentifier: String? = nil,
        failureCount: UInt = 0,
        status: Status = .ready
    ) {
        self.paymentProcessor = paymentProcessor
        self.paymentMethod = paymentMethod
        self.receiptCredentialRequestContext = receiptCredentialRequestContext
        self.receiptCredentialRequest = receiptCredentialRequest
        self.receiptCredentialPresentation = receiptCredentialPresentation
        self.subscriberID = subscriberID
        self.targetSubscriptionLevel = targetSubscriptionLevel
        self.priorSubscriptionLevel = priorSubscriptionLevel
        self.isBoost = isBoost
        self.amount = amount
        self.currencyCode = currencyCode
        self.boostPaymentIntentID = boostPaymentIntentID

        super.init(
            label: label,
            exclusiveProcessIdentifier: exclusiveProcessIdentifier,
            failureCount: failureCount,
            status: status
        )
    }

    required init(forRecordTypeFactoryInitializationFrom decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        paymentProcessor = try container.decode(String.self, forKey: .paymentProcessor)
        paymentMethod = try container.decodeIfPresent(String.self, forKey: .paymentMethod)

        receiptCredentialRequestContext = try container.decode(Data.self, forKey: .receiptCredentialRequestContext)
        receiptCredentialRequest = try container.decode(Data.self, forKey: .receiptCredentialRequest)
        receiptCredentialPresentation = try container.decodeIfPresent(Data.self, forKey: .receiptCredentialPresentation)

        isBoost = try container.decode(Bool.self, forKey: .isBoost)

        subscriberID = try container.decode(Data.self, forKey: .subscriberID)
        targetSubscriptionLevel = try container.decode(UInt.self, forKey: .targetSubscriptionLevel)
        priorSubscriptionLevel = try container.decode(UInt.self, forKey: .priorSubscriptionLevel)

        boostPaymentIntentID = try container.decode(String.self, forKey: .boostPaymentIntentID)

        amount = try container.decodeIfPresent(
            Data.self,
            forKey: .amount
        ).map { amountData in
            return try LegacySDSSerializer().deserializeLegacySDSData(
                amountData,
                propertyName: "amount"
            )
        }
        currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode)

        try super.init(baseClassDuringFactoryInitializationFrom: container.superDecoder())
    }

    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try super.encode(to: container.superEncoder())

        try container.encode(paymentProcessor, forKey: .paymentProcessor)
        try container.encodeIfPresent(paymentMethod, forKey: .paymentMethod)
        try container.encode(receiptCredentialRequestContext, forKey: .receiptCredentialRequestContext)
        try container.encode(receiptCredentialRequest, forKey: .receiptCredentialRequest)
        try container.encodeIfPresent(receiptCredentialPresentation, forKey: .receiptCredentialPresentation)
        try container.encode(subscriberID, forKey: .subscriberID)
        try container.encode(targetSubscriptionLevel, forKey: .targetSubscriptionLevel)
        try container.encode(priorSubscriptionLevel, forKey: .priorSubscriptionLevel)
        try container.encode(isBoost, forKey: .isBoost)
        try container.encodeIfPresent(
            LegacySDSSerializer().serializeAsLegacySDSData(property: amount),
            forKey: .amount
        )
        try container.encodeIfPresent(currencyCode, forKey: .currencyCode)
        try container.encode(boostPaymentIntentID, forKey: .boostPaymentIntentID)
    }

    // MARK: Update

    public func update(withReceiptCredentialPresentation presentation: Data, transaction: SDSAnyWriteTransaction) {
        anyUpdate(transaction: transaction) { record in
            record.receiptCredentialPresentation = presentation
        }
    }
}
