//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class BackupKeyReminderMegaphoneTests: XCTestCase {
    private var db: InMemoryDB!
    private var backupSettingsStore = BackupSettingsStore()

    override func setUp() {
        super.setUp()
        db = InMemoryDB()
    }

    private func checkPreconditions(tx: DBReadTransaction) -> Bool {
        let remoteConfig = RemoteConfig(clockSkew: 0, valueFlags: [
            "ios.allowBackups": "true"
        ])

        return ExperienceUpgradeManifest.checkPreconditionsForBackupKeyReminder(
            remoteConfig: remoteConfig,
            transaction: tx
        )
    }

    func testPreconditionsForBackupKeyMegaphone_backupsDisabled() throws {
        db.write { tx in
            backupSettingsStore.setBackupPlan(.disabled, tx: tx)
        }

        let shouldShowBackupKeyReminder = db.read { tx in
            checkPreconditions(tx: tx)
        }
        XCTAssertFalse(shouldShowBackupKeyReminder, "Don't show reminder if backups is not enabled")
    }

    func testPreconditionsForBackupKeyMegaphone_neverDoneBackup() throws {
        db.write { tx in
            backupSettingsStore.setBackupPlan(.free, tx: tx)
        }

        let shouldShowBackupKeyReminder = db.read { tx in
            checkPreconditions(tx: tx)
        }
        XCTAssertFalse(shouldShowBackupKeyReminder, "Don't show reminder if user has never done a backup")
    }

    func testPreconditionsForBackupKeyMegaphone_backupsTooNew() throws {
        db.write { tx in
            backupSettingsStore.setBackupPlan(.free, tx: tx)
        }

        db.write { tx in
            backupSettingsStore.setLastBackupDate(Date(), tx: tx)
        }

        let shouldShowBackupKeyReminder = db.read { tx in
            checkPreconditions(tx: tx)
        }
        XCTAssertFalse(shouldShowBackupKeyReminder, "Don't show reminder if user just registered for backups")
    }

    func testPreconditionsForBackupKeyMegaphone_firstReminder() throws {
        db.write { tx in
            backupSettingsStore.setBackupPlan(.free, tx: tx)
        }

        let fifteenDaysAgo = Date().addingTimeInterval(-15 * 24 * 60 * 60)
        db.write { tx in
            backupSettingsStore.setLastBackupDate(fifteenDaysAgo, tx: tx)
        }

        let shouldShowBackupKeyReminder = db.read { tx in
            checkPreconditions(tx: tx)
        }
        XCTAssertTrue(shouldShowBackupKeyReminder, "Should show reminder if user registered long enough ago and hasn't seen a backup key reminder yet")
    }

    func testPreconditionsForBackupKeyMegaphone_alreadySeenFirstReminder() throws {
        db.write { tx in
            backupSettingsStore.setBackupPlan(.free, tx: tx)
        }

        let fifteenDaysAgo = Date().addingTimeInterval(-15 * 24 * 60 * 60)
        db.write { tx in
            backupSettingsStore.setLastBackupDate(fifteenDaysAgo, tx: tx)
        }

        db.write { tx in
            backupSettingsStore.setLastBackupKeyReminderDate(Date(), tx: tx)
        }

        let shouldShowBackupKeyReminder = db.read { tx in
            checkPreconditions(tx: tx)
        }
        XCTAssertFalse(shouldShowBackupKeyReminder, "Don't show reminder if user has seen a backup key reminder recently")
    }

    func testPreconditionsForBackupKeyMegaphone_longEnoughAfterFirstReminder() throws {
        db.write { tx in
            backupSettingsStore.setBackupPlan(.free, tx: tx)
        }

        let moreThanSixMonthsAgo = Date().addingTimeInterval(-190 * 24 * 60 * 60)
        db.write { tx in
            // This will also set first backup date if its nil
            backupSettingsStore.setLastBackupDate(moreThanSixMonthsAgo, tx: tx)
        }

        db.write { tx in
            backupSettingsStore.setLastBackupKeyReminderDate(moreThanSixMonthsAgo, tx: tx)
        }

        let shouldShowBackupKeyReminder = db.read { tx in
            checkPreconditions(tx: tx)
        }
        XCTAssertTrue(shouldShowBackupKeyReminder, "Should show reminder if user registered long enough ago and hasn't seen a reminder in awhile")
    }
}
