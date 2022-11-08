//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit
import SignalMessaging
import SignalUI

protocol BadgeExpirationSheetDelegate: AnyObject {
    func badgeExpirationSheetActionTapped(_ action: BadgeExpirationSheetAction)
}

public enum BadgeExpirationSheetAction {
    case dismiss
    case openOneTimeDonationView
    case openMonthlyDonationView
}

public class BadgeExpirationSheetState {
    public enum Mode {
        case subscriptionExpiredBecauseOfChargeFailure(chargeFailure: Subscription.ChargeFailure)
        case subscriptionExpiredBecauseNotRenewed
        case boostExpired(hasCurrentSubscription: Bool)
        case giftBadgeExpired(hasCurrentSubscription: Bool)
        case giftNotRedeemed(fullName: String)
    }

    public struct Body {
        public let text: String
        public let hasLearnMoreLink: Bool

        public init(_ text: String, hasLearnMoreLink: Bool = false) {
            self.text = text
            self.hasLearnMoreLink = hasLearnMoreLink
        }
    }

    public struct ActionButton {
        public let action: BadgeExpirationSheetAction
        public let text: String
        public let hasNotNow: Bool

        public init(action: BadgeExpirationSheetAction, text: String, hasNotNow: Bool = false) {
            self.action = action
            self.text = text
            self.hasNotNow = hasNotNow
        }
    }

    public let badge: ProfileBadge
    private let mode: Mode

    public init(badge: ProfileBadge, mode: Mode) {
        self.badge = badge
        self.mode = mode
    }

    public lazy var titleText: String = {
        switch mode {
        case .subscriptionExpiredBecauseOfChargeFailure, .subscriptionExpiredBecauseNotRenewed:
            return NSLocalizedString("BADGE_EXPIRED_SUBSCRIPTION_TITLE",
                                     comment: "Title for subscription on the badge expiration sheet.")
        case .boostExpired:
            return NSLocalizedString("BADGE_EXPIRED_BOOST_TITLE",
                                     comment: "Title for boost on the badge expiration sheet.")
        case .giftBadgeExpired:
            return NSLocalizedString("BADGE_EXPIRED_GIFT_TITLE",
                                     value: "Your Gift Badge Has Expired",
                                     comment: "Title for gift on the badge expiration sheet.")
        case .giftNotRedeemed:
            return NSLocalizedString("GIFT_NOT_REDEEMED_TITLE",
                                     value: "Your Gift Has Expired",
                                     comment: "Title when trying to redeem a gift that's already expired.")
        }
    }()

    private var monthlyDonationCallToAction: String {
        NSLocalizedString(
            "BADGE_EXPIRED_MONTHLY_CALL_TO_ACTION",
            comment: "Shown when a non-monthly badge expires to suggest starting a recurring donation."
        )
    }

    public lazy var body: Body = {
        switch mode {
        case let .subscriptionExpiredBecauseOfChargeFailure(chargeFailure):
            let failureSpecificText = Self.getChargeFailureSpecificText(chargeFailure: chargeFailure)
            let formatText = NSLocalizedString("BADGE_SUBSCRIPTION_EXPIRED_BECAUSE_OF_CHARGE_FAILURE_BODY_FORMAT",
                                               comment: "String explaining to the user that their subscription badge has expired on the badge expiry sheet. Embeds {failure-specific sentence(s)} and {badge name}.")
            return Body(String(format: formatText, failureSpecificText, badge.localizedName), hasLearnMoreLink: true)
        case .subscriptionExpiredBecauseNotRenewed:
            let formatText = NSLocalizedString("BADGE_SUBSCRIPTION_EXPIRED_BECAUSE_OF_INACTIVITY_BODY_FORMAT",
                                               comment: "Body of the sheet shown when your subscription is canceled due to inactivity")
            return Body(String(format: formatText, badge.localizedName), hasLearnMoreLink: true)
        case let .boostExpired(hasCurrentSubscription):
            var bodyText = [String]()
            if hasCurrentSubscription {
                bodyText.append(NSLocalizedString(
                    "BADGE_EXPIRED_BOOST_CURRENT_SUSTAINER_BODY",
                    comment: "String explaining to the user that their boost badge has expired while they are a current subscription sustainer on the badge expiry sheet."
                ))
            } else {
                bodyText.append(NSLocalizedString(
                    "BADGE_EXPIRED_BOOST_BODY",
                    comment: "String explaining to the user that their boost badge has expired on the badge expiry sheet."
                ))
                bodyText.append(self.monthlyDonationCallToAction)
            }
            return Body(bodyText.joined(separator: "\n\n"))
        case let .giftBadgeExpired(hasCurrentSubscription):
            var bodyText = [String]()
            bodyText.append(NSLocalizedString(
                "BADGE_EXPIRED_GIFT_BODY",
                value: "Your gift badge has expired and is no longer available to be displayed on your profile.",
                comment: "String explaining to the user that their gift badge has expired. Shown on the badge expiration sheet."
            ))
            if !hasCurrentSubscription {
                bodyText.append(self.monthlyDonationCallToAction)
            }
            return Body(bodyText.joined(separator: "\n\n"))
        case let .giftNotRedeemed(fullName):
            let formatText = NSLocalizedString(
                "GIFT_NOT_REDEEMED_BODY_FORMAT",
                value: "Your gift from %@ has expired and can no longer be redeemed.",
                comment: "Shown when trying to redeem a gift that's already expired. Embeds {{contact name}}."
            )
            return Body(String(format: formatText, fullName))
        }
    }()

    private static func getChargeFailureSpecificText(chargeFailure: Subscription.ChargeFailure) -> String {
        switch chargeFailure.code {
        case "authentication_required":
            return NSLocalizedString("DONATION_PAYMENT_ERROR_AUTHENTICATION_REQUIRED",
                                     comment: "Donation payment error for decline failures where authentication is required.")
        case "approve_with_id":
            return NSLocalizedString("DONATION_PAYMENT_ERROR_PAYMENT_CANNOT_BE_AUTHORIZED",
                                     comment: "Donation payment error for decline failures where the payment cannot be authorized.")
        case "call_issuer":
            return NSLocalizedString("DONATION_PAYMENT_ERROR_CALL_ISSUER",
                                     comment: "Donation payment error for decline failures where the user may need to contact their card or bank.")
        case "card_not_supported":
            return NSLocalizedString("DONATION_PAYMENT_ERROR_CARD_NOT_SUPPORTED",
                                     comment: "Donation payment error for decline failures where the card is not supported.")
        case "expired_card":
            return NSLocalizedString("DONATION_PAYMENT_ERROR_EXPIRED_CARD",
                                     comment: "Donation payment error for decline failures where the card has expired.")
        case "incorrect_number":
            return NSLocalizedString("DONATION_PAYMENT_ERROR_INCORRECT_CARD_NUMBER",
                                     comment: "Donation payment error for decline failures where the card number is incorrect.")
        case "incorrect_cvc", "invalid_cvc":
            return NSLocalizedString("DONATION_PAYMENT_ERROR_INCORRECT_CARD_VERIFICATION_CODE",
                                     comment: "Donation payment error for decline failures where the card verification code (often called CVV or CVC) is incorrect.")
        case "insufficient_funds":
            return NSLocalizedString("DONATION_PAYMENT_ERROR_INSUFFICIENT_FUNDS",
                                     comment: "Donation payment error for decline failures where the card has insufficient funds.")
        case "invalid_expiry_month":
            return NSLocalizedString("DONATION_PAYMENT_ERROR_INVALID_EXPIRY_MONTH",
                                     comment: "Donation payment error for decline failures where the expiration month on the payment method is incorrect.")
        case "invalid_expiry_year":
            return NSLocalizedString("DONATION_PAYMENT_ERROR_INVALID_EXPIRY_YEAR",
                                     comment: "Donation payment error for decline failures where the expiration year on the payment method is incorrect.")
        case "invalid_number":
            return NSLocalizedString("DONATION_PAYMENT_ERROR_INVALID_NUMBER",
                                     comment: "Donation payment error for decline failures where the card number is incorrect.")
        case "issuer_not_available", "processing_error", "reenter_transaction":
            return NSLocalizedString("DONATION_PAYMENT_ERROR_ISSUER_NOT_AVAILABLE",
                                     comment: "Donation payment error for \"issuer not available\" decline failures. The user should try again or contact their card/bank.")
        default:
            return NSLocalizedString("DONATION_PAYMENT_ERROR_OTHER",
                                     comment: "Donation payment error for unspecified decline failures.")
        }
    }

    public lazy var actionButton: ActionButton = {
        switch mode {
        case .subscriptionExpiredBecauseOfChargeFailure:
            let text = CommonStrings.okayButton
            return ActionButton(action: .dismiss, text: text)
        case .subscriptionExpiredBecauseNotRenewed:
            let text = NSLocalizedString("BADGE_EXPIRED_SUBSCRIPTION_RENEWAL_BUTTON",
                                         comment: "Button text when a badge expires, asking you to renew your subscription")
            return ActionButton(action: .openMonthlyDonationView, text: text, hasNotNow: true)
        case let .boostExpired(hasCurrentSubscription):
            let text: String
            if hasCurrentSubscription {
                text = NSLocalizedString("BADGE_EXPIRED_BOOST_RENEWAL_BUTTON_SUSTAINER",
                                         comment: "Button title for boost on the badge expiration sheet, used if the user is already a sustainer.")
            } else {
                text = NSLocalizedString("BADGE_EXPIRED_BOOST_RENEWAL_BUTTON",
                                         comment: "Button title for boost on the badge expiration sheet, used if the user is not already a sustainer.")
            }
            return ActionButton(action: .openOneTimeDonationView, text: text, hasNotNow: true)
        case let .giftBadgeExpired(hasCurrentSubscription):
            if hasCurrentSubscription {
                return ActionButton(action: .dismiss, text: CommonStrings.okButton)
            } else {
                let text = NSLocalizedString(
                    "BADGE_EXPIRED_RENEWAL_MONTHLY",
                    value: "Make a Monthly Donation",
                    comment: "Button title to donate monthly on the badge expiration sheet."
                )
                return ActionButton(action: .openMonthlyDonationView, text: text, hasNotNow: true)
            }
        case .giftNotRedeemed:
            return ActionButton(action: .dismiss, text: CommonStrings.okButton)
        }
    }()
}

class BadgeExpirationSheet: OWSTableSheetViewController {
    private let state: BadgeExpirationSheetState

    public weak var delegate: BadgeExpirationSheetDelegate?

    public init(badge: ProfileBadge, mode: BadgeExpirationSheetState.Mode) {
        self.state = BadgeExpirationSheetState(badge: badge, mode: mode)
        owsAssertDebug(state.badge.assets != nil)

        super.init()

        updateTableContents()
    }

    public required init() {
        fatalError("init() has not been implemented")
    }

    public override func updateTableContents(shouldReload: Bool = true) {
        let contents = OWSTableContents()
        defer { tableViewController.setContents(contents, shouldReload: shouldReload) }

        let headerSection = OWSTableSection()
        headerSection.hasBackground = false
        headerSection.customHeaderHeight = 1
        contents.addSection(headerSection)

        headerSection.add(.init(customCellBlock: { [weak self] in
            let cell = OWSTableItem.newCell()
            guard let self = self else { return cell }
            cell.selectionStyle = .none

            let stackView = UIStackView()
            stackView.axis = .vertical
            stackView.alignment = .center
            stackView.layoutMargins = UIEdgeInsets(hMargin: 24, vMargin: 0)
            stackView.isLayoutMarginsRelativeArrangement = true

            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewEdges()

            let badgeImageView = UIImageView()
            badgeImageView.image = self.state.badge.assets?.universal112
            badgeImageView.autoSetDimensions(to: CGSize(square: 112))
            stackView.addArrangedSubview(badgeImageView)
            stackView.setCustomSpacing(16, after: badgeImageView)

            let titleLabel = UILabel()
            titleLabel.font = .ows_dynamicTypeTitle2.ows_semibold
            titleLabel.textColor = Theme.primaryTextColor
            titleLabel.textAlignment = .center
            titleLabel.numberOfLines = 0
            titleLabel.text = self.state.titleText
            stackView.addArrangedSubview(titleLabel)
            stackView.setCustomSpacing(12, after: titleLabel)

            let bodyLabel: UIView
            if self.state.body.hasLearnMoreLink {
                let learnMore = NSLocalizedString(
                    "BADGE_EXPIRED_LEARN_MORE_LINK",
                    comment: "Text for the 'learn more' link in the badge expiration sheet, shown when a badge expires due to a charge failure"
                ).styled(with: .link(SupportConstants.badgeExpirationLearnMoreURL))
                let label = LinkingTextView()
                label.attributedText = .composed(of: [self.state.body.text, " ", learnMore]).styled(with: .color(Theme.primaryTextColor), .font(.ows_dynamicTypeBody))
                label.textAlignment = .center
                label.linkTextAttributes = [
                    .foregroundColor: Theme.accentBlueColor,
                    .underlineColor: UIColor.clear,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
                bodyLabel = label
            } else {
                let label = UILabel()
                label.font = .ows_dynamicTypeBody
                label.textColor = Theme.primaryTextColor
                label.numberOfLines = 0
                label.text = self.state.body.text
                label.textAlignment = .center
                bodyLabel = label
            }
            stackView.addArrangedSubview(bodyLabel)
            stackView.setCustomSpacing(30, after: bodyLabel)

            return cell
        }, actionBlock: nil))

        let buttonSection = OWSTableSection()
        buttonSection.hasBackground = false
        contents.addSection(buttonSection)
        buttonSection.add(.init(customCellBlock: { [weak self] in
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            guard let self = self else { return cell }

            let stackView = UIStackView()
            stackView.axis = .vertical
            stackView.alignment = .center
            stackView.layoutMargins = UIEdgeInsets(top: 30, left: 24, bottom: 30, right: 24)
            stackView.spacing = 16
            stackView.isLayoutMarginsRelativeArrangement = true
            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewEdges()

            let actionButton = OWSFlatButton.button(title: self.state.actionButton.text,
                                                    font: UIFont.ows_dynamicTypeBody.ows_semibold,
                                                    titleColor: .white,
                                                    backgroundColor: .ows_accentBlue,
                                                    target: self,
                                                    selector: #selector(self.didTapAction))
            actionButton.autoSetHeightUsingFont()
            actionButton.cornerRadius = 8
            stackView.addArrangedSubview(actionButton)
            actionButton.autoPinWidthToSuperviewMargins()

            if self.state.actionButton.hasNotNow {
                let notNowButton = OWSButton(title: CommonStrings.notNowButton) { [weak self] in
                    guard let self = self else { return }
                    self.didDismiss()
                }
                notNowButton.setTitleColor(Theme.accentBlueColor, for: .normal)
                notNowButton.dimsWhenHighlighted = true
                stackView.addArrangedSubview(notNowButton)
            }

            return cell
        }, actionBlock: nil))
    }

    public override func willDismissInteractively() {
        didDismiss()
        super.willDismissInteractively()
    }

    @objc
    func didTapAction() {
        didDismiss()
        delegate?.badgeExpirationSheetActionTapped(state.actionButton.action)
    }

    @objc
    func didDismiss() {
        dismiss(animated: true, completion: nil)
    }
}
