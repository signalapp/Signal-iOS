//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class BackupSettingsStoreTests: XCTestCase {
    private var db: InMemoryDB!
    private var backupSettingsStore = BackupSettingsStore()

    override func setUp() {
        super.setUp()
        db = InMemoryDB()
    }

    func testLastAndFirstBackupDate() throws {
        var lastBackup = db.read { tx in
            backupSettingsStore.lastBackupDate(tx: tx)
        }
        XCTAssertNil(lastBackup, "Last backup should not be set")

        db.write { tx in
            backupSettingsStore.setLastBackupDate(Date(), tx: tx)
        }

        lastBackup = db.read { tx in
            backupSettingsStore.lastBackupDate(tx: tx)
        }
        XCTAssertNotNil(lastBackup, "Last backup should be set")

        var firstBackupDate = db.read { tx in
            backupSettingsStore.firstBackupDate(tx: tx)
        }
        XCTAssertNotNil(firstBackupDate, "First backup should be set with last backup")
        XCTAssertEqual(firstBackupDate, lastBackup, "First and last backups should be the same")

        let betweenBackupsDate = Date()

        db.write { tx in
            backupSettingsStore.setLastBackupDate(Date(), tx: tx)
        }

        firstBackupDate = db.read { tx in
            backupSettingsStore.firstBackupDate(tx: tx)
        }
        XCTAssertTrue(firstBackupDate! < betweenBackupsDate, "First backup should not update after it is first set")
    }

    func testBackupUpdatesRefreshDate() throws {
        var lastBackupRefresh = db.read { tx in
            backupSettingsStore.lastBackupRefreshDate(tx: tx)
        }
        XCTAssertNil(lastBackupRefresh, "Last backup should not be set")

        db.write { tx in
            backupSettingsStore.setLastBackupDate(Date(), tx: tx)
        }

        lastBackupRefresh = db.read { tx in
            backupSettingsStore.lastBackupRefreshDate(tx: tx)
        }
        XCTAssertNotNil(lastBackupRefresh, "Last backup should be set")
    }
}
