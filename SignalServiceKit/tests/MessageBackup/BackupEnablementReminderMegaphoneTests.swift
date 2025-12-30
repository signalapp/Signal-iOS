//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient
import XCTest

@testable import SignalServiceKit

class BackupEnablementReminderMegaphoneTests: XCTestCase {
    private let db: DB = InMemoryDB()
    private let backupSettingsStore: BackupSettingsStore = BackupSettingsStore()
    private let tsAccountManager: TSAccountManager = MockTSAccountManager()

    private var contactThread: TSContactThread!
    private var experienceUpgrade: ExperienceUpgrade!

    override func setUp() {
        super.setUp()
        let testPhone = E164("+16505550101")!
        let testPNI = Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b1")

        contactThread = TSContactThread(contactAddress: SignalServiceAddress(
            serviceId: testPNI,
            phoneNumber: testPhone.stringValue,
            cache: SignalServiceAddressCache(),
        ))
        experienceUpgrade = ExperienceUpgrade.makeNew(withManifest: ExperienceUpgradeManifest.enableBackupsReminder)
    }

    private func insertInteraction(thread: TSThread, db: Database) {
        let interaction = TSInteraction(timestamp: 0, receivedAtTimestamp: 0, thread: thread)
        try! interaction.asRecord().insert(db)
    }

    private func checkPreconditions(tx: DBReadTransaction) -> Bool {
        return ExperienceUpgradeManifest.checkPreconditionsForBackupEnablementReminder(
            backupSettingsStore: backupSettingsStore,
            tsAccountManager: tsAccountManager,
            transaction: tx,
        )
    }

    func testPreconditionsForRecoveryKeyMegaphone_backupsEnabled() throws {
        db.write { tx in
            backupSettingsStore.setBackupPlan(.free, tx: tx)
        }

        db.read { tx in
            let shouldShowBackupEnablementReminder = checkPreconditions(tx: tx)
            XCTAssertFalse(shouldShowBackupEnablementReminder, "Don't show reminder if backups is enabled")
        }
    }

    func testPreconditionsForRecoveryKeyMegaphone_lessThanRequiredMessages() throws {
        db.write { tx in
            backupSettingsStore.setBackupPlan(.disabled, tx: tx)
        }

        db.read { tx in
            XCTAssertFalse(checkPreconditions(tx: tx), "Don't show reminder if user doesn't have enough messages")
        }
    }

    func testPreconditionsForRecoveryKeyMegaphone_hasRequiredMessages() throws {
        db.write { tx in
            let db = tx.database
            try! contactThread!.asRecord().insert(db)
        }

        for i in 0..<2000 {
            let outgoingMessage = TSOutgoingMessage(in: contactThread!, messageBody: "good heavens + \(i)")
            db.write { tx in
                let db = tx.database
                try! outgoingMessage.asRecord().insert(db)
            }
        }

        db.read { tx in
            let shouldShowBackupEnablementReminder = checkPreconditions(tx: tx)
            XCTAssertTrue(shouldShowBackupEnablementReminder, "Should show reminder if user has enough messages")
        }
    }

    func testPreconditionsForRecoveryKeyMegaphone_backupsHasPreviouslyBeenEnabled() throws {

        // Enable then disable backups
        db.write { tx in backupSettingsStore.setBackupPlan(.free, tx: tx) }
        db.write { tx in backupSettingsStore.setBackupPlan(.disabled, tx: tx) }

        db.write { tx in
            let db = tx.database
            try! contactThread!.asRecord().insert(db)
        }

        for i in 0..<2000 {
            let outgoingMessage = TSOutgoingMessage(in: contactThread!, messageBody: "good heavens + \(i)")
            db.write { tx in
                let db = tx.database
                try! outgoingMessage.asRecord().insert(db)
            }
        }

        db.read { tx in
            let shouldShowBackupEnablementReminder = checkPreconditions(tx: tx)
            XCTAssertFalse(shouldShowBackupEnablementReminder, "Should not show reminder if user has enabled then disabled backups, even if they have enough messages")
        }
    }

    func testPreconditionsForRecoveryKeyMegaphone_snoozed() throws {
        experienceUpgrade.snoozeCount = 1

        experienceUpgrade.lastSnoozedTimestamp = Date().addingTimeInterval(-25 * TimeInterval.day).timeIntervalSince1970
        XCTAssertTrue(experienceUpgrade.isSnoozed, "should still be snoozed if last snooze was recent")

        experienceUpgrade.lastSnoozedTimestamp = Date().addingTimeInterval(-31 * TimeInterval.day).timeIntervalSince1970
        XCTAssertFalse(experienceUpgrade.isSnoozed, "should not be snoozed if last snooze was long enough ago")

        experienceUpgrade.snoozeCount = 2
        experienceUpgrade.lastSnoozedTimestamp = Date().addingTimeInterval(-31 * TimeInterval.day).timeIntervalSince1970
        XCTAssertTrue(experienceUpgrade.isSnoozed, "should still be snoozed if last snooze was recent")

        experienceUpgrade.lastSnoozedTimestamp = Date().addingTimeInterval(-91 * TimeInterval.day).timeIntervalSince1970
        XCTAssertFalse(experienceUpgrade.isSnoozed, "should not still be snoozed if last snooze was long enough ago")
    }
}

// MARK: -

private extension TSOutgoingMessage {
    convenience init(in thread: TSThread, messageBody: String) {
        let builder: TSOutgoingMessageBuilder = .withDefaultValues(
            thread: thread,
            messageBody: AttachmentContentValidatorMock.mockValidatedBody(messageBody),
        )
        self.init(outgoingMessageWith: builder, recipientAddressStates: [:])
    }
}
