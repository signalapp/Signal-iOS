//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalMessaging

final class StripeTest: XCTestCase {
    private let unknownCurrency = "ZZZ"

    func testParseNextActionRedirectUrl() {
        let notFoundTestCases: [Any?] = [
            nil,
            "https://example.com",
            ["next_action": "https://example.com"],
            [
                "next_action": [
                    "type": "incorrect type",
                    "redirect_to_url": ["url": "https://example.com"]
                ]
            ],
            [
                "next_action": [
                    "type": "redirect_to_url",
                    "redirect_to_url": "https://top-level-bad.example.com"
                ]
            ],
            [
                "next_action": [
                    "type": "redirect_to_url",
                    "redirect_to_url": ["url": "invalid URL"]
                ]
            ]
        ]
        for input in notFoundTestCases {
            XCTAssertNil(Stripe.parseNextActionRedirectUrl(from: input))
        }

        let actual = Stripe.parseNextActionRedirectUrl(from: [
            "next_action": [
                "type": "redirect_to_url",
                "redirect_to_url": ["url": "https://example.com"]
            ]
        ])
        let expected = URL(string: "https://example.com")!
        XCTAssertEqual(actual, expected)
    }

    func testIsBoostAmountTooSmall() {
        let minUsd = 5.as("USD")
        let minJpy = 50.as("JPY")
        let minUnknown = 0.as(unknownCurrency)

        let tooSmall: [(FiatMoney, FiatMoney)] = [
            ((-0.1).as("USD"), minUsd),
            ((-0.1).as("JPY"), minJpy),
            ((-0.1).as(unknownCurrency), minUnknown),
            (0.as("USD"), minUsd),
            (0.as("JPY"), minJpy),
            (0.as(unknownCurrency), minUnknown),
            (4.9.as("USD"), minUsd),
            (49.as("JPY"), minJpy),
            // Rounding
            (4.94.as("USD"), minUsd),
            (49.4.as("JPY"), minJpy)
        ]
        for (amount, minimumAmount) in tooSmall {
            XCTAssertTrue(
                DonationUtilities.isBoostAmountTooSmall(amount, minimumAmount: minimumAmount),
                "\(amount)"
            )
        }

        let allGood: [(FiatMoney, FiatMoney)] = [
            (5.as("USD"), minUsd),
            (10.as("USD"), minUsd),
            (1_000_000_000_000.as("USD"), minUsd),
            (50.as("JPY"), minJpy),
            (0.5.as(unknownCurrency), minUnknown),
            // Rounding
            (4.995.as("USD"), minUsd),
            (49.5.as("JPY"), minJpy)
        ]
        for (amount, minimumAmount) in allGood {
            XCTAssertFalse(
                DonationUtilities.isBoostAmountTooSmall(amount, minimumAmount: minimumAmount),
                "\(amount)"
            )
        }
    }
}

fileprivate extension Int {
    func `as`(_ currencyCode: Currency.Code) -> FiatMoney {
        FiatMoney(currencyCode: currencyCode, value: Decimal(self))
    }
}

fileprivate extension Double {
    func `as`(_ currencyCode: Currency.Code) -> FiatMoney {
        FiatMoney(currencyCode: currencyCode, value: Decimal(self))
    }
}
