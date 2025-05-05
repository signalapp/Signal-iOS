//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

/// Responsible for CRUD of the "Backup ID" and related keys, which are required
/// for CRUD on Backup materials (archives, media) themselves.
public class BackupIdManager {
    public protocol API {
        func reserveBackupId(
            localAci: Aci,
            messageBackupKey: BackupKey,
            mediaBackupKey: BackupKey,
            auth: ChatServiceAuth
        ) async throws

        func registerBackupKey(
            backupAuth: MessageBackupServiceAuth
        ) async throws

        func deleteBackupId(
            backupAuth: MessageBackupServiceAuth
        ) async throws
    }

    /// An opaque token returned after registering a Backup ID, which can be
    /// required by APIs that require a Backup ID to have been previously
    /// registered in order to succeed.
    public struct RegisteredBackupIDToken {}

    private let api: API
    private let backupRequestManager: MessageBackupRequestManager
    private let backupKeyMaterial: MessageBackupKeyMaterial
    private let db: DB

    public init(
        api: API,
        backupRequestManager: MessageBackupRequestManager,
        backupKeyMaterial: MessageBackupKeyMaterial,
        db: DB
    ) {
        self.api = api
        self.backupRequestManager = backupRequestManager
        self.backupKeyMaterial = backupKeyMaterial
        self.db = db
    }

    /// Initialize Backups by reserving a "Backup ID" and registering a public
    /// key used to sign Backup auth credentials. This only needs to be done
    /// once for a given account while Backups remains enabled.
    ///
    /// - Note
    /// These APIs are idempotent and safe to call multiple times.
    ///
    /// - Returns
    /// An opaque token indicating that a Backup ID has been registered.
    public func registerBackupId(
        localIdentifiers: LocalIdentifiers,
        auth: ChatServiceAuth
    ) async throws -> RegisteredBackupIDToken {
        let (messageBackupKey, mediaBackupKey) = try db.read { tx in
            return (
                try backupKeyMaterial.backupKey(type: .messages, tx: tx),
                try backupKeyMaterial.backupKey(type: .media, tx: tx),
            )
        }

        try await api.reserveBackupId(
            localAci: localIdentifiers.aci,
            messageBackupKey: messageBackupKey,
            mediaBackupKey: mediaBackupKey,
            auth: auth
        )

        for credentialType in MessageBackupAuthCredentialType.allCases {
            let backupAuth = try await backupRequestManager.fetchBackupServiceAuth(
                for: credentialType,
                localAci: localIdentifiers.aci,
                auth: auth
            )

            try await api.registerBackupKey(backupAuth: backupAuth)
        }

        return RegisteredBackupIDToken()
    }

    /// De-initialize Backups by deleting the "Backup ID". This is effectively a
    /// "delete Backup" operation, as subsequent to this operation any
    /// Backup-related objects for this account will be deleted from the server.
    public func deleteBackupId(
        localIdentifiers: LocalIdentifiers,
        auth: ChatServiceAuth
    ) async throws {
        let backupAuth = try await backupRequestManager.fetchBackupServiceAuth(
            for: .messages,
            localAci: localIdentifiers.aci,
            auth: auth
        )

        try await api.deleteBackupId(backupAuth: backupAuth)
    }

    // MARK: -

    public struct NetworkAPI: API {
        private let networkManager: NetworkManager

        public init(networkManager: NetworkManager) {
            self.networkManager = networkManager
        }

        public func registerBackupKey(
            backupAuth: MessageBackupServiceAuth
        ) async throws {
            _ = try await networkManager.asyncRequest(.backupSetPublicKeyRequest(
                backupAuth: backupAuth
            ))
        }

        public func reserveBackupId(
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

            let base64MessageRequestContext = messageBackupRequestContext.getRequest().serialize().asData.base64EncodedString()
            let base64MediaRequestContext = mediaBackupRequestContext.getRequest().serialize().asData.base64EncodedString()

            _ = try await networkManager.asyncRequest(
                .reserveBackupId(
                    backupId: base64MessageRequestContext,
                    mediaBackupId: base64MediaRequestContext,
                    auth: auth
                )
            )
        }

        public func deleteBackupId(backupAuth: MessageBackupServiceAuth) async throws {
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
        backupAuth: MessageBackupServiceAuth
    ) -> TSRequest {
        var request = TSRequest(
            url: URL(string: "v1/archives/keys")!,
            method: "PUT",
            parameters: ["backupIdPublicKey": Data(backupAuth.publicKey.serialize()).base64EncodedString()]
        )
        request.auth = .messageBackup(backupAuth)
        return request
    }

    static func deleteBackupRequest(
        backupAuth: MessageBackupServiceAuth
    ) -> TSRequest {
        var request = TSRequest(
            url: URL(string: "v1/archives")!,
            method: "DELETE",
            parameters: nil
        )
        request.auth = .messageBackup(backupAuth)
        return request
    }
}
