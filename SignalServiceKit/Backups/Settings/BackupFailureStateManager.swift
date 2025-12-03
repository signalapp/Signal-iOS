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

    init(
        backupSettingsStore: BackupSettingsStore,
        dateProvider: @escaping DateProvider,
        tsAccountManager: TSAccountManager,
    ) {
        self.backupSettingsStore = backupSettingsStore
        self.dateProvider = dateProvider
        self.tsAccountManager = tsAccountManager
    }

    // MARK: -

    public func hasFailedBackup(tx: DBReadTransaction) -> Bool {
        guard shouldBackupsBeRunning(tx: tx) else {
            return false
        }

        if backupSettingsStore.getInteractiveBackupErrorCount(tx: tx) >= Constants.requiredInteractiveFailuresForBadge {
            return true
        }

        if backupSettingsStore.getBackgroundBackupErrorCount(tx: tx) >= Constants.requiredBackgroundFailuresForBadge {
            return true
        }

        if !lastBackupWasRecent(tx: tx) {
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

        return hasFailedBackup(tx: tx)
    }

    // MARK: -

    private func shouldBackupsBeRunning(tx: DBReadTransaction) -> Bool {
        guard tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice else {
            // No backups on iPad, so no errors.
            return false
        }

        return switch backupSettingsStore.backupPlan(tx: tx) {
        case .disabled, .disabling: false
        case .free, .paid, .paidExpiringSoon, .paidAsTester: true
        }
    }

    /// Whether the user's last successful Backup happened "recently".
    private func lastBackupWasRecent(tx: DBReadTransaction) -> Bool {
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
}
