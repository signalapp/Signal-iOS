//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct MessageBackupKeyMaterialImpl: MessageBackupKeyMaterial {

    private enum Constants {
        static let MessageBackupThumbnailEncryptionInfoString = "20240513_Signal_Backups_EncryptThumbnail"
        static let MessageBackupThumbnailEncryptionDataLength = 64
    }

    private let svr: SecureValueRecovery

    public init(svr: SecureValueRecovery) {
        self.svr = svr
    }

    public func backupAuthRequestContext(
        localAci: Aci,
        type: MessageBackupAuthCredentialType,
        tx: DBReadTransaction
    ) throws -> BackupAuthCredentialRequestContext {
        return BackupAuthCredentialRequestContext.create(
            backupKey: try backupKey(mode: .remote, tx: tx).serialize(),
            aci: localAci.rawUUID
        )
    }

    public func backupID(localAci: Aci, mode: MessageBackup.EncryptionMode, tx: DBReadTransaction) throws -> Data {
        Data(try backupKey(mode: mode, tx: tx).deriveBackupId(aci: localAci))
    }

    public func backupPrivateKey(localAci: Aci, mode: MessageBackup.EncryptionMode, tx: DBReadTransaction) throws -> PrivateKey {
        try backupKey(mode: mode, tx: tx).deriveEcKey(aci: localAci)
    }

    public func messageBackupKey(
        localAci: Aci,
        mode: MessageBackup.EncryptionMode,
        tx: DBReadTransaction
    ) throws -> MessageBackupKey {
        let backupKey = try backupKey(mode: mode, tx: tx)
        return try MessageBackupKey(
            backupKey: backupKey,
            backupId: backupKey.deriveBackupId(aci: localAci)
        )
    }

    public func createEncryptingStreamTransform(
        localAci: Aci,
        mode: MessageBackup.EncryptionMode,
        tx: DBReadTransaction
    ) throws -> EncryptingStreamTransform {
        let encryptionKey = try messageBackupKey(localAci: localAci, mode: mode, tx: tx).aesKey
        return try EncryptingStreamTransform(iv: Randomness.generateRandomBytes(16), encryptionKey: Data(encryptionKey))
    }

    public func createDecryptingStreamTransform(
        localAci: Aci,
        mode: MessageBackup.EncryptionMode,
        tx: DBReadTransaction
    ) throws -> DecryptingStreamTransform {
        let encryptionKey = try messageBackupKey(localAci: localAci, mode: mode, tx: tx).aesKey
        return try DecryptingStreamTransform(encryptionKey: Data(encryptionKey))
    }

    public func createHmacGeneratingStreamTransform(
        localAci: Aci,
        mode: MessageBackup.EncryptionMode,
        tx: DBReadTransaction
    ) throws -> HmacStreamTransform {
        let hmacKey = try messageBackupKey(localAci: localAci, mode: mode, tx: tx).hmacKey
        return try HmacStreamTransform(hmacKey: Data(hmacKey), operation: .generate)
    }

    public func createHmacValidatingStreamTransform(
        localAci: Aci,
        mode: MessageBackup.EncryptionMode,
        tx: DBReadTransaction
    ) throws -> HmacStreamTransform {
        let hmacKey = try messageBackupKey(localAci: localAci, mode: mode, tx: tx).hmacKey
        return try HmacStreamTransform(hmacKey: Data(hmacKey), operation: .validate)
    }

    public func mediaEncryptionMetadata(
        mediaName: String,
        type: MediaTierEncryptionType,
        tx: any DBReadTransaction
    ) throws -> MediaTierEncryptionMetadata {
        let backupKey = try backupKey(mode: .remote, tx: tx)
        let mediaId = try backupKey.deriveMediaId(mediaName)

        let keyBytes: [UInt8]
        switch type {
        case .attachment:
            keyBytes = try backupKey.deriveMediaEncryptionKey(mediaId)
        case .thumbnail:
            // TODO: Remove this when libSignal supports this.
            guard let infoData = Constants.MessageBackupThumbnailEncryptionInfoString.data(using: .utf8) else {
                throw MessageBackupKeyMaterialError.invalidKeyInfo
            }
            keyBytes = try hkdf(
                outputLength: Constants.MessageBackupThumbnailEncryptionDataLength,
                inputKeyMaterial: backupKey.serialize(),
                salt: mediaId,
                info: infoData
            )
        }

        return MediaTierEncryptionMetadata(
            type: type,
            mediaId: Data(mediaId),
            hmacKey: Data(Array(keyBytes[0..<32])),
            aesKey: Data(Array(keyBytes[32..<64]))
        )
    }

    public func mediaId(
        mediaName: String,
        type: MediaTierEncryptionType,
        backupKey: BackupKey
    ) throws -> Data {
        let mediaName = {
            switch type {
            case .attachment:
                return mediaName
            case .thumbnail:
                return mediaName
            }
        }()

        return Data(try backupKey.deriveMediaId(mediaName))
    }

    /// Get the root backup key used by the encryption mode. The key may be derived
    /// differently depending on the mode, but derivations downstream of it work the same.
    public func backupKey(mode: MessageBackup.EncryptionMode, tx: DBReadTransaction) throws -> BackupKey {
        let resultData: Data
        switch mode {
        case .remote:
            guard let backupKey = svr.data(for: .backupKey, transaction: tx) else {
                throw MessageBackupKeyMaterialError.missingMasterKey
            }
            guard backupKey.type == .backupKey else {
                throw OWSAssertionError("Wrong key provided")
            }
            resultData = backupKey.rawData
        case .linknsync(let ephemeralBackupKey):
            let rawKey = ephemeralBackupKey.data
            guard rawKey.byteLength == SVR.DerivedKey.backupKeyLength else {
                throw MessageBackupKeyMaterialError.invalidEncryptionKey
            }
            resultData = rawKey
        }
        return try resultData.withUnsafeBytes { try BackupKey(contents: Array($0)) }
    }
}
