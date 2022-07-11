//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalUI

class BadgeThanksSheet: InteractiveSheetViewController {
    override var interactiveScrollViews: [UIScrollView] { [tableViewController.tableView] }
    override var sheetBackgroundColor: UIColor { tableViewController.tableBackgroundColor }
    private var shouldMakeVisibleAndPrimary = false

    var contentSizeHeight: CGFloat {
        // The table view doesn't have the correct height during normal layout
        // passes. To correct that problem, we call `layoutIfNeeded()`. However,
        // doing this causes `tableView.adjustedContentInset.bottom` to diverge
        // from its expected value of `view.safeAreaInsets.bottom` during
        // interactive drag animations, which results in really odd/jumpy layout
        // behavior. Given we always show this view attached to the bottom of the
        // screen, use `view.safeAreaInsets.bottom` directly for now.
        tableViewController.tableView.contentSize.height + self.view.safeAreaInsets.bottom
    }
    override var minimizedHeight: CGFloat {
        return min(contentSizeHeight, maximizedHeight)
    }
    override var maximizedHeight: CGFloat {
        min(contentSizeHeight, CurrentAppContext().frame.height - (view.safeAreaInsets.top + 32))
    }

    private let tableViewController = OWSTableViewController2()

    enum BadgeType {
        case boost
        case subscription
        case gift(shortName: String, fullName: String, notNowAction: () -> Void, incomingMessage: TSIncomingMessage)
    }

    private let badge: ProfileBadge
    private let badgeType: BadgeType

    private lazy var profileSnapshot = profileManagerImpl.localProfileSnapshot(shouldIncludeAvatar: false)
    private lazy var hasAnySustainerBadge = profileSnapshot.profileBadgeInfo?.first { SubscriptionBadgeIds.contains($0.badgeId) } != nil
    private lazy var visibleBadges = profileSnapshot.profileBadgeInfo?.filter { $0.isVisible ?? false } ?? []
    private var hasVisibleBadges: Bool { !visibleBadges.isEmpty }
    private var isPrimaryBadge: Bool { badge.id == visibleBadges.first?.badgeId }

    required init(badge: ProfileBadge, type: BadgeType) {
        owsAssertDebug(badge.assets != nil)
        self.badge = badge
        self.badgeType = type

        switch type {
        case .boost:
            owsAssertDebug(BoostBadgeIds.contains(badge.id))
        case .subscription:
            owsAssertDebug(SubscriptionBadgeIds.contains(badge.id))
        case .gift:
            owsAssertDebug(GiftBadgeIds.contains(badge.id))
        }

        super.init()

        tableViewController.shouldDeferInitialLoad = false
        updateTableContents()
    }

    public required init() {
        fatalError("init() has not been implemented")
    }

    override func willDismissInteractively() {
        super.willDismissInteractively()

        switch self.badgeType {
        case .boost, .subscription:
            self.saveVisibilityChanges()
        case .gift(_, _, notNowAction: let notNowAction, _):
            notNowAction()
        }
    }

    private func performConfirmationAction(_ promise: @escaping () -> Promise<Void>) {
        ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { modal in
            promise().ensure {
                modal.dismiss {
                    self.dismiss(animated: true)
                }
            }.catch { error in
                owsFailDebug("Unexpectedly failed to confirm badge action \(error)")
            }
        }
    }

    @discardableResult
    private func saveVisibilityChanges() -> Promise<Void> {
        let snapshot = profileManagerImpl.localProfileSnapshot(shouldIncludeAvatar: true)

        let newBadgeId = self.badge.id
        let allBadges = snapshot.profileBadgeInfo ?? []
        let nonPrimaryBadgeIds = allBadges.filter { $0.badgeId != newBadgeId }.map { $0.badgeId }
        let currentlyVisibleBadgeIds = allBadges.filter { $0.isVisible ?? false }.map { $0.badgeId }

        let visibleBadgeIds: [String]
        if shouldMakeVisibleAndPrimary {
            visibleBadgeIds = [newBadgeId] + nonPrimaryBadgeIds
        } else if !currentlyVisibleBadgeIds.isEmpty {
            if currentlyVisibleBadgeIds.contains(newBadgeId) && currentlyVisibleBadgeIds.first != newBadgeId {
                // We don't need to make any change, this saves us a profile update
                visibleBadgeIds = currentlyVisibleBadgeIds
            } else {
                // Put the new badge at the end
                visibleBadgeIds = nonPrimaryBadgeIds + [newBadgeId]
            }
        } else {
            visibleBadgeIds = []
        }

        guard visibleBadgeIds != currentlyVisibleBadgeIds else {
            // No change, we can skip the profile update.
            return Promise.value(())
        }

        return OWSProfileManager.updateLocalProfilePromise(
            profileGivenName: snapshot.givenName,
            profileFamilyName: snapshot.familyName,
            profileBio: snapshot.bio,
            profileBioEmoji: snapshot.bioEmoji,
            profileAvatarData: snapshot.avatarData,
            visibleBadgeIds: visibleBadgeIds,
            userProfileWriter: .localUser
        )
    }

    private static func redeemGiftBadge(incomingMessage: TSIncomingMessage) -> Promise<Void> {
        return firstly { () -> Promise<Void> in
            guard let giftBadge = incomingMessage.giftBadge else {
                throw OWSAssertionError("trying to redeem message without a badge")
            }
            return try SubscriptionManager.redeemReceiptCredentialPresentation(
                receiptCredentialPresentation: try giftBadge.getReceiptCredentialPresentation()
            )
        }.done(on: .global()) {
            Self.updateGiftBadge(incomingMessage: incomingMessage, state: .redeemed)
        }.`catch`(on: .global()) { error in
            // TODO: (GB) Handle errors when failing to redeem gift badges.
        }
    }

    private static func updateGiftBadge(incomingMessage: TSIncomingMessage, state: OWSGiftBadgeRedemptionState) {
        self.databaseStorage.write { transaction in
            incomingMessage.anyUpdateIncomingMessage(transaction: transaction) {
                $0.giftBadge?.redemptionState = state
            }

            if state == .redeemed {
                self.receiptManager.incomingGiftWasRedeemed(incomingMessage, transaction: transaction)

                ExperienceUpgradeManager.snoozeExperienceUpgrade(
                    .subscriptionMegaphone,
                    transaction: transaction.unwrapGrdbWrite
                )
            }
        }
    }

    private var titleText: String {
        switch self.badgeType {
        case .boost:
            return NSLocalizedString(
                "BADGE_THANKS_BOOST_TITLE",
                comment: "Title for boost on the thank you sheet."
            )
        case .subscription:
            return NSLocalizedString(
                "BADGE_THANKS_SUBSCRIPTION_TITLE",
                comment: "Title for subscription on the thank you sheet."
            )
        case .gift(shortName: let shortName, _, _, _):
            let formatText = NSLocalizedString(
                "BADGE_GIFTING_REDEEM_TITLE_FORMAT",
                comment: "Appears as the title when redeeming a gift you received. Embed {contact's short name, such as a first name}."
            )
            return String(format: formatText, shortName)
        }
    }

    private var bodyText: String {
        switch self.badgeType {
        case .boost, .subscription:
            let formatText = NSLocalizedString(
                "BADGE_THANKS_YOU_EARNED_FORMAT",
                comment: "String explaining to the user that they've earned a badge on the badge thank you sheet. Embed {badge name}."
            )
            return String(format: formatText, self.badge.localizedName)
        case .gift(_, fullName: let fullName, _, _):
            let formatText = NSLocalizedString(
                "BADGE_GIFTING_YOU_RECEIVED_FORMAT",
                comment: "Shown when redeeming a gift you received to explain to the user that they've earned a badge. Embed {contact name}."
            )
            return String(format: formatText, fullName)
        }
    }

    // MARK: -

    override public func viewDidLoad() {
        super.viewDidLoad()

        addChild(tableViewController)

        contentView.addSubview(tableViewController.view)
        tableViewController.view.autoPinEdgesToSuperviewEdges()

        shouldMakeVisibleAndPrimary = self.badgeType.isRecurring || !self.hasAnySustainerBadge

        updateViewState()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        self.tableViewController.tableView.layoutIfNeeded()
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

            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewMargins()

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

            let badgeImageView = UIImageView()
            switch self.badgeType {
            case .boost, .subscription:
                badgeImageView.image = self.badge.assets?.universal160
                badgeImageView.autoSetDimensions(to: CGSize(square: 160))
            case .gift:
                // Use a smaller image for gifts since they have an extra button.
                badgeImageView.image = self.badge.assets?.universal112
                badgeImageView.autoSetDimensions(to: CGSize(square: 112))
            }
            stackView.addArrangedSubview(badgeImageView)
            stackView.setCustomSpacing(14, after: badgeImageView)

            let badgeLabel = UILabel()
            badgeLabel.font = .ows_dynamicTypeTitle3.ows_semibold
            badgeLabel.textColor = Theme.primaryTextColor
            badgeLabel.textAlignment = .center
            badgeLabel.numberOfLines = 0
            badgeLabel.text = self.badge.localizedName
            stackView.addArrangedSubview(badgeLabel)
            stackView.setCustomSpacing(36, after: badgeLabel)

            return cell
        }, actionBlock: nil))

        switch self.badgeType {
        case let .gift(_, _, notNowAction: notNowAction, incomingMessage: incomingMessage):
            // Always show this section for gifts since they have an extra redemption step.
            contents.addSection(self.buildDisplayBadgeSection())
            contents.addSection(self.buildRedeemButtonSection(notNowAction: notNowAction, incomingMessage: incomingMessage))
        case .boost, .subscription:
            if !isPrimaryBadge {
                contents.addSection(self.buildDisplayBadgeSection())
            }
            contents.addSection(self.buildDoneButtonSection())
        }
    }

    private func buildDisplayBadgeSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.add(.switch(
            withText: hasVisibleBadges
            ? NSLocalizedString(
                "BADGE_THANKS_MAKE_FEATURED",
                comment: "Label prompting the user to feature the new badge on their profile on the badge thank you sheet."
            )
            : NSLocalizedString(
                "BADGE_THANKS_DISPLAY_ON_PROFILE_LABEL",
                comment: "Label prompting the user to display the new badge on their profile on the badge thank you sheet."
            ),
            isOn: { self.shouldMakeVisibleAndPrimary },
            target: self,
            selector: #selector(didToggleDisplayOnProfile)
        ))
        if hasVisibleBadges {
            section.footerTitle = NSLocalizedString(
                "BADGE_THANKS_TOGGLE_FOOTER",
                comment: "Footer explaining that only one badge can be featured at a time on the thank you sheet."
            )
        }
        return section
    }

    @objc
    func didToggleDisplayOnProfile(_ sender: UISwitch) {
        shouldMakeVisibleAndPrimary = sender.isOn
    }

    private func buildDoneButtonSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.hasBackground = false
        section.add(.init(customCellBlock: { [weak self] in
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            guard let self = self else { return cell }

            let button = OWSFlatButton()
            button.setTitle(
                title: CommonStrings.doneButton,
                font: .ows_dynamicTypeBody.ows_semibold,
                titleColor: .white
            )
            button.setBackgroundColors(upColor: .ows_accentBlue)
            button.setPressedBlock { [weak self] in
                guard let self = self else { return }
                self.performConfirmationAction {
                    self.saveVisibilityChanges()
                }
            }
            button.autoSetHeightUsingFont()
            button.cornerRadius = 8
            cell.contentView.addSubview(button)
            button.autoPinEdgesToSuperviewMargins()
            return cell
        }, actionBlock: nil))
        return section
    }

    private func buildRedeemButtonSection(notNowAction: @escaping () -> Void, incomingMessage: TSIncomingMessage) -> OWSTableSection {
        let section = OWSTableSection()
        section.hasBackground = false
        section.add(.init(customCellBlock: { [weak self] in
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            guard let self = self else { return cell }

            let stackView = UIStackView()
            stackView.axis = .vertical
            stackView.alignment = .center
            stackView.spacing = 24
            stackView.isLayoutMarginsRelativeArrangement = true
            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewMargins()

            let redeemButton = OWSFlatButton()
            redeemButton.setTitle(
                title: CommonStrings.redeemGiftButton,
                font: .ows_dynamicTypeBody.ows_semibold,
                titleColor: .white
            )
            redeemButton.setBackgroundColors(upColor: .ows_accentBlue)
            redeemButton.setPressedBlock { [weak self] in
                guard let self = self else { return }
                self.performConfirmationAction {
                    Self.redeemGiftBadge(incomingMessage: incomingMessage)
                        .then(on: .global()) { self.saveVisibilityChanges() }
                }
            }
            redeemButton.autoSetHeightUsingFont()
            redeemButton.cornerRadius = 8
            stackView.addArrangedSubview(redeemButton)
            redeemButton.autoPinWidthToSuperviewMargins()

            let notNowButton = OWSButton(title: CommonStrings.notNowButton) { [weak self] in
                notNowAction()
                self?.dismiss(animated: true)
            }
            notNowButton.titleLabel?.font = .ows_dynamicTypeBody
            notNowButton.setTitleColor(Theme.accentBlueColor, for: .normal)
            notNowButton.dimsWhenHighlighted = true
            stackView.addArrangedSubview(notNowButton)

            return cell
        }, actionBlock: nil))

        return section
    }
}

private extension BadgeThanksSheet.BadgeType {
    var isRecurring: Bool {
        switch self {
        case .boost, .gift:
            return false
        case .subscription:
            return true
        }
    }
}
