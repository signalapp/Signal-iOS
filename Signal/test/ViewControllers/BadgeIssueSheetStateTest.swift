//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import Signal
@testable import SignalServiceKit

class BadgeIssueSheetStateTest: XCTestCase {
    typealias State = BadgeIssueSheetState

    private func getSubscriptionBadge() -> ProfileBadge {
        let result = try! ProfileBadge(jsonDictionary: [
            "id": "R_MED",
            "category": "donor",
            "name": "Subscriber X",
            "description": "A subscriber badge!",
            "sprites6": ["ldpi.png", "mdpi.png", "hdpi.png", "xhdpi.png", "xxhdpi.png", "xxxhdpi.png"],
        ])
        return result
    }

    private func getBoostBadge() -> ProfileBadge {
        let result = try! ProfileBadge(jsonDictionary: [
            "id": "BOOST",
            "category": "donor",
            "name": "A Boost",
            "description": "A boost badge!",
            "sprites6": ["ldpi.png", "mdpi.png", "hdpi.png", "xhdpi.png", "xxhdpi.png", "xxxhdpi.png"],
        ])
        return result
    }

    private func getGiftBadge() -> ProfileBadge {
        let result = try! ProfileBadge(jsonDictionary: [
            "id": "GIFT",
            "category": "donor",
            "name": "A Gift",
            "description": "A gift badge!",
            "sprites6": ["ldpi.png", "mdpi.png", "hdpi.png", "xhdpi.png", "xxhdpi.png", "xxxhdpi.png"],
        ])
        return result
    }

    private func donationAllowedToken() -> DonationAllowedToken {
        return DonationAllowedToken(
            registeredState: try! RegisteredState(registrationState: .registered(.forUnitTests)),
            remoteConfig: MockRemoteConfigProvider().currentConfig(),
        )!
    }

    func testBadge() throws {
        let badge = getSubscriptionBadge()
        let state = State(
            badge: badge,
            donationAllowedToken: donationAllowedToken(),
            mode: .subscriptionBankPaymentProcessing,
        )
        XCTAssertIdentical(state.badge, badge)
    }

    func testActionButton() throws {
        let dismissButtonStates: [State] = [
            .init(
                badge: getGiftBadge(),
                donationAllowedToken: donationAllowedToken(),
                mode: .giftBadgeExpired(hasCurrentSubscription: true),
            ),
            .init(
                badge: getGiftBadge(),
                donationAllowedToken: donationAllowedToken(),
                mode: .giftBadgeExpired(hasCurrentSubscription: true),
            ),
            .init(
                badge: getBoostBadge(),
                donationAllowedToken: nil,
                mode: .boostExpired(hasCurrentSubscription: true),
            ),
            .init(
                badge: getGiftBadge(),
                donationAllowedToken: donationAllowedToken(),
                mode: .giftNotRedeemed(fullName: ""),
            ),
            .init(
                badge: getBoostBadge(),
                donationAllowedToken: donationAllowedToken(),
                mode: .boostBankPaymentProcessing,
            ),
            .init(
                badge: getSubscriptionBadge(),
                donationAllowedToken: donationAllowedToken(),
                mode: .subscriptionBankPaymentProcessing,
            ),
        ]
        for state in dismissButtonStates {
            if case .dismiss = state.actionButton.action {
                // OK
            } else {
                XCTFail()
            }
            XCTAssertFalse(state.actionButton.hasNotNow)
        }

        let donateButtonStates: [State] = [
            .init(
                badge: getSubscriptionBadge(),
                donationAllowedToken: donationAllowedToken(),
                mode: .subscriptionExpiredBecauseOfChargeFailure(chargeFailureCode: nil, paymentMethod: nil),
            ),
            .init(
                badge: getBoostBadge(),
                donationAllowedToken: donationAllowedToken(),
                mode: .boostExpired(hasCurrentSubscription: false),
            ),
            .init(
                badge: getBoostBadge(),
                donationAllowedToken: donationAllowedToken(),
                mode: .boostExpired(hasCurrentSubscription: true),
            ),
            .init(
                badge: getGiftBadge(),
                donationAllowedToken: donationAllowedToken(),
                mode: .giftBadgeExpired(hasCurrentSubscription: false),
            ),
            .init(
                badge: getSubscriptionBadge(),
                donationAllowedToken: donationAllowedToken(),
                mode: .bankPaymentFailed(chargeFailureCode: nil),
            ),
        ]
        for state in donateButtonStates {
            if case .openDonationView = state.actionButton.action {
                // OK
            } else {
                XCTFail()
            }
            XCTAssertTrue(state.actionButton.hasNotNow)
        }
    }
}
