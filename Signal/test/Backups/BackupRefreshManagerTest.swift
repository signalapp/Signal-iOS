//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import Signal
@testable import SignalServiceKit
import Testing

@MainActor
struct BackupRefreshManagerTest {
    private let backupSettingsStore: BackupSettingsStore
    private let db: InMemoryDB
    private let accountKeyStore: AccountKeyStore
    private let mockNetworkManager: MockNetworkManager
    private let mockBackupRefreshManager: BackupRefreshManager

    init() {
        self.backupSettingsStore = BackupSettingsStore()
        self.db = InMemoryDB()
        self.accountKeyStore = AccountKeyStore(
            backupSettingsStore: backupSettingsStore,
        )
        self.mockNetworkManager = MockNetworkManager()
        self.mockBackupRefreshManager = BackupRefreshManager(
            accountKeyStore: accountKeyStore,
            backupRequestManager: BackupRequestManagerMock(),
            backupSettingsStore: backupSettingsStore,
            db: db,
            networkManager: mockNetworkManager,
        )
    }

    var refreshSuccessResponse: (TSRequest, NetworkManager.RetryPolicy) async throws -> HTTPResponse = { request, _ in
        if request.url.absoluteString.hasSuffix("v1/archives") {
            return HTTPResponse(requestUrl: request.url, status: 204, headers: HttpHeaders(), bodyData: Data())
        }
        throw OWSAssertionError("")
    }

    @Test
    func testRefresh() async throws {
        // Set up.
        db.write { tx in
            backupSettingsStore.setBackupPlan(.free, tx: tx)
            accountKeyStore.setAccountEntropyPool(AccountEntropyPool(), tx: tx)
        }
        mockNetworkManager.asyncRequestHandlers.append(refreshSuccessResponse)
        mockNetworkManager.asyncRequestHandlers.append(refreshSuccessResponse)

        try await mockBackupRefreshManager.refreshBackup(localIdentifiers: LocalIdentifiers.forUnitTests)

        #expect(mockNetworkManager.asyncRequestHandlers.isEmpty)
    }

    @Test
    func testDisabledBackupIgnoresRefresh() async throws {
        // Set up.
        db.write { tx in
            backupSettingsStore.setBackupPlan(.disabled, tx: tx)
            accountKeyStore.setAccountEntropyPool(AccountEntropyPool(), tx: tx)
        }

        try await mockBackupRefreshManager.refreshBackup(localIdentifiers: LocalIdentifiers.forUnitTests)
    }
}
