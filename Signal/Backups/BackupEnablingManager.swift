//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import StoreKit
import UIKit

class BackupEnablingManager {
    struct DisplayableError: Error {
        let localizedActionSheetMessage: String

        init(_ localizedActionSheetMessage: String) {
            self.localizedActionSheetMessage = localizedActionSheetMessage
        }
    }

    private let backupDisablingManager: BackupDisablingManager
    private let backupIdManager: BackupIdManager
    private let backupSettingsStore: BackupSettingsStore
    private let backupSubscriptionManager: BackupSubscriptionManager
    private let db: DB
    private let tsAccountManager: TSAccountManager

    init(
        backupDisablingManager: BackupDisablingManager,
        backupIdManager: BackupIdManager,
        backupSettingsStore: BackupSettingsStore,
        backupSubscriptionManager: BackupSubscriptionManager,
        db: DB,
        tsAccountManager: TSAccountManager
    ) {
        self.backupDisablingManager = backupDisablingManager
        self.backupIdManager = backupIdManager
        self.backupSettingsStore = backupSettingsStore
        self.backupSubscriptionManager = backupSubscriptionManager
        self.db = db
        self.tsAccountManager = tsAccountManager
    }

    @MainActor
    func enableBackups(
        fromViewController: UIViewController,
        planSelection: ChooseBackupPlanViewController.PlanSelection,
    ) async throws(DisplayableError) {
        guard let localIdentifiers = db.read(block: { tx in
            tsAccountManager.localIdentifiers(tx: tx)
        }) else {
            throw DisplayableError(OWSLocalizedString(
                "CHOOSE_BACKUP_PLAN_CONFIRMATION_ERROR_NOT_REGISTERED",
                comment: "Message shown in an action sheet when the user tries to confirm a plan selection, but is not registered."
            ))
        }

        let networkErrorSheetMessage = OWSLocalizedString(
            "CHOOSE_BACKUP_PLAN_CONFIRMATION_ERROR_NETWORK_ERROR",
            comment: "Message shown in an action sheet when the user tries to confirm a plan selection, but encountered a network error."
        )

        // First, reserve a Backup ID. We'll need this regardless of which plan
        // the user chose, and we want to be sure it's succeeded before we
        // attempt a potential purchase. (Redeeming a Backups subscription
        // without this step will fail!)
        do {
            try await ModalActivityIndicatorViewController.presentAndPropagateResult(
                from: fromViewController
            ) {
                // This is a no-op unless we're also actively *disabling* Backups
                // remotely. If we are, we don't wanna race, so we'll wait for
                // it to finish.
                try? await self.backupDisablingManager.disableRemotelyIfNecessary()

                _ = try await self.backupIdManager.registerBackupId(
                    localIdentifiers: localIdentifiers,
                    auth: .implicit()
                )
            }
        } catch where error.isNetworkFailureOrTimeout {
            throw DisplayableError(networkErrorSheetMessage)
        } catch {
            owsFailDebug("Unexpectedly failed to register Backup ID! \(error)")
            throw DisplayableError(OWSLocalizedString(
                "CHOOSE_BACKUP_PLAN_CONFIRMATION_ERROR_GENERIC_ERROR",
                comment: "Message shown in an action sheet when the user tries to confirm a plan selection, but encountered a generic error."
            ))
        }

        switch planSelection {
        case .free:
            await db.awaitableWrite { tx in
                backupSettingsStore.setBackupPlan(.free, tx: tx)
            }

        case .paid:
            let purchaseResult: BackupSubscription.PurchaseResult
            do {
                purchaseResult = try await backupSubscriptionManager.purchaseNewSubscription()
            } catch StoreKitError.networkError {
                throw DisplayableError(networkErrorSheetMessage)
            } catch {
                owsFailDebug("StoreKit purchase unexpectedly failed: \(error)")
                throw DisplayableError(OWSLocalizedString(
                    "CHOOSE_BACKUP_PLAN_CONFIRMATION_ERROR_PURCHASE",
                    comment: "Message shown in an action sheet when the user tries to confirm selecting the paid plan, but encountered an error from Apple while purchasing."
                ))
            }

            switch purchaseResult {
            case .success:
                do {
                    try await ModalActivityIndicatorViewController.presentAndPropagateResult(
                        from: fromViewController
                    ) {
                        try await self.backupSubscriptionManager.redeemSubscriptionIfNecessary()
                    }
                } catch {
                    owsFailDebug("Unexpectedly failed to redeem subscription! \(error)")
                    throw DisplayableError(OWSLocalizedString(
                        "CHOOSE_BACKUP_PLAN_CONFIRMATION_ERROR_PURCHASE_REDEMPTION",
                        comment: "Message shown in an action sheet when the user tries to confirm selecting the paid plan, but encountered an error while redeeming their completed purchase."
                    ))
                }

                await db.awaitableWrite { tx in
                    let currentOptimizeLocalStorage = switch backupSettingsStore.backupPlan(tx: tx) {
                    case .disabled, .free:
                        false
                    case .paid(let optimizeLocalStorage), .paidExpiringSoon(let optimizeLocalStorage):
                        optimizeLocalStorage
                    }

                    backupSettingsStore.setBackupPlan(
                        .paid(optimizeLocalStorage: currentOptimizeLocalStorage),
                        tx: tx
                    )
                }

            case .pending:
                // The subscription won't be redeemed until if/when the purchase
                // is approved, but if/when that happens BackupPlan will get set
                // set to .paid. For the time being, we can enable Backups as
                // a free-tier user!
                await db.awaitableWrite { tx in
                    backupSettingsStore.setBackupPlan(.free, tx: tx)
                }

            case .userCancelled:
                // Do nothing – don't even dismiss "choose plan", to give
                // the user the chance to try again. We've reserved a Backup
                // ID at this point, but that's fine even if they don't end
                // up enabling Backups at all.
                break

            }
        }
    }
}
