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
        let minimums: [Currency.Code: FiatMoney] = [
            "USD": 5.as("USD"),
            "JPY": 50.as("JPY")
        ]

        let tooSmall: [FiatMoney] = [
            FiatMoney(currencyCode: "USD", value: -0.1),
            FiatMoney(currencyCode: "JPY", value: -0.1),
            FiatMoney(currencyCode: unknownCurrency, value: -0.1),
            FiatMoney(currencyCode: "USD", value: 0),
            FiatMoney(currencyCode: "JPY", value: 0),
            FiatMoney(currencyCode: unknownCurrency, value: 0),
            FiatMoney(currencyCode: "USD", value: 4.9),
            FiatMoney(currencyCode: "JPY", value: 49),
            // Rounding
            FiatMoney(currencyCode: "USD", value: 4.94),
            FiatMoney(currencyCode: "JPY", value: 49.4)
        ]
        for amount in tooSmall {
            XCTAssertTrue(
                DonationUtilities.isBoostAmountTooSmall(
                    amount,
                    givenMinimumAmounts: minimums
                ),
                "\(amount)"
            )
        }

        let allGood: [FiatMoney] = [
            FiatMoney(currencyCode: "USD", value: 5),
            FiatMoney(currencyCode: "USD", value: 10),
            FiatMoney(currencyCode: "USD", value: 1_000_000_000_000),
            FiatMoney(currencyCode: "JPY", value: 50),
            // Unknown currencies accept any positive value
            FiatMoney(currencyCode: unknownCurrency, value: 0.5),
            // Rounding
            FiatMoney(currencyCode: "USD", value: 4.995),
            FiatMoney(currencyCode: "JPY", value: 49.5)
        ]
        for amount in allGood {
            XCTAssertFalse(
                DonationUtilities.isBoostAmountTooSmall(
                    amount,
                    givenMinimumAmounts: minimums
                ),
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
