//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import XCTest
import Foundation
import Signal

class BadgeExpirationSheetStateTest: XCTestCase {
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

    func testBadge() throws {
        let badge = getSubscriptionBadge()
        let state = BadgeExpirationSheetState(badge: badge, mode: .subscriptionExpiredBecauseNotRenewed)
        XCTAssertIdentical(state.badge, badge)
    }

    func testTitleText() throws {
        let testCases: [(BadgeExpirationSheetState, String)] = [
            (
                BadgeExpirationSheetState(badge: getSubscriptionBadge(),
                                          mode: .subscriptionExpiredBecauseOfChargeFailure),
                NSLocalizedString("BADGE_EXPIRED_SUBSCRIPTION_TITLE",
                                  comment: "Title for subscription on the badge expiration sheet.")
            ),
            (
                BadgeExpirationSheetState(badge: getSubscriptionBadge(),
                                          mode: .subscriptionExpiredBecauseNotRenewed),
                NSLocalizedString("BADGE_EXPIRED_SUBSCRIPTION_TITLE",
                                  comment: "Title for subscription on the badge expiration sheet.")
            ),
            (
                BadgeExpirationSheetState(badge: getSubscriptionBadge(),
                                          mode: .boostExpired(hasCurrentSubscription: true)),
                NSLocalizedString("BADGE_EXPIRED_BOOST_TITLE",
                                  comment: "Title for boost on the badge expiration sheet.")
            )
        ]

        for (state, expected) in testCases {
            XCTAssertEqual(state.titleText, expected)
        }
    }

    func testBody() throws {
        let testCases: [(BadgeExpirationSheetState, String, Bool)] = [
            (
                BadgeExpirationSheetState(badge: getSubscriptionBadge(),
                                          mode: .subscriptionExpiredBecauseOfChargeFailure),
                NSLocalizedString("BADGE_SUBSCRIPTION_EXPIRED_BECAUSE_OF_CHARGE_FAILURE_BODY_FORMAT",
                                  comment: "String explaining to the user that their subscription badge has expired on the badge expiry sheet. Embed {badge name}."),
                true
            ),
            (
                BadgeExpirationSheetState(badge: getSubscriptionBadge(),
                                          mode: .subscriptionExpiredBecauseNotRenewed),
                NSLocalizedString("BADGE_SUBSCRIPTION_EXPIRED_BECAUSE_OF_INACTIVITY_BODY_FORMAT",
                                  comment: "Body of the sheet shown when your subscription is canceled due to inactivity"),
                true
            ),
            (
                BadgeExpirationSheetState(badge: getSubscriptionBadge(),
                                          mode: .boostExpired(hasCurrentSubscription: false)),
                NSLocalizedString("BADGE_EXIPRED_BOOST_BODY_FORMAT",
                                  comment: "String explaining to the user that their boost badge has expired on the badge expiry sheet."),
                false
            ),
            (
                BadgeExpirationSheetState(badge: getSubscriptionBadge(),
                                          mode: .boostExpired(hasCurrentSubscription: true)),
                NSLocalizedString("BADGE_EXIPRED_BOOST_CURRENT_SUSTAINER_BODY_FORMAT",
                                  comment: "String explaining to the user that their boost badge has expired while they are a current subscription sustainer on the badge expiry sheet."),
                false
            )
        ]

        for (state, expectedFormat, expectedHasLearnMore) in testCases {
            let body = state.body
            XCTAssertEqual(body.text, String(format: expectedFormat, state.badge.localizedName))
            XCTAssertEqual(body.hasLearnMoreLink, expectedHasLearnMore)
        }
    }

    func testActionButton() throws {
        let testCases: [(BadgeExpirationSheetState, BadgeExpirationSheetState.ActionButton)] = [
            (
                BadgeExpirationSheetState(badge: getSubscriptionBadge(),
                                          mode: .subscriptionExpiredBecauseOfChargeFailure),
                BadgeExpirationSheetState.ActionButton(action: .dismiss, text: CommonStrings.okayButton, hasNotNow: false)
            ),
            (
                BadgeExpirationSheetState(badge: getSubscriptionBadge(),
                                          mode: .subscriptionExpiredBecauseNotRenewed),
                BadgeExpirationSheetState.ActionButton(action: .openSubscriptionsView,
                                                    text: NSLocalizedString("BADGE_EXPIRED_SUBSCRIPTION_RENEWAL_BUTTON",
                                                                            comment: "Button text when a badge expires, asking you to renew your subscription"),
                                                    hasNotNow: true)
            ),
            (
                BadgeExpirationSheetState(badge: getSubscriptionBadge(),
                                          mode: .boostExpired(hasCurrentSubscription: false)),
                BadgeExpirationSheetState.ActionButton(action: .openSubscriptionsView,
                                                    text: NSLocalizedString("BADGE_EXPIRED_BOOST_RENEWAL_BUTTON",
                                                                            comment: "Button title for boost on the badge expiration sheet, used if the user is not already a sustainer."),
                                                    hasNotNow: true)
            ),
            (
                BadgeExpirationSheetState(badge: getSubscriptionBadge(),
                                          mode: .boostExpired(hasCurrentSubscription: true)),
                BadgeExpirationSheetState.ActionButton(action: .openBoostView,
                                                    text: NSLocalizedString("BADGE_EXPIRED_BOOST_RENEWAL_BUTTON_SUSTAINER",
                                                                            comment: "Button title for boost on the badge expiration sheet, used if the user is already a sustainer."),
                                                    hasNotNow: true)
            )
        ]

        for (state, expectedActionButton) in testCases {
            XCTAssertEqual(state.actionButton.action, expectedActionButton.action)
            XCTAssertEqual(state.actionButton.text, expectedActionButton.text)
            XCTAssertEqual(state.actionButton.hasNotNow, expectedActionButton.hasNotNow)
        }
    }
}
