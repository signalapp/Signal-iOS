//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class BackupFailureStateManager {

    let backupSettingsStore: BackupSettingsStore
    let dateProvider: DateProvider

    init(
        backupSettingsStore: BackupSettingsStore,
        dateProvider: @escaping DateProvider,
    ) {
        self.backupSettingsStore = backupSettingsStore
        self.dateProvider = dateProvider
    }

    public func shouldShowBackupFailurePrompt(tx: DBReadTransaction) -> Bool {
        let currentBackupPlan = backupSettingsStore.backupPlan(tx: tx)
        let lastBackupEnabledDetails = backupSettingsStore.lastBackupEnabledDetails(tx: tx)
        // Get the last successful backup, or if it's never succeeded, the last time backups was enabled
        let lastBackupDate = backupSettingsStore.lastBackupDate(tx: tx) ?? lastBackupEnabledDetails?.enabledTime
        let promptCount = backupSettingsStore.getBackupErrorPromptCount(tx: tx)
        let lastPromptDate = backupSettingsStore.getBackupErrorLastPromptDate(tx: tx)

        let backupsEnabled = switch currentBackupPlan {
        case .disabled, .disabling: false
        case .free, .paid, .paidExpiringSoon, .paidAsTester: true
        }

        guard backupsEnabled else {
            return false
        }

        guard backupSettingsStore.getLastBackupFailed(tx: tx) else {
            return false
        }

        // if date missing, or greater than 7 days, check if we should display
        if
            let lastBackupDate,
            abs(lastBackupDate.timeIntervalSince(dateProvider())) < .day * 7
        {
            return false
        }

        // If we've shown the prompt recently, don't show it again.
        let promptBackoff: TimeInterval = switch promptCount {
        case 0: 0
        case 1: 48 * .hour
        default: 72 * .hour
        }

        if
            let lastPromptDate,
            abs(lastPromptDate.timeIntervalSince(dateProvider())) < promptBackoff
        {
            // Snooze
            return false
        }

        return true
    }

    public func snoozeBackupFailurePrompt(tx: DBWriteTransaction) {
        let promptCount = backupSettingsStore.getBackupErrorPromptCount(tx: tx)
        backupSettingsStore.setBackupErrorPromptCount(promptCount + 1, tx: tx)
        backupSettingsStore.setBackupErrorLastPromptDate(dateProvider(), tx: tx)
    }

    /// Allow for managing backup badge state from arbitrary points.
    /// This allows each target to be separately cleared, and also allows
    /// backups to reset the state for all of them on a failure
    public func shouldShowErrorBadge(target: String, tx: DBReadTransaction) -> Bool {
        // Check that the last backup failed
        guard backupSettingsStore.getLastBackupFailed(tx: tx) else {
            return false
        }

        // See if this badge has been muted
        if backupSettingsStore.getErrorBadgeMuted(target: target, tx: tx) {
            return false
        }

        return true
    }

    public func clearErrorBadge(target: String, tx: DBWriteTransaction) {
        // set this target as muted
        backupSettingsStore.setErrorBadgeMuted(target: target, tx: tx)
    }
}
