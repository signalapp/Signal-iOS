//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import Foundation
import Signal

class BadgeExpirationSheetStateTest: XCTestCase {
    typealias State = BadgeExpirationSheetState

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

    func testBodyChangesForChargeFailuresWithDifferentPaymentMethods() throws {
        let subscriptionBadge = getSubscriptionBadge()

        let paymentMethods: [DonationPaymentMethod] = [.applePay, .creditOrDebitCard, .paypal]
        let bodyTexts = paymentMethods
            .map { paymentMethod in
                State(
                    badge: subscriptionBadge,
                    mode: .subscriptionExpiredBecauseOfChargeFailure(
                        chargeFailure: .init(code: "test error"),
                        paymentMethod: paymentMethod
                    ),
                    canDonate: true
                )
            }
            .map { $0.body.text }

        let uniqueBodyTexts = Set(bodyTexts)

        XCTAssertEqual(bodyTexts.count, uniqueBodyTexts.count, "Expected different body texts")
    }

    func testActionButton() throws {
        let dismissButtonStates: [State] = [
            .init(
                badge: getSubscriptionBadge(),
                mode: .subscriptionExpiredBecauseOfChargeFailure(
                    chargeFailure: Subscription.ChargeFailure(code: "insufficient_funds"),
                    paymentMethod: nil
                ),
                canDonate: true
            ),
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
                badge: getSubscriptionBadge(),
                mode: .boostExpired(hasCurrentSubscription: true),
                canDonate: false
            ),
            .init(
                badge: getGiftBadge(),
                mode: .giftNotRedeemed(fullName: ""),
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
                mode: .subscriptionExpiredBecauseNotRenewed,
                canDonate: true
            ),
            .init(
                badge: getSubscriptionBadge(),
                mode: .boostExpired(hasCurrentSubscription: false),
                canDonate: true
            ),
            .init(
                badge: getSubscriptionBadge(),
                mode: .boostExpired(hasCurrentSubscription: true),
                canDonate: true
            ),
            .init(
                badge: getGiftBadge(),
                mode: .giftBadgeExpired(hasCurrentSubscription: false),
                canDonate: true
            )
        ]
        for state in donateButtonStates {
            XCTAssertEqual(state.actionButton.action, .openDonationView)
            XCTAssertTrue(state.actionButton.hasNotNow)
        }
    }
}
