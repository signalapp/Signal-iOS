//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

final class StripeTest: XCTestCase {
    private let unknownCurrency = "ZZZ"

    func testIsAmountTooLarge() {
        let tooLarge: [(NSDecimalNumber, Currency.Code)] = [
            (1_000_000, "USD"),
            (100_000_000, "JPY"),
            (1_000_000, unknownCurrency)
        ]
        for (amount, currencyCode) in tooLarge {
            XCTAssertTrue(Stripe.isAmountTooLarge(amount, in: currencyCode))
        }

        let allGood: [(NSDecimalNumber, Currency.Code)] = [
            (0, "USD"),
            (999_999, "USD"),
            (99_999_999, "JPY"),
            (999_999, unknownCurrency)
        ]
        for (amount, currencyCode) in allGood {
            XCTAssertFalse(Stripe.isAmountTooLarge(amount, in: currencyCode))
        }
    }

    func testIsAmountTooSmall() {
        let tooSmall: [(NSDecimalNumber, Currency.Code)] = [
            (0, "USD"),
            (0.49, "USD"),
            (49, "JPY"),
            (0.49, unknownCurrency)
        ]
        for (amount, currencyCode) in tooSmall {
            XCTAssertTrue(Stripe.isAmountTooSmall(amount, in: currencyCode))
        }

        let allGood: [(NSDecimalNumber, Currency.Code)] = [
            (0.5, "USD"),
            (1, "USD"),
            (1_000_000_000_000, "USD"),
            (50, "JPY"),
            (0.5, unknownCurrency)
        ]
        for (amount, currencyCode) in allGood {
            XCTAssertFalse(Stripe.isAmountTooSmall(amount, in: currencyCode))
        }
    }
}
