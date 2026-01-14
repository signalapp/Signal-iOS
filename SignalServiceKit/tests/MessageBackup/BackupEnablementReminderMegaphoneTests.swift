//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import Testing

@testable import SignalServiceKit

struct BackupEnablementReminderMegaphoneTests {
    private let backupSettingsStore = BackupSettingsStore()
    private let tsAccountManager = MockTSAccountManager()

    private let remoteConfigProvider: MockRemoteConfigProvider = {
        let provider = MockRemoteConfigProvider()
        provider._currentConfig = RemoteConfig(clockSkew: 0, valueFlags: ["ios.backupsMegaphone": "true"])
        return provider
    }()

    private let contactThread = TSContactThread(contactAddress: SignalServiceAddress(
        serviceId: Pni.randomForTesting(),
        phoneNumber: "+16505550101",
        cache: SignalServiceAddressCache(),
    ))
    private let experienceUpgrade = ExperienceUpgrade.makeNew(withManifest: ExperienceUpgradeManifest.enableBackupsReminder)

    private func insertInteraction(thread: TSThread, db: Database) {
        let interaction = TSInteraction(timestamp: 0, receivedAtTimestamp: 0, thread: thread)
        try! interaction.asRecord().insert(db)
    }

    private func checkPreconditions(tx: DBReadTransaction) -> Bool {
        return ExperienceUpgradeManifest.checkPreconditionsForBackupEnablementReminder(
            backupSettingsStore: backupSettingsStore,
            remoteConfigProvider: remoteConfigProvider,
            tsAccountManager: tsAccountManager,
            transaction: tx,
        )
    }

    // MARK: -

    @Test
    func testBackupsEnabled() {
        let db = InMemoryDB()

        db.write { tx in
            backupSettingsStore.setBackupPlan(.free, tx: tx)
        }

        db.read { tx in
            let shouldShowBackupEnablementReminder = checkPreconditions(tx: tx)
            #expect(!shouldShowBackupEnablementReminder, "Don't show reminder if backups is enabled")
        }
    }

    @Test
    func testRemoteConfigDisabled() {
        let db = InMemoryDB()

        for i in 0..<2000 {
            let outgoingMessage = TSOutgoingMessage(in: contactThread, messageBody: "good heavens + \(i)")
            db.write { tx in
                let db = tx.database
                try! outgoingMessage.asRecord().insert(db)
            }
        }

        db.read { tx in
            #expect(checkPreconditions(tx: tx), "Megaphone should be allowed!")
        }

        remoteConfigProvider._currentConfig = RemoteConfig(clockSkew: 0, valueFlags: [:])

        db.read { tx in
            #expect(!checkPreconditions(tx: tx), "Megaphone should be disallowed by remote config.")
        }
    }

    @Test
    func testLessThanRequiredMessages() {
        let db = InMemoryDB()

        db.write { tx in
            backupSettingsStore.setBackupPlan(.disabled, tx: tx)
        }

        db.read { tx in
            #expect(!checkPreconditions(tx: tx), "Don't show reminder if user doesn't have enough messages")
        }
    }

    func testHasRequiredMessages() {
        let db = InMemoryDB()

        db.write { tx in
            let db = tx.database
            try! contactThread.asRecord().insert(db)
        }

        for i in 0..<2000 {
            let outgoingMessage = TSOutgoingMessage(in: contactThread, messageBody: "good heavens + \(i)")
            db.write { tx in
                let db = tx.database
                try! outgoingMessage.asRecord().insert(db)
            }
        }

        db.read { tx in
            let shouldShowBackupEnablementReminder = checkPreconditions(tx: tx)
            #expect(shouldShowBackupEnablementReminder, "Should show reminder if user has enough messages")
        }
    }

    func testBackupsHasPreviouslyBeenEnabled() {
        let db = InMemoryDB()

        // Enable then disable backups
        db.write { tx in backupSettingsStore.setBackupPlan(.free, tx: tx) }
        db.write { tx in backupSettingsStore.setBackupPlan(.disabled, tx: tx) }

        db.write { tx in
            let db = tx.database
            try! contactThread.asRecord().insert(db)
        }

        for i in 0..<2000 {
            let outgoingMessage = TSOutgoingMessage(in: contactThread, messageBody: "good heavens + \(i)")
            db.write { tx in
                let db = tx.database
                try! outgoingMessage.asRecord().insert(db)
            }
        }

        db.read { tx in
            let shouldShowBackupEnablementReminder = checkPreconditions(tx: tx)
            #expect(!shouldShowBackupEnablementReminder, "Should not show reminder if user has enabled then disabled backups, even if they have enough messages")
        }
    }

    func testSnoozed() throws {
        experienceUpgrade.snoozeCount = 1

        experienceUpgrade.lastSnoozedTimestamp = Date().addingTimeInterval(-25 * TimeInterval.day).timeIntervalSince1970
        #expect(experienceUpgrade.isSnoozed, "should still be snoozed if last snooze was recent")

        experienceUpgrade.lastSnoozedTimestamp = Date().addingTimeInterval(-31 * TimeInterval.day).timeIntervalSince1970
        #expect(!experienceUpgrade.isSnoozed, "should not be snoozed if last snooze was long enough ago")

        experienceUpgrade.snoozeCount = 2
        experienceUpgrade.lastSnoozedTimestamp = Date().addingTimeInterval(-31 * TimeInterval.day).timeIntervalSince1970
        #expect(experienceUpgrade.isSnoozed, "should still be snoozed if last snooze was recent")

        experienceUpgrade.lastSnoozedTimestamp = Date().addingTimeInterval(-91 * TimeInterval.day).timeIntervalSince1970
        #expect(!experienceUpgrade.isSnoozed, "should not still be snoozed if last snooze was long enough ago")
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
