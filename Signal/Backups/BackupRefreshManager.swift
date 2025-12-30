//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit

// MARK: -

final class BackupRefreshManager {
    private let accountKeyStore: AccountKeyStore
    private let api: NetworkAPI
    private let backupRequestManager: BackupRequestManager
    private let backupSettingsStore: BackupSettingsStore
    private let db: DB

    // Backups may expire after 30 days. Do a refresh every few days
    // to account for if the app isn't opened often.
    static let backupRefreshTimeInterval: TimeInterval = 3 * .day

    init(
        accountKeyStore: AccountKeyStore,
        backupRequestManager: BackupRequestManager,
        backupSettingsStore: BackupSettingsStore,
        db: DB,
        networkManager: NetworkManagerProtocol,
    ) {
        self.accountKeyStore = accountKeyStore
        self.api = NetworkAPI(networkManager: networkManager)
        self.backupRequestManager = backupRequestManager
        self.backupSettingsStore = backupSettingsStore
        self.db = db
    }

    private func rootBackupKeys(localIdentifiers: LocalIdentifiers) async throws -> (MessageRootBackupKey, MediaRootBackupKey) {
        try await db.awaitableWrite { tx in
            guard let messageRootBackupKey = try? accountKeyStore.getMessageRootBackupKey(aci: localIdentifiers.aci, tx: tx) else {
                throw OWSAssertionError("Missing message root backup key! Do we not have an AEP?")
            }

            // If we don't yet have an MRBK, this is an appropriate point to
            // generate one.
            let mediaRootBackupKey = accountKeyStore.getOrGenerateMediaRootBackupKey(tx: tx)

            return (messageRootBackupKey, mediaRootBackupKey)
        }
    }

    func refreshBackup(localIdentifiers: LocalIdentifiers) async throws {
        let backupPlan = db.read(block: backupSettingsStore.backupPlan(tx:))
        switch backupPlan {
        case .disabled:
            return
        case .disabling, .free, .paid, .paidExpiringSoon, .paidAsTester:
            break
        }

        let (messageBackupKey, mediaBackupKey) = try await rootBackupKeys(localIdentifiers: localIdentifiers)
        let messageBackupAuth = try await backupRequestManager.fetchBackupServiceAuth(
            for: messageBackupKey,
            localAci: localIdentifiers.aci,
            auth: .implicit(),
        )
        try await api.refreshBackup(auth: messageBackupAuth)

        let mediaBackupAuth = try await backupRequestManager.fetchBackupServiceAuth(
            for: mediaBackupKey,
            localAci: localIdentifiers.aci,
            auth: .implicit(),
        )
        try await api.refreshBackup(auth: mediaBackupAuth)
    }

    // MARK: -

    private struct NetworkAPI {
        private let networkManager: NetworkManagerProtocol

        init(networkManager: NetworkManagerProtocol) {
            self.networkManager = networkManager
        }

        func refreshBackup(auth: BackupServiceAuth) async throws {
            _ = try await networkManager.asyncRequest(.refreshBackup(auth: auth))
        }
    }
}

// MARK: -

private extension TSRequest {
    static func refreshBackup(auth: BackupServiceAuth) -> TSRequest {
        var request = TSRequest(
            url: URL(string: "v1/archives")!,
            method: "POST",
            parameters: [:],
        )
        request.auth = .backup(auth)
        return request
    }
}
