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
    /// 3. Nonce metadata, which we either have locally, or need to pull from SVRB.
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

        /// We need to fetch the forward secrecy token from SVRB. Callers generally don't
        /// worry about making requests; all that is needed is:
        /// 1. The header from the backup file (has the key for SVRB lookup)
        /// 2. Chat server auth (to fetch SVRB auth credentials from the chat server)
        case svrB(header: BackupNonce.MetadataHeader, auth: ChatServiceAuth)
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
    /// Chat auth is required because we always upload to SVRB when we generate a new
    /// forward secrecy token (and we need chat service auth to get a SVRB auth credential).
    case remoteExport(key: MessageRootBackupKey, chatAuth: ChatServiceAuth)

    /// A link'n'sync backup which uses a one-time ephemeral key (which we still use the BackupKey type for).
    /// This ephemeral key is combined with the ACI to derive the encryption key for the synced backup file.
    case linkNsync(ephemeralKey: BackupKey, aci: Aci)

    // TODO: [Backups] add local backup case. This should just have the backup key;
    // internally we will generate a backupId without the aci.
}

// MARK: - Libsignal.MessageBackupPurpose

extension BackupImportSource {
    var libsignalPurpose: LibSignalClient.MessageBackupPurpose {
        switch self {
        case .linkNsync:
            return .deviceTransfer
        case .remote:
            return .remoteBackup
        }
    }
}

extension BackupExportPurpose {
    var libsignalPurpose: LibSignalClient.MessageBackupPurpose {
        switch self {
        case .linkNsync:
            return .deviceTransfer
        case .remoteExport:
            return .remoteBackup
        }
    }
}

// MARK: - Errors

public enum SVRBError: Error, Equatable {
    /// An unrecoverable error; SVRB data is potentially lost forever.
    case unrecoverable
    /// Couldn't recover SVRB data because the backup key is incorrect;
    /// may be recoverable by entering a different AEP.
    case incorrectRecoveryKey
}

// MARK: - Encryption Key Derivation

extension BackupImportSource {
    private var logger: PrefixedLogger { .init(prefix: "[Backups]") }

    /// Derive the encryption key used to decrypt the backup file, potentially
    /// performing a fetch from SVRB, depending on the purpose and available data.
    func deriveBackupEncryptionKeyWithSVRBIfNeeded(
        backupRequestManager: BackupRequestManager,
        db: any DB,
        libsignalNet: LibSignalClient.Net,
        nonceStore: BackupNonceMetadataStore,
        logger: PrefixedLogger,
    ) async throws -> MessageBackupKey {
        switch self {
        case let .remote(key, noneSource):
            let forwardSecrecyToken: BackupForwardSecrecyToken?
            switch noneSource {
            case let .provisioningMessage(token):
                forwardSecrecyToken = token
            case let .svrB(metadataHeader, chatAuth):
                do {
                    forwardSecrecyToken = try await self.fetchForwardSecrecyTokenFromSvr(
                        key: key,
                        metadataHeader: metadataHeader,
                        chatAuth: chatAuth,
                        forceRefreshSVRBAuthCredential: false,
                        backupRequestManager: backupRequestManager,
                        db: db,
                        libsignalNet: libsignalNet,
                        nonceStore: nonceStore,
                        logger: logger,
                    )
                } catch SignalError.webSocketError {
                    // This may represent an "expired auth" error from the SVRB
                    // servers. Try again, force-refreshing credentials.
                    forwardSecrecyToken = try await self.fetchForwardSecrecyTokenFromSvr(
                        key: key,
                        metadataHeader: metadataHeader,
                        chatAuth: chatAuth,
                        forceRefreshSVRBAuthCredential: true,
                        backupRequestManager: backupRequestManager,
                        db: db,
                        libsignalNet: libsignalNet,
                        nonceStore: nonceStore,
                        logger: logger,
                    )
                }
            }

            return try MessageBackupKey(
                backupKey: key.backupKey,
                backupId: key.backupId,
                forwardSecrecyToken: forwardSecrecyToken,
            )

        case let .linkNsync(ephemeralKey, aci):
            return try MessageBackupKey(
                backupKey: ephemeralKey,
                backupId: ephemeralKey.deriveBackupId(aci: aci),
                forwardSecrecyToken: nil,
            )
        }
    }

    private func fetchForwardSecrecyTokenFromSvr(
        key: MessageRootBackupKey,
        metadataHeader: BackupNonce.MetadataHeader,
        chatAuth: ChatServiceAuth,
        forceRefreshSVRBAuthCredential: Bool,
        backupRequestManager: BackupRequestManager,
        db: any DB,
        libsignalNet: LibSignalClient.Net,
        nonceStore: BackupNonceMetadataStore,
        logger: PrefixedLogger,
    ) async throws -> BackupForwardSecrecyToken {
        let svrBAuth: LibSignalClient.Auth
        do {
            svrBAuth = try await backupRequestManager.fetchSVRBAuthCredential(
                key: key,
                chatServiceAuth: chatAuth,
                forceRefresh: forceRefreshSVRBAuthCredential,
                logger: logger,
            )
        } catch let error as CancellationError {
            throw error
        } catch let error where error.isNetworkFailureOrTimeout {
            throw error
        } catch let error {
            owsFailDebug("Permanently failed to fetch svrB auth! \(error)")
            throw SVRBError.unrecoverable
        }

        let svrB = libsignalNet.svrB(auth: svrBAuth)

        let response: SvrB.RestoreBackupResponse
        do {
            response = try await svrB.restore(
                backupKey: key.backupKey,
                metadata: metadataHeader.data,
            )
        } catch SignalError.invalidArgument {
            // Metadata is malformed. Totally unrecoverable.
            logger.error("SVRB metadata header malformed!")
            throw SVRBError.unrecoverable
        } catch SignalError.svrRestoreFailed {
            // Some SVRB error that means data is lost. Totally unrecoverable.
            logger.error("SVRB restore failed!")
            throw SVRBError.unrecoverable
        } catch SignalError.svrDataMissing {
            logger.error("SVRB data missing!")
            throw SVRBError.incorrectRecoveryKey
        } catch SignalError.rateLimitedError(let retryAfter, _) {
            // We never really expect this to happen.
            logger.warn("Rate-limited SVRB restore. retryAfter: \(retryAfter)")
            try await Task.sleep(nanoseconds: retryAfter.clampedNanoseconds)
            return try await fetchForwardSecrecyTokenFromSvr(
                key: key,
                metadataHeader: metadataHeader,
                chatAuth: chatAuth,
                forceRefreshSVRBAuthCredential: false,
                backupRequestManager: backupRequestManager,
                db: db,
                libsignalNet: libsignalNet,
                nonceStore: nonceStore,
                logger: logger,
            )
        } catch {
            logger.warn("Failed SVRB restore! \(error)")
            throw error
        }

        let forwardSecrecyToken = response.forwardSecrecyToken
        // Set the next secret metadata immediately; we won't use
        // it until we next create a backup and it will ensure that
        // when we do, this previous backup remains decryptable
        // if that next backups fails at the upload to cdn step.
        // It is ok if the restore process fails after this point,
        // either we try again and overwrite this, or we skip
        // and then the next time we make a backup we still use
        // this key which is at worst as good as a random starting point.
        await db.awaitableWrite { tx in
            nonceStore.setNextSecretMetadata(
                BackupNonce.NextSecretMetadata(data: response.nextBackupSecretData),
                for: key,
                tx: tx,
            )
        }
        return forwardSecrecyToken
    }
}

extension BackupExportPurpose {
    private var logger: PrefixedLogger { .init(prefix: "[Backups]") }

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
    /// performing an upload to SVRB, depending on the purpose and available data.
    func deriveEncryptionMetadataWithSVRBIfNeeded(
        backupRequestManager: BackupRequestManager,
        db: any DB,
        libsignalNet: LibSignalClient.Net,
        nonceStore: BackupNonceMetadataStore,
    ) async throws -> EncryptionMetadata {
        switch self {
        case let .remoteExport(key, chatAuth):
            do {
                return try await storeEncryptionMetadataToSVRB(
                    key: key,
                    chatAuth: chatAuth,
                    forceRefreshSVRBAuthCredential: false,
                    backupRequestManager: backupRequestManager,
                    db: db,
                    libsignalNet: libsignalNet,
                    nonceStore: nonceStore,
                )
            } catch SignalError.webSocketError {
                // This may represent an "expired auth" error from the SVRB
                // servers. Try again, force-refreshing credentials.
                return try await storeEncryptionMetadataToSVRB(
                    key: key,
                    chatAuth: chatAuth,
                    forceRefreshSVRBAuthCredential: true,
                    backupRequestManager: backupRequestManager,
                    db: db,
                    libsignalNet: libsignalNet,
                    nonceStore: nonceStore,
                )
            }
        case let .linkNsync(ephemeralKey, aci):
            let backupId = ephemeralKey.deriveBackupId(aci: aci)
            let encryptionKey = try MessageBackupKey(
                backupKey: ephemeralKey,
                backupId: backupId,
                forwardSecrecyToken: nil,
            )
            return BackupExportPurpose.EncryptionMetadata(
                encryptionKey: encryptionKey,
                backupId: backupId,
                metadataHeader: nil,
                nonceMetadata: nil,
            )
        }
    }

    private func storeEncryptionMetadataToSVRB(
        key: MessageRootBackupKey,
        chatAuth: ChatServiceAuth,
        forceRefreshSVRBAuthCredential: Bool,
        backupRequestManager: BackupRequestManager,
        db: any DB,
        libsignalNet: LibSignalClient.Net,
        nonceStore: BackupNonceMetadataStore,
    ) async throws -> EncryptionMetadata {
        let svrBAuth: LibSignalClient.Auth
        do {
            svrBAuth = try await backupRequestManager.fetchSVRBAuthCredential(
                key: key,
                chatServiceAuth: chatAuth,
                forceRefresh: forceRefreshSVRBAuthCredential,
                logger: logger,
            )
        } catch let error as CancellationError {
            throw error
        } catch let error where error.isNetworkFailureOrTimeout {
            throw error
        } catch let error {
            owsFailDebug("Permanently failed to fetch svrB auth. \(error)")
            throw SVRBError.unrecoverable
        }

        let svrB = libsignalNet.svrB(auth: svrBAuth)

        // We want what was the "next" secret metadata from the _last_ backup we made.
        // This is used as an input into the generator for the metadata for this new
        // backup (which is the "next" backup from that last time).
        let mostRecentSecretData: BackupNonce.NextSecretMetadata
        if
            let storedSecretData = db.read(block: { tx in
                nonceStore.getNextSecretMetadata(for: key, tx: tx)
            })
        {
            mostRecentSecretData = storedSecretData
        } else {
            mostRecentSecretData = BackupNonce.NextSecretMetadata(data: svrB.createNewBackupChain(backupKey: key.backupKey))
            await db.awaitableWrite { tx in
                nonceStore.setNextSecretMetadata(
                    mostRecentSecretData,
                    for: key,
                    tx: tx,
                )
            }
        }

        let response: SvrB.StoreBackupResponse
        do {
            response = try await svrB.store(backupKey: key.backupKey, previousSecretData: mostRecentSecretData.data)
        } catch SignalError.invalidArgument {
            // This happens when the "previousSecretData" is invalid.
            // To recover, we have to start over with `createNewBackupChain`.
            logger.error("Failed SVRB store w/ invalid argument, wiping next secret metadata")
            await db.awaitableWrite { tx in
                nonceStore.deleteNextSecretMetadata(tx: tx)
            }
            return try await storeEncryptionMetadataToSVRB(
                key: key,
                chatAuth: chatAuth,
                forceRefreshSVRBAuthCredential: false,
                backupRequestManager: backupRequestManager,
                db: db,
                libsignalNet: libsignalNet,
                nonceStore: nonceStore,
            )
        } catch SignalError.rateLimitedError(let retryAfter, _) {
            // We never really expect this to happen.
            logger.warn("Rate-limited SVRB store. retryAfter: \(retryAfter)")
            try await Task.sleep(nanoseconds: retryAfter.clampedNanoseconds)
            return try await storeEncryptionMetadataToSVRB(
                key: key,
                chatAuth: chatAuth,
                forceRefreshSVRBAuthCredential: false,
                backupRequestManager: backupRequestManager,
                db: db,
                libsignalNet: libsignalNet,
                nonceStore: nonceStore,
            )
        } catch let error {
            logger.warn("Failed SVRB store! \(error)")
            throw error
        }

        let encryptionKey: MessageBackupKey
        do {
            encryptionKey = try MessageBackupKey(
                backupKey: key.backupKey,
                backupId: key.backupId,
                forwardSecrecyToken: response.forwardSecrecyToken,
            )
        } catch {
            owsFailDebug("Failed to derive encryption key!")
            throw SVRBError.unrecoverable
        }

        return BackupExportPurpose.EncryptionMetadata(
            encryptionKey: encryptionKey,
            backupId: key.backupId,
            metadataHeader: BackupNonce.MetadataHeader(data: response.metadata),
            nonceMetadata: NonceMetadata(
                forwardSecrecyToken: response.forwardSecrecyToken,
                nextSecretMetadata: BackupNonce.NextSecretMetadata(data: response.nextBackupSecretData),
            ),
        )
    }
}
