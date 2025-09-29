//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SafariServices
import SignalServiceKit
import SignalUI
import UIKit

final class DonationSettingsViewController: OWSTableViewController2 {
    enum State {
        enum SubscriptionStatus {
            case loadFailed

            case noSubscription

            case pendingSubscription(PendingMonthlyIDEALDonation)

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
                subscriptionLevel: DonationSubscriptionLevel?,
                previouslyHadActiveSubscription: Bool,
                receiptCredentialRequestError: DonationReceiptCredentialRequestError?
            )
        }

        case initializing
        case loading
        case loadFinished(
            subscriptionStatus: SubscriptionStatus,
            oneTimeBoostReceiptCredentialRequestError: DonationReceiptCredentialRequestError?,
            profileBadgeLookup: ProfileBadgeLookup,
            pendingOneTimeDonation: PendingOneTimeIDEALDonation?,
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
            tsAccountManager: DependenciesBridge.shared.tsAccountManager,
        )
    }

    private static var canSendGiftBadges: Bool {
        DonationUtilities.canDonate(
            inMode: .gift,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager,
        )
    }

    public var showExpirationSheet: Bool

    /// This view can display sheets to the user on first appearance.  However there are  scenarios
    /// (eg. deep links) where suppressing any dialogs may be wanted.  This boolean allows for that.
    init(showExpirationSheet: Bool = true) {
        self.showExpirationSheet = showExpirationSheet
        super.init()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setUpAvatarView()
        title = OWSLocalizedString("DONATION_VIEW_TITLE", comment: "Title on the 'Donate to Signal' screen")
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task {
            await self.loadAndUpdateState()
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if showExpirationSheet {
            if !showPendingIDEALAuthorizationSheetIfNeeded() {
                showGiftBadgeExpirationSheetIfNeeded()
            }
            // viewDidAppear can be called multiple times, and we don't want
            // Record that an intial attempt was made to show a sheet and
            // don't try again after that. 
            showExpirationSheet = false
        }
    }

    @objc
    private func didLongPressAvatar(sender: UIGestureRecognizer) {
        let subscriberID = SSKEnvironment.shared.databaseStorageRef.read { DonationSubscriptionManager.getSubscriberID(transaction: $0) }
        guard let subscriberID = subscriberID else { return }

        UIPasteboard.general.string = subscriberID.asBase64Url

        presentToast(text: OWSLocalizedString("SUBSCRIPTION_SUBSCRIBER_ID_COPIED_TO_CLIPBOARD",
                                             comment: "Toast indicating that the user has copied their subscriber ID. (Externally referred to as donor ID)"))
    }

    // MARK: - Data loading

    func loadAndUpdateState() async {
        switch state {
        case .loading:
            owsFailDebug("Already loading!")
            return
        case .initializing, .loadFinished:
            self.state = .loading
            self.state = await self.loadState()
        }
    }

    private func loadState() async -> State {
        let idealStore = DependenciesBridge.shared.externalPendingIDEALDonationStore
        let profileManager = SSKEnvironment.shared.profileManagerRef
        let (
            subscriberID,
            hasEverRedeemedRecurringSubscriptionBadge,
            recurringSubscriptionReceiptCredentialRequestError,
            oneTimeBoostReceiptCredentialRequestError,
            hasAnyDonationReceipts,
            pendingIDEALOneTimeDonation,
            pendingIDEALSubscription,
            hasAnyBadges
        ) = SSKEnvironment.shared.databaseStorageRef.read { tx in
            let resultStore = DependenciesBridge.shared.donationReceiptCredentialResultStore

            return (
                subscriberID: DonationSubscriptionManager.getSubscriberID(transaction: tx),
                hasEverRedeemedRecurringSubscriptionBadge: resultStore.getRedemptionSuccessForAnyRecurringSubscription(tx: tx) != nil,
                recurringSubscriptionReceiptCredentialRequestError: resultStore.getRequestErrorForAnyRecurringSubscription(tx: tx),
                oneTimeBoostReceiptCredentialRequestError: resultStore.getRequestError(errorMode: .oneTimeBoost, tx: tx),
                hasAnyDonationReceipts: DonationReceiptFinder.hasAny(transaction: tx),
                idealStore.getPendingOneTimeDonation(tx: tx),
                idealStore.getPendingSubscription(tx: tx),
                profileManager.localUserProfile(tx: tx)?.hasBadge == true
            )
        }

        async let currentSubscription = DonationViewsUtil.loadCurrentSubscription(subscriberID: subscriberID)
        async let donationConfiguration = DonationSubscriptionManager.fetchDonationConfiguration()

        do {
            let subscriptionStatus: State.SubscriptionStatus
            if let currentSubscription = try await currentSubscription {
                subscriptionStatus = .hasSubscription(
                    subscription: currentSubscription,
                    subscriptionLevel: DonationViewsUtil.subscriptionLevelForSubscription(
                        subscriptionLevels: try await DonationViewsUtil.loadSubscriptionLevels(
                            donationConfiguration: try await donationConfiguration,
                            badgeStore: SSKEnvironment.shared.profileManagerRef.badgeStore
                        ),
                        subscription: currentSubscription
                    ),
                    previouslyHadActiveSubscription: hasEverRedeemedRecurringSubscriptionBadge,
                    receiptCredentialRequestError: recurringSubscriptionReceiptCredentialRequestError
                )

            } else if let pendingIDEALSubscription {
                subscriptionStatus = .pendingSubscription(pendingIDEALSubscription)
            } else {
                subscriptionStatus = .noSubscription
            }

            let result: State = .loadFinished(
                subscriptionStatus: subscriptionStatus,
                oneTimeBoostReceiptCredentialRequestError: oneTimeBoostReceiptCredentialRequestError,
                profileBadgeLookup: await loadProfileBadgeLookup(donationConfiguration: try? await donationConfiguration),
                pendingOneTimeDonation: pendingIDEALOneTimeDonation,
                hasAnyBadges: hasAnyBadges,
                hasAnyDonationReceipts: hasAnyDonationReceipts
            )
            if let pendingIDEALSubscription {
                // Serialized badges lose their assets, so ensure they've
                // been populated before returning.
                try? await SSKEnvironment.shared.profileManagerRef.badgeStore.populateAssetsOnBadge(pendingIDEALSubscription.newSubscriptionLevel.badge)
            }
            return result
        } catch {
            Logger.warn("[Donations] \(error)")
            owsFailDebugUnlessNetworkFailure(error)
            let result: State = .loadFinished(
                subscriptionStatus: .loadFailed,
                oneTimeBoostReceiptCredentialRequestError: oneTimeBoostReceiptCredentialRequestError,
                profileBadgeLookup: await loadProfileBadgeLookup(donationConfiguration: try? await donationConfiguration),
                pendingOneTimeDonation: pendingIDEALOneTimeDonation,
                hasAnyBadges: hasAnyBadges,
                hasAnyDonationReceipts: hasAnyDonationReceipts
            )
            return result
        }
    }

    private func loadProfileBadgeLookup(donationConfiguration: DonationSubscriptionManager.DonationConfiguration?) async -> ProfileBadgeLookup {
        if let donationConfiguration {
            let result = ProfileBadgeLookup(
                boostBadge: donationConfiguration.boost.badge,
                giftBadge: donationConfiguration.gift.badge,
                subscriptionLevels: donationConfiguration.subscription.levels
            )
            await result.attemptToPopulateBadgeAssets(populateAssetsOnBadge: SSKEnvironment.shared.profileManagerRef.badgeStore.populateAssetsOnBadge(_:))
            return result
        } else {
            Logger.warn("[Donations] Failed to fetch donation configuration. Proceeding without it, as it is only cosmetic here.")
            return ProfileBadgeLookup(
                boostBadge: nil,
                giftBadge: nil,
                subscriptionLevels: []
            )
        }
    }

    private func setUpAvatarView() {
        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            self.avatarView.update(transaction) { config in
                if let address = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction)?.aciAddress {
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
            pendingOneTimeDonation,
            hasAnyBadges,
            hasAnyDonationReceipts
        ):
            let sections = loadFinishedSections(
                subscriptionStatus: subscriptionStatus,
                profileBadgeLookup: profileBadgeLookup,
                oneTimeBoostReceiptCredentialRequestError: oneTimeBoostReceiptCredentialRequestError,
                pendingOneTimeDonation: pendingOneTimeDonation,
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
        section.add(AppSettingsViewsUtil.loadingTableItem())
        section.hasBackground = false
        return section
    }

    private func loadFinishedSections(
        subscriptionStatus: State.SubscriptionStatus,
        profileBadgeLookup: ProfileBadgeLookup,
        oneTimeBoostReceiptCredentialRequestError: DonationReceiptCredentialRequestError?,
        pendingOneTimeDonation: PendingOneTimeIDEALDonation?,
        hasAnyBadges: Bool,
        hasAnyDonationReceipts: Bool
    ) -> [OWSTableSection] {
        [
            mySupportSection(
                subscriptionStatus: subscriptionStatus,
                profileBadgeLookup: profileBadgeLookup,
                oneTimeBoostReceiptCredentialRequestError: oneTimeBoostReceiptCredentialRequestError,
                pendingOneTimeDonation: pendingOneTimeDonation,
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
            withText: OWSLocalizedString(
                "DONATION_VIEW_DONATE_ON_BEHALF_OF_A_FRIEND",
                comment: "Title for the \"donate for a friend\" button on the donation view."
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
            case .loadFailed, .hasSubscription, .pendingSubscription: return true
            case .noSubscription: return false
            }
        }()
        if shouldShowSubscriptionFaqLink {
            section.add(.disclosureItem(
                icon: .settingsHelp,
                withText: OWSLocalizedString(
                    "DONATION_VIEW_DONOR_FAQ",
                    comment: "Title for the 'Donor FAQ' button on the donation screen"
                ),
                actionBlock: { [weak self] in
                    let vc = SFSafariViewController(url: URL.Support.Donations.donorFAQ)
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
            withText: OWSLocalizedString("DONATION_RECEIPTS", comment: "Title of view where you can see all of your donation receipts, or button to take you there"),
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
                        let badgeThanksSheetPresenter = BadgeThanksSheetPresenter.fromGlobalsWithSneakyTransaction(
                            successMode: receiptCredentialSuccessMode
                        )
                    else { return }

                    Task {
                        await badgeThanksSheetPresenter.presentAndRecordBadgeThanks(
                            fromViewController: self
                        )
                    }
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
        let expiredGiftBadgeID = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            DonationSubscriptionManager.mostRecentlyExpiredGiftBadgeID(transaction: transaction)
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
            DonationSubscriptionManager.getCachedBadge(level: .giftBadge(.signalGift)).fetchIfNeeded()
        }.done { [weak self] cachedValue in
            guard let self = self else { return }
            guard UIApplication.shared.frontmostViewController == self else { return }
            guard case .profileBadge(let profileBadge) = cachedValue else {
                // The server confirmed this badge doesn't exist. This shouldn't happen,
                // but clear the flag so that we don't keep trying.
                Logger.warn("[Gifting] Clearing expired badge ID because the server said it didn't exist")
                DonationSubscriptionManager.clearMostRecentlyExpiredBadgeIDWithSneakyTransaction()
                return
            }

            let hasCurrentSubscription = SSKEnvironment.shared.databaseStorageRef.read { tx -> Bool in
                return DonationSubscriptionManager.probablyHasCurrentSubscription(tx: tx)
            }
            Logger.info("[Gifting] Showing badge gift expiration sheet (hasCurrentSubscription: \(hasCurrentSubscription))")
            let sheet = BadgeIssueSheet(badge: profileBadge, mode: .giftBadgeExpired(hasCurrentSubscription: hasCurrentSubscription))
            sheet.delegate = self
            self.present(sheet, animated: true)

            // We've shown it, so don't show it again.
            DonationSubscriptionManager.clearMostRecentlyExpiredGiftBadgeIDWithSneakyTransaction()
        }.cauterize()
    }

    // MARK: - IDEAL support methods

    /// Check if there is a pending iDEAL payment awaiting authorization.  If so, check how old the
    /// payment is and display a message that either it still needs external authorization or the payment
    /// failed and can be tried again.
    private func showPendingIDEALAuthorizationSheetIfNeeded() -> Bool {
        let idealStore = DependenciesBridge.shared.externalPendingIDEALDonationStore
        let expiration: TimeInterval = 15 * .minute

        func showError(title: String, message: String, donationMode: DonateViewController.DonateMode) {
            let actionSheet = ActionSheetController(
                title: title,
                message: message
            )

            actionSheet.addAction(ActionSheetAction(
                title: OWSLocalizedString(
                    "DONATION_BADGE_ISSUE_SHEET_TRY_AGAIN_BUTTON_TITLE",
                    comment: "Title for a button asking the user to try their donation again, because something went wrong."
                ),
                handler: { [weak self] _ in
                    guard let self else { return }
                    self.presentAwaitingIDEALAuthorizationActionSheet(donateMode: donationMode)
                }
            ))

            actionSheet.addAction(.init(
                title: CommonStrings.okayButton,
                style: .cancel,
                handler: nil
            ))

            presentActionSheet(actionSheet)
        }

        let (pendingOneTime, pendingSubscription) = SSKEnvironment.shared.databaseStorageRef.read { tx in
            let oneTimeDonation = idealStore.getPendingOneTimeDonation(tx: tx)
            let subscription = idealStore.getPendingSubscription(tx: tx)
            return (oneTimeDonation, subscription)
        }

        if let pendingOneTime {
            if abs(pendingOneTime.createDate.timeIntervalSinceNow) > expiration {
                let title = OWSLocalizedString(
                    "DONATION_SETTINGS_MY_SUPPORT_DONATION_FAILED_ALERT_TITLE",
                    comment: "Title for a sheet explaining that a payment failed."
                )
                let message = OWSLocalizedString(
                    "DONATION_SETTINGS_MY_SUPPORT_IDEAL_ONE_TIME_DONATION_FAILED_MESSAGE",
                    comment: "Message shown in a sheet explaining that the user's iDEAL one-time donation coultn't be processed."
                )
                showError(title: title, message: message, donationMode: .oneTime)

                // cleanup
                SSKEnvironment.shared.databaseStorageRef.write { tx in
                    idealStore.clearPendingOneTimeDonation(tx: tx)
                }
            } else {
                let title = OWSLocalizedString(
                    "DONATION_SETTINGS_MY_SUPPORT_DONATION_UNCONFIMRED_ALERT_TITLE",
                    comment: "Title for a sheet explaining that a payment needs confirmation."
                )
                let messageFormat = OWSLocalizedString(
                    "DONATION_SETTINGS_MY_SUPPORT_IDEAL_ONE_TIME_DONATION_NOT_CONFIRMED_MESSAGE_FORMAT",
                    comment: "Title for a sheet explaining that a payment needs confirmation."
                )
                let message = String(format: messageFormat, CurrencyFormatter.format(money: pendingOneTime.amount))
                showError(title: title, message: message, donationMode: .oneTime)
            }
            return true
        } else if let pendingSubscription {
            if abs(pendingSubscription.createDate.timeIntervalSinceNow) > expiration {
                let title = OWSLocalizedString(
                    "DONATION_SETTINGS_MY_SUPPORT_DONATION_FAILED_ALERT_TITLE",
                    comment: "Title for a sheet explaining that a payment failed."
                )
                let message = OWSLocalizedString(
                    "DONATION_SETTINGS_MY_SUPPORT_IDEAL_RECURRING_SUBSCRIPTION_FAILED_MESSAGE",
                    comment: "Message shown in a sheet explaining that the user's iDEAL recurring monthly donation coultn't be processed."
                )
                showError(title: title, message: message, donationMode: .monthly)
                SSKEnvironment.shared.databaseStorageRef.write { tx in
                    idealStore.clearPendingSubscription(tx: tx)
                }
            } else {
                let title = OWSLocalizedString(
                    "DONATION_SETTINGS_MY_SUPPORT_DONATION_UNCONFIMRED_ALERT_TITLE",
                    comment: "Title for a sheet explaining that a payment needs confirmation."
                )
                let messageFormat = OWSLocalizedString(
                    "DONATION_SETTINGS_MY_SUPPORT_IDEAL_RECURRING_SUBSCRIPTION_NOT_CONFIRMED_MESSAGE_FORMAT",
                    comment: "Message shown in a sheet explaining that the user's iDEAL recurring monthly donation hasn't been confirmed. Embeds {{ formatted current amount }}."
                )
                let message = String(format: messageFormat, CurrencyFormatter.format(money: pendingSubscription.amount))
                showError(title: title, message: message, donationMode: .monthly)
            }
            return true
        }
        return false
    }

    func presentAwaitingIDEALAuthorizationActionSheet(donateMode: DonateViewController.DonateMode) {
        let actionSheet = ActionSheetController(
            title: nil,
            message: OWSLocalizedString(
                "DONATION_SETTINGS_CANCEL_DONATION_AWAITING_AUTHORIZATION_MESSAGE",
                comment: "Prompt confirming the user wants to abandon the current donation flow and start a new donation."
            )
        )

        actionSheet.addAction(showDonateAndClearPendingIDEALDonation(
            title: OWSLocalizedString(
                "DONATION_SETTINGS_CANCEL_DONATION_AWAITING_AUTHORIZATION_DONATE_ACTION",
                comment: "Button title confirming the user wants to begin a new donation."
            ),
            preferredDonateMode: donateMode
        ))
        actionSheet.addAction(OWSActionSheets.cancelAction)

        self.presentActionSheet(actionSheet, animated: true)
    }

    private func showDonateAndClearPendingIDEALDonation(
        title: String,
        preferredDonateMode: DonateViewController.DonateMode
    ) -> ActionSheetAction {
        return clearErrorAndShowDonateAction(title: title, donateMode: preferredDonateMode) { tx in
            switch preferredDonateMode {
            case .oneTime:
                DependenciesBridge.shared.externalPendingIDEALDonationStore
                    .clearPendingOneTimeDonation(tx: tx)
            case .monthly:
                DependenciesBridge.shared.externalPendingIDEALDonationStore
                    .clearPendingSubscription(tx: tx)
            }
        }
    }

    func clearErrorAndShowDonateAction(
        title: String,
        donateMode: DonateViewController.DonateMode,
        clearErrorBlock: @escaping (DBWriteTransaction) -> Void
    ) -> ActionSheetAction {
        return ActionSheetAction(title: title) { _ in
            SSKEnvironment.shared.databaseStorageRef.write { tx in
                clearErrorBlock(tx)
            }

            // Not ideal, because this makes network requests. However, this
            // should be rare, and doing it this way avoids us needing to add
            // methods for updating the state outside the normal loading flow.
            Task { [weak self] in
                await self?.loadAndUpdateState()
                self?.showDonateViewController(preferredDonateMode: donateMode)
            }
        }
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
        if !SSKEnvironment.shared.reachabilityManagerRef.isReachable {
            OWSActionSheets.showErrorAlert(
                message: OWSLocalizedString(
                    "PROFILE_VIEW_NO_CONNECTION",
                    comment: "Error shown when the user tries to update their profile when the app is not connected to the internet."
                )
            )
            return
        }
        Task {
            await self.didCompleteBadgeConfiguration(setting, viewController: vc)
        }
    }

    private func didCompleteBadgeConfiguration(_ badgeConfiguration: BadgeConfiguration, viewController: BadgeConfigurationViewController) async {
        let profileManager = SSKEnvironment.shared.profileManagerRef
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        do {
            let localProfile = databaseStorage.read { tx in profileManager.localUserProfile(tx: tx) }
            let allBadgeIds = localProfile?.badges.map { $0.badgeId } ?? []
            let oldVisibleBadgeIds = localProfile?.visibleBadges.map { $0.badgeId } ?? []

            let newVisibleBadgeIds: [String]
            switch badgeConfiguration {
            case .doNotDisplayPublicly:
                newVisibleBadgeIds = []
            case .display(featuredBadge: let newFeaturedBadge):
                guard allBadgeIds.contains(newFeaturedBadge.badgeId) else {
                    throw OWSAssertionError("Invalid badge")
                }
                newVisibleBadgeIds = [newFeaturedBadge.badgeId] + allBadgeIds.filter { $0 != newFeaturedBadge.badgeId }
            }

            if oldVisibleBadgeIds != newVisibleBadgeIds {
                Logger.info("[Donations] Updating visible badges from \(oldVisibleBadgeIds) to \(newVisibleBadgeIds)")
                viewController.showDismissalActivity = true
                let updatePromise = await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                    SSKEnvironment.shared.profileManagerRef.updateLocalProfile(
                        profileGivenName: .noChange,
                        profileFamilyName: .noChange,
                        profileBio: .noChange,
                        profileBioEmoji: .noChange,
                        profileAvatarData: .noChange,
                        visibleBadgeIds: .setTo(newVisibleBadgeIds),
                        unsavedRotatedProfileKey: nil,
                        userProfileWriter: .localUser,
                        authedAccount: .implicit(),
                        tx: tx
                    )
                }
                try await updatePromise.awaitable()
            }

            let displayBadgesOnProfile: Bool
            switch badgeConfiguration {
            case .doNotDisplayPublicly:
                displayBadgesOnProfile = false
            case .display:
                displayBadgesOnProfile = true
            }

            await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                DonationSubscriptionManager.setDisplayBadgesOnProfile(
                    displayBadgesOnProfile,
                    updateStorageService: true,
                    transaction: tx
                )
            }
        } catch {
            owsFailDebug("Failed to update profile: \(error)")
        }
        self.navigationController?.popViewController(animated: true)
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
