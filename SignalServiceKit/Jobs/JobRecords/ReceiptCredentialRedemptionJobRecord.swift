//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public final class DonationReceiptCredentialRedemptionJobRecord: JobRecord, FactoryInitializableFromRecordType {
    override class var jobRecordType: JobRecordType { .donationReceiptCredentialRedemption }

    public let paymentProcessor: String
    public let paymentMethod: String?

    public let receiptCredentialRequestContext: Data
    public let receiptCredentialRequest: Data

    private(set) var _receiptCredential: Data?
    let _receiptCredentialPresentation: Data?

    /// While this job now persists a `ReceiptCredential` we can convert to a
    /// presentation on the fly, it historically persisted the presentation
    /// directly. This method abstracts over those differences, which are not
    /// interesting to callers!
    func getReceiptCredentialPresentation() throws -> ReceiptCredentialPresentation? {
        if let _receiptCredential {
            return try DonationSubscriptionManager.generateReceiptCredentialPresentation(
                receiptCredential: try ReceiptCredential(contents: [UInt8](_receiptCredential))
            )
        } else if let _receiptCredentialPresentation {
            return try ReceiptCredentialPresentation(contents: [UInt8](_receiptCredentialPresentation))
        }

        return nil
    }

    public let isBoost: Bool

    public let subscriberID: Data
    public let targetSubscriptionLevel: UInt
    public let priorSubscriptionLevel: UInt
    public let isNewSubscription: Bool
    public let shouldSuppressPaymentAlreadyRedeemed: Bool

    public let boostPaymentIntentID: String

    public let amount: Decimal?
    public let currencyCode: String?

    init(
        paymentProcessor: String,
        paymentMethod: String?,
        receiptCredentialRequestContext: Data,
        receiptCredentialRequest: Data,
        subscriberID: Data,
        targetSubscriptionLevel: UInt,
        priorSubscriptionLevel: UInt,
        isNewSubscription: Bool,
        shouldSuppressPaymentAlreadyRedeemed: Bool,
        isBoost: Bool,
        amount: Decimal?,
        currencyCode: String?,
        boostPaymentIntentID: String
    ) {
        self.paymentProcessor = paymentProcessor
        self.paymentMethod = paymentMethod
        self.receiptCredentialRequestContext = receiptCredentialRequestContext
        self.receiptCredentialRequest = receiptCredentialRequest
        self._receiptCredential = nil
        self._receiptCredentialPresentation = nil
        self.subscriberID = subscriberID
        self.targetSubscriptionLevel = targetSubscriptionLevel
        self.priorSubscriptionLevel = priorSubscriptionLevel
        self.isNewSubscription = isNewSubscription
        self.shouldSuppressPaymentAlreadyRedeemed = shouldSuppressPaymentAlreadyRedeemed
        self.isBoost = isBoost
        self.amount = amount
        self.currencyCode = currencyCode
        self.boostPaymentIntentID = boostPaymentIntentID

        super.init(
            failureCount: 0,
            status: .ready
        )
    }

#if TESTABLE_BUILD
    init(
        paymentProcessor: String,
        paymentMethod: String?,
        receiptCredentialRequestContext: Data,
        receiptCredentialRequest: Data,
        receiptCredential: Data?,
        receiptCredentialPresentation: Data?,
        subscriberID: Data,
        targetSubscriptionLevel: UInt,
        priorSubscriptionLevel: UInt,
        isNewSubscription: Bool,
        shouldSuppressPaymentAlreadyRedeemed: Bool,
        isBoost: Bool,
        amount: Decimal?,
        currencyCode: String?,
        boostPaymentIntentID: String,
        failureCount: UInt,
        status: Status
    ) {
        self.paymentProcessor = paymentProcessor
        self.paymentMethod = paymentMethod
        self.receiptCredentialRequestContext = receiptCredentialRequestContext
        self.receiptCredentialRequest = receiptCredentialRequest
        self._receiptCredential = receiptCredential
        self._receiptCredentialPresentation = receiptCredentialPresentation
        self.subscriberID = subscriberID
        self.targetSubscriptionLevel = targetSubscriptionLevel
        self.priorSubscriptionLevel = priorSubscriptionLevel
        self.isNewSubscription = isNewSubscription
        self.shouldSuppressPaymentAlreadyRedeemed = shouldSuppressPaymentAlreadyRedeemed
        self.isBoost = isBoost
        self.amount = amount
        self.currencyCode = currencyCode
        self.boostPaymentIntentID = boostPaymentIntentID

        super.init(
            failureCount: failureCount,
            status: status
        )
    }
#endif

    required init(forRecordTypeFactoryInitializationFrom decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        paymentProcessor = try container.decode(String.self, forKey: .paymentProcessor)
        paymentMethod = try container.decodeIfPresent(String.self, forKey: .paymentMethod)

        receiptCredentialRequestContext = try container.decode(Data.self, forKey: .receiptCredentialRequestContext)
        receiptCredentialRequest = try container.decode(Data.self, forKey: .receiptCredentialRequest)
        _receiptCredential = try container.decodeIfPresent(Data.self, forKey: ._receiptCredential)
        _receiptCredentialPresentation = try container.decodeIfPresent(Data.self, forKey: ._receiptCredentialPresentation)

        isBoost = try container.decode(Bool.self, forKey: .isBoost)

        subscriberID = try container.decode(Data.self, forKey: .subscriberID)
        targetSubscriptionLevel = try container.decode(UInt.self, forKey: .targetSubscriptionLevel)
        priorSubscriptionLevel = try container.decode(UInt.self, forKey: .priorSubscriptionLevel)
        isNewSubscription = try container.decodeIfPresent(Bool.self, forKey: .isNewSubscription) ?? true
        shouldSuppressPaymentAlreadyRedeemed = try container.decodeIfPresent(Bool.self, forKey: .shouldSuppressPaymentAlreadyRedeemed) ?? false

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
        try container.encodeIfPresent(_receiptCredential, forKey: ._receiptCredential)
        try container.encodeIfPresent(_receiptCredentialPresentation, forKey: ._receiptCredentialPresentation)
        try container.encode(subscriberID, forKey: .subscriberID)
        try container.encode(targetSubscriptionLevel, forKey: .targetSubscriptionLevel)
        try container.encode(priorSubscriptionLevel, forKey: .priorSubscriptionLevel)
        try container.encode(isNewSubscription, forKey: .isNewSubscription)
        try container.encode(shouldSuppressPaymentAlreadyRedeemed, forKey: .shouldSuppressPaymentAlreadyRedeemed)
        try container.encode(isBoost, forKey: .isBoost)
        try container.encodeIfPresent(
            LegacySDSSerializer().serializeAsLegacySDSData(property: amount),
            forKey: .amount
        )
        try container.encodeIfPresent(currencyCode, forKey: .currencyCode)
        try container.encode(boostPaymentIntentID, forKey: .boostPaymentIntentID)
    }

    // MARK: Update

    func setReceiptCredential(_ receiptCredential: ReceiptCredential, tx: SDSAnyWriteTransaction) {
        anyUpdate(transaction: tx) { record in
            record._receiptCredential = receiptCredential.serialize().asData
        }
    }
}
