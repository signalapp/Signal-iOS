//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import SignalMessaging

protocol BadgeExpirationSheetDelegate: AnyObject {
    func badgeExpirationSheetActionTapped(_ action: BadgeExpirationSheetAction)
}

public enum BadgeExpirationSheetAction {
    case dismiss
    case openBoostView
    case openSubscriptionsView
}

public class BadgeExpirationSheetState {
    public enum Mode {
        case subscriptionExpiredBecauseOfChargeFailure
        case subscriptionExpiredBecauseNotRenewed
        case boostExpired(hasCurrentSubscription: Bool)
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
        }
    }()

    public lazy var body: Body = {
        func format(_ formatText: String) -> String {
            String(format: formatText, badge.localizedName)
        }

        switch mode {
        case .subscriptionExpiredBecauseOfChargeFailure:
            let formatText = NSLocalizedString("BADGE_SUBSCRIPTION_EXPIRED_BECAUSE_OF_CHARGE_FAILURE_BODY_FORMAT",
                                               comment: "String explaing to the user that their subscription badge has expired on the badge expiry sheetsheet. Embed {badge name}.")
            return Body(format(formatText), hasLearnMoreLink: true)
        case .subscriptionExpiredBecauseNotRenewed:
            let formatText = NSLocalizedString("BADGE_SUBSCRIPTION_EXPIRED_BECAUSE_OF_INACTIVITY_BODY_FORMAT",
                                               comment: "Body of the sheet shown when your subscription is canceled due to inactivity")
            return Body(format(formatText), hasLearnMoreLink: true)
        case let .boostExpired(hasCurrentSubscription):
            let formatText: String
            if hasCurrentSubscription {
                formatText = NSLocalizedString("BADGE_EXIPRED_BOOST_CURRENT_SUSTAINER_BODY_FORMAT",
                                               comment: "String explaing to the user that their boost badge has expired while they are a current subscription sustainer on the badge expiry sheetsheet.")
            } else {
                formatText = NSLocalizedString("BADGE_EXIPRED_BOOST_BODY_FORMAT",
                                               comment: "String explaing to the user that their boost badge has expired on the badge expiry sheetsheet.")
            }
            return Body(format(formatText))
        }
    }()

    public lazy var actionButton: ActionButton = {
        switch mode {
        case .subscriptionExpiredBecauseOfChargeFailure:
            let text = CommonStrings.okayButton
            return ActionButton(action: .dismiss, text: text)
        case .subscriptionExpiredBecauseNotRenewed:
            let text = NSLocalizedString("BADGE_EXPIRED_SUBSCRIPTION_RENEWAL_BUTTON",
                                         comment: "Button text when a badge expires, asking you to renew your subscription")
            return ActionButton(action: .openSubscriptionsView, text: text, hasNotNow: true)
        case let .boostExpired(hasCurrentSubscription):
            let action: BadgeExpirationSheetAction
            let text: String
            if hasCurrentSubscription {
                action = .openBoostView
                text = NSLocalizedString("BADGE_EXPIRED_BOOST_RENEWAL_BUTTON_SUSTAINER",
                                         comment: "Button title for boost on the badge expiration sheet, used if the user is already a sustainer.")
            } else {
                action = .openSubscriptionsView
                text = NSLocalizedString("BADGE_EXPIRED_BOOST_RENEWAL_BUTTON",
                                         comment: "Button title for boost on the badge expiration sheet, used if the user is not already a sustainer.")
            }
            return ActionButton(action: action, text: text, hasNotNow: true)
        }
    }()
}

class BadgeExpirationSheet: InteractiveSheetViewController {
    private let state: BadgeExpirationSheetState

    override var interactiveScrollViews: [UIScrollView] { [tableViewController.tableView] }
    override var sheetBackgroundColor: UIColor { tableViewController.tableBackgroundColor }
    private var shouldMakeVisibleAndPrimary = false
    public weak var delegate: BadgeExpirationSheetDelegate?

    var contentSizeHeight: CGFloat {
        tableViewController.tableView.layoutIfNeeded()
        return tableViewController.tableView.contentSize.height + tableViewController.tableView.adjustedContentInset.top
    }
    override var minimizedHeight: CGFloat {
        return min(contentSizeHeight, maximizedHeight)
    }
    override var maximizedHeight: CGFloat {
        min(contentSizeHeight, CurrentAppContext().frame.height - (view.safeAreaInsets.top + 32))
    }

    private let tableViewController = OWSTableViewController2()

    public init(badge: ProfileBadge, mode: BadgeExpirationSheetState.Mode) {
        self.state = BadgeExpirationSheetState(badge: badge, mode: mode)
        owsAssertDebug(state.badge.assets != nil)

        super.init()

        tableViewController.shouldDeferInitialLoad = false
        updateTableContents()
    }

    public required init() {
        fatalError("init() has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        addChild(tableViewController)

        contentView.addSubview(tableViewController.view)
        tableViewController.view.autoPinEdgesToSuperviewEdges()

        updateViewState()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updateViewState()
    }

    private var previousMinimizedHeight: CGFloat?
    private func updateViewState() {
        if minimizedHeight != previousMinimizedHeight {
            heightConstraint?.constant = minimizedHeight
            previousMinimizedHeight = minimizedHeight
        }
    }

    override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }

    private func updateTableContents() {
        let contents = OWSTableContents()
        defer { tableViewController.contents = contents }

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
