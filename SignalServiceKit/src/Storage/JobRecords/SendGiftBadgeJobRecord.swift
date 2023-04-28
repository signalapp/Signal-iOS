//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public final class SendGiftBadgeJobRecord: JobRecord, FactoryInitializableFromRecordType {
    override class var jobRecordType: JobRecordType { .sendGiftBadge }

    public let paymentProcessor: String
    public let receiptCredentialRequestContext: Data
    public let receiptCredentialRequest: Data
    public let amount: Decimal
    public let currencyCode: String

    public let paymentIntentClientSecret: String?
    public let paymentIntentId: String?
    public let paymentMethodId: String?

    public let paypalPayerId: String?
    public let paypalPaymentId: String?
    public let paypalPaymentToken: String?

    public let threadId: String
    public let messageText: String

    public init(
        paymentProcessor: String,
        receiptCredentialRequestContext: Data,
        receiptCredentialRequest: Data,
        amount: Decimal,
        currencyCode: String,
        paymentIntentClientSecret: String?,
        paymentIntentId: String?,
        paymentMethodId: String?,
        paypalPayerId: String?,
        paypalPaymentId: String?,
        paypalPaymentToken: String?,
        threadId: String,
        messageText: String,
        label: String,
        exclusiveProcessIdentifier: String? = nil,
        failureCount: UInt = 0,
        status: Status = .ready
    ) {
        self.paymentProcessor = paymentProcessor
        self.receiptCredentialRequestContext = receiptCredentialRequestContext
        self.receiptCredentialRequest = receiptCredentialRequest
        self.amount = amount
        self.currencyCode = currencyCode

        self.paymentIntentClientSecret = paymentIntentClientSecret
        self.paymentIntentId = paymentIntentId
        self.paymentMethodId = paymentMethodId

        self.paypalPayerId = paypalPayerId
        self.paypalPaymentId = paypalPaymentId
        self.paypalPaymentToken = paypalPaymentToken

        self.threadId = threadId
        self.messageText = messageText

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
        receiptCredentialRequestContext = try container.decode(Data.self, forKey: .receiptCredentialRequestContext)
        receiptCredentialRequest = try container.decode(Data.self, forKey: .receiptCredentialRequest)
        amount = try LegacySDSSerializer().deserializeLegacySDSData(
            try container.decode(Data.self, forKey: .amount),
            propertyName: "amount"
        )
        currencyCode = try container.decode(String.self, forKey: .currencyCode)

        paymentIntentClientSecret = try container.decodeIfPresent(String.self, forKey: .paymentIntentClientSecret)
        paymentIntentId = try container.decodeIfPresent(String.self, forKey: .boostPaymentIntentID)
        paymentMethodId = try container.decodeIfPresent(String.self, forKey: .paymentMethodId)

        paypalPayerId = try container.decodeIfPresent(String.self, forKey: .paypalPayerId)
        paypalPaymentId = try container.decodeIfPresent(String.self, forKey: .paypalPaymentId)
        paypalPaymentToken = try container.decodeIfPresent(String.self, forKey: .paypalPaymentToken)

        threadId = try container.decode(String.self, forKey: .threadId)
        messageText = try container.decode(String.self, forKey: .messageText)

        try super.init(baseClassDuringFactoryInitializationFrom: container.superDecoder())
    }

    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try super.encode(to: container.superEncoder())

        try container.encode(paymentProcessor, forKey: .paymentProcessor)
        try container.encode(receiptCredentialRequestContext, forKey: .receiptCredentialRequestContext)
        try container.encode(receiptCredentialRequest, forKey: .receiptCredentialRequest)
        try container.encode(LegacySDSSerializer().serializeAsLegacySDSData(property: amount), forKey: .amount)
        try container.encode(currencyCode, forKey: .currencyCode)

        try container.encodeIfPresent(paymentIntentClientSecret, forKey: .paymentIntentClientSecret)
        try container.encodeIfPresent(paymentIntentId, forKey: .boostPaymentIntentID)
        try container.encodeIfPresent(paymentMethodId, forKey: .paymentMethodId)

        try container.encodeIfPresent(paypalPayerId, forKey: .paypalPayerId)
        try container.encodeIfPresent(paypalPaymentId, forKey: .paypalPaymentId)
        try container.encodeIfPresent(paypalPaymentToken, forKey: .paypalPaymentToken)

        try container.encode(threadId, forKey: .threadId)
        try container.encode(messageText, forKey: .messageText)
    }
}
