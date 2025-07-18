//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Testing

@testable import SignalServiceKit

@MainActor
struct BackupDisablingManagerTest {
    @Test
    func testPreviousFailurePersistsUntilFutureSuccess() async throws {
        let mockBackupAttachmentDownloadQueueStatusManager = MockBackupAttachmentDownloadQueueStatusManager()
        let mockBackupIdManager = MockBackupIdManager()
        let mockBackupPlanManager = MockBackupPlanManager()
        let mockBackupListMediaManager = MockBackupListMediaManager()
        let mockDB = InMemoryDB()
        let mockTSAccountManager = MockTSAccountManager()

        let disablingManager = BackupDisablingManager(
            authCredentialStore: AuthCredentialStore(),
            backupAttachmentDownloadQueueStatusManager: mockBackupAttachmentDownloadQueueStatusManager,
            backupCDNCredentialStore: BackupCDNCredentialStore(),
            backupIdManager: mockBackupIdManager,
            backupListMediaManager: mockBackupListMediaManager,
            backupPlanManager: mockBackupPlanManager,
            backupSettingsStore: BackupSettingsStore(),
            db: mockDB,
            tsAccountManager: mockTSAccountManager
        )

        struct DeleteBackupError: Error {}
        mockBackupIdManager.deleteBackupIdMock = { throw DeleteBackupError() }

        _ = await disablingManager.startDisablingBackups()
        await disablingManager.disableRemotelyIfNecessary()
        mockDB.read { tx in
            #expect(disablingManager.disableRemotelyFailed(tx: tx))
        }

        mockDB.write { tx in
            try! mockBackupPlanManager.setBackupPlan(.free, tx: tx)
            #expect(!disablingManager.disableRemotelyFailed(tx: tx))
        }

        mockBackupIdManager.deleteBackupIdMock = { }
        _ = await disablingManager.startDisablingBackups()
        await disablingManager.disableRemotelyIfNecessary()
        mockDB.read { tx in
            #expect(!disablingManager.disableRemotelyFailed(tx: tx))
        }
    }
}
