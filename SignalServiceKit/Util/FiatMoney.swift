//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A type that represents an amount of money in a given fiat currency, such as 5 euros.
///
/// It's often useful to pair a currency with an amount. This simple type helps with that.
public struct FiatMoney: Codable, Equatable, Hashable, Sendable, CustomDebugStringConvertible {
    enum CodingKeys: String, CodingKey {
        case currencyCode
        case value
    }

    /// The currency for this amount of money.
    ///
    /// For example, for €1.23, this the currency is `EUR`.
    public var currencyCode: Currency.Code

    /// The amount of money.
    ///
    /// For example, for €1.23, this value is `1.23`.
    public var value: Decimal

    /// Creates a money instance.
    ///
    /// - Parameter currencyCode: The currency code, such as `EUR`.
    /// - Parameter value: The amount of money, such as `12.34`.
    public init(currencyCode: Currency.Code, value: Decimal) {
        self.currencyCode = currencyCode
        self.value = value
    }

    public var debugDescription: String { "FiatMoney(\(value) \(currencyCode))" }
}
