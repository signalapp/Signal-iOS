//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

public final class DonationReceipt: NSObject, SDSCodableModel {
    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id
        case uniqueId
        case timestamp
        case subscriptionLevel
        case currencyCode
        case amount
    }

    public var id: RowId?
    public let uniqueId: String
    public let timestamp: Date
    public let subscriptionLevel: UInt?
    public let amount: Decimal
    public let currencyCode: Currency.Code

    public static let databaseTableName = "model_DonationReceipt"

    public var isBoost: Bool { subscriptionLevel == nil }

    public var localizedName: String {
        isBoost
        ? NSLocalizedString("DONATION_RECEIPT_ONE_TIME", comment: "Title for one-time donation receipts")
        : NSLocalizedString("DONATION_RECEIPT_RECURRING", comment: "Title for recurring donation receipts")
    }

    public init(
        timestamp: Date,
        subscriptionLevel: UInt? = nil,
        amount: Decimal,
        currencyCode: Currency.Code
    ) {
        self.uniqueId = UUID().uuidString
        self.timestamp = timestamp
        self.subscriptionLevel = subscriptionLevel
        self.amount = amount
        self.currencyCode = currencyCode
    }
}
