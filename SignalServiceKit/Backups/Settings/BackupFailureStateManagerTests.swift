//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Testing
@testable import SignalServiceKit

class BackupFailureStateManagerTests {
    private let backupSettingStore = BackupSettingsStore()
    private let db: DB!
    private var date: Date!
    private var dateProvider: DateProvider!
    private var sut: BackupFailureStateManager!

    init() {
        self.db = InMemoryDB()
        self.date = Date()
        self.dateProvider = { self.date }
        self.sut = BackupFailureStateManager(dateProvider: self.dateProvider)
        db.write {
            backupSettingStore.setBackupPlan(.paid(optimizeLocalStorage: true), tx: $0)
        }
    }

    @Test func testShowPrompt() {
        db.write {
            backupSettingStore.setLastBackupDate(timeBeforeNow(7 * .day), tx: $0)
            backupSettingStore.setLastBackupFailed(tx: $0)
        }

        let showPrompt = db.read { sut.shouldShowBackupFailurePrompt(tx: $0) }
        #expect(showPrompt)
    }

    @Test func testNoShowPrompt() {
        db.write {
            backupSettingStore.setLastBackupDate(timeBeforeNow(6 * .day), tx: $0)
            backupSettingStore.setLastBackupFailed(tx: $0)
        }

        let showPrompt = db.read { sut.shouldShowBackupFailurePrompt(tx: $0) }
        #expect(showPrompt == false)
    }

    @Test func testShowPromptAfterNeverSucceeding() {
        db.write {
            backupSettingStore.setLastBackupEnabledDetails(
                backupsEnabledTime: timeBeforeNow(7 * .day),
                notificationDelay: 0,
                tx: $0
            )
            backupSettingStore.setLastBackupFailed(tx: $0)
        }

        let showPrompt = db.read { sut.shouldShowBackupFailurePrompt(tx: $0) }
        #expect(showPrompt)
    }

    // Test Snooze
    @Test func testSnoozePrompt() {
        db.write {
            backupSettingStore.setLastBackupDate(timeBeforeNow(7 * .day), tx: $0)
            backupSettingStore.setLastBackupFailed(tx: $0)
            sut.snoozeBackupFailurePrompt(tx: $0)
        }

        var showPrompt = db.read { sut.shouldShowBackupFailurePrompt(tx: $0) }
        #expect(showPrompt == false)

        // Fast forward 1 day (and 1 second)
        date = date.addingTimeInterval(.day + 1)

        showPrompt = db.read { sut.shouldShowBackupFailurePrompt(tx: $0) }
        #expect(showPrompt == false)

        // Fast forward another day (and 1 second)
        date = date.addingTimeInterval(.day + 1)

        showPrompt = db.read { sut.shouldShowBackupFailurePrompt(tx: $0) }
        #expect(showPrompt)
    }

    private func timeBeforeNow(_ interval: TimeInterval) -> Date {
        // bump the time a second earlier than the requested time to avoid running
        // into small time differences that trip up comparisons.
        return dateProvider().advanced(by: -(interval) - 1)
    }
}
