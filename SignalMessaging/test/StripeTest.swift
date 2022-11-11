//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

final class StripeTest: XCTestCase {
    private let unknownCurrency = "ZZZ"

    func testIsAmountTooLarge() {
        let tooLarge: [FiatMoney] = [
            FiatMoney(currencyCode: "USD", value: 1_000_000),
            FiatMoney(currencyCode: "JPY", value: 100_000_000),
            FiatMoney(currencyCode: "IDR", value: 1_000_000_000_000),
            FiatMoney(currencyCode: unknownCurrency, value: 1_000_000),
            // Rounding
            FiatMoney(currencyCode: "USD", value: 999_999.995)
        ]
        for amount in tooLarge {
            XCTAssertTrue(Stripe.isAmountTooLarge(amount), "\(amount)")
        }

        let allGood: [FiatMoney] = [
            FiatMoney(currencyCode: "USD", value: 0),
            FiatMoney(currencyCode: "USD", value: 999_999.99),
            FiatMoney(currencyCode: "JPY", value: 99_999_999),
            FiatMoney(currencyCode: "IDR", value: 9_999_999_999.99),
            FiatMoney(currencyCode: unknownCurrency, value: 999_999.99),
            // Rounding
            FiatMoney(currencyCode: "USD", value: 999_999.994)
        ]
        for amount in allGood {
            XCTAssertFalse(Stripe.isAmountTooLarge(amount), "\(amount)")
        }
    }

    func testIsAmountTooSmall() {
        let tooSmall: [FiatMoney] = [
            FiatMoney(currencyCode: "USD", value: 0),
            FiatMoney(currencyCode: "JPY", value: 0),
            FiatMoney(currencyCode: unknownCurrency, value: 0),
            FiatMoney(currencyCode: "USD", value: 0.49),
            FiatMoney(currencyCode: "JPY", value: 49),
            // Rounding
            FiatMoney(currencyCode: "USD", value: 0.494),
            FiatMoney(currencyCode: "JPY", value: 49.4),
            FiatMoney(currencyCode: unknownCurrency, value: 0.494)
        ]
        for amount in tooSmall {
            XCTAssertTrue(Stripe.isAmountTooSmall(amount), "\(amount)")
        }

        let allGood: [FiatMoney] = [
            FiatMoney(currencyCode: "USD", value: 0.5),
            FiatMoney(currencyCode: "USD", value: 1),
            FiatMoney(currencyCode: "USD", value: 1_000_000_000_000),
            FiatMoney(currencyCode: "JPY", value: 50),
            FiatMoney(currencyCode: unknownCurrency, value: 0.5),
            // Rounding
            FiatMoney(currencyCode: "USD", value: 0.495),
            FiatMoney(currencyCode: "JPY", value: 49.5),
            FiatMoney(currencyCode: unknownCurrency, value: 0.495)
        ]
        for amount in allGood {
            XCTAssertFalse(Stripe.isAmountTooSmall(amount), "\(amount)")
        }
    }
}
