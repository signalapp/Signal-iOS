//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import Signal

class BadgeGiftingChooseBadgeViewControllerStateTest: XCTestCase {
    typealias State = BadgeGiftingChooseBadgeViewController.State

    private func getGiftBadge() -> ProfileBadge {
        try! ProfileBadge(jsonDictionary: [
            "id": "GIFT",
            "category": "donor",
            "name": "A Gift",
            "description": "A gift badge!",
            "sprites6": ["ldpi.png", "mdpi.png", "hdpi.png", "xhdpi.png", "xxhdpi.png", "xxxhdpi.png"]
        ])
    }

    func testCanContinue() throws {
        let stuck: [State] = [.initializing, .loading, .loadFailed]
        stuck.forEach { XCTAssertFalse($0.canContinue) }

        let notStuck: State = .loaded(selectedCurrencyCode: "EUR", badge: getGiftBadge(), pricesByCurrencyCode: ["EUR": 123, "USD": 456])
        XCTAssertTrue(notStuck.canContinue)
    }

    func testSelectCurrencyCode() throws {
        let badge = getGiftBadge()

        let before = State.loaded(selectedCurrencyCode: "USD", badge: badge, pricesByCurrencyCode: ["EUR": 123, "USD": 456])
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
