//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct MessageBackupKeyMaterialImpl: MessageBackupKeyMaterial {

    private let mrbkStore: MediaRootBackupKeyStore
    private let svrKeyDeriver: SVRKeyDeriver

    public init(
        mrbkStore: MediaRootBackupKeyStore,
        svrKeyDeriver: SVRKeyDeriver
    ) {
        self.mrbkStore = mrbkStore
        self.svrKeyDeriver = svrKeyDeriver
    }

    /// Get the root backup key used by the encryption mode. The key may be derived
    /// differently depending on the mode, but derivations downstream of it work the same.
    public func backupKey(
        type: MessageBackupAuthCredentialType,
        tx: DBReadTransaction
    ) throws(MessageBackupKeyMaterialError) -> BackupKey {
        let resultData: Data
        switch type {
        case .media:
            guard let backupKey = mrbkStore.getMediaRootBackupKey(tx: tx) else {
                throw MessageBackupKeyMaterialError.missingMediaRootBackupKey
            }
            resultData = backupKey
        case .messages:
            guard let backupKey = svrKeyDeriver.data(for: .backupKey, tx: tx) else {
                throw MessageBackupKeyMaterialError.missingMasterKey
            }
            guard backupKey.type == .backupKey else {
                owsFailDebug("Wrong key provided")
                throw MessageBackupKeyMaterialError.missingMasterKey
            }
            resultData = backupKey.rawData
        }
        do {
            return try resultData.withUnsafeBytes { try BackupKey(contents: Array($0)) }
        } catch {
            throw MessageBackupKeyMaterialError.derivationError(error)
        }
    }

    public func mediaEncryptionMetadata(
        mediaName: String,
        type: MediaTierEncryptionType,
        tx: any DBReadTransaction
    ) throws(MessageBackupKeyMaterialError) -> MediaTierEncryptionMetadata {
        let backupKey = try backupKey(type: .media, tx: tx)
        let mediaId: [UInt8]
        do {
            mediaId = try backupKey.deriveMediaId(mediaName)
        } catch {
            throw MessageBackupKeyMaterialError.derivationError(error)
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
            throw MessageBackupKeyMaterialError.derivationError(error)
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
    ) throws(MessageBackupKeyMaterialError) -> BackupKey {
        fatalError("Unimplemented")
    }

    public func mediaEncryptionMetadata(
        mediaName: String,
        type: MediaTierEncryptionType,
        tx: any DBReadTransaction
    ) throws(MessageBackupKeyMaterialError) -> MediaTierEncryptionMetadata {
        fatalError("Unimplemented")
    }
}

#endif
