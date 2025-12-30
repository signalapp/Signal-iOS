//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

/// Responsible for CRUD of the "BackupKey", which is an asymmetric key used to
/// sign Backup auth credentials.
///
/// - SeeAlso ``BackupIdService``
public protocol BackupKeyService {

    /// "Enable" Backups by setting a public key used to sign Backup auth
    /// credentials. This should only be done once for a given account while
    /// Backups remains enabled, although it is idempotent and safe to call
    /// repeatedly.
    func registerBackupKey(
        localIdentifiers: LocalIdentifiers,
        auth: ChatServiceAuth,
    ) async throws

    /// De-initialize Backups by deleting a previously-registered BackupKey.
    /// This is effectively a "delete Backup" operation, as subsequent to this
    /// operation any Backup-related objects for this account will be deleted
    /// from the server.
    ///
    /// - Important
    /// This operation is key to, but not all of, "disabling Backups". Callers
    /// interested in a user-level "disable Backups" operation should instead
    /// refer to `BackupDisablingManager`.
    func deleteBackupKey(
        localIdentifiers: LocalIdentifiers,
        auth: ChatServiceAuth,
    ) async throws

    /// See ``deleteBackupKey(localIdentifiers:auth:)``. Similar, but with
    /// Backup auth prepared ahead of time.
    func deleteBackupKey(
        localIdentifiers: LocalIdentifiers,
        backupAuth: BackupServiceAuth,
    ) async throws
}

// MARK: -

final class BackupKeyServiceImpl: BackupKeyService {
    private let accountKeyStore: AccountKeyStore
    private let backupRequestManager: BackupRequestManager
    private let backupSettingsStore: BackupSettingsStore
    private let db: DB
    private let logger: PrefixedLogger
    private let networkManager: NetworkManager

    init(
        accountKeyStore: AccountKeyStore,
        backupRequestManager: BackupRequestManager,
        backupSettingsStore: BackupSettingsStore,
        db: DB,
        networkManager: NetworkManager,
    ) {
        self.accountKeyStore = accountKeyStore
        self.backupRequestManager = backupRequestManager
        self.backupSettingsStore = backupSettingsStore
        self.db = db
        self.logger = PrefixedLogger(prefix: "[Backups]")
        self.networkManager = networkManager
    }

    private func rootBackupKeys(
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction,
    ) throws -> (MessageRootBackupKey, MediaRootBackupKey) {
        guard let messageRootBackupKey = try? accountKeyStore.getMessageRootBackupKey(aci: localIdentifiers.aci, tx: tx) else {
            throw OWSAssertionError("Missing message root backup key! Do we not have an AEP?")
        }

        let mediaRootBackupKey = accountKeyStore.getOrGenerateMediaRootBackupKey(tx: tx)

        return (messageRootBackupKey, mediaRootBackupKey)
    }

    // MARK: -

    func registerBackupKey(
        localIdentifiers: LocalIdentifiers,
        auth: ChatServiceAuth,
    ) async throws {
        try await _registerBackupKey(
            localIdentifiers: localIdentifiers,
            auth: auth,
            retryOnFail: true,
        )
    }

    private func _registerBackupKey(
        localIdentifiers: LocalIdentifiers,
        auth: ChatServiceAuth,
        retryOnFail: Bool,
    ) async throws {
        let (messageBackupKey, mediaBackupKey) = try await db.awaitableWrite { tx in
            try rootBackupKeys(localIdentifiers: localIdentifiers, tx: tx)
        }

        do {
            let messageBackupAuth = try await backupRequestManager.fetchBackupServiceAuth(
                for: messageBackupKey,
                localAci: localIdentifiers.aci,
                auth: auth,
            )

            _ = try await networkManager.asyncRequest(
                .backupSetPublicKeyRequest(backupAuth: messageBackupAuth),
            )

            let mediaBackupAuth = try await backupRequestManager.fetchBackupServiceAuth(
                for: mediaBackupKey,
                localAci: localIdentifiers.aci,
                auth: auth,
            )

            _ = try await networkManager.asyncRequest(
                .backupSetPublicKeyRequest(backupAuth: mediaBackupAuth),
            )
        } catch SignalError.verificationFailed where retryOnFail {
            // This error is thrown if the backupID was never registered remotely.
            // We *should* set it above in registerBackupIDIfNecessary based on local state,
            // but in case local and remote state ever get out of sync, this will clear
            // local state and re-register the backupID remotely.
            Logger.error("Verification failed fetching BackupServiceAuth, clearing local state and retrying once.")
            await db.awaitableWrite { tx in
                BackupSettingsStore().setHaveSetBackupID(haveSetBackupID: false, tx: tx)
            }

            return try await _registerBackupKey(
                localIdentifiers: localIdentifiers,
                auth: auth,
                retryOnFail: false,
            )
        }
    }

    // MARK: -

    func deleteBackupKey(
        localIdentifiers: LocalIdentifiers,
        auth: ChatServiceAuth,
    ) async throws {
        let (
            messageBackupKey,
            mediaBackupKey,
        ) = db.read { (
            try? accountKeyStore.getMessageRootBackupKey(aci: localIdentifiers.aci, tx: $0),
            accountKeyStore.getMediaRootBackupKey(tx: $0),
        ) }

        func deleteBackup(key: BackupKeyMaterial) async throws {
            let backupAuth = try await backupRequestManager.fetchBackupServiceAuth(
                for: key,
                localAci: localIdentifiers.aci,
                auth: auth,
            )

            try await deleteBackupKey(
                localIdentifiers: localIdentifiers,
                backupAuth: backupAuth,
            )
        }

        if let messageBackupKey {
            try await deleteBackup(key: messageBackupKey)
        }
        if let mediaBackupKey {
            try await deleteBackup(key: mediaBackupKey)
        }
    }

    func deleteBackupKey(
        localIdentifiers: LocalIdentifiers,
        backupAuth: BackupServiceAuth,
    ) async throws {
        do {
            _ = try await networkManager.asyncRequest(
                .deleteBackupRequest(backupAuth: backupAuth),
            )
        } catch where error.httpStatusCode == 401 {
            // This will happen if, for whatever reason, the user doesn't have
            // a Backup to delete. (It's a 401 because this really means the
            // server has deleted the key we use to authenticate Backup
            // requests, which happens in response to an earlier success in
            // calling this API.)
            //
            // Treat this like a success: maybe we deleted earlier, but
            // never got the response back.
            logger.warn("Got 401 deleting Backup: treating like success.")
        }
    }

    // MARK: -

    private struct NetworkAPI {
        private let networkManager: NetworkManager

        init(networkManager: NetworkManager) {
            self.networkManager = networkManager
        }

        func registerBackupKey(
            backupAuth: BackupServiceAuth,
        ) async throws {
            _ = try await networkManager.asyncRequest(
                .backupSetPublicKeyRequest(backupAuth: backupAuth),
            )
        }
    }
}

// MARK: -

private extension TSRequest {
    static func backupSetPublicKeyRequest(
        backupAuth: BackupServiceAuth,
    ) -> TSRequest {
        var request = TSRequest(
            url: URL(string: "v1/archives/keys")!,
            method: "PUT",
            parameters: ["backupIdPublicKey": backupAuth.publicKey.serialize().base64EncodedString()],
        )
        request.auth = .backup(backupAuth)
        return request
    }

    static func deleteBackupRequest(
        backupAuth: BackupServiceAuth,
    ) -> TSRequest {
        var request = TSRequest(
            url: URL(string: "v1/archives")!,
            method: "DELETE",
            parameters: nil,
        )
        // The first time you call this, a "delete" operation is enqueued on the
        // server to be performed asynchronously (e.g., within 24h). If you call
        // again with an async deletion already enqueued, it'll delete
        // synchronously, which can be very slow.
        request.timeoutInterval = 30
        request.auth = .backup(backupAuth)
        return request
    }
}

// MARK: -

#if TESTABLE_BUILD

class MockBackupKeyService: BackupKeyService {
    func registerBackupKey(localIdentifiers: LocalIdentifiers, auth: ChatServiceAuth) async throws {
        // Do nothing
    }

    var deleteBackupKeyMock: (() async throws -> Void)?
    func deleteBackupKey(localIdentifiers: LocalIdentifiers, auth: ChatServiceAuth) async throws {
        if let deleteBackupKeyMock {
            return try await deleteBackupKeyMock()
        }
    }

    func deleteBackupKey(localIdentifiers: LocalIdentifiers, backupAuth: BackupServiceAuth) async throws {
        // Do nothing
    }
}

#endif
