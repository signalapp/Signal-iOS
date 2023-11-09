//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SafariServices
import SignalCoreKit
import SignalMessaging
import SignalUI
import UIKit

class DonationSettingsViewController: OWSTableViewController2 {
    enum State {
        enum SubscriptionStatus {
            case loadFailed

            case noSubscription

            /// The user has a subscription, which may be active or inactive.
            ///
            /// Both active and inactive subscriptions may be in a "processing"
            /// state. Inactive subscriptions may also have a charge failure
            /// if payment failed.
            ///
            /// The receipt credential request error may be present for either
            /// active or inactive subscriptions. In most cases, it will reflect
            /// either a processing or failed payment – state that is available
            /// from the subscription itself – but if something rare went wrong
            /// it may also reflect an error external to the subscription.
            case hasSubscription(
                subscription: Subscription,
                subscriptionLevel: SubscriptionLevel?,
                previouslyHadActiveSubscription: Bool,
                receiptCredentialRequestError: SubscriptionReceiptCredentialRequestError?
            )
        }

        case initializing
        case loading
        case loadFinished(
            subscriptionStatus: SubscriptionStatus,
            oneTimeBoostReceiptCredentialRequestError: SubscriptionReceiptCredentialRequestError?,
            profileBadgeLookup: ProfileBadgeLookup,
            hasAnyBadges: Bool,
            hasAnyDonationReceipts: Bool
        )

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

    private static var canDonateInAnyWay: Bool {
        DonationUtilities.canDonateInAnyWay(
            localNumber: DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.phoneNumber
        )
    }

    private static var canSendGiftBadges: Bool {
        DonationUtilities.canDonate(
            inMode: .gift,
            localNumber: DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.phoneNumber
        )
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setUpAvatarView()
        title = OWSLocalizedString("DONATION_VIEW_TITLE", comment: "Title on the 'Donate to Signal' screen")
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
        let subscriberID = databaseStorage.read { SubscriptionManagerImpl.getSubscriberID(transaction: $0) }
        guard let subscriberID = subscriberID else { return }

        UIPasteboard.general.string = subscriberID.asBase64Url

        presentToast(text: OWSLocalizedString("SUBSCRIPTION_SUBSCRIBER_ID_COPIED_TO_CLIPBOARD",
                                             comment: "Toast indicating that the user has copied their subscriber ID."))
    }

    // MARK: - Data loading

    func loadAndUpdateState() -> Guarantee<Void> {
        switch state {
        case .loading:
            owsFailDebug("Already loading!")
            return .value(())
        case .initializing, .loadFinished:
            self.state = .loading
            return loadState().done { self.state = $0 }
        }
    }

    private func loadState() -> Guarantee<State> {
        let (
            subscriberID,
            hasEverRedeemedRecurringSubscriptionBadge,
            recurringSubscriptionReceiptCredentialRequestError,
            oneTimeBoostReceiptCredentialRequestError,
            hasAnyDonationReceipts
        ) = databaseStorage.read { tx in
            let resultStore = DependenciesBridge.shared.subscriptionReceiptCredentialResultStore

            return (
                subscriberID: SubscriptionManagerImpl.getSubscriberID(transaction: tx),
                hasEverRedeemedRecurringSubscriptionBadge: SubscriptionManagerImpl.getHasEverRedeemedRecurringSubscriptionBadge(tx: tx),
                recurringSubscriptionReceiptCredentialRequestError: resultStore.getRequestError(
                    errorMode: .recurringSubscription, tx: tx.asV2Read
                ),
                oneTimeBoostReceiptCredentialRequestError: resultStore.getRequestError(
                    errorMode: .oneTimeBoost, tx: tx.asV2Read
                ),
                hasAnyDonationReceipts: DonationReceiptFinder.hasAny(transaction: tx)
            )
        }

        let hasAnyBadges: Bool = Self.hasAnyBadges()

        let subscriptionLevelsPromise = DonationViewsUtil.loadSubscriptionLevels(badgeStore: self.profileManager.badgeStore)
        let currentSubscriptionPromise = DonationViewsUtil.loadCurrentSubscription(subscriberID: subscriberID)
        let profileBadgeLookupPromise = loadProfileBadgeLookup()

        return profileBadgeLookupPromise.then { profileBadgeLookup -> Guarantee<State> in
            subscriptionLevelsPromise.then { subscriptionLevels -> Promise<State> in
                currentSubscriptionPromise.then { currentSubscription -> Guarantee<State> in
                    let result: State = .loadFinished(
                        subscriptionStatus: {
                            guard let currentSubscription else {
                                return .noSubscription
                            }

                            return .hasSubscription(
                                subscription: currentSubscription,
                                subscriptionLevel: DonationViewsUtil.subscriptionLevelForSubscription(
                                    subscriptionLevels: subscriptionLevels,
                                    subscription: currentSubscription
                                ),
                                previouslyHadActiveSubscription: hasEverRedeemedRecurringSubscriptionBadge,
                                receiptCredentialRequestError: recurringSubscriptionReceiptCredentialRequestError
                            )
                        }(),
                        oneTimeBoostReceiptCredentialRequestError: oneTimeBoostReceiptCredentialRequestError,
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
                    oneTimeBoostReceiptCredentialRequestError: oneTimeBoostReceiptCredentialRequestError,
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

    private func loadProfileBadgeLookup() -> Guarantee<ProfileBadgeLookup> {
        return firstly { () -> Promise<SubscriptionManagerImpl.DonationConfiguration> in
            SubscriptionManagerImpl.fetchDonationConfiguration()
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
                if let address = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)?.aciAddress {
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
        let contents = OWSTableContents()

        contents.add(heroSection())

        switch state {
        case .initializing, .loading:
            contents.add(loadingSection())
        case let .loadFinished(
            subscriptionStatus,
            oneTimeBoostReceiptCredentialRequestError,
            profileBadgeLookup,
            hasAnyBadges,
            hasAnyDonationReceipts
        ):
            let sections = loadFinishedSections(
                subscriptionStatus: subscriptionStatus,
                profileBadgeLookup: profileBadgeLookup,
                oneTimeBoostReceiptCredentialRequestError: oneTimeBoostReceiptCredentialRequestError,
                hasAnyBadges: hasAnyBadges,
                hasAnyDonationReceipts: hasAnyDonationReceipts
            )
            contents.add(sections: sections)
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
            let buttonTitle = OWSLocalizedString(
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
            button.titleLabel?.font = UIFont.dynamicTypeBody.semibold()
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
        oneTimeBoostReceiptCredentialRequestError: SubscriptionReceiptCredentialRequestError?,
        hasAnyBadges: Bool,
        hasAnyDonationReceipts: Bool
    ) -> [OWSTableSection] {
        [
            mySupportSection(
                subscriptionStatus: subscriptionStatus,
                profileBadgeLookup: profileBadgeLookup,
                oneTimeBoostReceiptCredentialRequestError: oneTimeBoostReceiptCredentialRequestError,
                hasAnyBadges: hasAnyBadges
            ),
            otherWaysToDonateSection(),
            moreSection(
                subscriptionStatus: subscriptionStatus,
                profileBadgeLookup: profileBadgeLookup,
                hasAnyDonationReceipts: hasAnyDonationReceipts
            )
        ].compacted()
    }

    private func otherWaysToDonateSection() -> OWSTableSection? {
        guard Self.canSendGiftBadges else { return nil }

        let title = OWSLocalizedString(
            "DONATION_VIEW_OTHER_WAYS_TO_DONATE_TITLE",
            comment: "Title for the \"other ways to donate\" section on the donation view."
        )
        let section = OWSTableSection(title: title)

        section.add(.disclosureItem(
            icon: .donateGift,
            name: OWSLocalizedString(
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
        let section = OWSTableSection(title: OWSLocalizedString(
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
                name: OWSLocalizedString(
                    "DONATION_VIEW_DONOR_FAQ",
                    comment: "Title for the 'Donor FAQ' button on the donation screen"
                ),
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "donorFAQ"),
                actionBlock: { [weak self] in
                    let vc = SFSafariViewController(url: SupportConstants.donorFAQURL)
                    self?.present(vc, animated: true, completion: nil)
                }
            ))
        }

        guard section.itemCount > 0 else {
            return nil
        }

        return section
    }

    private func donationReceiptsItem(profileBadgeLookup: ProfileBadgeLookup) -> OWSTableItem {
        .disclosureItem(
            icon: .donateReceipts,
            name: OWSLocalizedString("DONATION_RECEIPTS", comment: "Title of view where you can see all of your donation receipts, or button to take you there"),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "subscriptionReceipts"),
            actionBlock: { [weak self] in
                let vc = DonationReceiptsViewController(profileBadgeLookup: profileBadgeLookup)
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        )
    }

    // MARK: - Showing subscription view controller

    func showDonateViewController(preferredDonateMode: DonateViewController.DonateMode) {
        let donateVc = DonateViewController(preferredDonateMode: preferredDonateMode) { [weak self] finishResult in
            guard let self = self else { return }
            switch finishResult {
            case let .completedDonation(_, receiptCredentialSuccessMode):
                self.navigationController?.popToViewController(self, animated: true) { [weak self] in
                    guard
                        let self,
                        let badgeThanksSheetPresenter = BadgeThanksSheetPresenter.loadWithSneakyTransaction(
                            successMode: receiptCredentialSuccessMode
                        )
                    else { return }

                    badgeThanksSheetPresenter.presentBadgeThanksAndClearSuccess(
                        fromViewController: self
                    )
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
            SubscriptionManagerImpl.mostRecentlyExpiredGiftBadgeID(transaction: transaction)
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
            SubscriptionManagerImpl.getCachedBadge(level: .giftBadge(.signalGift)).fetchIfNeeded()
        }.done { [weak self] cachedValue in
            guard let self = self else { return }
            guard UIApplication.shared.frontmostViewController == self else { return }
            guard case .profileBadge(let profileBadge) = cachedValue else {
                // The server confirmed this badge doesn't exist. This shouldn't happen,
                // but clear the flag so that we don't keep trying.
                Logger.warn("[Gifting] Clearing expired badge ID because the server said it didn't exist")
                SubscriptionManagerImpl.clearMostRecentlyExpiredBadgeIDWithSneakyTransaction()
                return
            }

            let hasCurrentSubscription = self.databaseStorage.read { transaction -> Bool in
                self.subscriptionManager.hasCurrentSubscription(transaction: transaction)
            }
            Logger.info("[Gifting] Showing badge gift expiration sheet (hasCurrentSubscription: \(hasCurrentSubscription))")
            let sheet = BadgeIssueSheet(badge: profileBadge, mode: .giftBadgeExpired(hasCurrentSubscription: hasCurrentSubscription))
            sheet.delegate = self
            self.present(sheet, animated: true)

            // We've shown it, so don't show it again.
            SubscriptionManagerImpl.clearMostRecentlyExpiredGiftBadgeIDWithSneakyTransaction()
        }.cauterize()
    }
}

// MARK: - Badge Issue Delegate

extension DonationSettingsViewController: BadgeIssueSheetDelegate {
    func badgeIssueSheetActionTapped(_ action: BadgeIssueSheetAction) {
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
                message: OWSLocalizedString("PROFILE_VIEW_NO_CONNECTION",
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
                    userProfileWriter: .localUser
                )
            } else {
                return Promise.value(())
            }
        }.then(on: DispatchQueue.global()) { () -> Promise<Void> in
            let displayBadgesOnProfile: Bool
            switch setting {
            case .doNotDisplayPublicly:
                displayBadgesOnProfile = false
            case .display:
                displayBadgesOnProfile = true
            }

            return Self.databaseStorage.write(.promise) { transaction in
                Self.subscriptionManager.setDisplayBadgesOnProfile(
                    displayBadgesOnProfile,
                    updateStorageService: true,
                    transaction: transaction
                )
            }
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
