//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct BackupKeyMaterialImpl: BackupKeyMaterial {

    private let accountKeyStore: AccountKeyStore

    public init(
        accountKeyStore: AccountKeyStore
    ) {
        self.accountKeyStore = accountKeyStore
    }

    /// Get the root backup key used by the encryption mode. The key may be derived
    /// differently depending on the mode, but derivations downstream of it work the same.
    public func backupKey(
        type: BackupAuthCredentialType,
        tx: DBReadTransaction
    ) throws(BackupKeyMaterialError) -> BackupKey {
        switch type {
        case .media:
            guard let backupKey = accountKeyStore.getMediaRootBackupKey(tx: tx) else {
                throw BackupKeyMaterialError.missingMediaRootBackupKey
            }
            return backupKey
        case .messages:
            guard let backupKey = accountKeyStore.getMessageRootBackupKey(tx: tx) else {
                throw BackupKeyMaterialError.missingMessageBackupKey
            }
            return backupKey
        }
    }

    public func mediaEncryptionMetadata(
        mediaName: String,
        type: MediaTierEncryptionType,
        tx: DBReadTransaction
    ) throws(BackupKeyMaterialError) -> MediaTierEncryptionMetadata {
        let backupKey = try backupKey(type: .media, tx: tx)
        let mediaId: Data
        do {
            mediaId = try backupKey.deriveMediaId(mediaName)
        } catch {
            throw BackupKeyMaterialError.derivationError(error)
        }
        let keyBytes: Data
        do {
            switch type {
            case .outerLayerFullsizeOrThumbnail:
                keyBytes = try backupKey.deriveMediaEncryptionKey(mediaId)
            case .transitTierThumbnail:
                keyBytes = try backupKey.deriveThumbnailTransitEncryptionKey(mediaId)
            }
        } catch {
            throw BackupKeyMaterialError.derivationError(error)
        }
        owsPrecondition(keyBytes.count >= 64)
        return MediaTierEncryptionMetadata(
            type: type,
            mediaId: mediaId,
            hmacKey: keyBytes.prefix(32),
            aesKey: keyBytes.dropFirst(32).prefix(32),
        )
    }
}

#if TESTABLE_BUILD

open class BackupKeyMaterialMock: BackupKeyMaterial {

    public var mediaBackupKey: BackupKey!
    public var messagesBackupKey: BackupKey!

    public func backupKey(
        type: BackupAuthCredentialType,
        tx: DBReadTransaction
    ) throws(BackupKeyMaterialError) -> BackupKey {
        switch type {
        case .media: return mediaBackupKey
        case .messages: return messagesBackupKey
        }
    }

    public func mediaEncryptionMetadata(
        mediaName: String,
        type: MediaTierEncryptionType,
        tx: DBReadTransaction
    ) throws(BackupKeyMaterialError) -> MediaTierEncryptionMetadata {
        fatalError("Unimplemented")
    }
}

#endif
