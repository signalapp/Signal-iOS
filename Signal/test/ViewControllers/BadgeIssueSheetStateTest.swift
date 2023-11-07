//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import Signal
@testable import SignalMessaging

class BadgeIssueSheetStateTest: XCTestCase {
    typealias State = BadgeIssueSheetState

    private func getSubscriptionBadge(populateAssets: Bool = true) -> ProfileBadge {
        let result = try! ProfileBadge(jsonDictionary: [
            "id": "R_MED",
            "category": "donor",
            "name": "Subscriber X",
            "description": "A subscriber badge!",
            "sprites6": ["ldpi.png", "mdpi.png", "hdpi.png", "xhdpi.png", "xxhdpi.png", "xxxhdpi.png"]
        ])
        if populateAssets {
            result._testingOnly_populateAssets()
        }
        return result
    }

    private func getBoostBadge(populateAssets: Bool = true) -> ProfileBadge {
        let result = try! ProfileBadge(jsonDictionary: [
            "id": "BOOST",
            "category": "donor",
            "name": "A Boost",
            "description": "A boost badge!",
            "sprites6": ["ldpi.png", "mdpi.png", "hdpi.png", "xhdpi.png", "xxhdpi.png", "xxxhdpi.png"]
        ])
        if populateAssets {
            result._testingOnly_populateAssets()
        }
        return result
    }

    private func getGiftBadge(populateAssets: Bool = true) -> ProfileBadge {
        let result = try! ProfileBadge(jsonDictionary: [
            "id": "GIFT",
            "category": "donor",
            "name": "A Gift",
            "description": "A gift badge!",
            "sprites6": ["ldpi.png", "mdpi.png", "hdpi.png", "xhdpi.png", "xxhdpi.png", "xxxhdpi.png"]
        ])
        if populateAssets {
            result._testingOnly_populateAssets()
        }
        return result
    }

    func testBadge() throws {
        let badge = getSubscriptionBadge()
        let state = State(
            badge: badge,
            mode: .subscriptionExpiredBecauseNotRenewed,
            canDonate: true
        )
        XCTAssertIdentical(state.badge, badge)
    }

    func testActionButton() throws {
        let dismissButtonStates: [State] = [
            .init(
                badge: getGiftBadge(),
                mode: .giftBadgeExpired(hasCurrentSubscription: true),
                canDonate: true
            ),
            .init(
                badge: getGiftBadge(),
                mode: .giftBadgeExpired(hasCurrentSubscription: true),
                canDonate: true
            ),
            .init(
                badge: getBoostBadge(),
                mode: .boostExpired(hasCurrentSubscription: true),
                canDonate: false
            ),
            .init(
                badge: getGiftBadge(),
                mode: .giftNotRedeemed(fullName: ""),
                canDonate: true
            ),
            .init(
                badge: getBoostBadge(),
                mode: .boostBankPaymentProcessing,
                canDonate: true
            ),
            .init(
                badge: getSubscriptionBadge(),
                mode: .subscriptionBankPaymentProcessing,
                canDonate: true
            )
        ]
        for state in dismissButtonStates {
            XCTAssertEqual(state.actionButton.action, .dismiss)
            XCTAssertFalse(state.actionButton.hasNotNow)
        }

        let donateButtonStates: [State] = [
            .init(
                badge: getSubscriptionBadge(),
                mode: .subscriptionExpiredBecauseOfChargeFailure,
                canDonate: true
            ),
            .init(
                badge: getSubscriptionBadge(),
                mode: .subscriptionExpiredBecauseNotRenewed,
                canDonate: true
            ),
            .init(
                badge: getBoostBadge(),
                mode: .boostExpired(hasCurrentSubscription: false),
                canDonate: true
            ),
            .init(
                badge: getBoostBadge(),
                mode: .boostExpired(hasCurrentSubscription: true),
                canDonate: true
            ),
            .init(
                badge: getGiftBadge(),
                mode: .giftBadgeExpired(hasCurrentSubscription: false),
                canDonate: true
            ),
            .init(
                badge: getSubscriptionBadge(),
                mode: .bankPaymentFailed,
                canDonate: true
            )
        ]
        for state in donateButtonStates {
            XCTAssertEqual(state.actionButton.action, .openDonationView)
            XCTAssertTrue(state.actionButton.hasNotNow)
        }
    }
}
