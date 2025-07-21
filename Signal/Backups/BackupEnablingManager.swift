//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import StoreKit
import UIKit

final class BackupEnablingManager {
    struct DisplayableError: Error {
        let localizedActionSheetMessage: String

        init(_ localizedActionSheetMessage: String) {
            self.localizedActionSheetMessage = localizedActionSheetMessage
        }

        fileprivate static let networkError = DisplayableError(OWSLocalizedString(
            "CHOOSE_BACKUP_PLAN_CONFIRMATION_ERROR_NETWORK_ERROR",
            comment: "Message shown in an action sheet when the user tries to confirm a plan selection, but encountered a network error."
        ))

        fileprivate static let genericError = DisplayableError(OWSLocalizedString(
            "CHOOSE_BACKUP_PLAN_CONFIRMATION_ERROR_GENERIC_ERROR",
            comment: "Message shown in an action sheet when the user tries to confirm a plan selection, but encountered a generic error."
        ))
    }

    private let backupAttachmentUploadEraStore: BackupAttachmentUploadEraStore
    private let backupDisablingManager: BackupDisablingManager
    private let backupIdManager: BackupIdManager
    private let backupPlanManager: BackupPlanManager
    private let backupSubscriptionManager: BackupSubscriptionManager
    private let backupTestFlightEntitlementManager: BackupTestFlightEntitlementManager
    private let db: DB
    private let tsAccountManager: TSAccountManager

    init(
        backupAttachmentUploadEraStore: BackupAttachmentUploadEraStore,
        backupDisablingManager: BackupDisablingManager,
        backupIdManager: BackupIdManager,
        backupPlanManager: BackupPlanManager,
        backupSubscriptionManager: BackupSubscriptionManager,
        backupTestFlightEntitlementManager: BackupTestFlightEntitlementManager,
        db: DB,
        tsAccountManager: TSAccountManager
    ) {
        self.backupAttachmentUploadEraStore = backupAttachmentUploadEraStore
        self.backupDisablingManager = backupDisablingManager
        self.backupIdManager = backupIdManager
        self.backupPlanManager = backupPlanManager
        self.backupSubscriptionManager = backupSubscriptionManager
        self.backupTestFlightEntitlementManager = backupTestFlightEntitlementManager
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

        do {
            try await ModalActivityIndicatorViewController.presentAndPropagateResult(
                from: fromViewController
            ) { [self] in
                try await _enableBackups(
                    planSelection: planSelection,
                    localIdentifiers: localIdentifiers
                )
            }
        } catch let error as DisplayableError {
            throw error
        } catch {
            owsFailDebug("Unexpected non-displayable error enabling Backups! \(error)")
            throw .genericError
        }
    }

    private func _enableBackups(
        planSelection: ChooseBackupPlanViewController.PlanSelection,
        localIdentifiers: LocalIdentifiers,
    ) async throws(DisplayableError) {
        // First, reserve a Backup ID. We'll need this regardless of which plan
        // the user chose, and we want to be sure it's succeeded before we
        // attempt a potential purchase. (Redeeming a Backups subscription
        // without this step will fail!)
        do {
            // This is a no-op unless we're also actively *disabling* Backups
            // remotely. If we are, we don't wanna race, so we'll wait for
            // it to finish.
            await self.backupDisablingManager.disableRemotelyIfNecessary()

            _ = try await self.backupIdManager.registerBackupId(
                localIdentifiers: localIdentifiers,
                auth: .implicit()
            )
        } catch where error.isNetworkFailureOrTimeout {
            throw .networkError
        } catch {
            owsFailDebug("Unexpectedly failed to register Backup ID! \(error)")
            throw .genericError
        }

        switch planSelection {
        case .free:
            try await setBackupPlan { _ in .free }
        case .paid:
            if FeatureFlags.Backups.avoidStoreKitForTesters {
                try await enablePaidPlanWithoutStoreKit()
            } else {
                try await enablePaidPlanWithStoreKit()
            }
        }
    }

    // MARK: -

    private func enablePaidPlanWithStoreKit() async throws(DisplayableError) {
        let purchaseResult: BackupSubscription.PurchaseResult
        do {
            purchaseResult = try await backupSubscriptionManager.purchaseNewSubscription()
        } catch StoreKitError.networkError {
            throw .networkError
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
                try await self.backupSubscriptionManager.redeemSubscriptionIfNecessary()
            } catch {
                owsFailDebug("Unexpectedly failed to redeem subscription! \(error)")
                throw DisplayableError(OWSLocalizedString(
                    "CHOOSE_BACKUP_PLAN_CONFIRMATION_ERROR_PURCHASE_REDEMPTION",
                    comment: "Message shown in an action sheet when the user tries to confirm selecting the paid plan, but encountered an error while redeeming their completed purchase."
                ))
            }

            try await setBackupPlan { tx in
                let currentOptimizeLocalStorage: Bool
                switch backupPlanManager.backupPlan(tx: tx) {
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
            // Do nothing – don't even dismiss "choose plan", to give
            // the user the chance to try again. We've reserved a Backup
            // ID at this point, but that's fine even if they don't end
            // up enabling Backups at all.
            break

        }
    }

    private func enablePaidPlanWithoutStoreKit() async throws(DisplayableError) {
        do {
            try await backupTestFlightEntitlementManager.acquireEntitlement()
        } catch where error.isNetworkFailureOrTimeout {
            throw .networkError
        } catch {
            owsFailDebug("Unexpectedly failed to renew Backup entitlement for tester! \(error)")
            throw .genericError
        }

        try await setBackupPlan { tx in
            // Rotate the upload era, since now that we're paid we'll probably
            // want to do uploads, and to that end need to do a list-media.
            backupAttachmentUploadEraStore.rotateUploadEra(tx: tx)

            return .paidAsTester(optimizeLocalStorage: false)
        }
    }

    // MARK: -

    private func setBackupPlan(
        block: (DBWriteTransaction) -> BackupPlan,
    ) async throws(DisplayableError) {
        do {
            try await db.awaitableWriteWithRollbackIfThrows { tx in
                let newBackupPlan = block(tx)
                try backupPlanManager.setBackupPlan(newBackupPlan, tx: tx)
            }
        } catch {
            owsFailDebug("Failed to set BackupPlan! \(error)")
            throw .genericError
        }
    }
}
