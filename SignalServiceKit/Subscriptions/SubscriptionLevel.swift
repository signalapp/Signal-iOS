//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class SubscriptionLevel: Comparable, Equatable, Codable {
    public let level: UInt
    public let name: String
    public let badge: ProfileBadge
    public let amounts: [Currency.Code: FiatMoney]

    public init(
        level: UInt,
        name: String,
        badge: ProfileBadge,
        amounts: [Currency.Code: FiatMoney]
    ) {
        self.level = level
        self.name = name
        self.badge = badge
        self.amounts = amounts
    }

    // MARK: Comparable

    public static func < (lhs: SubscriptionLevel, rhs: SubscriptionLevel) -> Bool {
        return lhs.level < rhs.level
    }

    public static func == (lhs: SubscriptionLevel, rhs: SubscriptionLevel) -> Bool {
        return lhs.level == rhs.level
    }
}
