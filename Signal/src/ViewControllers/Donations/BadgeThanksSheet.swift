//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalServiceKit
import SignalUI

struct ProfileBadgesSnapshot {
    /// The IDs and visibility status of badges added to the account. Even
    /// though each badge's visibility status can be independently edited, the
    /// expected steady state is that they're all either visible or invisible.
    /// When adding a new badge, it starts out invisible, and dismissing this
    /// sheet will make it visible, if needed.
    let existingBadges: [Badge]

    struct Badge {
        var id: String
        var isVisible: Bool
    }
}

struct VisibleBadgeResolver {
    let badgesSnapshot: ProfileBadgesSnapshot

    enum SwitchType {
        case displayOnProfile
        case makeFeaturedBadge
        case none
    }

    func switchType(for newBadgeId: String) -> SwitchType {
        if self.isVisibleAndFeatured(badgeId: newBadgeId) {
            return .none
        }
        if self.isAnyBadgeVisible() {
            return .makeFeaturedBadge
        }
        return .displayOnProfile
    }

    func switchDefault(for newBadgeId: String) -> Bool {
        // If the badge is already featured, suggest keeping it featured. In this
        // case, no switch is presented to the user (see above), so the eventual
        // position of the badge would be determined entirely by the following if
        // statements, which could lead to odd behavior in some cases.
        if self.isVisibleAndFeatured(badgeId: newBadgeId) {
            return true
        }
        // If you're buying a recurring badge, suggest featuring it.
        if SubscriptionBadgeIds.contains(newBadgeId) {
            return true
        }
        // If you're buying a one-time badge (prior check didn't pass), don't
        // suggest featuring it if you already have a recurring badge.
        if self.hasAnySustainerBadge() {
            return false
        }
        return true
    }

    func currentlyVisibleBadgeIds() -> [String] {
        self.badgesSnapshot.existingBadges.lazy.filter { $0.isVisible }.map { $0.id }
    }

    func visibleBadgeIds(adding newBadgeId: String, isVisibleAndFeatured: Bool) -> [String] {
        lazy var currentlyVisibleBadgeIds = self.currentlyVisibleBadgeIds()
        lazy var nonNewBadgeIds = self.badgesSnapshot.existingBadges.lazy.filter { $0.id != newBadgeId }.map { $0.id }

        // If the user has selected "Display on Profile" or "Make Featured Badge",
        // we make this the first visible badge. We also make all other badges
        // visible -- we don't currently support displaying only a subset.
        if isVisibleAndFeatured {
            return [newBadgeId] + nonNewBadgeIds
        }

        // For all the remaining cases, the switch was shown, and it's set to "off".

        // If there aren't any badges visible, don't make this one visible.
        if currentlyVisibleBadgeIds.isEmpty {
            return []
        }

        // We have some visible badges, but the user doesn't want this badge to be featured.
        if currentlyVisibleBadgeIds.first == newBadgeId {
            return nonNewBadgeIds + [newBadgeId]
        }

        // The badge is already visible. Leave it where it is to avoid a redundant profile update.
        if currentlyVisibleBadgeIds.contains(newBadgeId) {
            return currentlyVisibleBadgeIds
        }

        // The badge isn't visible but should be. At it to the end of the list of badges.
        return nonNewBadgeIds + [newBadgeId]
    }

    private func hasAnySustainerBadge() -> Bool {
        self.badgesSnapshot.existingBadges.first { SubscriptionBadgeIds.contains($0.id) } != nil
    }

    private func firstVisibleBadge() -> ProfileBadgesSnapshot.Badge? {
        self.badgesSnapshot.existingBadges.first { $0.isVisible }
    }

    private func isAnyBadgeVisible() -> Bool {
        self.firstVisibleBadge() != nil
    }

    private func isVisibleAndFeatured(badgeId: String) -> Bool {
        self.firstVisibleBadge()?.id == badgeId
    }

}

class BadgeThanksSheet: OWSTableSheetViewController {

    enum BadgeType {
        case boost
        case subscription
        case gift(shortName: String, notNowAction: () -> Void, incomingMessage: TSIncomingMessage)
    }

    private let badge: ProfileBadge
    private let badgeType: BadgeType

    private let initialVisibleBadgeResolver: VisibleBadgeResolver
    private lazy var shouldMakeVisibleAndPrimary = self.initialVisibleBadgeResolver.switchDefault(for: self.badge.id)

    /// Displays a message after a badge has been redeemed.
    ///
    /// - Parameter newBadge: The badge that was just redeemed.
    ///
    /// - Parameter newBadgeType: The semantic type of badge that was redeemed.
    /// For example, was the badge redeemed through the subscription flow? The
    /// one-time flow? The "Donate for a Friend" flow?
    ///
    /// - Parameter oldBadgesSnapshot: A snapshot of the user's badges before
    /// `newBadge` was redeemed. You can capture this value by calling
    /// `currentProfileBadgesSnapshot()`.
    required init(
        newBadge badge: ProfileBadge,
        newBadgeType badgeType: BadgeType,
        oldBadgesSnapshot: ProfileBadgesSnapshot
    ) {
        owsAssertDebug(badge.assets != nil)
        self.badge = badge
        self.badgeType = badgeType
        self.initialVisibleBadgeResolver = VisibleBadgeResolver(badgesSnapshot: oldBadgesSnapshot)

        switch badgeType {
        case .boost:
            owsAssertDebug(BoostBadgeIds.contains(badge.id))
        case .subscription:
            owsAssertDebug(SubscriptionBadgeIds.contains(badge.id))
        case .gift:
            owsAssertDebug(GiftBadgeIds.contains(badge.id))
        }

        super.init()

        updateTableContents()
    }

    public required init() {
        fatalError("init() has not been implemented")
    }

    static func currentProfileBadgesSnapshot() -> ProfileBadgesSnapshot {
        let profileSnapshot = self.profileManagerImpl.localProfileSnapshot(shouldIncludeAvatar: false)
        return profileBadgesSnapshot(for: profileSnapshot)
    }

    private static func profileBadgesSnapshot(for profileSnapshot: OWSProfileSnapshot) -> ProfileBadgesSnapshot {
        ProfileBadgesSnapshot(
            existingBadges: (profileSnapshot.profileBadgeInfo ?? []).map {
                ProfileBadgesSnapshot.Badge(id: $0.badgeId, isVisible: $0.isVisible ?? false)
            }
        )
    }

    override func willDismissInteractively() {
        super.willDismissInteractively()

        switch self.badgeType {
        case .boost, .subscription:
            self.saveVisibilityChanges()
        case let .gift(_, notNowAction, _):
            notNowAction()
        }
    }

    private func performConfirmationAction(_ promise: @escaping () -> Promise<Void>, errorHandler: @escaping (Error) -> Void) {
        ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { modal in
            promise().done {
                modal.dismiss {
                    self.dismiss(animated: true)
                }
            }.catch { error in
                owsFailDebug("Unexpectedly failed to confirm badge action \(error)")
                modal.dismiss {
                    errorHandler(error)
                }
            }
        }
    }

    @discardableResult
    private func saveVisibilityChanges() -> Promise<Void> {
        let snapshot = profileManagerImpl.localProfileSnapshot(shouldIncludeAvatar: true)
        let visibleBadgeResolver = VisibleBadgeResolver(badgesSnapshot: Self.profileBadgesSnapshot(for: snapshot))
        let visibleBadgeIds = visibleBadgeResolver.visibleBadgeIds(
            adding: self.badge.id,
            isVisibleAndFeatured: self.shouldMakeVisibleAndPrimary
        )
        guard visibleBadgeIds != visibleBadgeResolver.currentlyVisibleBadgeIds() else {
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
            return SubscriptionManagerImpl.redeemReceiptCredentialPresentation(
                receiptCredentialPresentation: try giftBadge.getReceiptCredentialPresentation()
            )
        }.done(on: DispatchQueue.global()) {
            Self.updateGiftBadge(incomingMessage: incomingMessage, state: .redeemed)
        }
    }

    private static func updateGiftBadge(incomingMessage: TSIncomingMessage, state: OWSGiftBadgeRedemptionState) {
        self.databaseStorage.write { transaction in
            incomingMessage.anyUpdateIncomingMessage(transaction: transaction) {
                $0.giftBadge?.redemptionState = state
            }

            if state == .redeemed {
                self.receiptManager.incomingGiftWasRedeemed(incomingMessage, transaction: transaction)
            }
        }
    }

    private var titleText: String {
        switch self.badgeType {
        case .boost, .subscription:
            return NSLocalizedString(
                "BADGE_THANKS_TITLE",
                comment: "When you make a donation to Signal, you will receive a badge. A thank-you sheet appears when this happens. This is the title of that sheet."
            )
        case let .gift(shortName, _, _):
            let formatText = NSLocalizedString(
                "DONATION_ON_BEHALF_OF_A_FRIEND_REDEEM_BADGE_TITLE_FORMAT",
                comment: "A friend has donated on your behalf and you received a badge. A sheet opens for you to redeem this badge. Embeds {{contact's short name, such as a first name}}."
            )
            return String(format: formatText, shortName)
        }
    }

    private var bodyText: String {
        switch self.badgeType {
        case .boost, .subscription:
            let formatText = NSLocalizedString(
                "BADGE_THANKS_BODY",
                comment: "When you make a donation to Signal, you will receive a badge. A thank-you sheet appears when this happens. This is the body text on that sheet."
            )
            return String(format: formatText, self.badge.localizedName)
        case let .gift(shortName, _, _):
            let formatText = NSLocalizedString(
                "DONATION_ON_BEHALF_OF_A_FRIEND_YOU_RECEIVED_A_BADGE_FORMAT",
                comment: "A friend has donated on your behalf and you received a badge. This text says that you received a badge, and from whom. Embeds {{contact's short name, such as a first name}}."
            )
            return String(format: formatText, shortName)
        }
    }

    // MARK: -

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

            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewMargins()

            let titleLabel = UILabel()
            titleLabel.font = .dynamicTypeTitle2.semibold()
            titleLabel.textColor = Theme.primaryTextColor
            titleLabel.textAlignment = .center
            titleLabel.numberOfLines = 0
            titleLabel.text = self.titleText
            stackView.addArrangedSubview(titleLabel)
            stackView.setCustomSpacing(12, after: titleLabel)

            let bodyLabel = UILabel()
            bodyLabel.font = .dynamicTypeBody
            bodyLabel.textColor = Theme.primaryTextColor
            bodyLabel.textAlignment = .center
            bodyLabel.numberOfLines = 0
            bodyLabel.text = self.bodyText
            stackView.addArrangedSubview(bodyLabel)
            stackView.setCustomSpacing(30, after: bodyLabel)

            let badgeImageView = UIImageView()
            let shouldShowBadgeLabel: Bool
            switch self.badgeType {
            case .boost, .subscription:
                badgeImageView.image = self.badge.assets?.universal160
                badgeImageView.autoSetDimensions(to: CGSize(square: 160))
                shouldShowBadgeLabel = true
            case .gift:
                // Use a smaller image for gifts since they have an extra button.
                badgeImageView.image = self.badge.assets?.universal112
                badgeImageView.autoSetDimensions(to: CGSize(square: 112))
                shouldShowBadgeLabel = false
            }
            stackView.addArrangedSubview(badgeImageView)

            if shouldShowBadgeLabel {
                let badgeLabel = UILabel()
                badgeLabel.font = .dynamicTypeTitle3.semibold()
                badgeLabel.textColor = Theme.primaryTextColor
                badgeLabel.textAlignment = .center
                badgeLabel.numberOfLines = 0
                badgeLabel.text = self.badge.localizedName
                stackView.addArrangedSubview(badgeLabel)
                stackView.setCustomSpacing(14, after: badgeImageView)
                stackView.setCustomSpacing(36, after: badgeLabel)
            } else {
                stackView.setCustomSpacing(36, after: badgeImageView)
            }

            return cell
        }, actionBlock: nil))

        if let displayBadgeSection = self.buildDisplayBadgeSection() {
            contents.addSection(displayBadgeSection)
        }

        switch self.badgeType {
        case let .gift(_, notNowAction, incomingMessage):
            contents.addSection(self.buildRedeemButtonSection(notNowAction: notNowAction, incomingMessage: incomingMessage))
        case .boost, .subscription:
            contents.addSection(self.buildDoneButtonSection())
        }
    }

    private func buildDisplayBadgeSection() -> OWSTableSection? {
        let switchText: String
        let showFooter: Bool
        switch self.initialVisibleBadgeResolver.switchType(for: self.badge.id) {
        case .none:
            return nil
        case .displayOnProfile:
            switchText = NSLocalizedString(
                "BADGE_THANKS_DISPLAY_ON_PROFILE_LABEL",
                comment: "Label prompting the user to display the new badge on their profile on the badge thank you sheet."
            )
            showFooter = false
        case .makeFeaturedBadge:
            switchText = NSLocalizedString(
                "BADGE_THANKS_MAKE_FEATURED",
                comment: "Label prompting the user to feature the new badge on their profile on the badge thank you sheet."
            )
            showFooter = true
        }

        let section = OWSTableSection()
        section.add(.switch(
            withText: switchText,
            isOn: { self.shouldMakeVisibleAndPrimary },
            target: self,
            selector: #selector(didToggleDisplayOnProfile)
        ))
        if showFooter {
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
                font: .dynamicTypeBody.semibold(),
                titleColor: .white
            )
            button.setBackgroundColors(upColor: .ows_accentBlue)
            button.setPressedBlock { [weak self] in
                guard let self = self else { return }
                self.performConfirmationAction {
                    self.saveVisibilityChanges()
                } errorHandler: { error in
                    self.dismiss(animated: true)
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
                font: .dynamicTypeBody.semibold(),
                titleColor: .white
            )
            redeemButton.setBackgroundColors(upColor: .ows_accentBlue)
            redeemButton.setPressedBlock { [weak self] in
                guard let self = self else { return }
                self.performConfirmationAction {
                    Self.redeemGiftBadge(incomingMessage: incomingMessage)
                        .then(on: DispatchQueue.global()) { self.saveVisibilityChanges() }
                } errorHandler: { error in
                    OWSActionSheets.showActionSheet(
                        title: NSLocalizedString(
                            "FAILED_TO_REDEEM_BADGE_RECEIVED_AFTER_DONATION_FROM_A_FRIEND_TITLE",
                            comment: "Shown as the title of an alert when failing to redeem a badge that was received after a friend donated on your behalf."
                        ),
                        message: NSLocalizedString(
                            "FAILED_TO_REDEEM_BADGE_RECEIVED_AFTER_DONATION_FROM_A_FRIEND_BODY",
                            comment: "Shown as the body of an alert when failing to redeem a badge that was received after a friend donated on your behalf."
                        )
                    )
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
            notNowButton.titleLabel?.font = .dynamicTypeBody
            notNowButton.setTitleColor(Theme.accentBlueColor, for: .normal)
            notNowButton.dimsWhenHighlighted = true
            stackView.addArrangedSubview(notNowButton)

            return cell
        }, actionBlock: nil))

        return section
    }
}
