//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import GRDB
import XCTest

@testable import SignalServiceKit

class BackupEnablementReminderMegaphoneTests: XCTestCase {
    private let db = InMemoryDB()
    private let backupSettingsStore = BackupSettingsStore()
    private var contactThread: TSContactThread!

    override func setUp() {
        super.setUp()
        let testPhone = E164("+16505550101")!
        let testPNI = Pni.constantForTesting("PNI:00000000-0000-4000-8000-0000000000b1")
        contactThread = TSContactThread(contactAddress: SignalServiceAddress(
            serviceId: testPNI,
            phoneNumber: testPhone.stringValue,
            cache: SignalServiceAddressCache()
        ))
    }

    private func insertInteraction(thread: TSThread, db: Database) {
        let interaction = TSInteraction(timestamp: 0, receivedAtTimestamp: 0, thread: thread)
        try! interaction.asRecord().insert(db)
    }

    func testPreconditionsForBackupKeyMegaphone_backupsEnabled() throws {
        db.write { tx in
            backupSettingsStore.setBackupPlan(.free, tx: tx)
        }

        db.read { tx in
            let shouldShowBackupEnablementReminder = ExperienceUpgradeManifest.checkPreconditionsForBackupEnablementReminder(transaction: tx)
            XCTAssertFalse(shouldShowBackupEnablementReminder, "Don't show reminder if backups is enabled")
        }
    }

    func testPreconditionsForBackupKeyMegaphone_lessThanRequiredMessages() throws {
        db.write { tx in
            backupSettingsStore.setBackupPlan(.disabled, tx: tx)
        }

        db.read { transaction in
            XCTAssertFalse(ExperienceUpgradeManifest.checkPreconditionsForBackupEnablementReminder(transaction: transaction), "Don't show reminder if user doesn't have enough messages")
        }
    }

    func testPreconditionsForBackupKeyMegaphone_hasRequiredMessages() throws {
        db.write { tx in
            backupSettingsStore.setBackupPlan(.disabled, tx: tx)
        }

        db.write { transaction in
            let db = transaction.database
            try! contactThread!.asRecord().insert(db)
        }

        for i in 0..<2000 {
            let outgoingMessage = TSOutgoingMessage(in: contactThread!, messageBody: "good heavens + \(i)")
            db.write { transaction in
                let db = transaction.database
                try! outgoingMessage.asRecord().insert(db)
            }
        }

        db.read { transaction in
            let shouldShowBackupEnablementReminder = ExperienceUpgradeManifest.checkPreconditionsForBackupEnablementReminder(transaction: transaction)
            XCTAssertTrue(shouldShowBackupEnablementReminder, "Should show reminder if user has enough messages")
        }
    }
}

// MARK: -

private extension TSOutgoingMessage {
    convenience init(in thread: TSThread, messageBody: String) {
        let builder: TSOutgoingMessageBuilder = .withDefaultValues(thread: thread, messageBody: messageBody)
        self.init(outgoingMessageWith: builder, recipientAddressStates: [:])
    }
}
