//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct MessageBackupKeyMaterialImpl: MessageBackupKeyMaterial {
    private let svr: SecureValueRecovery
    private let mrbkStore: MediaRootBackupKeyStore

    public init(
        mrbkStore: MediaRootBackupKeyStore,
        svr: SecureValueRecovery
    ) {
        self.mrbkStore = mrbkStore
        self.svr = svr
    }

    /// Get the root backup key used by the encryption mode. The key may be derived
    /// differently depending on the mode, but derivations downstream of it work the same.
    public func backupKey(type: MessageBackupAuthCredentialType, tx: DBReadTransaction) throws -> BackupKey {
        let resultData: Data
        switch type {
        case .media:
            guard let backupKey = mrbkStore.getMediaRootBackupKey(tx: tx) else {
                throw MessageBackupKeyMaterialError.missingMasterKey
            }
            resultData = backupKey
        case .messages:
            guard let backupKey = svr.data(for: .backupKey, transaction: tx) else {
                throw MessageBackupKeyMaterialError.missingMasterKey
            }
            guard backupKey.type == .backupKey else {
                throw OWSAssertionError("Wrong key provided")
            }
            resultData = backupKey.rawData
        }
        return try resultData.withUnsafeBytes { try BackupKey(contents: Array($0)) }
    }

    public func mediaEncryptionMetadata(
        mediaName: String,
        type: MediaTierEncryptionType,
        tx: any DBReadTransaction
    ) throws -> MediaTierEncryptionMetadata {
        let backupKey = try backupKey(type: .media, tx: tx)
        let mediaId = try backupKey.deriveMediaId(mediaName)
        let keyBytes: [UInt8]
        switch type {
        case .attachment:
            keyBytes = try backupKey.deriveMediaEncryptionKey(mediaId)
        case .thumbnail:
            keyBytes = try backupKey.deriveThumbnailTransitEncryptionKey(mediaId)
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

open class MessageBackupKeyMaterialMock: MessageBackupKeyMaterial {
    public func backupKey(
        type: MessageBackupAuthCredentialType,
        tx: any DBReadTransaction
    ) throws -> BackupKey {
        throw OWSAssertionError("Unimplemented")
    }

    public func mediaEncryptionMetadata(
        mediaName: String,
        type: MediaTierEncryptionType,
        tx: any DBReadTransaction
    ) throws -> MediaTierEncryptionMetadata {
        throw OWSAssertionError("Unimplemented")
    }
}

#endif
