//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import Foundation
import Signal

class BadgeExpirationSheetStateTest: XCTestCase {
    typealias State = BadgeExpirationSheetState

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

    func testTitleText() throws {
        let testCases: [(State, String)] = [
            (
                State(
                    badge: getSubscriptionBadge(),
                    mode: .subscriptionExpiredBecauseOfChargeFailure(
                        chargeFailure: Subscription.ChargeFailure(code: "insufficient_funds"),
                        paymentMethod: nil
                    ),
                    canDonate: true
                ),
                NSLocalizedString(
                    "BADGE_EXPIRED_SUBSCRIPTION_TITLE",
                    comment: "Title for subscription on the badge expiration sheet."
                )
            ),
            (
                State(
                    badge: getSubscriptionBadge(),
                    mode: .subscriptionExpiredBecauseNotRenewed,
                    canDonate: true
                ),
                NSLocalizedString(
                    "BADGE_EXPIRED_SUBSCRIPTION_TITLE",
                    comment: "Title for subscription on the badge expiration sheet."
                )
            ),
            (
                State(
                    badge: getSubscriptionBadge(),
                    mode: .boostExpired(hasCurrentSubscription: true),
                    canDonate: true
                ),
                NSLocalizedString(
                    "BADGE_EXPIRED_BOOST_TITLE",
                    comment: "Title for boost on the badge expiration sheet."
                )
            ),
            (
                State(
                    badge: getGiftBadge(),
                    mode: .giftBadgeExpired(hasCurrentSubscription: true),
                    canDonate: true
                ),
                NSLocalizedString(
                    "DONATION_FROM_A_FRIEND_BADGE_EXPIRED_TITLE",
                    comment: "Someone donated on your behalf and you got a badge, which expired. A sheet appears to tell you about this. This is the title on that sheet."
                )
            ),
            (
                State(
                    badge: getGiftBadge(),
                    mode: .giftNotRedeemed(fullName: ""),
                    canDonate: true
                ),
                NSLocalizedString(
                    "DONATION_FROM_A_FRIEND_BADGE_NOT_REDEEMED_TITLE",
                    comment: "Someone donated on your behalf and you got a badge, which expired before you could redeem it. A sheet appears to tell you about this. This is the title on that sheet."
                )
            )
        ]

        for (state, expected) in testCases {
            XCTAssertEqual(state.titleText, expected)
        }
    }

    func testBodyForApplePay() throws {
        let subscriptionBadge = getSubscriptionBadge()

        let chargeFailureTestCases: [[String?]: String] = [
            ["authentication_required"]: NSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_AUTHENTICATION_REQUIRED",
                comment: "Apple Pay donation error for decline failures where authentication is required."
            ),
            ["approve_with_id"]: NSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_PAYMENT_CANNOT_BE_AUTHORIZED",
                comment: "Apple Pay donation error for decline failures where the payment cannot be authorized."
            ),
            ["call_issuer"]: NSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_CALL_ISSUER",
                comment: "Apple Pay donation error for decline failures where the user may need to contact their card or bank."
            ),
            ["card_not_supported"]: NSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_CARD_NOT_SUPPORTED",
                comment: "Apple Pay donation error for decline failures where the card is not supported."
            ),
            [
                "card_velocity_exceeded", "currency_not_supported", "do_not_honor",
                "do_not_try_again", "fraudulent", "generic_decline", "invalid_account",
                "invalid_amount", "lost_card", "merchant_blacklist",
                "new_account_information_available", "no_action_taken", "not_permitted",
                "restricted_card", "revocation_of_all_authorizations",
                "revocation_of_authorization", "security_violation", "service_not_allowed",
                "stolen_card", "stop_payment_order", "testmode_decline", "transaction_not_allowed",
                "try_again_later", "withdrawal_count_limit_exceeded",
                "GARBAGE", nil
            ]: NSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_OTHER",
                comment: "Apple Pay donation error for unspecified decline failures."
            ),
            ["expired_card"]: NSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_EXPIRED_CARD",
                comment: "Apple Pay donation error for decline failures where the card has expired."
            ),
            ["incorrect_number"]: NSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_INCORRECT_CARD_NUMBER",
                comment: "Apple Pay donation error for decline failures where the card number is incorrect."
            ),
            ["incorrect_cvc", "invalid_cvc"]: NSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_INCORRECT_CARD_VERIFICATION_CODE",
                comment: "Apple Pay donation error for decline failures where the card verification code (often called CVV or CVC) is incorrect."
            ),
            ["insufficient_funds"]: NSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_INSUFFICIENT_FUNDS",
                comment: "Apple Pay donation error for decline failures where the card has insufficient funds."
            ),
            ["invalid_expiry_month"]: NSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_INVALID_EXPIRY_MONTH",
                comment: "Apple Pay donation error for decline failures where the expiration month on the payment method is incorrect."
            ),
            ["invalid_expiry_year"]: NSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_INVALID_EXPIRY_YEAR",
                comment: "Apple Pay donation error for decline failures where the expiration year on the payment method is incorrect."
            ),
            ["invalid_number"]: NSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_INVALID_NUMBER",
                comment: "Apple Pay donation error for decline failures where the card number is incorrect."
            ),
            [
                "issuer_not_available", "processing_error", "reenter_transaction"
            ]: NSLocalizedString(
                "APPLE_PAY_DONATION_ERROR_ISSUER_NOT_AVAILABLE",
                comment: "Apple Pay donation error for \"issuer not available\" decline failures. The user should try again or contact their card/bank."
            )
        ]
        for (codes, expectedSubstring) in chargeFailureTestCases {
            for code in codes {
                let chargeFailure: Subscription.ChargeFailure
                if let code = code {
                    chargeFailure = Subscription.ChargeFailure(code: code)
                } else {
                    chargeFailure = Subscription.ChargeFailure()
                }
                let state = State(
                    badge: subscriptionBadge,
                    mode: .subscriptionExpiredBecauseOfChargeFailure(
                        chargeFailure: chargeFailure,
                        paymentMethod: .applePay
                    ),
                    canDonate: true
                )
                let body = state.body

                XCTAssert(body.text.contains(expectedSubstring))
                XCTAssertTrue(body.hasLearnMoreLink)
            }
        }

        let otherTestCases: [(State, String, Bool)] = [
            (
                State(
                    badge: getSubscriptionBadge(),
                    mode: .subscriptionExpiredBecauseNotRenewed,
                    canDonate: true
                ),
                NSLocalizedString("BADGE_SUBSCRIPTION_EXPIRED_BECAUSE_OF_INACTIVITY_BODY_FORMAT",
                                  comment: "Body of the sheet shown when your subscription is canceled due to inactivity"),
                true
            ),
            (
                State(
                    badge: getSubscriptionBadge(),
                    mode: .boostExpired(hasCurrentSubscription: false),
                    canDonate: true
                ),
                NSLocalizedString(
                    "BADGE_EXPIRED_BOOST_BODY",
                    comment: "String explaining to the user that their boost badge has expired on the badge expiry sheet."
                ),
                false
            ),
            (
                State(
                    badge: getSubscriptionBadge(),
                    mode: .boostExpired(hasCurrentSubscription: true),
                    canDonate: true
                ),
                NSLocalizedString("BADGE_EXPIRED_BOOST_CURRENT_SUSTAINER_BODY",
                                  comment: "String explaining to the user that their boost badge has expired while they are a current subscription sustainer on the badge expiry sheet."),
                false
            ),
            (
                State(
                    badge: getGiftBadge(),
                    mode: .giftBadgeExpired(hasCurrentSubscription: true),
                    canDonate: true
                ),
                NSLocalizedString(
                    "DONATION_FROM_A_FRIEND_BADGE_EXPIRED_BODY",
                    comment: "Someone donated on your behalf and you got a badge, which expired. A sheet appears to tell you about this. This is the text on that sheet."
                ),
                false
            ),
            (
                State(
                    badge: getGiftBadge(),
                    mode: .giftNotRedeemed(fullName: "John Doe"),
                    canDonate: true
                ),
                NSLocalizedString(
                    "DONATION_FROM_A_FRIEND_BADGE_NOT_REDEEMED_BODY_FORMAT",
                    comment: "Someone donated on your behalf and you got a badge, which expired before you could redeem it. A sheet appears to tell you about this. This is the text on that sheet. Embeds {{contact name}}."
                ).replacingOccurrences(of: "%@", with: "John Doe").replacingOccurrences(of: "%1$@", with: "John Doe"),
                false
            )
        ]
        for (state, expectedFormat, expectedHasLearnMore) in otherTestCases {
            let body = state.body
            XCTAssertEqual(body.text, String(format: expectedFormat, state.badge.localizedName))
            XCTAssertEqual(body.hasLearnMoreLink, expectedHasLearnMore)
        }
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
            XCTAssertEqual(state.actionButton.text, CommonStrings.okayButton)
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
        let expectedDonateButtonText = NSLocalizedString(
            "BADGE_EXPIRED_DONATE_BUTTON",
            comment: "Button text when a badge expires, asking users to donate"
        )
        for state in donateButtonStates {
            XCTAssertEqual(state.actionButton.action, .openDonationView)
            XCTAssertEqual(state.actionButton.text, expectedDonateButtonText)
            XCTAssertTrue(state.actionButton.hasNotNow)
        }
    }
}
