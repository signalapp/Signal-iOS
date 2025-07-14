//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

/// An opaque token returned after registering a Backup ID, which can be
/// required by APIs that require a Backup ID to have been previously
/// registered in order to succeed.
public struct RegisteredBackupIDToken {}

/// Responsible for CRUD of the "Backup ID" and related keys, which are required
/// for CRUD on Backup materials (archives, media) themselves.
public protocol BackupIdManager {
    /// Initialize Backups by reserving a "Backup ID" and registering a public
    /// key used to sign Backup auth credentials. This only needs to be done
    /// once for a given account while Backups remains enabled.
    ///
    /// - Note
    /// These APIs are idempotent and safe to call multiple times.
    ///
    /// - Returns
    /// An opaque token indicating that a Backup ID has been registered.
    func registerBackupId(
        localIdentifiers: LocalIdentifiers,
        auth: ChatServiceAuth
    ) async throws -> RegisteredBackupIDToken

    /// De-initialize Backups by deleting the "Backup ID". This is effectively a
    /// "delete Backup" operation, as subsequent to this operation any
    /// Backup-related objects for this account will be deleted from the server.
    ///
    /// - Important
    /// This operation is key to, but not all of, "disabling Backups". Callers
    /// interested in a user-level "disable Backups" operation should instead
    /// refer to `BackupDisablingManager`.
    func deleteBackupId(
        localIdentifiers: LocalIdentifiers,
        auth: ChatServiceAuth
    ) async throws

    /// See ``deleteBackupId(localIdentifiers:auth:)``. Similar, but with
    /// Backup auth prepared ahead of time.
    func deleteBackupId(
        localIdentifiers: LocalIdentifiers,
        backupAuth: BackupServiceAuth
    ) async throws
}

// MARK: -

final class BackupIdManagerImpl: BackupIdManager {
    private let accountKeyStore: AccountKeyStore
    private let api: NetworkAPI
    private let backupRequestManager: BackupRequestManager
    private let db: DB

    init(
        accountKeyStore: AccountKeyStore,
        backupRequestManager: BackupRequestManager,
        db: DB,
        networkManager: NetworkManager,
    ) {
        self.accountKeyStore = accountKeyStore
        self.api = NetworkAPI(networkManager: networkManager)
        self.backupRequestManager = backupRequestManager
        self.db = db
    }

    func registerBackupId(
        localIdentifiers: LocalIdentifiers,
        auth: ChatServiceAuth
    ) async throws -> RegisteredBackupIDToken {
        let (
            messageBackupKey,
            mediaBackupKey
        ): (
            BackupKey,
            BackupKey
        ) = try await db.awaitableWrite { tx in

            guard let messageRootBackupKey = accountKeyStore.getMessageRootBackupKey(tx: tx) else {
                throw OWSAssertionError("Missing message root backup key! Do we not have an AEP?")
            }

            // If we don't yet have an MRBK, this is an appropriate point to
            // agenerate one.
            let mediaRootBackupKey = accountKeyStore.getOrGenerateMediaRootBackupKey(tx: tx)

            return (messageRootBackupKey, mediaRootBackupKey)
        }

        try await api.reserveBackupId(
            localAci: localIdentifiers.aci,
            messageBackupKey: messageBackupKey,
            mediaBackupKey: mediaBackupKey,
            auth: auth
        )

        for credentialType in BackupAuthCredentialType.allCases {
            let backupAuth = try await backupRequestManager.fetchBackupServiceAuth(
                for: credentialType,
                localAci: localIdentifiers.aci,
                auth: auth
            )

            try await api.registerBackupKey(backupAuth: backupAuth)
        }

        return RegisteredBackupIDToken()
    }

    func deleteBackupId(
        localIdentifiers: LocalIdentifiers,
        auth: ChatServiceAuth
    ) async throws {
        for credentialType in BackupAuthCredentialType.allCases {
            let backupAuth = try await backupRequestManager.fetchBackupServiceAuth(
                for: credentialType,
                localAci: localIdentifiers.aci,
                auth: auth
            )

            try await deleteBackupId(
                localIdentifiers: localIdentifiers,
                backupAuth: backupAuth
            )
        }
    }

    func deleteBackupId(
        localIdentifiers: LocalIdentifiers,
        backupAuth: BackupServiceAuth
    ) async throws {
        do {
            try await api.deleteBackupId(backupAuth: backupAuth)
        } catch where error.httpStatusCode == 401 {
            // This will happen if, for whatever reason, the user doesn't have
            // a Backup to delete. (It's a 401 because this really means the
            // server has deleted the key we use to authenticate Backup
            // requests, which happens in response to an earlier success in
            // calling this API.)
            //
            // Treat this like a success: maybe we deleted earlier, but
            // never got the response back.
        }
    }

    // MARK: -

    private struct NetworkAPI {
        private let networkManager: NetworkManager

        init(networkManager: NetworkManager) {
            self.networkManager = networkManager
        }

        func registerBackupKey(
            backupAuth: BackupServiceAuth
        ) async throws {
            _ = try await networkManager.asyncRequest(
                .backupSetPublicKeyRequest(backupAuth: backupAuth)
            )
        }

        func reserveBackupId(
            localAci: Aci,
            messageBackupKey: BackupKey,
            mediaBackupKey: BackupKey,
            auth: ChatServiceAuth
        ) async throws {
            let messageBackupRequestContext: BackupAuthCredentialRequestContext = .create(
                backupKey: messageBackupKey.serialize(),
                aci: localAci.rawUUID
            )
            let mediaBackupRequestContext: BackupAuthCredentialRequestContext = .create(
                backupKey: mediaBackupKey.serialize(),
                aci: localAci.rawUUID
            )

            let base64MessageRequestContext = messageBackupRequestContext.getRequest().serialize().base64EncodedString()
            let base64MediaRequestContext = mediaBackupRequestContext.getRequest().serialize().base64EncodedString()

            _ = try await networkManager.asyncRequest(
                .reserveBackupId(
                    backupId: base64MessageRequestContext,
                    mediaBackupId: base64MediaRequestContext,
                    auth: auth
                )
            )
        }

        func deleteBackupId(backupAuth: BackupServiceAuth) async throws {
            _ = try await networkManager.asyncRequest(
                .deleteBackupRequest(backupAuth: backupAuth)
            )
        }
    }
}

// MARK: -

private extension TSRequest {
    static func reserveBackupId(
        backupId: String,
        mediaBackupId: String,
        auth: ChatServiceAuth
    ) -> TSRequest {
        var request = TSRequest(
            url: URL(string: "v1/archives/backupid")!,
            method: "PUT",
            parameters: [
                "messagesBackupAuthCredentialRequest": backupId,
                "mediaBackupAuthCredentialRequest": mediaBackupId
            ]
        )
        request.auth = .identified(auth)
        return request
    }

    static func backupSetPublicKeyRequest(
        backupAuth: BackupServiceAuth
    ) -> TSRequest {
        var request = TSRequest(
            url: URL(string: "v1/archives/keys")!,
            method: "PUT",
            parameters: ["backupIdPublicKey": backupAuth.publicKey.serialize().base64EncodedString()]
        )
        request.auth = .backup(backupAuth)
        return request
    }

    static func deleteBackupRequest(
        backupAuth: BackupServiceAuth
    ) -> TSRequest {
        var request = TSRequest(
            url: URL(string: "v1/archives")!,
            method: "DELETE",
            parameters: nil
        )
        request.auth = .backup(backupAuth)
        return request
    }
}

// MARK: -

#if TESTABLE_BUILD

class MockBackupIdManager: BackupIdManager {
    var registerBackupIdMock: (() async throws -> RegisteredBackupIDToken)?
    func registerBackupId(localIdentifiers: LocalIdentifiers, auth: ChatServiceAuth) async throws -> RegisteredBackupIDToken {
        if let registerBackupIdMock {
            return try await registerBackupIdMock()
        }

        throw OWSAssertionError("Mock not implemented!")
    }

    var deleteBackupIdMock: (() async throws -> Void)?
    func deleteBackupId(localIdentifiers: LocalIdentifiers, auth: ChatServiceAuth) async throws {
        if let deleteBackupIdMock {
            return try await deleteBackupIdMock()
        }

        throw OWSAssertionError("Mock not implemented!")
    }

    func deleteBackupId(localIdentifiers: LocalIdentifiers, backupAuth: BackupServiceAuth) async throws {
        throw OWSAssertionError("Mock not implemented!")
    }
}

#endif
