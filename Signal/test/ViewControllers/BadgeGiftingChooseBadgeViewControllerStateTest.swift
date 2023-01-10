//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import Signal
@testable import SignalMessaging

class BadgeGiftingChooseBadgeViewControllerStateTest: XCTestCase {
    typealias State = BadgeGiftingChooseBadgeViewController.State

    private static func loadedState(selectedCurrencyCode: Currency.Code) -> State {
        .loaded(
            selectedCurrencyCode: selectedCurrencyCode,
            giftConfiguration: .init(
                level: 999,
                badge: try! ProfileBadge(jsonDictionary: [
                    "id": "GIFT",
                    "category": "donor",
                    "name": "A Gift",
                    "description": "A gift badge!",
                    "sprites6": ["ldpi.png", "mdpi.png", "hdpi.png", "xhdpi.png", "xxhdpi.png", "xxxhdpi.png"]
                ]),
                presetAmount: [
                    "EUR": .init(currencyCode: "EUR", value: 123),
                    "USD": .init(currencyCode: "USD", value: 456)
                ]
            ),
            paymentMethodsConfiguration: .init(supportedPaymentMethodsByCurrency: [
                "USD": [.applePay, .creditOrDebitCard, .paypal],
                "EUR": [.applePay, .creditOrDebitCard, .paypal]
            ])
        )
    }

    func testCanContinue() throws {
        let stuck: [State] = [.initializing, .loading, .loadFailed]
        stuck.forEach { XCTAssertFalse($0.canContinue) }

        let notStuck = Self.loadedState(selectedCurrencyCode: "EUR")
        XCTAssertTrue(notStuck.canContinue)
    }

    func testSelectCurrencyCode() throws {
        let before = Self.loadedState(selectedCurrencyCode: "USD")
        let after = before.selectCurrencyCode("EUR")

        func assertCurrencyCode(_ state: State, expected: Currency.Code) throws {
            switch state {
            case let .loaded(actual, _, _):
                XCTAssertEqual(actual, expected)
            default:
                XCTFail("Invalid state")
            }
        }
        try assertCurrencyCode(before, expected: "USD")
        try assertCurrencyCode(after, expected: "EUR")
    }
}
