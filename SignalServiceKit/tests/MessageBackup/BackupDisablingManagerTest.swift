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
        let mockAccountEntropyPoolManager = MockAccountEntropyPoolManager()
        let mockAuthCredentialStore = AuthCredentialStore(dateProvider: { Date() })
        let mockBackupAttachmentDownloadQueueStatusManager = MockBackupAttachmentDownloadQueueStatusManager()
        let mockBackupCDNCredentialStore = BackupCDNCredentialStore()
        let mockBackupKeyService = MockBackupKeyService()
        let mockBackupAttachmentCoordinator = MockBackupAttachmentCoordinator()
        let mockBackupPlanManager = MockBackupPlanManager()
        let mockDB = InMemoryDB()
        let mockBackupSettingsStore = BackupSettingsStore()
        let mockTSAccountManager = MockTSAccountManager()

        let disablingManager = BackupDisablingManager(
            accountEntropyPoolManager: mockAccountEntropyPoolManager,
            authCredentialStore: mockAuthCredentialStore,
            backupAttachmentCoordinator: mockBackupAttachmentCoordinator,
            backupAttachmentDownloadQueueStatusManager: mockBackupAttachmentDownloadQueueStatusManager,
            backupCDNCredentialStore: mockBackupCDNCredentialStore,
            backupKeyService: mockBackupKeyService,
            backupPlanManager: mockBackupPlanManager,
            backupSettingsStore: mockBackupSettingsStore,
            db: mockDB,
            tsAccountManager: mockTSAccountManager,
        )

        struct DeleteBackupError: Error {}
        mockBackupKeyService.deleteBackupKeyMock = { throw DeleteBackupError() }

        _ = await disablingManager.startDisablingBackups(aepSideEffect: nil)
        await disablingManager.disableRemotelyIfNecessary()
        mockDB.read { tx in
            #expect(disablingManager.disableRemotelyFailed(tx: tx))
        }

        mockDB.write { tx in
            mockBackupPlanManager.setBackupPlan(.free, tx: tx)
            #expect(!disablingManager.disableRemotelyFailed(tx: tx))
        }

        mockBackupKeyService.deleteBackupKeyMock = { }
        _ = await disablingManager.startDisablingBackups(aepSideEffect: nil)
        await disablingManager.disableRemotelyIfNecessary()
        mockDB.read { tx in
            #expect(!disablingManager.disableRemotelyFailed(tx: tx))
        }
    }
}
