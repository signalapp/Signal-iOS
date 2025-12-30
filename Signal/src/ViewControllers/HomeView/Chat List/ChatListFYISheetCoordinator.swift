//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

@MainActor
class ChatListFYISheetCoordinator {
    fileprivate enum FYISheet {
        struct BadgeThanks {
            let redemptionSuccess: DonationReceiptCredentialRedemptionSuccess
            let successMode: DonationReceiptCredentialResultStore.Mode
        }

        struct BadgeIssue {
            let redemptionError: DonationReceiptCredentialRequestError
            let badge: ProfileBadge
            let errorMode: DonationReceiptCredentialResultStore.Mode
        }

        struct BadgeExpiration {
            let expiredBadgeID: String
            let donationSubscriberID: Data?
            let mostRecentSubscriptionPaymentMethod: DonationPaymentMethod?
            let probablyHasCurrentSubscription: Bool
        }

        struct BackupSubscriptionExpired {
            enum SubscriptionType {
                case iap
                case testFlight
            }

            let subscriptionType: SubscriptionType
        }

        struct BackupSubscriptionFailedToRenew {}

        case badgeThanks(BadgeThanks)
        case badgeIssue(BadgeIssue)
        case badgeExpiration(BadgeExpiration)
        case backupSubscriptionExpired(BackupSubscriptionExpired)
        case backupSubscriptionFailedToRenew(BackupSubscriptionFailedToRenew)
    }

    private let backupExportJobRunner: BackupExportJobRunner
    private let backupSubscriptionIssueStore: BackupSubscriptionIssueStore
    private let donationReceiptCredentialResultStore: DonationReceiptCredentialResultStore
    private let donationSubscriptionManager: DonationSubscriptionManager.Type
    private let db: DB
    private let networkManager: NetworkManager
    private let profileManager: ProfileManager

    init(
        backupExportJobRunner: BackupExportJobRunner,
        backupSubscriptionIssueStore: BackupSubscriptionIssueStore,
        donationReceiptCredentialResultStore: DonationReceiptCredentialResultStore,
        donationSubscriptionManager: DonationSubscriptionManager.Type,
        db: DB,
        networkManager: NetworkManager,
        profileManager: ProfileManager,
    ) {
        self.backupExportJobRunner = backupExportJobRunner
        self.backupSubscriptionIssueStore = backupSubscriptionIssueStore
        self.donationReceiptCredentialResultStore = donationReceiptCredentialResultStore
        self.donationSubscriptionManager = donationSubscriptionManager
        self.db = db
        self.networkManager = networkManager
        self.profileManager = profileManager
    }

    func presentIfNecessary(
        from chatListViewController: ChatListViewController,
    ) async {
        guard
            chatListViewController.isChatListTopmostViewController(),
            let nextSheet = db.read(block: { nextSheetToPresent(tx: $0) })
        else {
            return
        }

        await present(fyiSheet: nextSheet, from: chatListViewController)
    }

    // MARK: -

    private func nextSheetToPresent(tx: DBReadTransaction) -> FYISheet? {
        if let sheet = shouldShowBadgeThanksSheet(successMode: .oneTimeBoost, tx: tx) {
            return sheet
        } else if let sheet = shouldShowBadgeThanksSheet(successMode: .recurringSubscriptionInitiation, tx: tx) {
            return sheet
        } else if let sheet = shouldShowBadgeIssueSheet(errorMode: .oneTimeBoost, tx: tx) {
            return sheet
        } else if let sheet = shouldShowBadgeIssueSheet(errorMode: .recurringSubscriptionInitiation, tx: tx) {
            return sheet
        } else if let sheet = shouldShowBadgeIssueSheet(errorMode: .recurringSubscriptionRenewal, tx: tx) {
            return sheet
        } else if
            let expiredBadgeID = donationSubscriptionManager.mostRecentlyExpiredBadgeID(transaction: tx),
            donationSubscriptionManager.showExpirySheetOnHomeScreenKey(transaction: tx)
        {
            return .badgeExpiration(FYISheet.BadgeExpiration(
                expiredBadgeID: expiredBadgeID,
                donationSubscriberID: donationSubscriptionManager.getSubscriberID(transaction: tx),
                mostRecentSubscriptionPaymentMethod: donationSubscriptionManager.getMostRecentSubscriptionPaymentMethod(transaction: tx),
                probablyHasCurrentSubscription: donationSubscriptionManager.probablyHasCurrentSubscription(tx: tx),
            ))
        } else if backupSubscriptionIssueStore.shouldWarnIAPSubscriptionExpired(tx: tx) {
            return .backupSubscriptionExpired(FYISheet.BackupSubscriptionExpired(subscriptionType: .iap))
        } else if backupSubscriptionIssueStore.shouldWarnTestFlightSubscriptionExpired(tx: tx) {
            return .backupSubscriptionExpired(FYISheet.BackupSubscriptionExpired(subscriptionType: .testFlight))
        } else if backupSubscriptionIssueStore.shouldWarnIAPSubscriptionFailedToRenew(tx: tx) {
            return .backupSubscriptionFailedToRenew(FYISheet.BackupSubscriptionFailedToRenew())
        } else {
            return nil
        }
    }

    /// Checks for `.badgeThanks` FYI sheets.
    ///
    /// When creating a new donation we show a `BadgeThankSheet` inline in the
    /// donate flow, if payment succeeds quickly (in which case we won't need to
    /// show one here). However, bank-transfer payment methods (e.g., SEPA) take
    /// ~days to process and may succeed in the background, in which case we
    /// should show a sheet.
    ///
    /// We don't want to show a sheet for subscription renewals, which succeed
    /// silently.
    private func shouldShowBadgeThanksSheet(
        successMode: DonationReceiptCredentialResultStore.Mode,
        tx: DBReadTransaction,
    ) -> FYISheet? {
        guard
            let redemptionSuccess = donationReceiptCredentialResultStore
                .getRedemptionSuccess(successMode: successMode, tx: tx),
            !donationReceiptCredentialResultStore
                .hasPresentedSuccess(successMode: successMode, tx: tx)
        else {
            return nil
        }

        return .badgeThanks(FYISheet.BadgeThanks(
            redemptionSuccess: redemptionSuccess,
            successMode: successMode,
        ))
    }

    /// Checks for `.badgeIssue` FYI sheets.
    ///
    /// See inline comments: we expect these to be handled inline in the donate
    /// flow for non-bank payments, so we avoid showing what are likely
    /// redundant errors here.
    private func shouldShowBadgeIssueSheet(
        errorMode: DonationReceiptCredentialResultStore.Mode,
        tx: DBReadTransaction,
    ) -> FYISheet? {
        guard
            let redemptionError = donationReceiptCredentialResultStore
                .getRequestError(errorMode: errorMode, tx: tx),
            !donationReceiptCredentialResultStore
                .hasPresentedError(errorMode: errorMode, tx: tx)
        else {
            return nil
        }

        switch redemptionError.errorCode {
        case .paymentStillProcessing:
            // Not a terminal error – no reason to show a sheet.
            return nil
        case
            .paymentFailed,
            .localValidationFailed,
            .serverValidationFailed,
            .paymentNotFound,
            .paymentIntentRedeemed:
            break
        }

        switch redemptionError.paymentMethod {
        case nil, .applePay, .creditOrDebitCard, .paypal:
            // Non-SEPA payment methods generally get their errors immediately,
            // and so errors from initiating a donation should have been
            // presented when the user was in the donate view. Consequently, we
            // only want to present renewal errors here.
            switch errorMode {
            case .oneTimeBoost, .recurringSubscriptionInitiation:
                return nil
            case .recurringSubscriptionRenewal:
                break
            }
        case .sepa, .ideal:
            // SEPA donations won't error out immediately upon initiation
            // (they'll spend time processing first), so we should show errors
            // for any variety of donation here.
            break
        }

        return .badgeIssue(FYISheet.BadgeIssue(
            redemptionError: redemptionError,
            badge: redemptionError.badge,
            errorMode: errorMode,
        ))
    }

    // MARK: -

    private func present(
        fyiSheet: FYISheet,
        from chatListViewController: ChatListViewController,
    ) async {
        switch fyiSheet {
        case .badgeThanks(let badgeThanks):
            await _present(badgeThanks: badgeThanks, from: chatListViewController)
        case .badgeIssue(let badgeIssue):
            await _present(badgeIssue: badgeIssue, from: chatListViewController)
        case .badgeExpiration(let badgeExpiration):
            await _present(badgeExpiration: badgeExpiration, from: chatListViewController)
        case .backupSubscriptionExpired(let backupSubscriptionExpired):
            await _present(backupSubscriptionExpired: backupSubscriptionExpired, from: chatListViewController)
        case .backupSubscriptionFailedToRenew(let backupSubscriptionFailedToRenew):
            await _present(backupSubscriptionFailedToRenew: backupSubscriptionFailedToRenew, from: chatListViewController)
        }
    }

    private func _present(
        badgeThanks: FYISheet.BadgeThanks,
        from chatListViewController: ChatListViewController,
    ) async {
        let badgeThanksSheetPresenter: BadgeThanksSheetPresenter = .fromGlobals(
            redemptionSuccess: badgeThanks.redemptionSuccess,
            successMode: badgeThanks.successMode,
        )

        await badgeThanksSheetPresenter.presentAndRecordBadgeThanks(fromViewController: chatListViewController)
    }

    private func _present(
        badgeIssue: FYISheet.BadgeIssue,
        from chatListViewController: ChatListViewController,
    ) async {
        let logger = PrefixedLogger(prefix: "[Donations]")

        let redemptionError = badgeIssue.redemptionError
        let chargeFailureCodeIfPaymentFailed = redemptionError.chargeFailureCodeIfPaymentFailed
        let paymentMethod = redemptionError.paymentMethod
        let badge = badgeIssue.badge
        let errorMode = badgeIssue.errorMode

        do {
            try await profileManager.badgeStore.populateAssetsOnBadge(badge)
        } catch {
            logger.error("Failed to populate badge assets! \(error)")
            return
        }

        guard chatListViewController.isChatListTopmostViewController() else {
            logger.warn("Not presenting error – no longer the top view controller.")
            return
        }

        let badgeIssueSheetMode: BadgeIssueSheetState.Mode = {
            switch errorMode {
            case .oneTimeBoost, .recurringSubscriptionInitiation:
                return .bankPaymentFailed(
                    chargeFailureCode: chargeFailureCodeIfPaymentFailed,
                )
            case .recurringSubscriptionRenewal:
                return .subscriptionExpiredBecauseOfChargeFailure(
                    chargeFailureCode: chargeFailureCodeIfPaymentFailed,
                    paymentMethod: paymentMethod,
                )
            }
        }()

        let badgeIssueSheet = BadgeIssueSheet(
            badge: badge,
            mode: badgeIssueSheetMode,
        )
        badgeIssueSheet.delegate = chatListViewController

        await chatListViewController.awaitablePresent(badgeIssueSheet, animated: true)

        await db.awaitableWrite { tx in
            donationReceiptCredentialResultStore.setHasPresentedError(
                errorMode: errorMode,
                tx: tx,
            )
        }
    }

    private func _present(
        badgeExpiration: FYISheet.BadgeExpiration,
        from chatListViewController: ChatListViewController,
    ) async {
        let logger = PrefixedLogger(prefix: "[Donations]")

        let expiredBadgeID = badgeExpiration.expiredBadgeID
        let donationSubscriberID = badgeExpiration.donationSubscriberID
        let probablyHasCurrentSubscription = badgeExpiration.probablyHasCurrentSubscription

        if BoostBadgeIds.contains(expiredBadgeID) {
            logger.info("Showing expiry sheet for expired boost badge.")

            let boostBadge: ProfileBadge
            do {
                boostBadge = try await donationSubscriptionManager.getBoostBadge()
                try await profileManager.badgeStore.populateAssetsOnBadge(boostBadge)
            } catch {
                logger.warn("Failed to fetch boost badge and assets for expiration! \(error)")
                return
            }

            guard chatListViewController.isChatListTopmostViewController() else {
                return
            }

            let badgeIssueSheet = BadgeIssueSheet(
                badge: boostBadge,
                mode: .boostExpired(hasCurrentSubscription: probablyHasCurrentSubscription),
            )
            badgeIssueSheet.delegate = chatListViewController

            await chatListViewController.awaitablePresent(badgeIssueSheet, animated: true)

            await db.awaitableWrite { tx in
                donationSubscriptionManager.setShowExpirySheetOnHomeScreenKey(show: false, transaction: tx)
            }
        } else if SubscriptionBadgeIds.contains(expiredBadgeID) {
            /// We expect to show an error sheet when the subscription fails to
            /// renew and we learn about it from the receipt credential
            /// redemption job kicked off by the keep-alive.
            ///
            /// Consequently, we don't need/want to show a sheet for the badge
            /// expiration itself, since we should've already shown a sheet.
            ///
            /// It's possible that the subscription simply "expired" due to
            /// inactivity (the subscription was not kept-alive), in which case
            /// we won't have shown a sheet because there won't have been a
            /// renewal failure. That's ok – we'll let the badge expire
            /// silently.
            ///
            /// We'll still fetch the subscription, but just for logging
            /// purposes.
            logger.info("Not showing expiry sheet for expired subscription badge.")

            let currentSubscription: Subscription?
            if let donationSubscriberID {
                do {
                    currentSubscription = try await SubscriptionFetcher(networkManager: networkManager)
                        .fetch(subscriberID: donationSubscriberID)
                } catch {
                    logger.warn("Failed to get subscription during badge expiration!")
                    return
                }
            } else {
                currentSubscription = nil
            }

            if
                donationSubscriberID != nil,
                let currentSubscription
            {
                owsAssertDebug(
                    currentSubscription.status == .canceled,
                    "Current subscription is not canceled, but the badge expired!",
                    logger: logger,
                )

                if let chargeFailure = currentSubscription.chargeFailure {
                    logger.warn("Badge expired for subscription with charge failure: \(chargeFailure.code ?? "nil")")
                } else {
                    logger.warn("Badge expired for subscription without charge failure. It probably expired due to inactivity, but hasn't yet been deleted.")
                }
            } else if donationSubscriberID != nil {
                logger.warn("Missing subscription for expired badge. It probably expired due to inactivity and was deleted.")
            } else {
                logger.warn("Missing subscriber ID for expired subscription badge.")
            }

            await db.awaitableWrite { tx in
                donationSubscriptionManager.setShowExpirySheetOnHomeScreenKey(show: false, transaction: tx)
            }
        }
    }

    private func _present(
        backupSubscriptionExpired: FYISheet.BackupSubscriptionExpired,
        from chatListViewController: ChatListViewController,
    ) async {
        let logger = PrefixedLogger(prefix: "[Backups]")
        logger.info("Showing BackupSubscriptionExpired FYI sheet.")

        let sheet = BackupSubscriptionExpiredHeroSheet(
            subscriptionType: backupSubscriptionExpired.subscriptionType,
            onManageBackups: {
                SignalApp.shared.showAppSettings(mode: .backups)
            },
        )
        chatListViewController.present(sheet, animated: true) { [self] in
            db.write { tx in
                let snoozeMethod: (Bool, DBWriteTransaction) -> Void
                switch backupSubscriptionExpired.subscriptionType {
                case .iap:
                    snoozeMethod = backupSubscriptionIssueStore.setShouldWarnIAPSubscriptionExpired
                case .testFlight:
                    snoozeMethod = backupSubscriptionIssueStore.setShouldWarnTestFlightSubscriptionExpired
                }

                // We showed the sheet, no need to show it again.
                snoozeMethod(false, tx)
            }
        }
    }

    private func _present(
        backupSubscriptionFailedToRenew: FYISheet.BackupSubscriptionFailedToRenew,
        from chatListViewController: ChatListViewController,
    ) async {
        let logger = PrefixedLogger(prefix: "[Backups]")
        logger.info("Showing BackupSubscriptionFailedToRenew FYI sheet.")

        let sheet = BackupSubscriptionFailedToRenewHeroSheet(
            onManageSubscription: {
                SignalApp.shared.showAppSettings(mode: .backups)
            },
        )
        chatListViewController.present(sheet, animated: true) { [self] in
            db.write { tx in
                backupSubscriptionIssueStore.setDidWarnIAPSubscriptionFailedToRenew(tx: tx)
            }
        }
    }
}

// MARK: - ChatListViewController: BadgeIssueSheetDelegate

extension ChatListViewController: BadgeIssueSheetDelegate {
    func badgeIssueSheetActionTapped(_ action: BadgeIssueSheetAction) {
        switch action {
        case .dismiss:
            break
        case .openDonationView:
            showAppSettings(mode: .donate(donateMode: .oneTime))
        }
    }
}

// MARK: -

private class BackupSubscriptionExpiredHeroSheet: HeroSheetViewController {
    init(
        subscriptionType: ChatListFYISheetCoordinator.FYISheet.BackupSubscriptionExpired.SubscriptionType,
        onManageBackups: @escaping () -> Void,
    ) {
        let bodyString: String = switch subscriptionType {
        case .iap:
            OWSLocalizedString(
                "BACKUP_PLAN_DOWNGRADED_SHEET_BODY",
                comment: "Body for a sheet shown when your Backup plan is downgraded.",
            )
        case .testFlight:
            OWSLocalizedString(
                "BACKUP_PLAN_DOWNGRADED_SHEET_BODY_TESTFLIGHT",
                comment: "Body for a sheet shown when your Backup plan is downgraded because you stopped using TestFlight.",
            )
        }

        super.init(
            hero: .image(.backupsError),
            title: OWSLocalizedString(
                "BACKUP_PLAN_DOWNGRADED_SHEET_TITLE",
                comment: "Title for a sheet shown when your Backup plan is downgraded.",
            ),
            body: bodyString,
            primaryButton: HeroSheetViewController.Button(
                title: OWSLocalizedString(
                    "BACKUP_PLAN_DOWNGRADED_SHEET_PRIMARY_BUTTON",
                    comment: "Primary button for a sheet shown when your Backup plan is downgraded.",
                ),
                action: { sheet in
                    sheet.dismiss(animated: true) {
                        onManageBackups()
                    }
                },
            ),
            secondaryButton: .dismissing(
                title: CommonStrings.notNowButton,
                style: .secondary,
            ),
        )
    }
}

// MARK: -

private class BackupSubscriptionFailedToRenewHeroSheet: HeroSheetViewController {
    init(
        onManageSubscription: @escaping () -> Void,
    ) {
        super.init(
            hero: .image(.backupsError),
            title: OWSLocalizedString(
                "BACKUP_SUBSCRIPTION_FAILED_TO_RENEW_SHEET_TITLE",
                comment: "Title for a sheet shown when your Backup subscription fails to renew.",
            ),
            body: OWSLocalizedString(
                "BACKUP_SUBSCRIPTION_FAILED_TO_RENEW_SHEET_MESSAGE",
                comment: "Message for a sheet shown when your Backup subscription fails to renew.",
            ),
            primaryButton: HeroSheetViewController.Button(
                title: OWSLocalizedString(
                    "BACKUP_SUBSCRIPTION_FAILED_TO_RENEW_SHEET_PRIMARY_BUTTON",
                    comment: "Primary button for a sheet shown when your Backup subscription fails to renew.",
                ),
                action: { sheet in
                    sheet.dismiss(animated: true) {
                        onManageSubscription()
                    }
                },
            ),
            secondaryButton: .dismissing(
                title: CommonStrings.notNowButton,
                style: .secondary,
            ),
        )
    }
}
