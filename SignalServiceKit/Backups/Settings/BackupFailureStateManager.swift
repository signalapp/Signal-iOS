//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class BackupFailureStateManager {

    let backupSettingsStore = BackupSettingsStore()
    let dateProvider: DateProvider

    init(dateProvider: @escaping DateProvider) {
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
}
