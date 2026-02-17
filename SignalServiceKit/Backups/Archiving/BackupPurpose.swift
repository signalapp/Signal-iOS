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

public enum SVRBError: Error, Equatable, IsRetryableProvider {
    /// Network errors and other transient errors that
    /// can usually be resolved by an automatic retry, at
    /// computer time scale.
    case retryableAutomatically
    /// Some error that may be resolved by trying again later (e.g. temporary outage)
    /// at human time scale.
    case retryableByUser
    /// An unrecoverable error; SVRB data is potentially lost forever.
    case unrecoverable
    /// Couldn't recover SVRB data because the backup key is incorrect;
    /// may be recoverable by entering a different AEP.
    case incorrectRecoveryKey
    /// A caught-and-rethrown `CancellationError`.
    case cancellationError

    public var isRetryableProvider: Bool {
        switch self {
        case .retryableAutomatically:
            return true
        case .retryableByUser:
            // This is for automatic retries;
            // these errors can be retried by
            // the user.
            return false
        case .unrecoverable, .incorrectRecoveryKey, .cancellationError:
            return false
        }
    }
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
    ) async throws -> MessageBackupKey {
        switch self {
        case let .remote(key, noneSource):
            let forwardSecrecyToken: BackupForwardSecrecyToken?
            switch noneSource {
            case let .provisioningMessage(token):
                forwardSecrecyToken = token
            case let .svrB(metadataHeader, chatAuth):
                var isRetry = false
                forwardSecrecyToken = try await Retry.performWithBackoff(
                    maxAttempts: 2,
                    block: {
                        do throws(SVRBError) {
                            return try await self.fetchForwardSecrecyTokenFromSvr(
                                key: key,
                                metadataHeader: metadataHeader,
                                chatAuth: chatAuth,
                                isRetry: isRetry,
                                backupRequestManager: backupRequestManager,
                                db: db,
                                libsignalNet: libsignalNet,
                                nonceStore: nonceStore,
                            )
                        } catch .cancellationError {
                            throw CancellationError()
                        } catch let error {
                            isRetry = true
                            throw error
                        }
                    },
                )
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
        isRetry: Bool,
        backupRequestManager: BackupRequestManager,
        db: any DB,
        libsignalNet: LibSignalClient.Net,
        nonceStore: BackupNonceMetadataStore,
    ) async throws(SVRBError) -> BackupForwardSecrecyToken {
        let svrBAuth: LibSignalClient.Auth
        do {
            svrBAuth = try await backupRequestManager.fetchSVRBAuthCredential(
                key: key,
                chatServiceAuth: chatAuth,
                // Force fetch new credentials on retries to make sure
                // it wasn't stale credentials that caused the problem.
                forceRefresh: isRetry,
            )
        } catch is CancellationError {
            throw .cancellationError
        } catch let error {
            if error.isNetworkFailureOrTimeout {
                throw .retryableAutomatically
            } else if error.isRetryable {
                throw .retryableAutomatically
            } else {
                owsFailDebug("Permanently failed to fetch svrB auth")
                throw .unrecoverable
            }
        }

        let svrB = libsignalNet.svrB(auth: svrBAuth)

        let response: SvrB.RestoreBackupResponse
        do {
            response = try await svrB.restore(
                backupKey: key.backupKey,
                metadata: metadataHeader.data,
            )
        } catch is CancellationError {
            throw .cancellationError
        } catch let error {
            switch error as? LibSignalClient.SignalError {
            case .invalidArgument:
                // Metadata is malformed. Totally unrecoverable.
                logger.error("SVRB metadata header malformed; cannot recover backup")
                throw .unrecoverable
            case .svrRestoreFailed:
                // Some SVRB error that means data is lost. Totally unrecoverable.
                logger.error("SVRB restore failed; cannot recover backup")
                throw .unrecoverable
            case .svrDataMissing:
                logger.error("SVRB data missing; cannot recover backup")
                throw .incorrectRecoveryKey
            case .rateLimitedError(let retryAfter, _):
                // Do a quite rudimentary thing where we just wait
                // for the retry time, which will leave the user with
                // a spinner. But we never really expect this to happen.
                logger.warn("Rate-limited SVRB restore, waiting...")
                try? await Task.sleep(nanoseconds: retryAfter.clampedNanoseconds)
                return try await fetchForwardSecrecyTokenFromSvr(
                    key: key,
                    metadataHeader: metadataHeader,
                    chatAuth: chatAuth,
                    isRetry: false, /* not that kind of retry */
                    backupRequestManager: backupRequestManager,
                    db: db,
                    libsignalNet: libsignalNet,
                    nonceStore: nonceStore,
                )
            case .connectionFailed, .connectionTimeoutError, .ioError, .webSocketError:
                // Network-level failures mostly end up in these buckets;
                // these can be retried automatically.
                throw .retryableAutomatically
            default:
                // Everything else let the user retry. This will inevitably
                // include things that are bugs, leaving users in retry loops.
                logger.error("Failed SVRB restore w/ unknown error: \(error)")
                throw .retryableByUser
            }
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
            var isRetry = false
            return try await Retry.performWithBackoff(
                maxAttempts: 2,
                block: {
                    do throws(SVRBError) {
                        return try await storeEncryptionMetadataToSVRB(
                            key: key,
                            chatAuth: chatAuth,
                            isRetry: isRetry,
                            backupRequestManager: backupRequestManager,
                            db: db,
                            libsignalNet: libsignalNet,
                            nonceStore: nonceStore,
                        )
                    } catch .cancellationError {
                        throw CancellationError()
                    } catch let error {
                        isRetry = true
                        throw error
                    }
                },
            )
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
        isRetry: Bool,
        backupRequestManager: BackupRequestManager,
        db: any DB,
        libsignalNet: LibSignalClient.Net,
        nonceStore: BackupNonceMetadataStore,
    ) async throws(SVRBError) -> EncryptionMetadata {
        let svrBAuth: LibSignalClient.Auth
        do {
            svrBAuth = try await backupRequestManager.fetchSVRBAuthCredential(
                key: key,
                chatServiceAuth: chatAuth,
                // Force fetch new credentials on retries to make sure
                // it wasn't stale credentials that caused the problem.
                forceRefresh: isRetry,
            )
        } catch let error {
            if error is CancellationError {
                throw .cancellationError
            } else if error.isNetworkFailureOrTimeout {
                throw .retryableAutomatically
            } else if error.isRetryable {
                throw .retryableAutomatically
            } else {
                owsFailDebug("Permanently failed to fetch svrB auth")
                throw .unrecoverable
            }
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
        } catch is CancellationError {
            throw .cancellationError
        } catch let error {
            switch error as? LibSignalClient.SignalError {
            case .invalidArgument:
                // This happens when the "previousSecretData" is invalid.
                // To recover, we have to start over with `createNewBackupChain`.
                logger.error("Failed SVRB store w/ invalid argument, wiping next secret metadata")
                await db.awaitableWrite { tx in
                    nonceStore.deleteNextSecretMetadata(tx: tx)
                }
                return try await storeEncryptionMetadataToSVRB(
                    key: key,
                    chatAuth: chatAuth,
                    isRetry: false, /* Its not that kind of retry */
                    backupRequestManager: backupRequestManager,
                    db: db,
                    libsignalNet: libsignalNet,
                    nonceStore: nonceStore,
                )
            case .rateLimitedError(let retryAfter, _):
                // Do a quite rudimentary thing where we just wait
                // for the retry time, which will leave the user with
                // a spinner. But we never really expect this to happen.
                logger.warn("Rate-limited SVRB store, waiting...")
                try? await Task.sleep(nanoseconds: NSEC_PER_MSEC * UInt64(retryAfter * 1000))
                return try await storeEncryptionMetadataToSVRB(
                    key: key,
                    chatAuth: chatAuth,
                    isRetry: false, /* Its not that kind of retry */
                    backupRequestManager: backupRequestManager,
                    db: db,
                    libsignalNet: libsignalNet,
                    nonceStore: nonceStore,
                )
            case .connectionFailed, .connectionTimeoutError, .ioError, .webSocketError:
                // Network-level failures mostly end up in these buckets;
                // these can be retried automatically.
                throw .retryableAutomatically
            default:
                // Everything else let the user retry. This will inevitably
                // include things that are bugs, leaving users in retry loops.
                logger.error("Failed SVRB store w/ unknown error: \(error)")
                throw .retryableByUser
            }
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
            throw .unrecoverable
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
