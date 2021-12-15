//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import SignalMessaging

protocol BadgeExpirationSheetDelegate: AnyObject {
    func badgeExpirationSheetActionButtonTapped(_ badgeExpirationSheet: BadgeExpirationSheet)
    func badgeExpirationSheetNotNowButtonTapped(_ badgeExpirationSheet: BadgeExpirationSheet)
}

class BadgeExpirationSheet: InteractiveSheetViewController {
    override var interactiveScrollViews: [UIScrollView] { [tableViewController.tableView] }
    override var renderExternalHandle: Bool { false }
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
    private let handleContainer = UIView()

    private let badge: ProfileBadge

    public var badgeID: String {
        return badge.id
    }

    private lazy var isCurrentSustainer = {
        return SubscriptionManager.hasCurrentSubscriptionWithSneakyTransaction()
    }()

    required init(badge: ProfileBadge) {
        owsAssertDebug(badge.assets != nil)
        self.badge = badge

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

        // We add the handle directly to the content view,
        // so that it doesn't scroll with the table.
        handleContainer.backgroundColor = Theme.tableView2PresentedBackgroundColor
        contentView.addSubview(handleContainer)
        handleContainer.autoPinWidthToSuperview()
        handleContainer.autoPinEdge(toSuperviewEdge: .top)

        let handle = UIView()
        handle.backgroundColor = tableViewController.separatorColor
        handle.autoSetDimensions(to: CGSize(width: 36, height: 5))
        handle.layer.cornerRadius = 5 / 2
        handleContainer.addSubview(handle)
        handle.autoPinHeightToSuperview(withMargin: 12)
        handle.autoHCenterInSuperview()

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
        handleContainer.backgroundColor = Theme.tableView2PresentedBackgroundColor
        updateTableContents()
    }

    var titleText: String {
        if BoostBadgeIds.contains(badge.id) {
            return NSLocalizedString(
                "BADGE_EXPIRED_BOOST_TITLE",
                comment: "Title for boost on the badge expiration sheet."
            )
        } else {
            return NSLocalizedString(
                "BADGE_EXPIRED_SUBSCRIPTION_TITLE",
                comment: "Title for subscription on the badge expiration sheet."
            )
        }
    }

    var bodyText: String {
        var formatText: String

        if BoostBadgeIds.contains(badge.id) {
            if isCurrentSustainer {
                formatText = NSLocalizedString(
                    "BADGE_EXIPRED_BOOST_CURRENT_SUSTAINER_BODY_FORMAT",
                    comment: "String explaing to the user that their boost badge has expired while they are a current subscription sustainer on the badge expiry sheetsheet."
                )
            } else {
                formatText = NSLocalizedString(
                    "BADGE_EXIPRED_BOOST_BODY_FORMAT",
                    comment: "String explaing to the user that their boost badge has expired on the badge expiry sheetsheet."
                )
            }
        } else {
            formatText = NSLocalizedString(
                "BADGE_EXIPRED_SUBSCRIPTION_BODY_FORMAT",
                comment: "String explaing to the user that their subscription badge has expired on the badge expiry sheetsheet. Embed {badge name}."
            )
        }

        return String(format: formatText, badge.localizedName)
    }

    var actionButtonText: String {
        if BoostBadgeIds.contains(badge.id) {
            if isCurrentSustainer {
                return NSLocalizedString("BADGE_EXPIRED_BOOST_RENEWAL_BUTTON_SUSTAINER",
                                         comment: "Button title for boost on the badge expiration sheet, used if the user is already a sustainer.")
            } else {
                return NSLocalizedString("BADGE_EXPIRED_BOOST_RENEWAL_BUTTON",
                                         comment: "Button title for boost on the badge expiration sheet, used if the user is not already a sustainer.")
            }
        } else {
            return NSLocalizedString("BADGE_EXPIRED_SUBSCRIPTION_RENEWAL_BUTTON",
                                     comment: "Button title for subscription on the badge expiration sheet.")
        }
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
            badgeImageView.image = self.badge.assets?.universal112
            badgeImageView.autoSetDimensions(to: CGSize(square: 112))
            stackView.addArrangedSubview(badgeImageView)
            stackView.setCustomSpacing(16, after: badgeImageView)

            let titleLabel = UILabel()
            titleLabel.font = .ows_dynamicTypeTitle2.ows_semibold
            titleLabel.textColor = Theme.primaryTextColor
            titleLabel.textAlignment = .center
            titleLabel.numberOfLines = 0
            titleLabel.text = self.titleText
            stackView.addArrangedSubview(titleLabel)
            stackView.setCustomSpacing(12, after: titleLabel)

            let bodyLabel = UILabel()
            bodyLabel.font = .ows_dynamicTypeBody
            bodyLabel.textColor = Theme.primaryTextColor
            bodyLabel.textAlignment = .center
            bodyLabel.numberOfLines = 0
            bodyLabel.text = self.bodyText
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
            stackView.layoutMargins = UIEdgeInsets(top: 30, left: 24, bottom: 0, right: 24)
            stackView.spacing = 16
            stackView.isLayoutMarginsRelativeArrangement = true
            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewEdges()

            let actionButton = OWSFlatButton.button(title: self.actionButtonText,
                                                    font: UIFont.ows_dynamicTypeBody.ows_semibold,
                                                    titleColor: .white,
                                                    backgroundColor: .ows_accentBlue,
                                                    target: self,
                                                    selector: #selector(self.didTapAction))
            actionButton.autoSetHeightUsingFont()
            actionButton.cornerRadius = 8
            stackView.addArrangedSubview(actionButton)
            actionButton.autoPinWidthToSuperviewMargins()

            let notNowButton = OWSButton(title: CommonStrings.notNowButton) { [weak self] in
                guard let self = self else { return }
                self.didTapNotNow()
            }
            notNowButton.setTitleColor(Theme.accentBlueColor, for: .normal)
            notNowButton.dimsWhenHighlighted = true
            stackView.addArrangedSubview(notNowButton)

            return cell
        }, actionBlock: nil))
    }

    public override func willDismissInteractively() {
        didTapNotNow()
        super.willDismissInteractively()
    }

    @objc
    func didTapAction() {
        if let delegate = delegate {
            dismiss(animated: true, completion: nil)
            delegate.badgeExpirationSheetActionButtonTapped(self)
        }
    }

    @objc
    func didTapNotNow() {
        dismiss(animated: true, completion: nil)
    }
}
