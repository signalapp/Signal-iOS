//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

/// Responsible for CRUD of the "Backup-ID", which is set on all accounts and
/// required to later enable Backups via setting a "BackupKey".
///
/// - SeeAlso ``BackupKeyService``
public protocol BackupIdService {

    /// Registers the backup ID only if local state tells us we haven't
    /// done so before. This method updates local state if successful.
    func registerBackupIDIfNecessary(
        localAci: Aci,
        auth: ChatServiceAuth,
    ) async throws
}

// MARK: -

final class BackupIdServiceImpl: BackupIdService {
    private let accountKeyStore: AccountKeyStore
    private let backupSettingsStore: BackupSettingsStore
    private let db: DB
    private let networkManager: NetworkManager
    private let tsAccountManager: TSAccountManager

    init(
        accountKeyStore: AccountKeyStore,
        backupSettingsStore: BackupSettingsStore,
        db: DB,
        networkManager: NetworkManager,
        tsAccountManager: TSAccountManager,
    ) {
        self.accountKeyStore = accountKeyStore
        self.backupSettingsStore = backupSettingsStore
        self.db = db
        self.networkManager = networkManager
        self.tsAccountManager = tsAccountManager
    }

    private func rootBackupKeys(
        localAci: Aci,
        tx: DBWriteTransaction,
    ) throws -> (MessageRootBackupKey, MediaRootBackupKey) {
        guard let messageRootBackupKey = try? accountKeyStore.getMessageRootBackupKey(aci: localAci, tx: tx) else {
            throw OWSAssertionError("Missing message root backup key! Do we not have an AEP?")
        }

        let mediaRootBackupKey = accountKeyStore.getOrGenerateMediaRootBackupKey(tx: tx)

        return (messageRootBackupKey, mediaRootBackupKey)
    }

    // MARK: -

    func registerBackupIDIfNecessary(
        localAci: Aci,
        auth: ChatServiceAuth
    ) async throws {
        guard FeatureFlags.Backups.supported else {
            return
        }

        let (
            haveSetBackupId,
            isRegisteredPrimaryDevice,
        ): (Bool, Bool) = db.read { tx in
            return (
                backupSettingsStore.haveSetBackupID(tx: tx),
                tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice,
            )
        }

        guard !haveSetBackupId else {
            // Skip if we've already done it.
            return
        }

        guard isRegisteredPrimaryDevice else {
            // Only the primary may set this.
            return
        }

        let (messageBackupKey, mediaBackupKey) = try await db.awaitableWrite { tx in
            try rootBackupKeys(localAci: localAci, tx: tx)
        }

        try await registerBackupId(
            localAci: localAci,
            messageBackupKey: messageBackupKey,
            mediaBackupKey: mediaBackupKey,
            auth: auth
        )

        await db.awaitableWrite { tx in
            backupSettingsStore.setHaveSetBackupID(haveSetBackupID: true, tx: tx)
        }
    }

    private func registerBackupId(
        localAci: Aci,
        messageBackupKey: MessageRootBackupKey,
        mediaBackupKey: MediaRootBackupKey,
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
            .registerBackupId(
                backupId: base64MessageRequestContext,
                mediaBackupId: base64MediaRequestContext,
                auth: auth
            ),
        )
    }
}

// MARK: -

private extension TSRequest {
    static func registerBackupId(
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
}

// MARK: -

#if TESTABLE_BUILD

class MockBackupIdService: BackupIdService {
    func registerBackupIDIfNecessary(localAci: Aci, auth: ChatServiceAuth) async throws {
        // Do nothing
    }
}

#endif
