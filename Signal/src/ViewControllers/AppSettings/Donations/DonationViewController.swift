//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalUI
import UIKit
import SafariServices

class DonationViewController: OWSTableViewController2 {
    private enum State {
        case initializing
        case loading
        case loaded(hasAnyDonationReceipts: Bool,
                    profileBadgeLookup: ProfileBadgeLookup,
                    subscriptionLevels: [SubscriptionLevel],
                    currentSubscription: Subscription?)
        case loadFailed(hasAnyDonationReceipts: Bool,
                        profileBadgeLookup: ProfileBadgeLookup)

        public var debugDescription: String {
            switch self {
            case .initializing:
                return "initializing"
            case .loading:
                return "loading"
            case .loaded:
                return "loaded"
            case .loadFailed:
                return "loadFailed"
            }
        }
    }

    private var state: State = .initializing {
        didSet {
            Logger.info("[Donations] DonationViewController state changed to \(state.debugDescription)")
            updateTableContents()
        }
    }

    private var avatarImage: UIImage?
    private var avatarView: ConversationAvatarView = {
        let sizeClass = ConversationAvatarView.Configuration.SizeClass.eightyEight
        let newAvatarView = ConversationAvatarView(sizeClass: sizeClass, localUserDisplayMode: .asUser)
        return newAvatarView
    }()

    private lazy var statusLabel = LinkingTextView()

    public override func viewDidLoad() {
        super.viewDidLoad()
        setUpAvatarView()
        title = NSLocalizedString("DONATION_VIEW_TITLE", comment: "Title on the 'Donate to Signal' screen")
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadAndUpdateState()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        showGiftBadgeExpirationSheetIfNeeded()
    }

    @objc
    private func didLongPressAvatar(sender: UIGestureRecognizer) {
        let subscriberID = databaseStorage.read { SubscriptionManager.getSubscriberID(transaction: $0) }
        guard let subscriberID = subscriberID else { return }

        UIPasteboard.general.string = subscriberID.asBase64Url

        presentToast(text: NSLocalizedString("SUBSCRIPTION_SUBSCRIBER_ID_COPIED_TO_CLIPBOARD",
                                             comment: "Toast indicating that the user has copied their subscriber ID."))
    }

    // MARK: - Data loading

    private func loadAndUpdateState() {
        switch state {
        case .loading:
            return
        case .initializing, .loadFailed, .loaded:
            self.state = .loading
            loadState().done { self.state = $0 }
        }
    }

    private func loadState() -> Guarantee<State> {
        let (subscriberID, hasAnyDonationReceipts) = databaseStorage.read { transaction -> (Data?, Bool) in
            let subscriberID = SubscriptionManager.getSubscriberID(transaction: transaction)
            let hasAnyDonationReceipts = DonationReceiptFinder.hasAny(transaction: transaction)

            return (subscriberID, hasAnyDonationReceipts)
        }

        let subscriptionLevelsPromise = DonationViewsUtil.loadSubscriptionLevels(badgeStore: self.profileManager.badgeStore)
        let currentSubscriptionPromise = DonationViewsUtil.loadCurrentSubscription(subscriberID: subscriberID)
        let profileBadgeLookupPromise = loadProfileBadgeLookup(hasAnyDonationReceipts: hasAnyDonationReceipts,
                                                               subscriberID: subscriberID)

        return profileBadgeLookupPromise.then { profileBadgeLookup -> Guarantee<State> in
            subscriptionLevelsPromise.then { subscriptionLevels -> Promise<State> in
                currentSubscriptionPromise.then { currentSubscription -> Guarantee<State> in
                    let result: State = .loaded(hasAnyDonationReceipts: hasAnyDonationReceipts,
                                                profileBadgeLookup: profileBadgeLookup,
                                                subscriptionLevels: subscriptionLevels,
                                                currentSubscription: currentSubscription)
                    return Guarantee.value(result)
                }
            }.recover { error -> Guarantee<State> in
                Logger.warn("[Donations] \(error)")
                let result: State = .loadFailed(hasAnyDonationReceipts: hasAnyDonationReceipts,
                                                profileBadgeLookup: profileBadgeLookup)
                return Guarantee.value(result)
            }
        }
    }

    private func loadProfileBadgeLookup(hasAnyDonationReceipts: Bool, subscriberID: Data?) -> Guarantee<ProfileBadgeLookup> {
        let willEverShowBadges: Bool = hasAnyDonationReceipts || subscriberID != nil
        guard willEverShowBadges else { return Guarantee.value(ProfileBadgeLookup()) }

        let oneTimeBadgesPromise = firstly {
            SubscriptionManager.getOneTimeBadges()
        }.map {
            // Make the result an Optional.
            $0
        }.recover { error -> Guarantee<SubscriptionManager.OneTimeBadgeResponse?> in
            Logger.warn("[Donations] Failed to fetch boost badge \(error). Proceeding without it, as it is only cosmetic here")
            return Guarantee.value(nil)
        }

        let subscriptionLevelsPromise: Guarantee<[SubscriptionLevel]> = SubscriptionManager.getSubscriptions()
            .recover { error -> Guarantee<[SubscriptionLevel]> in
                Logger.warn("[Donations] Failed to fetch subscription levels \(error). Proceeding without them, as they are only cosmetic here")
                return Guarantee.value([])
            }

        return oneTimeBadgesPromise.then { oneTimeBadgeResponse in
            subscriptionLevelsPromise.map { subscriptionLevels in
                ProfileBadgeLookup(boostBadge: try? oneTimeBadgeResponse?.parse(level: .boostBadge),
                                   giftBadge: try? oneTimeBadgeResponse?.parse(level: .giftBadge(.signalGift)),
                                   subscriptionLevels: subscriptionLevels)
            }.then { profileBadgeLookup in
                profileBadgeLookup.attemptToPopulateBadgeAssets(populateAssetsOnBadge: self.profileManager.badgeStore.populateAssetsOnBadge).map { profileBadgeLookup }
            }
        }
    }

    private func setUpAvatarView() {
        databaseStorage.read { transaction in
            self.avatarView.update(transaction) { config in
                if let address = tsAccountManager.localAddress(with: transaction) {
                    config.dataSource = .address(address)
                    config.addBadgeIfApplicable = true
                }
            }
        }

        avatarView.isUserInteractionEnabled = true
        avatarView.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(didLongPressAvatar)))
    }

    // MARK: - Table contents

    private func updateTableContents() {
        self.contents = OWSTableContents(sections: getTableSections())
    }

    private func getTableSections() -> [OWSTableSection] {
        switch state {
        case .initializing, .loading:
            return [loadingSection()]
        case let .loaded(hasAnyDonationReceipts, profileBadgeLookup, subscriptionLevels, currentSubscription):
            return loadedSections(hasAnyDonationReceipts: hasAnyDonationReceipts,
                                  profileBadgeLookup: profileBadgeLookup,
                                  subscriptionLevels: subscriptionLevels,
                                  currentSubscription: currentSubscription)
        case let .loadFailed(hasAnyDonationReceipts, profileBadgeLookup):
            return loadFailedSections(hasAnyDonationReceipts: hasAnyDonationReceipts,
                                      profileBadgeLookup: profileBadgeLookup)
        }
    }

    private func loadingSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.add(AppSettingsViewsUtil.loadingTableItem(cellOuterInsets: cellOuterInsets))
        section.hasBackground = false
        return section
    }

    private func loadedSections(hasAnyDonationReceipts: Bool,
                                profileBadgeLookup: ProfileBadgeLookup,
                                subscriptionLevels: [SubscriptionLevel],
                                currentSubscription: Subscription?) -> [OWSTableSection] {
        if let currentSubscription = currentSubscription {
            return hasActiveSubscriptionSections(hasAnyDonationReceipts: hasAnyDonationReceipts,
                                                 profileBadgeLookup: profileBadgeLookup,
                                                 subscriptionLevels: subscriptionLevels,
                                                 currentSubscription: currentSubscription)
        } else {
            return hasNoActiveSubscriptionSections(hasAnyDonationReceipts: hasAnyDonationReceipts,
                                                   profileBadgeLookup: profileBadgeLookup)
        }
    }

    private func loadFailedSections(hasAnyDonationReceipts: Bool,
                                    profileBadgeLookup: ProfileBadgeLookup) -> [OWSTableSection] {
        var result = [OWSTableSection]()

        let heroSection: OWSTableSection = {
            let section = OWSTableSection()
            section.hasBackground = false
            section.customHeaderView = {
                let heroStack = self.heroHeaderView()
                heroStack.layoutMargins = UIEdgeInsets(top: 0, left: 19, bottom: 0, right: 19)

                let label = UILabel()
                label.text = NSLocalizedString("DONATION_VIEW_LOAD_FAILED",
                                               comment: "Text that's shown when the donation view fails to load data, probably due to network failure")
                label.font = .ows_dynamicTypeBodyClamped
                label.numberOfLines = 0
                label.textColor = .ows_accentRed
                label.textAlignment = .center
                heroStack.addArrangedSubview(label)

                return heroStack
            }()
            return section
        }()
        result.append(heroSection)

        if let otherWaysToGiveSection = getOtherWaysToGiveSection() {
            result.append(otherWaysToGiveSection)
        }

        if hasAnyDonationReceipts {
            result.append(receiptsSection(profileBadgeLookup: profileBadgeLookup))
        }

        return result
    }

    private func hasActiveSubscriptionSections(hasAnyDonationReceipts: Bool,
                                               profileBadgeLookup: ProfileBadgeLookup,
                                               subscriptionLevels: [SubscriptionLevel],
                                               currentSubscription: Subscription) -> [OWSTableSection] {
        var result = [OWSTableSection]()

        let heroSection: OWSTableSection = {
            let section = OWSTableSection()
            section.hasBackground = false
            section.customHeaderView = {
                let heroStack = heroHeaderView()
                heroStack.layoutMargins = UIEdgeInsets(top: 0, left: 19, bottom: 0, right: 19)
                return heroStack
            }()
            return section
        }()
        result.append(heroSection)

        let currentSubscriptionSection: OWSTableSection = {
            let title = NSLocalizedString("DONATION_VIEW_MY_SUPPORT_TITLE",
                                          comment: "Title for the 'my support' section in the donation view")

            let section = OWSTableSection(title: title)

            let subscriptionLevel = DonationViewsUtil.subscriptionLevelForSubscription(subscriptionLevels: subscriptionLevels, subscription: currentSubscription)
            let subscriptionRedemptionFailureReason = DonationViewsUtil.getSubscriptionRedemptionFailureReason(subscription: currentSubscription)
            section.add(DonationViewsUtil.getMySupportCurrentSubscriptionTableItem(subscriptionLevel: subscriptionLevel,
                                                                                   currentSubscription: currentSubscription,
                                                                                   subscriptionRedemptionFailureReason: subscriptionRedemptionFailureReason,
                                                                                   statusLabelToModify: statusLabel))
            statusLabel.delegate = self

            section.add(.disclosureItem(
                icon: .settingsManage,
                name: NSLocalizedString("DONATION_VIEW_MANAGE_SUBSCRIPTION", comment: "Title for the 'Manage Subscription' button on the donation screen"),
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "manageSubscription"),
                actionBlock: { [weak self] in
                    self?.showSubscriptionViewController()
                }
            ))

            section.add(.disclosureItem(
                icon: .settingsBadges,
                name: NSLocalizedString("DONATION_VIEW_MANAGE_BADGES", comment: "Title for the 'Badges' button on the donation screen"),
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "badges"),
                actionBlock: { [weak self] in
                    guard let self = self else { return }
                    let vc = BadgeConfigurationViewController(fetchingDataFromLocalProfileWithDelegate: self)
                    self.navigationController?.pushViewController(vc, animated: true)
                }
            ))

            return section
        }()
        result.append(currentSubscriptionSection)

        if let otherWaysToGiveSection = getOtherWaysToGiveSection() {
            result.append(otherWaysToGiveSection)
        }

        let moreSection: OWSTableSection = {
            let section = OWSTableSection(title: NSLocalizedString("DONATION_VIEW_MORE_SECTION_TITLE",
                                                                   comment: "Title for the 'more' section on the donation screen"))

            // It should be unusual to hit this case—having a subscription but no receipts—
            // but it is possible. For example, it can happen if someone started a subscription
            // before a receipt was saved.
            if hasAnyDonationReceipts {
                section.add(donationReceiptsItem(profileBadgeLookup: profileBadgeLookup))
            }

            section.add(.disclosureItem(
                icon: .settingsHelp,
                name: NSLocalizedString("DONATION_VIEW_SUBSCRIPTION_FAQ",
                                        comment: "Title for the 'Subscription FAQ' button on the donation screen"),
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "subscriptionFAQ"),
                actionBlock: { [weak self] in
                    let vc = SFSafariViewController(url: SupportConstants.subscriptionFAQURL)
                    self?.present(vc, animated: true, completion: nil)
                }
            ))
            return section
        }()
        result.append(moreSection)

        return result
    }

    private func hasNoActiveSubscriptionSections(hasAnyDonationReceipts: Bool,
                                                 profileBadgeLookup: ProfileBadgeLookup) -> [OWSTableSection] {
        var result = [OWSTableSection]()

        let heroSection: OWSTableSection = {
            let section = OWSTableSection()
            section.add(.init(customCellBlock: { [weak self] in
                let cell = OWSTableItem.newCell()

                guard let self = self else { return cell }

                let heroStack = self.heroHeaderView()
                cell.addSubview(heroStack)
                heroStack.autoPinEdgesToSuperviewMargins(with: UIEdgeInsets(hMargin: 0, vMargin: 6))
                heroStack.spacing = 20

                let button: OWSButton
                if DonationUtilities.isApplePayAvailable {
                    let title = NSLocalizedString("DONATION_VIEW_MAKE_A_MONTHLY_DONATION",
                                                  comment: "Text of the 'make a monthly donation' button on the donation screen")
                    button = OWSButton(title: title) { [weak self] in
                        self?.showSubscriptionViewController()
                    }
                } else {
                    let title = NSLocalizedString("DONATION_VIEW_DONATE_TO_SIGNAL",
                                                  comment: "Text of the 'donate to signal' button on the donation screen")
                    button = OWSButton(title: title) {
                        DonationViewsUtil.openDonateWebsite()
                    }
                }
                button.dimsWhenHighlighted = true
                button.layer.cornerRadius = 8
                button.backgroundColor = .ows_accentBlue
                button.titleLabel?.font = UIFont.ows_dynamicTypeBody.ows_semibold
                heroStack.addArrangedSubview(button)
                button.autoSetDimension(.height, toSize: 48)
                button.autoPinWidthToSuperviewMargins()

                return cell
            }))
            return section
        }()
        result.append(heroSection)

        if let otherWaysToGiveSection = getOtherWaysToGiveSection() {
            result.append(otherWaysToGiveSection)
        }

        if hasAnyDonationReceipts {
            result.append(receiptsSection(profileBadgeLookup: profileBadgeLookup))
        }

        return result
    }

    private func heroHeaderView() -> UIStackView {
        let heroView = DonationHeroView(avatarView: avatarView)
        heroView.delegate = self
        return heroView
    }

    private func getOtherWaysToGiveSection() -> OWSTableSection? {
        let title = NSLocalizedString("DONATION_VIEW_OTHER_WAYS_TO_GIVE_TITLE",
                                                         comment: "Title for the 'other ways to give' section on the donation view")
        let section = OWSTableSection(title: title)
        section.add(.disclosureItem(
            icon: .settingsBoost,
            name: NSLocalizedString("DONATION_VIEW_ONE_TIME_DONATION",
                                    comment: "Title for the 'one-time donation' link in the donation view"),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "one-time donation"),
            actionBlock: { [weak self] in
                if DonationUtilities.isApplePayAvailable {
                    let vc = BoostViewController()
                    self?.navigationController?.pushViewController(vc, animated: true)
                } else {
                    DonationViewsUtil.openDonateWebsite()
                }
            }
        ))

        if DonationUtilities.canSendGiftBadges {
            section.add(.disclosureItem(
                icon: .settingsGift,
                name: NSLocalizedString("DONATION_VIEW_GIFT", comment: "Title for the 'Gift a Badge' link in the donation view"),
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "giftBadge"),
                actionBlock: { [weak self] in
                    guard let self = self else { return }

                    // It's possible (but unlikely) to lose the ability to send gifts while this button is
                    // visible. For example, Apple Pay could be disabled in parental controls after this
                    // screen is opened.
                    guard DonationUtilities.canSendGiftBadges else {
                        // We might want to show a better UI here, but making the button a no-op is
                        // preferable to launching the view controller.
                        return
                    }

                    let vc = BadgeGiftingChooseBadgeViewController()
                    self.navigationController?.pushViewController(vc, animated: true)
                }
            ))
        }

        return section
    }

    private func receiptsSection(profileBadgeLookup: ProfileBadgeLookup) -> OWSTableSection {
        OWSTableSection(title: NSLocalizedString("DONATION_VIEW_RECEIPTS_SECTION_TITLE",
                                                 comment: "Title for the 'receipts' section on the donation screen"),
                        items: [donationReceiptsItem(profileBadgeLookup: profileBadgeLookup)])
    }

    private func donationReceiptsItem(profileBadgeLookup: ProfileBadgeLookup) -> OWSTableItem {
        .disclosureItem(
            icon: .settingsReceipts,
            name: NSLocalizedString("DONATION_RECEIPTS", comment: "Title of view where you can see all of your donation receipts, or button to take you there"),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "subscriptionReceipts"),
            actionBlock: { [weak self] in
                let vc = DonationReceiptsViewController(profileBadgeLookup: profileBadgeLookup)
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        )
    }

    // MARK: - Showing subscription view controller

    private func showSubscriptionViewController() {
        self.navigationController?.pushViewController(SubscriptionViewController(), animated: true)
    }

    // MARK: - Gift Badge Expiration

    public static func shouldShowExpiredGiftBadgeSheetWithSneakyTransaction() -> Bool {
        let expiredGiftBadgeID = self.databaseStorage.read { transaction in
            SubscriptionManager.mostRecentlyExpiredGiftBadgeID(transaction: transaction)
        }
        guard let expiredGiftBadgeID = expiredGiftBadgeID, GiftBadgeIds.contains(expiredGiftBadgeID) else {
            return false
        }
        return true
    }

    private func showGiftBadgeExpirationSheetIfNeeded() {
        guard Self.shouldShowExpiredGiftBadgeSheetWithSneakyTransaction() else {
            return
        }
        Logger.info("[Gifting] Preparing to show gift badge expiration sheet...")
        firstly {
            SubscriptionManager.getCachedBadge(level: .giftBadge(.signalGift)).fetchIfNeeded()
        }.done { [weak self] cachedValue in
            guard let self = self else { return }
            guard UIApplication.shared.frontmostViewController == self else { return }
            guard case .profileBadge(let profileBadge) = cachedValue else {
                // The server confirmed this badge doesn't exist. This shouldn't happen,
                // but clear the flag so that we don't keep trying.
                Logger.warn("[Gifting] Clearing expired badge ID because the server said it didn't exist")
                SubscriptionManager.clearMostRecentlyExpiredBadgeIDWithSneakyTransaction()
                return
            }

            let hasCurrentSubscription = self.databaseStorage.read { transaction -> Bool in
                self.subscriptionManager.hasCurrentSubscription(transaction: transaction)
            }
            Logger.info("[Gifting] Showing badge gift expiration sheet (hasCurrentSubscription: \(hasCurrentSubscription))")
            let sheet = BadgeExpirationSheet(badge: profileBadge, mode: .giftBadgeExpired(hasCurrentSubscription: hasCurrentSubscription))
            sheet.delegate = self
            self.present(sheet, animated: true)

            // We've shown it, so don't show it again.
            SubscriptionManager.clearMostRecentlyExpiredGiftBadgeIDWithSneakyTransaction()
        }.cauterize()
    }
}

// MARK: - Badge Expiration Delegate

extension DonationViewController: BadgeExpirationSheetDelegate {
    func badgeExpirationSheetActionTapped(_ action: BadgeExpirationSheetAction) {
        switch action {
        case .dismiss:
            break
        case .openSubscriptionsView:
            self.showSubscriptionViewController()
        case .openBoostView:
            owsFailDebug("not supported")
        }
    }
}

// MARK: - Badge management delegate

extension DonationViewController: BadgeConfigurationDelegate {
    func badgeConfiguration(_ vc: BadgeConfigurationViewController, didCompleteWithBadgeSetting setting: BadgeConfiguration) {
        if !self.reachabilityManager.isReachable {
            OWSActionSheets.showErrorAlert(
                message: NSLocalizedString("PROFILE_VIEW_NO_CONNECTION",
                                           comment: "Error shown when the user tries to update their profile when the app is not connected to the internet."))
            return
        }

        firstly { () -> Promise<Void> in
            let snapshot = profileManagerImpl.localProfileSnapshot(shouldIncludeAvatar: true)
            let allBadges = snapshot.profileBadgeInfo ?? []
            let oldVisibleBadges = allBadges.filter { $0.isVisible ?? true }
            let oldVisibleBadgeIds = oldVisibleBadges.map { $0.badgeId }

            let newVisibleBadgeIds: [String]
            switch setting {
            case .doNotDisplayPublicly:
                newVisibleBadgeIds = []
            case .display(featuredBadge: let newFeaturedBadge):
                let allBadgeIds = allBadges.map { $0.badgeId }
                guard allBadgeIds.contains(newFeaturedBadge.badgeId) else {
                    throw OWSAssertionError("Invalid badge")
                }
                newVisibleBadgeIds = [newFeaturedBadge.badgeId] + allBadgeIds.filter { $0 != newFeaturedBadge.badgeId }
            }

            if oldVisibleBadgeIds != newVisibleBadgeIds {
                Logger.info("[Donations] Updating visible badges from \(oldVisibleBadgeIds) to \(newVisibleBadgeIds)")
                vc.showDismissalActivity = true
                return OWSProfileManager.updateLocalProfilePromise(
                    profileGivenName: snapshot.givenName,
                    profileFamilyName: snapshot.familyName,
                    profileBio: snapshot.bio,
                    profileBioEmoji: snapshot.bioEmoji,
                    profileAvatarData: snapshot.avatarData,
                    visibleBadgeIds: newVisibleBadgeIds,
                    userProfileWriter: .localUser)
            } else {
                return Promise.value(())
            }
        }.then(on: .global()) { () -> Promise<Void> in
            let displayBadgesOnProfile: Bool
            switch setting {
            case .doNotDisplayPublicly:
                displayBadgesOnProfile = false
            case .display:
                displayBadgesOnProfile = true
            }

            return Self.databaseStorage.writePromise { transaction in
                Self.subscriptionManager.setDisplayBadgesOnProfile(
                    displayBadgesOnProfile,
                    updateStorageService: true,
                    transaction: transaction
                )
            }.asVoid()
        }.done {
            self.navigationController?.popViewController(animated: true)
        }.catch { error in
            owsFailDebug("Failed to update profile: \(error)")
            self.navigationController?.popViewController(animated: true)
        }
    }

    func badgeConfirmationDidCancel(_: BadgeConfigurationViewController) {
        self.navigationController?.popViewController(animated: true)
    }
}

// MARK: - Donation hero delegate

extension DonationViewController: DonationHeroViewDelegate {
    func present(readMoreSheet: DonationReadMoreSheetViewController) {
        present(readMoreSheet, animated: true)
    }
}

// MARK: - Badge can't be added

extension DonationViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        if textView == statusLabel {
            let currentSubscription: Subscription?
            switch state {
            case .initializing, .loading, .loadFailed:
                currentSubscription = nil
            case let .loaded(_, _, _, subscription):
                currentSubscription = subscription
            }

            DonationViewsUtil.presentBadgeCantBeAddedSheet(viewController: self,
                                                           currentSubscription: currentSubscription)
        }
        return false
    }
}
