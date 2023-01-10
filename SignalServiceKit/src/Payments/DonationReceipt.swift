//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public final class DonationReceipt: NSObject, SDSCodableModel {
    public enum DonationReceiptType {
        case boost
        case subscription(subscriptionLevel: UInt)
        case gift
    }

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id
        case uniqueId
        case timestamp
        case receiptType
        case subscriptionLevel
        case currencyCode
        case amount
    }

    public var id: RowId?
    public let uniqueId: String
    public let receiptType: DonationReceiptType
    public let timestamp: Date
    public let amount: FiatMoney

    public static let databaseTableName = "model_DonationReceipt"

    public var localizedName: String {
        switch receiptType {
        case .boost:
            return NSLocalizedString(
                "DONATION_RECEIPT_ONE_TIME",
                comment: "Title for one-time donation receipts"
            )
        case .subscription:
            return NSLocalizedString(
                "DONATION_RECEIPT_RECURRING",
                comment: "Title for recurring donation receipts"
            )
        case .gift:
            return NSLocalizedString(
                "DONATION_RECEIPT_FOR_DONATION_ON_BEHALF_OF_A_FRIEND",
                comment: "Title for receipts for donations given on a friend's behalf"
            )
        }
    }

    public init(
        receiptType: DonationReceiptType,
        timestamp: Date,
        amount: FiatMoney
    ) {
        self.uniqueId = UUID().uuidString
        self.receiptType = receiptType
        self.timestamp = timestamp
        self.amount = amount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(RowId.self, forKey: .id)
        uniqueId = try container.decode(String.self, forKey: .uniqueId)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        amount = FiatMoney(
            currencyCode: try container.decode(Currency.Code.self, forKey: .currencyCode),
            value: try container.decode(Decimal.self, forKey: .amount)
        )

        let subscriptionLevel = try container.decodeIfPresent(UInt.self, forKey: .subscriptionLevel)
        let rawReceiptType = try container.decodeIfPresent(UInt.self, forKey: .receiptType)
        switch rawReceiptType {
        case nil:
            Logger.info("Parsing an older donation receipt")
            if let subscriptionLevel = subscriptionLevel {
                receiptType = .subscription(subscriptionLevel: subscriptionLevel)
            } else {
                receiptType = .boost
            }
        case 0:
            receiptType = .boost
        case 1:
            guard let subscriptionLevel = subscriptionLevel else {
                owsFail("Found a donation receipt, marked as a subscription, with no subscription level")
            }
            receiptType = .subscription(subscriptionLevel: subscriptionLevel)
        case 2:
            receiptType = .gift
        default:
            owsFail("Found a donation receipt with an unknown receipt type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(uniqueId, forKey: .uniqueId)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(amount.value, forKey: .amount)
        try container.encode(amount.currencyCode, forKey: .currencyCode)

        switch receiptType {
        case .boost:
            try container.encode(0, forKey: .receiptType)
        case .subscription(let subscriptionLevel):
            try container.encode(1, forKey: .receiptType)
            try container.encode(subscriptionLevel, forKey: .subscriptionLevel)
        case .gift:
            try container.encode(2, forKey: .receiptType)
        }
    }
}
