//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import StoreKit
import UIKit

final class BackupEnablingManager {
    private let backupAttachmentUploadEraStore: BackupAttachmentUploadEraStore
    private let backupDisablingManager: BackupDisablingManager
    private let backupKeyService: BackupKeyService
    private let backupPlanManager: BackupPlanManager
    private let backupSettingsStore: BackupSettingsStore
    private let backupSubscriptionIssueStore: BackupSubscriptionIssueStore
    private let backupSubscriptionManager: BackupSubscriptionManager
    private let backupTestFlightEntitlementManager: BackupTestFlightEntitlementManager
    private let db: DB
    private let logger: PrefixedLogger
    private let tsAccountManager: TSAccountManager
    private let notificationPresenter: NotificationPresenter

    init(
        backupAttachmentUploadEraStore: BackupAttachmentUploadEraStore,
        backupDisablingManager: BackupDisablingManager,
        backupKeyService: BackupKeyService,
        backupPlanManager: BackupPlanManager,
        backupSettingsStore: BackupSettingsStore,
        backupSubscriptionIssueStore: BackupSubscriptionIssueStore,
        backupSubscriptionManager: BackupSubscriptionManager,
        backupTestFlightEntitlementManager: BackupTestFlightEntitlementManager,
        db: DB,
        tsAccountManager: TSAccountManager,
        notificationPresenter: NotificationPresenter
    ) {
        self.backupAttachmentUploadEraStore = backupAttachmentUploadEraStore
        self.backupDisablingManager = backupDisablingManager
        self.backupKeyService = backupKeyService
        self.backupPlanManager = backupPlanManager
        self.backupSettingsStore = backupSettingsStore
        self.backupSubscriptionIssueStore = backupSubscriptionIssueStore
        self.backupSubscriptionManager = backupSubscriptionManager
        self.backupTestFlightEntitlementManager = backupTestFlightEntitlementManager
        self.db = db
        self.logger = PrefixedLogger(prefix: "[Backups]")
        self.tsAccountManager = tsAccountManager
        self.notificationPresenter = notificationPresenter
    }

    @MainActor
    func enableBackups(
        fromViewController: UIViewController,
        planSelection: ChooseBackupPlanViewController.PlanSelection,
    ) async throws(ActionSheetDisplayableError) {
        let (
            registrationState,
            localIdentifiers,
        ): (
            TSRegistrationState,
            LocalIdentifiers?
        ) = db.read { tx in
            return (
                tsAccountManager.registrationState(tx: tx),
                tsAccountManager.localIdentifiers(tx: tx),
            )
        }

        guard
            let localIdentifiers,
            registrationState.isRegistered
        else {
            throw .custom(localizedMessage: OWSLocalizedString(
                "CHOOSE_BACKUP_PLAN_CONFIRMATION_ERROR_NOT_REGISTERED",
                comment: "Message shown in an action sheet when the user tries to confirm a plan selection, but is not registered."
            ))
        }

        owsPrecondition(
            registrationState.isRegisteredPrimaryDevice,
            "Attempting to enable Backups on a non-primary device!"
        )

        try await ModalActivityIndicatorViewController.presentAndPropagateResult(
            from: fromViewController
        ) { [self] () throws(ActionSheetDisplayableError) in
            try await _enableBackups(
                planSelection: planSelection,
                localIdentifiers: localIdentifiers
            )
        }

        scheduleEnableBackupsNotification()
    }

    private func _enableBackups(
        planSelection: ChooseBackupPlanViewController.PlanSelection,
        localIdentifiers: LocalIdentifiers,
    ) async throws(ActionSheetDisplayableError) {
        // First, reserve a Backup ID. We'll need this regardless of which plan
        // the user chose, and we want to be sure it's succeeded before we
        // attempt a potential purchase. (Redeeming a Backups subscription
        // without this step will fail!)
        do {
            // This is a no-op unless we're also actively *disabling* Backups
            // remotely. If we are, we don't wanna race, so we'll wait for
            // it to finish.
            await self.backupDisablingManager.disableRemotelyIfNecessary()

            _ = try await self.backupKeyService.registerBackupKey(
                localIdentifiers: localIdentifiers,
                auth: .implicit()
            )
        } catch where error.isNetworkFailureOrTimeout {
            throw .networkError
        } catch let error as OWSHTTPError where error.responseStatusCode == 429 {
            logger.error("Rate limited when Registering Backup ID! \(error)")
            if
                let retryAfterHeader = error.responseHeaders?["retry-after"],
                let retryAfterTime = TimeInterval(retryAfterHeader)
            {
                let title = OWSLocalizedString(
                    "CHOOSE_BACKUP_PLAN_CONFIRMATION_ERROR_RATE_LIMITED_TITLE",
                    comment: "Message shown in an action sheet when the user tries to confirm a plan selection, but encounters a rate limit. They should wait the requested amount of time and try again. {{ Embeds 1 & 2: the preformatted time they must wait before enabling backups, such as \"1 week\" or \"6 hours\". }}"
                )
                let message = OWSLocalizedString(
                    "CHOOSE_BACKUP_PLAN_CONFIRMATION_ERROR_RATE_LIMITED",
                    comment: "Message shown in an action sheet when the user tries to confirm a plan selection, but encounters a rate limit. They should wait the requested amount of time and try again."
                )
                let nextRetryString = DateUtil.formatDuration(
                    seconds: UInt32(retryAfterTime),
                    useShortFormat: false
                )
                throw .custom(
                    localizedTitle: title,
                    localizedMessage: String(format: message, nextRetryString)
                )
            } else {
                throw .genericError
            }
        } catch {
            owsFailDebug("Unexpectedly failed to register Backup ID! \(error)", logger: logger)
            throw .genericError
        }

        // Proactively clear persisted subscription-related issues, as they'll
        // be superceded, and/or re-set, by our imminent enabling attempt.
        await db.awaitableWrite { tx in
            backupSubscriptionIssueStore.setStopWarningIAPSubscriptionAlreadyRedeemed(tx: tx)
            backupSubscriptionIssueStore.setStopWarningIAPSubscriptionNotFoundLocally(tx: tx)
        }

        switch planSelection {
        case .free:
            try await setBackupPlan { _ in .free }
        case .paid:
            if BuildFlags.Backups.avoidStoreKitForTesters {
                try await enablePaidPlanWithoutStoreKit()
            } else {
                try await enablePaidPlanWithStoreKit()
            }
        }
    }

    // MARK: -

    private func scheduleEnableBackupsNotification() {
        let backupsEnabledTimestamp = Date()
        let notificationDelay = TimeInterval.random(in: .hour...(.hour * 3))
        db.write { tx in
            backupSettingsStore.setLastBackupEnabledDetails(
                backupsEnabledTime: backupsEnabledTimestamp,
                notificationDelay: notificationDelay,
                tx: tx
            )
        }
        notificationPresenter.scheduleNotifyForBackupsEnabled(backupsTimestamp: backupsEnabledTimestamp)
    }

    // MARK: -

    private func enablePaidPlanWithStoreKit() async throws(ActionSheetDisplayableError) {
        let purchaseResult: BackupSubscription.PurchaseResult
        do {
            purchaseResult = try await backupSubscriptionManager.purchaseNewSubscription()
        } catch StoreKitError.networkError {
            throw .networkError
        } catch {
            owsFailDebug("StoreKit purchase unexpectedly failed: \(error)", logger: logger)
            throw .custom(localizedMessage: OWSLocalizedString(
                "CHOOSE_BACKUP_PLAN_CONFIRMATION_ERROR_PURCHASE",
                comment: "Message shown in an action sheet when the user tries to confirm selecting the paid plan, but encountered an error from Apple while purchasing."
            ))
        }

        switch purchaseResult {
        case .success:
            do {
                try await self.backupSubscriptionManager.redeemSubscriptionIfNecessary()
            } catch {
                owsFailDebug("Unexpectedly failed to redeem subscription! \(error)", logger: logger)
                throw .custom(localizedMessage: OWSLocalizedString(
                    "CHOOSE_BACKUP_PLAN_CONFIRMATION_ERROR_PURCHASE_REDEMPTION",
                    comment: "Message shown in an action sheet when the user tries to confirm selecting the paid plan, but encountered an error while redeeming their completed purchase."
                ))
            }

            try await setBackupPlan { currentBackupPlan in
                let currentOptimizeLocalStorage: Bool
                switch currentBackupPlan {
                case .disabled, .disabling, .free:
                    currentOptimizeLocalStorage = false
                case
                        .paid(let optimizeLocalStorage),
                        .paidExpiringSoon(let optimizeLocalStorage),
                        .paidAsTester(let optimizeLocalStorage):
                    currentOptimizeLocalStorage = optimizeLocalStorage
                }

                return .paid(optimizeLocalStorage: currentOptimizeLocalStorage)
            }

        case .pending:
            // The subscription won't be redeemed until if/when the purchase
            // is approved, but if/when that happens BackupPlan will get set
            // set to .paid. For the time being, we can enable Backups as
            // a free-tier user!
            try await setBackupPlan { _ in .free }

        case .userCancelled:
            throw .userCancelled

        }
    }

    private func enablePaidPlanWithoutStoreKit() async throws(ActionSheetDisplayableError) {
        do {
            try await backupTestFlightEntitlementManager.acquireEntitlement()
        } catch where error.isNetworkFailureOrTimeout {
            throw .networkError
        } catch {
            owsFailDebug("Unexpectedly failed to renew Backup entitlement for tester! \(error)", logger: logger)
            throw .genericError
        }

        try await setBackupPlan { _ in
            return .paidAsTester(optimizeLocalStorage: false)
        }
    }

    // MARK: -

    private func setBackupPlan(
        block: (_ currentBackupPlan: BackupPlan) -> BackupPlan,
    ) async throws(ActionSheetDisplayableError) {
        do {
            try await db.awaitableWriteWithRollbackIfThrows { tx in
                let newBackupPlan = block(backupPlanManager.backupPlan(tx: tx))
                try backupPlanManager.setBackupPlan(newBackupPlan, tx: tx)
            }
        } catch {
            owsFailDebug("Failed to set BackupPlan! \(error)", logger: logger)
            throw .genericError
        }
    }
}
