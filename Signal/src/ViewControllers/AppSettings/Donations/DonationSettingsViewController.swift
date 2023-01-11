//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SafariServices
import SignalMessaging
import SignalUI
import UIKit

class DonationSettingsViewController: OWSTableViewController2 {
    private enum State {
        enum SubscriptionStatus {
            case loadFailed
            case noSubscription
            case hasSubscription(
                subscription: Subscription,
                // If this is nil, the server has sent us bad data.
                subscriptionLevel: SubscriptionLevel?,
                isSubscriptionRedemptionPending: Bool,
                subscriptionRedemptionFailureReason: SubscriptionRedemptionFailureReason
            )
        }

        case initializing
        case loading
        case loadFinished(
            subscriptionStatus: SubscriptionStatus,
            profileBadgeLookup: ProfileBadgeLookup,
            hasAnyBadges: Bool,
            hasAnyDonationReceipts: Bool
        )

        public var currentSubscription: Subscription? {
            switch self {
            case let .loadFinished(subscriptionStatus, _, _, _):
                switch subscriptionStatus {
                case let .hasSubscription(subscription, _, _, _):
                    return subscription
                default:
                    return nil
                }
            default:
                return nil
            }
        }

        public var debugDescription: String {
            switch self {
            case .initializing:
                return "initializing"
            case .loading:
                return "loading"
            case .loadFinished:
                return "loadFinished"
            }
        }
    }

    private var state: State = .initializing {
        didSet {
            Logger.info("[Donations] DonationSettingsViewController state changed to \(state.debugDescription)")
            updateTableContents()
        }
    }

    private var avatarView: ConversationAvatarView = DonationViewsUtil.avatarView()

    private lazy var statusLabel = LinkingTextView()

    private static var canDonateInAnyWay: Bool {
        DonationUtilities.canDonateInAnyWay(localNumber: tsAccountManager.localNumber)
    }

    private static var canSendGiftBadges: Bool {
        RemoteConfig.canSendGiftBadges &&
        DonationUtilities.canDonate(inMode: .gift, localNumber: tsAccountManager.localNumber)
    }

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
        case .initializing, .loadFinished:
            self.state = .loading
            loadState().done { self.state = $0 }
        }
    }

    private func loadState() -> Guarantee<State> {
        typealias ValuesFromDatabase = (
            subscriberID: Data?,
            isSubscriptionRedemptionPendingInDatabase: Bool,
            hasAnyDonationReceipts: Bool
        )

        let (
            subscriberID,
            isSubscriptionRedemptionPendingInDatabase,
            hasAnyDonationReceipts
        ) = databaseStorage.read { transaction -> ValuesFromDatabase in
            let subscriberID = SubscriptionManager.getSubscriberID(transaction: transaction)
            return (
                subscriberID: subscriberID,
                isSubscriptionRedemptionPendingInDatabase: (
                    subscriberID != nil && (
                        SubscriptionManager.subscriptionJobQueue.hasPendingJobs(transaction: transaction) ||
                        SubscriptionManager.subscriptionJobQueue.runningOperations.get().count != 0
                    )
                ),
                hasAnyDonationReceipts: DonationReceiptFinder.hasAny(transaction: transaction)
            )
        }

        let hasAnyBadges: Bool = Self.hasAnyBadges()

        let subscriptionLevelsPromise = DonationViewsUtil.loadSubscriptionLevels(badgeStore: self.profileManager.badgeStore)
        let currentSubscriptionPromise = DonationViewsUtil.loadCurrentSubscription(subscriberID: subscriberID)
        let profileBadgeLookupPromise = loadProfileBadgeLookup(hasAnyDonationReceipts: hasAnyDonationReceipts)

        return profileBadgeLookupPromise.then { profileBadgeLookup -> Guarantee<State> in
            subscriptionLevelsPromise.then { subscriptionLevels -> Promise<State> in
                currentSubscriptionPromise.then { currentSubscription -> Guarantee<State> in
                    let result: State = .loadFinished(
                        subscriptionStatus: {
                            guard let currentSubscription = currentSubscription else {
                                return .noSubscription
                            }
                            return .hasSubscription(
                                subscription: currentSubscription,
                                subscriptionLevel: DonationViewsUtil.subscriptionLevelForSubscription(
                                    subscriptionLevels: subscriptionLevels,
                                    subscription: currentSubscription
                                ),
                                isSubscriptionRedemptionPending: isSubscriptionRedemptionPendingInDatabase,
                                subscriptionRedemptionFailureReason: DonationViewsUtil.getSubscriptionRedemptionFailureReason(
                                    subscription: currentSubscription
                                )
                            )
                        }(),
                        profileBadgeLookup: profileBadgeLookup,
                        hasAnyBadges: hasAnyBadges,
                        hasAnyDonationReceipts: hasAnyDonationReceipts
                    )
                    return Guarantee.value(result)
                }
            }.recover { error -> Guarantee<State> in
                Logger.warn("[Donations] \(error)")
                owsFailDebugUnlessNetworkFailure(error)
                let result: State = .loadFinished(
                    subscriptionStatus: .loadFailed,
                    profileBadgeLookup: profileBadgeLookup,
                    hasAnyBadges: hasAnyBadges,
                    hasAnyDonationReceipts: hasAnyDonationReceipts
                )
                return Guarantee.value(result)
            }
        }
    }

    private static func hasAnyBadges() -> Bool {
        let snapshot = profileManagerImpl.localProfileSnapshot(shouldIncludeAvatar: false)
        let allBadges = snapshot.profileBadgeInfo ?? []
        return !allBadges.isEmpty
    }

    private func loadProfileBadgeLookup(hasAnyDonationReceipts: Bool) -> Guarantee<ProfileBadgeLookup> {
        let willEverShowBadges = hasAnyDonationReceipts
        guard willEverShowBadges else { return Guarantee.value(ProfileBadgeLookup()) }

        return firstly { () -> Promise<SubscriptionManager.DonationConfiguration> in
            SubscriptionManager.fetchDonationConfiguration()
        }.map { donationConfiguration -> ProfileBadgeLookup in
            ProfileBadgeLookup(
                boostBadge: donationConfiguration.boost.badge,
                giftBadge: donationConfiguration.gift.badge,
                subscriptionLevels: donationConfiguration.subscription.levels
            )
        }.recover { error -> Guarantee<ProfileBadgeLookup> in
            Logger.warn("[Donations] Failed to fetch donation configuration \(error). Proceeding without it, as it is only cosmetic here.")
            return .value(ProfileBadgeLookup(
                boostBadge: nil,
                giftBadge: nil,
                subscriptionLevels: []
            ))
        }.then { profileBadgeLookup in
            profileBadgeLookup.attemptToPopulateBadgeAssets(
                populateAssetsOnBadge: self.profileManager.badgeStore.populateAssetsOnBadge
            ).map { profileBadgeLookup }
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

    /// Will there be anything other than the "Donate" button? Can be used to skip this screen.
    ///
    /// Once gift badges are added (or anything else that's always shown), we can remove this.
    static func hasAnythingToShowWithSneakyTransaction() -> Bool {
        (
            canSendGiftBadges ||
            hasAnyBadges() ||
            databaseStorage.read { DonationReceiptFinder.hasAny(transaction: $0) }
        )
    }

    // MARK: - Table contents

    private func updateTableContents() {
        let contents = OWSTableContents()

        contents.addSection(heroSection())

        switch state {
        case .initializing, .loading:
            contents.addSection(loadingSection())
        case let .loadFinished(subscriptionStatus, profileBadgeLookup, hasAnyBadges, hasAnyDonationReceipts):
            let sections = loadFinishedSections(
                subscriptionStatus: subscriptionStatus,
                profileBadgeLookup: profileBadgeLookup,
                hasAnyBadges: hasAnyBadges,
                hasAnyDonationReceipts: hasAnyDonationReceipts
            )
            contents.addSections(sections)
        }

        self.contents = contents
    }

    private func heroSection() -> OWSTableSection {
        OWSTableSection(items: [.init(customCellBlock: { [weak self] in
            let cell = OWSTableItem.newCell()
            guard let self = self else { return cell }
            cell.layoutMargins = OWSTableViewController2.cellOuterInsets(in: self.view)
            cell.contentView.layoutMargins = .zero

            let heroStack = DonationHeroView(avatarView: self.avatarView)
            heroStack.delegate = self
            let buttonTitle = NSLocalizedString(
                "DONATION_SCREEN_DONATE_BUTTON",
                comment: "On the donation settings screen, tapping this button will take the user to a screen where they can donate."
            )
            let button = OWSButton(title: buttonTitle) { [weak self] in
                if Self.canDonateInAnyWay {
                    self?.showDonateViewController(preferredDonateMode: .oneTime)
                } else {
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

            cell.contentView.addSubview(heroStack)
            heroStack.autoPinEdgesToSuperviewMargins(with: UIEdgeInsets(hMargin: 0, vMargin: 6))

            return cell
        })])
    }

    private func loadingSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.add(AppSettingsViewsUtil.loadingTableItem(cellOuterInsets: cellOuterInsets))
        section.hasBackground = false
        return section
    }

    private func loadFinishedSections(
        subscriptionStatus: State.SubscriptionStatus,
        profileBadgeLookup: ProfileBadgeLookup,
        hasAnyBadges: Bool,
        hasAnyDonationReceipts: Bool
    ) -> [OWSTableSection] {
        [
            mySupportSection(subscriptionStatus: subscriptionStatus, hasAnyBadges: hasAnyBadges),
            otherWaysToGiveSection(),
            moreSection(
                subscriptionStatus: subscriptionStatus,
                profileBadgeLookup: profileBadgeLookup,
                hasAnyDonationReceipts: hasAnyDonationReceipts
            )
        ].compacted()
    }

    private func mySupportSection(
        subscriptionStatus: State.SubscriptionStatus,
        hasAnyBadges: Bool
    ) -> OWSTableSection? {
        let title = NSLocalizedString("DONATION_VIEW_MY_SUPPORT_TITLE",
                                      comment: "Title for the 'my support' section in the donation view")
        let section = OWSTableSection(title: title)

        switch subscriptionStatus {
        case .loadFailed:
            section.add(.label(withText: NSLocalizedString(
                "DONATION_VIEW_LOAD_FAILED",
                comment: "Text that's shown when the donation view fails to load data, probably due to network failure"
            )))
        case .noSubscription:
            break
        case let .hasSubscription(subscription, subscriptionLevel, isSubscriptionRedemptionPending, subscriptionRedemptionFailureReason):
            section.add(DonationViewsUtil.getMySupportCurrentSubscriptionTableItem(subscriptionLevel: subscriptionLevel,
                                                                                   currentSubscription: subscription,
                                                                                   isSubscriptionRedemptionPending: isSubscriptionRedemptionPending,
                                                                                   subscriptionRedemptionFailureReason: subscriptionRedemptionFailureReason,
                                                                                   statusLabelToModify: statusLabel))
            statusLabel.delegate = self

            section.add(.disclosureItem(
                icon: .settingsManage,
                name: NSLocalizedString("DONATION_VIEW_MANAGE_SUBSCRIPTION", comment: "Title for the 'Manage Subscription' button on the donation screen"),
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "manageSubscription"),
                actionBlock: { [weak self] in
                    self?.showDonateViewController(preferredDonateMode: .monthly)
                }
            ))
        }

        if hasAnyBadges {
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
        }

        guard section.itemCount() > 0 else {
            return nil
        }
        return section
    }

    private func otherWaysToGiveSection() -> OWSTableSection? {
        guard Self.canSendGiftBadges else { return nil }

        let title = NSLocalizedString("DONATION_VIEW_OTHER_WAYS_TO_GIVE_TITLE",
                                                         comment: "Title for the 'other ways to give' section on the donation view")
        let section = OWSTableSection(title: title)

        section.add(.disclosureItem(
            icon: .settingsGift,
            name: NSLocalizedString(
                "DONATION_VIEW_DONATE_ON_BEHALF_OF_A_FRIEND",
                comment: "Title for the \"donate for a friend\" button on the donation view."
            ),
            accessibilityIdentifier: UIView.accessibilityIdentifier(
                in: self,
                name: "donationOnBehalfOfAFriend"
            ),
            actionBlock: { [weak self] in
                guard let self = self else { return }

                // It's possible (but unlikely) to lose the ability to send gifts while this button is
                // visible. For example, Apple Pay could be disabled in parental controls after this
                // screen is opened.
                guard Self.canSendGiftBadges else {
                    // We might want to show a better UI here, but making the button a no-op is
                    // preferable to launching the view controller.
                    return
                }

                let vc = BadgeGiftingChooseBadgeViewController()
                self.navigationController?.pushViewController(vc, animated: true)
            }
        ))

        return section
    }

    private func moreSection(
        subscriptionStatus: State.SubscriptionStatus,
        profileBadgeLookup: ProfileBadgeLookup,
        hasAnyDonationReceipts: Bool
    ) -> OWSTableSection? {
        let section = OWSTableSection(title: NSLocalizedString(
            "DONATION_VIEW_MORE_SECTION_TITLE",
            comment: "Title for the 'more' section on the donation screen"
        ))

        // It should be unusual to hit this case—having a subscription but no receipts—
        // but it is possible. For example, it can happen if someone started a subscription
        // before a receipt was saved.
        if hasAnyDonationReceipts {
            section.add(donationReceiptsItem(profileBadgeLookup: profileBadgeLookup))
        }

        let shouldShowSubscriptionFaqLink: Bool = {
            if hasAnyDonationReceipts { return true }
            switch subscriptionStatus {
            case .loadFailed, .hasSubscription: return true
            case .noSubscription: return false
            }
        }()
        if shouldShowSubscriptionFaqLink {
            section.add(.disclosureItem(
                icon: .settingsHelp,
                name: NSLocalizedString(
                    "DONATION_VIEW_SUBSCRIPTION_FAQ",
                    comment: "Title for the 'Subscription FAQ' button on the donation screen"
                ),
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "subscriptionFAQ"),
                actionBlock: { [weak self] in
                    let vc = SFSafariViewController(url: SupportConstants.subscriptionFAQURL)
                    self?.present(vc, animated: true, completion: nil)
                }
            ))
        }

        guard section.itemCount() > 0 else {
            return nil
        }

        return section
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

    private func showDonateViewController(preferredDonateMode: DonateViewController.DonateMode) {
        let donateVc = DonateViewController(preferredDonateMode: preferredDonateMode) { [weak self] finishResult in
            guard let self = self else { return }
            switch finishResult {
            case let .completedDonation(_, thanksSheet):
                self.navigationController?.popToViewController(self, animated: true) { [weak self] in
                    self?.present(thanksSheet, animated: true)
                }
            case let .monthlySubscriptionCancelled(_, toastText):
                self.navigationController?.popToViewController(self, animated: true) { [weak self] in
                    guard let self = self else { return }
                    self.view.presentToast(text: toastText, fromViewController: self)
                }
            }

        }

        self.navigationController?.pushViewController(donateVc, animated: true)
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

extension DonationSettingsViewController: BadgeExpirationSheetDelegate {
    func badgeExpirationSheetActionTapped(_ action: BadgeExpirationSheetAction) {
        switch action {
        case .dismiss:
            break
        case .openDonationView:
            self.showDonateViewController(preferredDonateMode: .oneTime)
        }
    }
}

// MARK: - Badge management delegate

extension DonationSettingsViewController: BadgeConfigurationDelegate {
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

extension DonationSettingsViewController: DonationHeroViewDelegate {
    func present(readMoreSheet: DonationReadMoreSheetViewController) {
        present(readMoreSheet, animated: true)
    }
}

// MARK: - Badge can't be added

extension DonationSettingsViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        if textView == statusLabel {
            DonationViewsUtil.presentBadgeCantBeAddedSheet(
                from: self,
                currentSubscription: state.currentSubscription
            )
        }
        return false
    }
}
