//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit
public import SignalServiceKit
import SignalUI

protocol BadgeIssueSheetDelegate: AnyObject {
    func badgeIssueSheetActionTapped(_ action: BadgeIssueSheetAction)
}

public enum BadgeIssueSheetAction {
    case dismiss
    case openDonationView
}

public class BadgeIssueSheetState {
    public enum Mode {
        case subscriptionExpiredBecauseOfChargeFailure(
            chargeFailureCode: String?,
            paymentMethod: DonationPaymentMethod?,
        )
        case boostExpired(hasCurrentSubscription: Bool)
        case giftBadgeExpired(hasCurrentSubscription: Bool)

        case giftNotRedeemed(fullName: String)

        case bankPaymentFailed(chargeFailureCode: String?)
        case boostBankPaymentProcessing
        case subscriptionBankPaymentProcessing
    }

    public struct Body {
        public let text: String
        public let learnMoreLink: URL?

        public init(_ text: String, learnMoreLink: URL? = nil) {
            self.text = text
            self.learnMoreLink = learnMoreLink
        }
    }

    public struct ActionButton {
        public let action: BadgeIssueSheetAction
        public let text: String
        public let hasNotNow: Bool

        public init(action: BadgeIssueSheetAction, text: String, hasNotNow: Bool) {
            self.action = action
            self.text = text
            self.hasNotNow = hasNotNow
        }
    }

    public let badge: ProfileBadge
    private let mode: Mode
    private let canDonate: Bool

    public init(badge: ProfileBadge, mode: Mode, canDonate: Bool) {
        self.badge = badge
        self.mode = mode
        self.canDonate = canDonate
    }

    public lazy var titleText: String = {
        switch mode {
        case .subscriptionExpiredBecauseOfChargeFailure:
            return OWSLocalizedString(
                "BADGE_EXPIRED_SUBSCRIPTION_TITLE",
                comment: "Title for subscription on the badge expiration sheet.",
            )
        case .boostExpired:
            return OWSLocalizedString(
                "BADGE_EXPIRED_BOOST_TITLE",
                comment: "Title for boost on the badge expiration sheet.",
            )
        case .giftBadgeExpired:
            return OWSLocalizedString(
                "DONATION_FROM_A_FRIEND_BADGE_EXPIRED_TITLE",
                comment: "Someone donated on your behalf and you got a badge, which expired. A sheet appears to tell you about this. This is the title on that sheet.",
            )
        case .giftNotRedeemed:
            return OWSLocalizedString(
                "DONATION_FROM_A_FRIEND_BADGE_NOT_REDEEMED_TITLE",
                comment: "Someone donated on your behalf and you got a badge, which expired before you could redeem it. A sheet appears to tell you about this. This is the title on that sheet.",
            )
        case .bankPaymentFailed:
            return OWSLocalizedString(
                "DONATION_BADGE_ISSUE_SHEET_BANK_PAYMENT_FAILED_TITLE",
                comment: "Title for a sheet explaining that a donation via bank payment has failed.",
            )
        case .boostBankPaymentProcessing, .subscriptionBankPaymentProcessing:
            return OWSLocalizedString(
                "DONATION_BADGE_ISSUE_SHEET_BANK_PAYMENT_PROCESSING_TITLE",
                comment: "Title for a sheet explaining that a donation via bank payment is pending.",
            )
        }
    }()

    public lazy var body: Body = {
        switch mode {
        case let .subscriptionExpiredBecauseOfChargeFailure(
            chargeFailureCode,
            paymentMethod,
        ):
            let formatText = OWSLocalizedString(
                "BADGE_SUBSCRIPTION_EXPIRED_BECAUSE_OF_CHARGE_FAILURE_BODY_FORMAT",
                comment: "String explaining to the user on a badge expiry sheet that their subscription badge has expired because the renewal payment failed. Embeds {{ a specific, already-localized string describing the payment failure }}. Will have a 'learn more' link appended, when it is rendered.",
            )

            let (chargeFailureString, _) = DonationViewsUtil.localizedDonationFailure(
                chargeErrorCode: chargeFailureCode,
                paymentMethod: paymentMethod,
            )

            return Body(
                String(format: formatText, chargeFailureString),
                learnMoreLink: URL.Support.Donations.badgeExpiration,
            )
        case let .boostExpired(hasCurrentSubscription):
            let bodyText: String
            if hasCurrentSubscription {
                bodyText = OWSLocalizedString(
                    "BADGE_EXPIRED_BOOST_CURRENT_SUSTAINER_BODY",
                    comment: "String explaining to the user that their boost badge has expired while they are a current subscription sustainer on the badge expiry sheet.",
                )
            } else {
                bodyText = OWSLocalizedString(
                    "BADGE_EXPIRED_BOOST_BODY",
                    comment: "String explaining to the user that their boost badge has expired on the badge expiry sheet.",
                )
            }
            return Body(bodyText)
        case .giftBadgeExpired:
            let bodyText = OWSLocalizedString(
                "DONATION_FROM_A_FRIEND_BADGE_EXPIRED_BODY",
                comment: "Someone donated on your behalf and you got a badge, which expired. A sheet appears to tell you about this. This is the text on that sheet.",
            )
            return Body(bodyText)
        case let .giftNotRedeemed(fullName):
            let formatText = OWSLocalizedString(
                "DONATION_FROM_A_FRIEND_BADGE_NOT_REDEEMED_BODY_FORMAT",
                comment: "Someone donated on your behalf and you got a badge, which expired before you could redeem it. A sheet appears to tell you about this. This is the text on that sheet. Embeds {{contact name}}.",
            )
            return Body(String(format: formatText, fullName))
        case let .bankPaymentFailed(chargeFailureCode):
            let formatText = OWSLocalizedString(
                "DONATION_BADGE_ISSUE_SHEET_BANK_PAYMENT_FAILED_MESSAGE",
                comment: "Message for a sheet explaining that a donation via bank payment has failed. Embeds {{ a specific, already-localized string describing the payment failure }}.",
            )

            let (chargeFailureString, _) = DonationViewsUtil.localizedDonationFailure(
                chargeErrorCode: chargeFailureCode,
                paymentMethod: .sepa,
            )

            return Body(String(format: formatText, chargeFailureString))
        case .boostBankPaymentProcessing:
            let bodyFormat = OWSLocalizedString(
                "DONATION_BADGE_ISSUE_SHEET_ONE_TIME_BANK_PAYMENT_PROCESSING_MESSAGE",
                comment: "Message for a sheet explaining that a one-time donation via bank payment is pending, and how that will affect the user's badge. Embeds {{ the name of the badge }}. Will have a 'learn more' link appended, when it is rendered.",
            )

            return Body(
                String(format: bodyFormat, badge.localizedName),
                learnMoreLink: URL.Support.Donations.donationPending,
            )
        case .subscriptionBankPaymentProcessing:
            let bodyFormat = OWSLocalizedString(
                "DONATION_BADGE_ISSUE_SHEET_RECURRING_BANK_PAYMENT_PROCESSING_MESSAGE",
                comment: "Message for a sheet explaining that a recurring donation via bank payment is pending, and how that will affect the user's badge. Embeds {{ the name of the badge }}. Will have a 'learn more' link appended, when it is rendered.",
            )

            return Body(
                String(format: bodyFormat, badge.localizedName),
                learnMoreLink: URL.Support.Donations.donationPending,
            )
        }
    }()

    public lazy var actionButton: ActionButton = {
        enum AskUserToDonateMode {
            case dontAsk
            case askToDonate
            case askToTryAgain
            case askToRenewSubscription
        }

        let askUserToDonateMode: AskUserToDonateMode = {
            guard canDonate else { return .dontAsk }

            switch mode {
            case
                .boostExpired,
                .giftBadgeExpired(hasCurrentSubscription: false):
                return .askToDonate
            case .bankPaymentFailed:
                return .askToTryAgain
            case .subscriptionExpiredBecauseOfChargeFailure:
                return .askToRenewSubscription
            case
                .giftBadgeExpired(hasCurrentSubscription: true),
                .giftNotRedeemed,
                .boostBankPaymentProcessing,
                .subscriptionBankPaymentProcessing:
                return .dontAsk
            }
        }()

        switch askUserToDonateMode {
        case .dontAsk:
            return ActionButton(
                action: .dismiss,
                text: CommonStrings.okayButton,
                hasNotNow: false,
            )
        case .askToDonate:
            return ActionButton(
                action: .openDonationView,
                text: OWSLocalizedString(
                    "BADGE_EXPIRED_DONATE_BUTTON",
                    comment: "Button text when a badge expires, asking users to donate",
                ),
                hasNotNow: true,
            )
        case .askToTryAgain:
            return ActionButton(
                action: .openDonationView,
                text: OWSLocalizedString(
                    "DONATION_BADGE_ISSUE_SHEET_TRY_AGAIN_BUTTON_TITLE",
                    comment: "Title for a button asking the user to try their donation again, because something went wrong.",
                ),
                hasNotNow: true,
            )
        case .askToRenewSubscription:
            return ActionButton(
                action: .openDonationView,
                text: OWSLocalizedString(
                    "DONATION_BADGE_ISSUE_SHEET_RENEW_SUBSCRIPTION_BUTTON_TITLE",
                    comment: "Title for a button asking the user to renew their subscription, because it has expired.",
                ),
                hasNotNow: true,
            )
        }
    }()

    var showIconAlert: Bool {
        switch mode {
        case
            .boostExpired,
            .giftBadgeExpired,
            .bankPaymentFailed,
            .subscriptionExpiredBecauseOfChargeFailure:
            return true
        case
            .giftNotRedeemed,
            .boostBankPaymentProcessing,
            .subscriptionBankPaymentProcessing:
            return false
        }
    }
}

class BadgeIssueSheet: OWSTableSheetViewController {
    private let state: BadgeIssueSheetState

    weak var delegate: BadgeIssueSheetDelegate?

    init(badge: ProfileBadge, mode: BadgeIssueSheetState.Mode) {
        self.state = BadgeIssueSheetState(
            badge: badge,
            mode: mode,
            canDonate: DonationUtilities.canDonateInAnyWay(
                tsAccountManager: DependenciesBridge.shared.tsAccountManager,
            ),
        )
        owsAssertDebug(state.badge.assets != nil)

        super.init()

        updateTableContents()
    }

    override func tableContents() -> OWSTableContents {
        let contents = OWSTableContents()

        let headerSection = OWSTableSection()
        headerSection.hasBackground = false
        headerSection.customHeaderHeight = 1
        contents.add(headerSection)

        headerSection.add(.init(customCellBlock: { [weak self] in
            let cell = OWSTableItem.newCell()
            guard let self else { return cell }
            cell.selectionStyle = .none

            let stackView = UIStackView()
            stackView.axis = .vertical
            stackView.alignment = .center
            stackView.layoutMargins = .init(top: 24, left: 24, bottom: 0, right: 24)
            stackView.isLayoutMarginsRelativeArrangement = true

            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewEdges()

            let containerView = UIView()
            stackView.addArrangedSubview(containerView)
            stackView.setCustomSpacing(24, after: containerView)

            let badgeImageView = UIImageView()
            badgeImageView.image = self.state.badge.assets?.universal160
            badgeImageView.autoSetDimensions(to: CGSize(square: 80))
            containerView.addSubview(badgeImageView)
            badgeImageView.autoPinEdgesToSuperviewEdges()

            if self.state.showIconAlert {
                let alertImageView = UIImageView()
                alertImageView.image = UIImage(named: "alert")
                alertImageView.autoSetDimensions(to: CGSize(square: 24))
                containerView.addSubview(alertImageView)
                alertImageView.autoPinEdge(.right, to: .right, of: badgeImageView)
                alertImageView.autoPinEdge(.top, to: .top, of: badgeImageView)
            }

            let titleLabel = UILabel.title2Label(text: self.state.titleText)
            stackView.addArrangedSubview(titleLabel)
            stackView.setCustomSpacing(12, after: titleLabel)

            let bodyLabel: UIView
            if let learnMoreLink = self.state.body.learnMoreLink {
                let learnMore = OWSLocalizedString(
                    "BADGE_EXPIRED_LEARN_MORE_LINK",
                    comment: "Text for the 'learn more' link in a sheet explaining there's been an issue with your badge.",
                ).styled(with: .link(learnMoreLink))
                let label = LinkingTextView()
                label.attributedText = .composed(of: [self.state.body.text, " ", learnMore])
                    .styled(with: .color(.Signal.secondaryLabel), .font(.dynamicTypeSubheadlineClamped))
                label.textAlignment = .center
                bodyLabel = label
            } else {
                let label = UILabel()
                label.font = .dynamicTypeSubheadlineClamped
                label.textColor = .Signal.secondaryLabel
                label.numberOfLines = 0
                label.text = self.state.body.text
                label.textAlignment = .center
                bodyLabel = label
            }
            stackView.addArrangedSubview(bodyLabel)
            stackView.setCustomSpacing(24, after: bodyLabel)

            return cell
        }, actionBlock: nil))

        let buttonSection = OWSTableSection()
        buttonSection.hasBackground = false
        contents.add(buttonSection)
        buttonSection.add(.init(customCellBlock: { [weak self] in
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            guard let self else { return cell }

            let actionButton = UIButton(
                configuration: .largePrimary(title: self.state.actionButton.text),
                primaryAction: UIAction { _ in
                    self.didTapAction()
                },
            )

            var buttons = [actionButton]

            if self.state.actionButton.hasNotNow {
                let notNowButton = UIButton(
                    configuration: .largeSecondary(title: CommonStrings.notNowButton),
                    primaryAction: UIAction { _ in
                        self.didDismiss()
                    },
                )
                buttons.append(notNowButton)
            }

            let stackView = UIStackView.verticalButtonStack(buttons: buttons, isFullWidthButtons: true)
            stackView.directionalLayoutMargins.bottom = 0
            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewEdges()

            return cell
        }, actionBlock: nil))

        return contents
    }

    override func willDismissInteractively() {
        didDismiss()
        super.willDismissInteractively()
    }

    @objc
    private func didTapAction() {
        didDismiss()
        delegate?.badgeIssueSheetActionTapped(state.actionButton.action)
    }

    @objc
    private func didDismiss() {
        dismiss(animated: true, completion: nil)
    }
}
