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
    case openDonationView
}

public class BadgeExpirationSheetState {
    public enum Mode {
        case subscriptionExpiredBecauseOfChargeFailure(
            chargeFailure: Subscription.ChargeFailure,
            paymentMethod: DonationPaymentMethod?
        )
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
    private let canDonate: Bool

    public init(badge: ProfileBadge, mode: Mode, canDonate: Bool) {
        self.badge = badge
        self.mode = mode
        self.canDonate = canDonate
    }

    public lazy var titleText: String = {
        switch mode {
        case .subscriptionExpiredBecauseOfChargeFailure, .subscriptionExpiredBecauseNotRenewed:
            return OWSLocalizedString(
                "BADGE_EXPIRED_SUBSCRIPTION_TITLE",
                comment: "Title for subscription on the badge expiration sheet."
            )
        case .boostExpired:
            return OWSLocalizedString(
                "BADGE_EXPIRED_BOOST_TITLE",
                comment: "Title for boost on the badge expiration sheet."
            )
        case .giftBadgeExpired:
            return OWSLocalizedString(
                "DONATION_FROM_A_FRIEND_BADGE_EXPIRED_TITLE",
                comment: "Someone donated on your behalf and you got a badge, which expired. A sheet appears to tell you about this. This is the title on that sheet."
            )
        case .giftNotRedeemed:
            return OWSLocalizedString(
                "DONATION_FROM_A_FRIEND_BADGE_NOT_REDEEMED_TITLE",
                comment: "Someone donated on your behalf and you got a badge, which expired before you could redeem it. A sheet appears to tell you about this. This is the title on that sheet."
            )
        }
    }()

    public lazy var body: Body = {
        switch mode {
        case let .subscriptionExpiredBecauseOfChargeFailure(chargeFailure, paymentMethod):
            let failureSpecificText = DonationViewsUtil.localizedDonationFailure(
                chargeErrorCode: chargeFailure.code,
                paymentMethod: paymentMethod
            )
            let formatText = OWSLocalizedString(
                "BADGE_SUBSCRIPTION_EXPIRED_BECAUSE_OF_CHARGE_FAILURE_BODY_FORMAT",
                comment: "String explaining to the user that their subscription badge has expired on the badge expiry sheet. Embeds {failure-specific sentence(s)}."
            )
            return Body(String(format: formatText, failureSpecificText), hasLearnMoreLink: true)
        case .subscriptionExpiredBecauseNotRenewed:
            let formatText = OWSLocalizedString(
                "BADGE_SUBSCRIPTION_EXPIRED_BECAUSE_OF_INACTIVITY_BODY_FORMAT",
                comment: "Body of the sheet shown when your subscription is canceled due to inactivity"
            )
            return Body(String(format: formatText, badge.localizedName), hasLearnMoreLink: true)
        case let .boostExpired(hasCurrentSubscription):
            let bodyText: String
            if hasCurrentSubscription {
                bodyText = OWSLocalizedString(
                    "BADGE_EXPIRED_BOOST_CURRENT_SUSTAINER_BODY",
                    comment: "String explaining to the user that their boost badge has expired while they are a current subscription sustainer on the badge expiry sheet."
                )
            } else {
                bodyText = OWSLocalizedString(
                    "BADGE_EXPIRED_BOOST_BODY",
                    comment: "String explaining to the user that their boost badge has expired on the badge expiry sheet."
                )
            }
            return Body(bodyText)
        case .giftBadgeExpired:
            let bodyText = OWSLocalizedString(
                "DONATION_FROM_A_FRIEND_BADGE_EXPIRED_BODY",
                comment: "Someone donated on your behalf and you got a badge, which expired. A sheet appears to tell you about this. This is the text on that sheet."
            )
            return Body(bodyText)
        case let .giftNotRedeemed(fullName):
            let formatText = OWSLocalizedString(
                "DONATION_FROM_A_FRIEND_BADGE_NOT_REDEEMED_BODY_FORMAT",
                comment: "Someone donated on your behalf and you got a badge, which expired before you could redeem it. A sheet appears to tell you about this. This is the text on that sheet. Embeds {{contact name}}."
            )
            return Body(String(format: formatText, fullName))
        }
    }()

    public lazy var actionButton: ActionButton = {
        let shouldAskUsersToDonate: Bool = {
            guard canDonate else { return false }
            switch mode {
            case .subscriptionExpiredBecauseNotRenewed, .boostExpired:
                return true
            case let .giftBadgeExpired(hasCurrentSubscription):
                return !hasCurrentSubscription
            case .subscriptionExpiredBecauseOfChargeFailure, .giftNotRedeemed:
                return false
            }
        }()

        if shouldAskUsersToDonate {
            let text = OWSLocalizedString(
                "BADGE_EXPIRED_DONATE_BUTTON",
                comment: "Button text when a badge expires, asking users to donate"
            )
            return .init(action: .openDonationView, text: text, hasNotNow: true)
        } else {
            return .init(action: .dismiss, text: CommonStrings.okayButton)
        }
    }()
}

class BadgeExpirationSheet: OWSTableSheetViewController {
    private let state: BadgeExpirationSheetState

    public weak var delegate: BadgeExpirationSheetDelegate?

    public init(badge: ProfileBadge, mode: BadgeExpirationSheetState.Mode) {
        self.state = BadgeExpirationSheetState(
            badge: badge,
            mode: mode,
            canDonate: DonationUtilities.canDonateInAnyWay(
                localNumber: Self.tsAccountManager.localNumber
            )
        )
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
            titleLabel.font = .dynamicTypeTitle2.semibold()
            titleLabel.textColor = Theme.primaryTextColor
            titleLabel.textAlignment = .center
            titleLabel.numberOfLines = 0
            titleLabel.text = self.state.titleText
            stackView.addArrangedSubview(titleLabel)
            stackView.setCustomSpacing(12, after: titleLabel)

            let bodyLabel: UIView
            if self.state.body.hasLearnMoreLink {
                let learnMore = OWSLocalizedString(
                    "BADGE_EXPIRED_LEARN_MORE_LINK",
                    comment: "Text for the 'learn more' link in the badge expiration sheet, shown when a badge expires due to a charge failure"
                ).styled(with: .link(SupportConstants.badgeExpirationLearnMoreURL))
                let label = LinkingTextView()
                label.attributedText = .composed(of: [self.state.body.text, " ", learnMore]).styled(with: .color(Theme.primaryTextColor), .font(.dynamicTypeBody))
                label.textAlignment = .center
                label.linkTextAttributes = [
                    .foregroundColor: Theme.accentBlueColor,
                    .underlineColor: UIColor.clear,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
                bodyLabel = label
            } else {
                let label = UILabel()
                label.font = .dynamicTypeBody
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
                                                    font: UIFont.dynamicTypeBody.semibold(),
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
