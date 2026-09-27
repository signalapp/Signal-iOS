//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class BackupFailureStateManager {

    private enum Constants {
        static let requiredInteractiveFailuresForBadge = 1
        static let requiredBackgroundFailuresForBadge = 3
    }

    private let backupSettingsStore: BackupSettingsStore
    private let dateProvider: DateProvider
    private let tsAccountManager: TSAccountManager
    private let localFileBackupStore: LocalFileBackupStore

    init(
        backupSettingsStore: BackupSettingsStore,
        dateProvider: @escaping DateProvider,
        tsAccountManager: TSAccountManager,
        localFileBackupStore: LocalFileBackupStore,
    ) {
        self.backupSettingsStore = backupSettingsStore
        self.dateProvider = dateProvider
        self.tsAccountManager = tsAccountManager
        self.localFileBackupStore = localFileBackupStore
    }

    // MARK: -

    public func hasFailedRemoteBackup(tx: DBReadTransaction) -> Bool {
        guard shouldRemoteBackupsBeRunning(tx: tx) else {
            return false
        }

        if backupSettingsStore.getInteractiveBackupErrorCount(tx: tx) >= Constants.requiredInteractiveFailuresForBadge {
            return true
        }

        if backupSettingsStore.getBackgroundBackupErrorCount(tx: tx) >= Constants.requiredBackgroundFailuresForBadge {
            return true
        }

        if !lastRemoteBackupWasRecent(tx: tx) {
            return true
        }

        return false
    }

    public func hasFailedLocalBackup(tx: DBReadTransaction) -> Bool {
        guard shouldLocalBackupsBeRunning(tx: tx) else {
            return false
        }

        if localFileBackupStore.getInteractiveLocalFileBackupErrorCount(tx: tx) >= Constants.requiredInteractiveFailuresForBadge {
            return true
        }

        if localFileBackupStore.getBackgroundLocalFileBackupErrorCount(tx: tx) >= Constants.requiredBackgroundFailuresForBadge {
            return true
        }

        if !lastLocalBackupWasRecent(tx: tx) {
            return true
        }

        return false
    }

    public func hasFailedAnyBackup(tx: DBReadTransaction) -> Bool {
        if hasFailedRemoteBackup(tx: tx) {
            return true
        }

        if hasFailedLocalBackup(tx: tx) {
            return true
        }

        return false
    }

    /// Allow for managing backup badge state from arbitrary points.
    /// This allows each target to be separately cleared, and also allows
    /// backups to reset the state for all of them on a failure
    public func shouldShowErrorBadge(
        target: BackupSettingsStore.ErrorBadgeTarget,
        tx: DBReadTransaction,
    ) -> Bool {
        // See if this badge has been muted
        if backupSettingsStore.getErrorBadgeMuted(target: target, tx: tx) {
            return false
        }

        return hasFailedAnyBackup(tx: tx)
    }

    // MARK: -

    private func shouldRemoteBackupsBeRunning(tx: DBReadTransaction) -> Bool {
        guard tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice else {
            // No backups on linked devices, so no errors.
            return false
        }

        return switch backupSettingsStore.backupPlan(tx: tx) {
        case .disabled, .disabling: false
        case .free, .paid, .paidExpiringSoon, .paidAsTester: true
        }
    }

    private func shouldLocalBackupsBeRunning(tx: DBReadTransaction) -> Bool {
        guard tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice else {
            // No backups on linked devices, so no errors.
            return false
        }

        return localFileBackupStore.localBackupsEnabled(tx: tx)
    }

    /// Whether the user's last successful Backup happened "recently".
    private func lastRemoteBackupWasRecent(tx: DBReadTransaction) -> Bool {
        // Get the last successful backup, or if it's never succeeded the last
        // time backups were enabled.
        let lastBackupDate: Date? = {
            if let lastBackupDetails = backupSettingsStore.lastBackupDetails(tx: tx) {
                return lastBackupDetails.date
            }

            if let lastBackupEnabledTime = backupSettingsStore.lastBackupEnabledDetails(tx: tx)?.enabledTime {
                return lastBackupEnabledTime
            }

            return nil
        }()

        guard let lastBackupDate else {
            return false
        }

        return dateProvider().timeIntervalSince(lastBackupDate) < .week
    }

    private func lastLocalBackupWasRecent(tx: DBReadTransaction) -> Bool {
        // Get the last successful backup, or if it's never succeeded the last
        // time backups were enabled.
        let lastBackupDate: Date? = {
            if let lastBackupDetails = localFileBackupStore.lastBackupDetails(tx: tx) {
                return lastBackupDetails.date
            }

            if let lastBackupEnabledDate = localFileBackupStore.lastLocalFileBackupEnabledDate(tx: tx) {
                return lastBackupEnabledDate
            }

            return nil
        }()

        guard let lastBackupDate else {
            return false
        }

        return dateProvider().timeIntervalSince(lastBackupDate) < .week
    }
}
