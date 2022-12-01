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
            XCTAssertTrue(DonationUtilities.isAmountTooSmall(amount), "\(amount)")
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
            XCTAssertFalse(DonationUtilities.isAmountTooSmall(amount), "\(amount)")
        }
    }
}
