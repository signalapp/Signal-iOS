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
        let mediaId: [UInt8]
        do {
            mediaId = try backupKey.deriveMediaId(mediaName)
        } catch {
            throw BackupKeyMaterialError.derivationError(error)
        }
        let keyBytes: [UInt8]
        do {
            switch type {
            case .attachment:
                keyBytes = try backupKey.deriveMediaEncryptionKey(mediaId)
            case .thumbnail:
                keyBytes = try backupKey.deriveThumbnailTransitEncryptionKey(mediaId)
            }
        } catch {
            throw BackupKeyMaterialError.derivationError(error)
        }
        return MediaTierEncryptionMetadata(
            type: type,
            mediaId: Data(mediaId),
            hmacKey: Data(Array(keyBytes[0..<32])),
            aesKey: Data(Array(keyBytes[32..<64]))
        )
    }
}

#if TESTABLE_BUILD

open class BackupKeyMaterialMock: BackupKeyMaterial {
    public func backupKey(
        type: BackupAuthCredentialType,
        tx: DBReadTransaction
    ) throws(BackupKeyMaterialError) -> BackupKey {
        fatalError("Unimplemented")
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
