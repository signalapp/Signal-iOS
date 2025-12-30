//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class RecoveryKeyReminderMegaphoneTests: XCTestCase {
    private let backupSettingsStore: BackupSettingsStore = BackupSettingsStore()
    private let db: DB = InMemoryDB()
    private let tsAccountManager: TSAccountManager = MockTSAccountManager()

    private func checkPreconditions(tx: DBReadTransaction) -> Bool {
        return ExperienceUpgradeManifest.checkPreconditionsForRecoveryKeyReminder(
            backupSettingsStore: backupSettingsStore,
            tsAccountManager: tsAccountManager,
            transaction: tx,
        )
    }

    func testPreconditionsForRecoveryKeyMegaphone_backupsDisabled() throws {
        db.write { tx in
            backupSettingsStore.setBackupPlan(.disabled, tx: tx)
        }

        let shouldShowRecoveryKeyReminder = db.read { tx in
            checkPreconditions(tx: tx)
        }
        XCTAssertFalse(shouldShowRecoveryKeyReminder, "Don't show reminder if backups is not enabled")
    }

    func testPreconditionsForRecoveryKeyMegaphone_neverDoneBackup() throws {
        db.write { tx in
            backupSettingsStore.setBackupPlan(.free, tx: tx)
        }

        let shouldShowRecoveryKeyReminder = db.read { tx in
            checkPreconditions(tx: tx)
        }
        XCTAssertFalse(shouldShowRecoveryKeyReminder, "Don't show reminder if user has never done a backup")
    }

    func testPreconditionsForRecoveryKeyMegaphone_backupsTooNew() throws {
        db.write { tx in
            backupSettingsStore.setBackupPlan(.free, tx: tx)
        }

        db.write { tx in
            backupSettingsStore.setLastBackupDate(Date(), tx: tx)
        }

        let shouldShowRecoveryKeyReminder = db.read { tx in
            checkPreconditions(tx: tx)
        }
        XCTAssertFalse(shouldShowRecoveryKeyReminder, "Don't show reminder if user just registered for backups")
    }

    func testPreconditionsForRecoveryKeyMegaphone_firstReminder() throws {
        db.write { tx in
            backupSettingsStore.setBackupPlan(.free, tx: tx)
        }

        let fifteenDaysAgo = Date().addingTimeInterval(-15 * 24 * 60 * 60)
        db.write { tx in
            backupSettingsStore.setLastBackupDate(fifteenDaysAgo, tx: tx)
        }

        let shouldShowRecoveryKeyReminder = db.read { tx in
            checkPreconditions(tx: tx)
        }
        XCTAssertTrue(shouldShowRecoveryKeyReminder, "Should show reminder if user registered long enough ago and hasn't seen a recovery key reminder yet")
    }

    func testPreconditionsForRecoveryKeyMegaphone_alreadySeenFirstReminder() throws {
        db.write { tx in
            backupSettingsStore.setBackupPlan(.free, tx: tx)
        }

        let fifteenDaysAgo = Date().addingTimeInterval(-15 * 24 * 60 * 60)
        db.write { tx in
            backupSettingsStore.setLastBackupDate(fifteenDaysAgo, tx: tx)
        }

        db.write { tx in
            backupSettingsStore.setLastRecoveryKeyReminderDate(Date(), tx: tx)
        }

        let shouldShowRecoveryKeyReminder = db.read { tx in
            checkPreconditions(tx: tx)
        }
        XCTAssertFalse(shouldShowRecoveryKeyReminder, "Don't show reminder if user has seen a recovery key reminder recently")
    }

    func testPreconditionsForRecoveryKeyMegaphone_longEnoughAfterFirstReminder() throws {
        db.write { tx in
            backupSettingsStore.setBackupPlan(.free, tx: tx)
        }

        let moreThanSixMonthsAgo = Date().addingTimeInterval(-190 * 24 * 60 * 60)
        db.write { tx in
            // This will also set first backup date if its nil
            backupSettingsStore.setLastBackupDate(moreThanSixMonthsAgo, tx: tx)
        }

        db.write { tx in
            backupSettingsStore.setLastRecoveryKeyReminderDate(moreThanSixMonthsAgo, tx: tx)
        }

        let shouldShowRecoveryKeyReminder = db.read { tx in
            checkPreconditions(tx: tx)
        }
        XCTAssertTrue(shouldShowRecoveryKeyReminder, "Should show reminder if user registered long enough ago and hasn't seen a reminder in awhile")
    }
}

// MARK: -

private extension BackupSettingsStore {
    func lastBackupDate(tx: DBReadTransaction) -> Date? {
        return lastBackupDetails(tx: tx)?.date
    }

    func setLastBackupDate(_ date: Date, tx: DBWriteTransaction) {
        setLastBackupDetails(date: date, backupFileSizeBytes: 1, backupMediaSizeBytes: 1, tx: tx)
    }
}
