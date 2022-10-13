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
        let state = State(badge: badge, mode: .subscriptionExpiredBecauseNotRenewed)
        XCTAssertIdentical(state.badge, badge)
    }

    func testTitleText() throws {
        let testCases: [(State, String)] = [
            (
                State(badge: getSubscriptionBadge(),
                      mode: .subscriptionExpiredBecauseOfChargeFailure(chargeFailure: Subscription.ChargeFailure(code: "insufficient_funds"))),
                NSLocalizedString("BADGE_EXPIRED_SUBSCRIPTION_TITLE",
                                  comment: "Title for subscription on the badge expiration sheet.")
            ),
            (
                State(badge: getSubscriptionBadge(), mode: .subscriptionExpiredBecauseNotRenewed),
                NSLocalizedString("BADGE_EXPIRED_SUBSCRIPTION_TITLE",
                                  comment: "Title for subscription on the badge expiration sheet.")
            ),
            (
                State(badge: getSubscriptionBadge(), mode: .boostExpired(hasCurrentSubscription: true)),
                NSLocalizedString("BADGE_EXPIRED_BOOST_TITLE",
                                  comment: "Title for boost on the badge expiration sheet.")
            ),
            (
                State(badge: getGiftBadge(), mode: .giftBadgeExpired(hasCurrentSubscription: true)),
                NSLocalizedString("BADGE_EXPIRED_GIFT_TITLE",
                                  value: "Your Gift Badge Has Expired",
                                  comment: "Title for gift on the badge expiration sheet.")
            ),
            (
                State(badge: getGiftBadge(), mode: .giftNotRedeemed(fullName: "")),
                NSLocalizedString("GIFT_NOT_REDEEMED_TITLE",
                                  value: "Your Gift Has Expired",
                                  comment: "Title when trying to redeem a gift that's already expired.")
            )
        ]

        for (state, expected) in testCases {
            XCTAssertEqual(state.titleText, expected)
        }
    }

    func testBody() throws {
        let subscriptionBadge = getSubscriptionBadge()

        let chargeFailureTestCases: [[String?]: String] = [
            ["authentication_required"]: NSLocalizedString("DONATION_PAYMENT_ERROR_AUTHENTICATION_REQUIRED",
                                                           comment: "Donation payment error for decline failures where authentication is required."),
            ["approve_with_id"]: NSLocalizedString("DONATION_PAYMENT_ERROR_PAYMENT_CANNOT_BE_AUTHORIZED",
                                                   comment: "Donation payment error for decline failures where the payment cannot be authorized."),
            ["call_issuer"]: NSLocalizedString("DONATION_PAYMENT_ERROR_CALL_ISSUER",
                                               comment: "Donation payment error for decline failures where the user may need to contact their card or bank."),
            ["card_not_supported"]: NSLocalizedString("DONATION_PAYMENT_ERROR_CARD_NOT_SUPPORTED",
                                                      comment: "Donation payment error for decline failures where the card is not supported."),
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
            ]: NSLocalizedString("DONATION_PAYMENT_ERROR_OTHER",
                                 comment: "Donation payment error for unspecified decline failures."),
            ["expired_card"]: NSLocalizedString("DONATION_PAYMENT_ERROR_EXPIRED_CARD",
                                                comment: "Donation payment error for decline failures where the card has expired."),
            ["incorrect_number"]: NSLocalizedString("DONATION_PAYMENT_ERROR_INCORRECT_CARD_NUMBER",
                                                    comment: "Donation payment error for decline failures where the card number is incorrect."),
            ["incorrect_cvc", "invalid_cvc"]: NSLocalizedString("DONATION_PAYMENT_ERROR_INCORRECT_CARD_VERIFICATION_CODE",
                                                                comment: "Donation payment error for decline failures where the card verification code (often called CVV or CVC) is incorrect."),
            ["insufficient_funds"]: NSLocalizedString("DONATION_PAYMENT_ERROR_INSUFFICIENT_FUNDS",
                                                      comment: "Donation payment error for decline failures where the card has insufficient funds."),
            ["invalid_expiry_month"]: NSLocalizedString("DONATION_PAYMENT_ERROR_INVALID_EXPIRY_MONTH",
                                                        comment: "Donation payment error for decline failures where the expiration month on the payment method is incorrect."),
            ["invalid_expiry_year"]: NSLocalizedString("DONATION_PAYMENT_ERROR_INVALID_EXPIRY_YEAR",
                                                       comment: "Donation payment error for decline failures where the expiration year on the payment method is incorrect."),
            ["invalid_number"]: NSLocalizedString("DONATION_PAYMENT_ERROR_INVALID_NUMBER",
                                                  comment: "Donation payment error for decline failures where the card number is incorrect."),
            [
                "issuer_not_available", "processing_error", "reenter_transaction"
            ]: NSLocalizedString("DONATION_PAYMENT_ERROR_ISSUER_NOT_AVAILABLE",
                                 comment: "Donation payment error for \"issuer not available\" decline failures. The user should try again or contact their card/bank.")
        ]
        for (codes, expectedSubstring) in chargeFailureTestCases {
            for code in codes {
                let chargeFailure: Subscription.ChargeFailure
                if let code = code {
                    chargeFailure = Subscription.ChargeFailure(code: code)
                } else {
                    chargeFailure = Subscription.ChargeFailure()
                }
                let state = State(badge: subscriptionBadge,
                                  mode: .subscriptionExpiredBecauseOfChargeFailure(chargeFailure: chargeFailure))
                let body = state.body

                XCTAssert(body.text.contains(expectedSubstring))
                XCTAssert(body.text.contains(subscriptionBadge.localizedName))
                XCTAssertTrue(body.hasLearnMoreLink)
            }
        }

        let otherTestCases: [(State, String, Bool)] = [
            (
                State(badge: getSubscriptionBadge(), mode: .subscriptionExpiredBecauseNotRenewed),
                NSLocalizedString("BADGE_SUBSCRIPTION_EXPIRED_BECAUSE_OF_INACTIVITY_BODY_FORMAT",
                                  comment: "Body of the sheet shown when your subscription is canceled due to inactivity"),
                true
            ),
            (
                State(badge: getSubscriptionBadge(), mode: .boostExpired(hasCurrentSubscription: false)),
                NSLocalizedString("BADGE_EXPIRED_BOOST_BODY",
                                  comment: "String explaining to the user that their boost badge has expired on the badge expiry sheet.")
                + "\n\n"
                + NSLocalizedString("BADGE_EXPIRED_MONTHLY_CALL_TO_ACTION",
                                    comment: "Shown when a non-monthly badge expires to suggest starting a recurring donation."),
                false
            ),
            (
                State(badge: getSubscriptionBadge(), mode: .boostExpired(hasCurrentSubscription: true)),
                NSLocalizedString("BADGE_EXPIRED_BOOST_CURRENT_SUSTAINER_BODY",
                                  comment: "String explaining to the user that their boost badge has expired while they are a current subscription sustainer on the badge expiry sheet."),
                false
            ),
            (
                State(badge: getGiftBadge(), mode: .giftBadgeExpired(hasCurrentSubscription: false)),
                NSLocalizedString(
                    "BADGE_EXPIRED_GIFT_BODY",
                    value: "Your gift badge has expired and is no longer available to be displayed on your profile.",
                    comment: "String explaining to the user that their gift badge has expired. Shown on the badge expiration sheet."
                )
                + "\n\n"
                + NSLocalizedString(
                    "BADGE_EXPIRED_MONTHLY_CALL_TO_ACTION",
                    comment: "Shown when a non-monthly badge expires to suggest starting a recurring donation."
                ),
                false
            ),
            (
                State(badge: getGiftBadge(), mode: .giftBadgeExpired(hasCurrentSubscription: true)),
                NSLocalizedString(
                    "BADGE_EXPIRED_GIFT_BODY",
                    value: "Your gift badge has expired and is no longer available to be displayed on your profile.",
                    comment: "String explaining to the user that their gift badge has expired. Shown on the badge expiration sheet."
                ),
                false
            ),
            (
                State(badge: getGiftBadge(), mode: .giftNotRedeemed(fullName: "John Doe")),
                NSLocalizedString(
                    "GIFT_NOT_REDEEMED_BODY_FORMAT",
                    value: "Your gift from %@ has expired and can no longer be redeemed.",
                    comment: "Shown when trying to redeem a gift that's already expired. Embeds {{contact name}}."
                ).replacingOccurrences(of: "%@", with: "John Doe"),
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
        let testCases: [(State, State.ActionButton)] = [
            (
                State(badge: getSubscriptionBadge(),
                      mode: .subscriptionExpiredBecauseOfChargeFailure(chargeFailure: Subscription.ChargeFailure(code: "insufficient_funds"))),
                State.ActionButton(action: .dismiss, text: CommonStrings.okayButton, hasNotNow: false)
            ),
            (
                State(badge: getSubscriptionBadge(), mode: .subscriptionExpiredBecauseNotRenewed),
                State.ActionButton(action: .openSubscriptionsView,
                                   text: NSLocalizedString("BADGE_EXPIRED_SUBSCRIPTION_RENEWAL_BUTTON",
                                                           comment: "Button text when a badge expires, asking you to renew your subscription"),
                                   hasNotNow: true)
            ),
            (
                State(badge: getSubscriptionBadge(), mode: .boostExpired(hasCurrentSubscription: false)),
                State.ActionButton(action: .openSubscriptionsView,
                                   text: NSLocalizedString("BADGE_EXPIRED_BOOST_RENEWAL_BUTTON",
                                                           comment: "Button title for boost on the badge expiration sheet, used if the user is not already a sustainer."),
                                   hasNotNow: true)
            ),
            (
                State(badge: getSubscriptionBadge(), mode: .boostExpired(hasCurrentSubscription: true)),
                State.ActionButton(action: .openBoostView,
                                   text: NSLocalizedString("BADGE_EXPIRED_BOOST_RENEWAL_BUTTON_SUSTAINER",
                                                           comment: "Button title for boost on the badge expiration sheet, used if the user is already a sustainer."),
                                   hasNotNow: true)
            ),
            (
                State(badge: getGiftBadge(), mode: .giftBadgeExpired(hasCurrentSubscription: false)),
                State.ActionButton(action: .openSubscriptionsView,
                                   text: NSLocalizedString("BADGE_EXPIRED_RENEWAL_MONTHLY",
                                                           value: "Make a Monthly Donation",
                                                           comment: "Button title to donate monthly on the badge expiration sheet."),
                                   hasNotNow: true)
            ),
            (
                State(badge: getGiftBadge(), mode: .giftBadgeExpired(hasCurrentSubscription: true)),
                State.ActionButton(action: .dismiss, text: CommonStrings.okButton, hasNotNow: false)
            ),
            (
                State(badge: getGiftBadge(), mode: .giftNotRedeemed(fullName: "")),
                State.ActionButton(action: .dismiss, text: CommonStrings.okButton, hasNotNow: false)
            )
        ]

        for (state, expectedActionButton) in testCases {
            XCTAssertEqual(state.actionButton.action, expectedActionButton.action)
            XCTAssertEqual(state.actionButton.text, expectedActionButton.text)
            XCTAssertEqual(state.actionButton.hasNotNow, expectedActionButton.hasNotNow)
        }
    }
}
