//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

/// Source of a backup being imported, that also includes the necessary information
/// for decryption, since the encryption scheme varies by purpose (and has different inputs).
public enum BackupImportSource {
    /// A backup uploaded to the remote media tier cdn.
    /// Encryption makes use of...
    /// 1. AEP (used to derive ``MessageRootBackupKey/backupKey``
    /// 2. ACI (used with backup key to derive ``MessageRootBackupKey/backupId``)
    /// 3. Nonce metadata, which we either have locally, or need to pull from SVR🐝.
    case remote(key: MessageRootBackupKey, nonceSource: NonceMetadataSource)

    /// A link'n'sync backup which uses a one-time ephemeral key (which we still use the BackupKey type for).
    /// This ephemeral key is combined with the ACI to derive the encryption key for the synced backup file.
    case linkNsync(ephemeralKey: BackupKey, aci: Aci)

    // TODO: [Backups] add local backup case. This should just have the backup key
    // and the backupId we pull out of the local backup metadata file, no aci.

    public enum NonceMetadataSource {
        /// We already have the forward secrecy token from Quick Restore;
        /// the old primary device can provide the new primary with the last
        /// forward secrecy token it used to generate a backup.
        case provisioningMessage(BackupForwardSecrecyToken)

        /// We need to fetch the forward secrecy token from SVR🐝. Callers generally don't
        /// worry about making requests; all that is needed is:
        /// 1. The header from the backup file (has the key for SVR🐝 lookup)
        /// 2. Chat server auth (to fetch SVR🐝 auth credentials from the chat server)
        case svr🐝(header: BackupNonce.MetadataHeader, auth: ChatServiceAuth)
    }
}

/// Wrapper around the purpose behind a given backup (whether importing or exporting)
/// that also includes the necessary information for encryption/decryption, since what
/// the encryption scheme is varies by purpose (and has different inputs).
public enum BackupExportPurpose {
    /// A backup to upload to the remote media tier cdn.
    /// Encryption makes use of...
    /// 1. AEP (used to derive ``MessageRootBackupKey/backupKey``
    /// 2. ACI (used with backup key to derive ``MessageRootBackupKey/backupId``)
    /// 3. Nonce metadata, which we generate locally.
    ///
    /// Chat auth is required because we always upload to SVR🐝 when we generate a new
    /// forward secrecy token (and we need chat service auth to get a SVR🐝 auth credential).
    case remoteExport(key: MessageRootBackupKey, chatAuth: ChatServiceAuth)

    /// A link'n'sync backup which uses a one-time ephemeral key (which we still use the BackupKey type for).
    /// This ephemeral key is combined with the ACI to derive the encryption key for the synced backup file.
    case linkNsync(ephemeralKey: BackupKey, aci: Aci)

    // TODO: [Backups] add local backup case. This should just have the backup key;
    // internally we will generate a backupId without the aci.
}

// MARK: - Libsignal.MessageBackupPurpose

extension BackupImportSource {
    internal var libsignalPurpose: LibSignalClient.MessageBackupPurpose {
        switch self {
        case .linkNsync:
            return .deviceTransfer
        case .remote:
            return .remoteBackup
        }
    }
}

extension BackupExportPurpose {
    internal var libsignalPurpose: LibSignalClient.MessageBackupPurpose {
        switch self {
        case .linkNsync:
            return .deviceTransfer
        case .remoteExport:
            return .remoteBackup
        }
    }
}

// MARK: - Encryption Key Derivation

extension BackupImportSource {

    /// Derive the encryption key used to decrypt the backup file, potentially
    /// performing a fetch from SVR🐝, depending on the purpose and available data.
    internal func deriveBackupEncryptionKeyWithSvr🐝IfNeeded(
        backupRequestManager: BackupRequestManager,
        db: any DB,
        libsignalNet: LibSignalClient.Net,
        nonceStore: BackupNonceMetadataStore,
    ) async throws -> MessageBackupKey {
        switch self {
        case let .remote(key, noneSource):
            let forwardSecrecyToken: BackupForwardSecrecyToken?
            switch noneSource {
            case let .provisioningMessage(token):
                forwardSecrecyToken = token
            case let .svr🐝(metadataHeader, chatAuth):
                let svr🐝Auth = try await backupRequestManager.fetchSvr🐝AuthCredential(
                    key: key,
                    chatServiceAuth: chatAuth,
                    forceRefresh: false
                )

                let svr🐝 = libsignalNet.svr🐝(auth: svr🐝Auth)

                // TODO: [SVR🐝]: error handling
                let response = try await svr🐝.restore(
                    backupKey: key.backupKey,
                    metadata: metadataHeader.data
                )

                forwardSecrecyToken = response.forwardSecrecyToken
                // Set the next secret metadata immediately; we won't use
                // it until we next create a backup and it will ensure that
                // when we do, this previous backup remains decryptable
                // if that next backups fails at the upload to cdn step.
                // It is ok if the restore process fails after this point,
                // either we try again and overwrite this, or we skip
                // and then the next time we make a backup we still use
                // this key which is at worst as good as a random starting point.
                await db.awaitableWrite { tx in
                    nonceStore.setNextSecretMetadata(response.nextSecretMetadata, tx: tx)
                }
            }

            return try MessageBackupKey(
                backupKey: key.backupKey,
                backupId: key.backupId,
                forwardSecrecyToken: forwardSecrecyToken
            )

        case let .linkNsync(ephemeralKey, aci):
            return try MessageBackupKey(
                backupKey: ephemeralKey,
                backupId: ephemeralKey.deriveBackupId(aci: aci),
                forwardSecrecyToken: nil
            )
        }
    }
}

extension BackupExportPurpose {

    struct EncryptionMetadata {
        let encryptionKey: MessageBackupKey
        let backupId: Data
        /// If non-nil, this header should be prepended to the backup file
        /// in plaintext.
        let metadataHeader: BackupNonce.MetadataHeader?
        /// If non-nil, this metadata should be persisted after the upload
        /// of a backup succeeds (and ONLY if it succeeds).
        let nonceMetadata: NonceMetadata?
    }

    struct NonceMetadata {
        let forwardSecrecyToken: BackupForwardSecrecyToken
        let nextSecretMetadata: BackupNonce.NextSecretMetadata
    }

    /// Derive the encryption key used to encrypt the backup file, potentially
    /// performing an upload to SVR🐝, depending on the purpose and available data.
    internal func deriveEncryptionMetadataWithSvr🐝IfNeeded(
        backupRequestManager: BackupRequestManager,
        db: any DB,
        libsignalNet: LibSignalClient.Net,
        nonceStore: BackupNonceMetadataStore,
    ) async throws -> EncryptionMetadata {
        switch self {
        case let .remoteExport(key, chatAuth):
            let svr🐝Auth = try await backupRequestManager.fetchSvr🐝AuthCredential(
                key: key,
                chatServiceAuth: chatAuth,
                forceRefresh: false
            )

            let svr🐝 = libsignalNet.svr🐝(auth: svr🐝Auth)

            // We want what was the "next" secret metadata from the _last_ backup we made.
            // This is used as an input into the generator for the metadata for this new
            // backup (which is the "next" backup from that last time).
            let mostRecentSecretData: BackupNonce.NextSecretMetadata
            if let storedSecretData = db.read(block: nonceStore.getNextSecretMetadata(tx:)) {
                mostRecentSecretData = storedSecretData
            } else {
                mostRecentSecretData = BackupNonce.NextSecretMetadata(data: svr🐝.createNewBackupChain(backupKey: key.backupKey))
                await db.awaitableWrite { tx in
                    nonceStore.setNextSecretMetadata(mostRecentSecretData, tx: tx)
                }
            }

            // TODO: [SVR🐝]: error handling
            let response = try await svr🐝.store(backupKey: key.backupKey, previousSecretData: mostRecentSecretData.data)

            let encryptionKey = try MessageBackupKey(
                backupKey: key.backupKey,
                backupId: key.backupId,
                forwardSecrecyToken: response.forwardSecrecyToken
            )

            return BackupExportPurpose.EncryptionMetadata(
                encryptionKey: encryptionKey,
                backupId: key.backupId,
                metadataHeader: response.headerMetadata,
                nonceMetadata: NonceMetadata(
                    forwardSecrecyToken: response.forwardSecrecyToken,
                    nextSecretMetadata: response.nextSecretMetadata
                )
            )
        case let .linkNsync(ephemeralKey, aci):
            let backupId = ephemeralKey.deriveBackupId(aci: aci)
            let encryptionKey = try MessageBackupKey(
                backupKey: ephemeralKey,
                backupId: backupId,
                forwardSecrecyToken: nil
            )
            return BackupExportPurpose.EncryptionMetadata(
                encryptionKey: encryptionKey,
                backupId: backupId,
                metadataHeader: nil,
                nonceMetadata: nil
            )
        }
    }
}

// swiftlint:disable:next type_name
public typealias Svr🐝 = LibSignalClient.SvrB

extension LibSignalClient.Net {

    func svr🐝(auth: LibSignalClient.Auth) -> Svr🐝 {
        return self.svrB(auth: auth)
    }
}
