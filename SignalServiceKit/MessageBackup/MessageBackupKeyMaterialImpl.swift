//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct MessageBackupKeyMaterialImpl: MessageBackupKeyMaterial {

    private enum Constants {
        static let MessageBackupIdInfoString = "20231003_Signal_Backups_GenerateBackupId"
        static let MessageBackupIdLength = 16

        static let MessageBackupEncryptionInfoString = "20231003_Signal_Backups_EncryptMessageBackup"
        static let MessageBackupEncryptionDataLength = 64

        static let MessageBackupPrivateKeyInfoString = "20231003_Signal_Backups_GenerateBackupIdKeyPair"
        static let MessageBackupPrivateKeyDataLength = 32

        static let MessageBackupMediaIdInfoString = "20231003_Signal_Backups_Media_ID"
        static let MessageBackupMediaIdDataLength = 15

        static let MessageBackupMediaEncryptionInfoString = "20231003_Signal_Backups_EncryptMedia"
        static let MessageBackupMediaEncryptionDataLength = 80

        static let MessageBackupThumbnailEncryptionInfoString = "20240513_Signal_Backups_EncryptThumbnail"
        static let MessageBackupThumbnailEncryptionDataLength = 64
    }

    private let svr: SecureValueRecovery

    public init(svr: SecureValueRecovery) {
        self.svr = svr
    }

    public func backupAuthRequestContext(localAci: Aci, tx: DBReadTransaction) throws -> BackupAuthCredentialRequestContext {
        guard let backupKey = svr.data(for: .backupKey, transaction: tx) else {
            throw MessageBackupKeyMaterialError.missingMasterKey
        }
        return BackupAuthCredentialRequestContext.create(backupKey: backupKey.rawData, aci: localAci.rawUUID)
    }

    public func backupID(localAci: Aci, tx: DBReadTransaction) throws -> Data {
        let keyBytes = try buildBackupEncryptionMaterial(
            salt: localAci.serviceIdBinary,
            info: Constants.MessageBackupIdInfoString,
            length: Constants.MessageBackupIdLength,
            tx: tx
        )
        return Data(keyBytes)
    }

    public func backupPrivateKey(localAci: Aci, tx: DBReadTransaction) throws -> PrivateKey {
        let privateKeyBytes = try buildBackupEncryptionMaterial(
            salt: localAci.serviceIdBinary,
            info: Constants.MessageBackupPrivateKeyInfoString,
            length: Constants.MessageBackupPrivateKeyDataLength,
            tx: tx
        )
        return try PrivateKey(privateKeyBytes)
    }

    public func messageBackupKey(localAci: Aci, tx: DBReadTransaction) throws -> MessageBackupKey {
        guard let masterKey = svr.masterKeyDataForKeysSyncMessage(tx: tx) else {
            throw MessageBackupKeyMaterialError.missingMasterKey
        }
        return try MessageBackupKey(masterKey: Array(masterKey), aci: localAci)
    }

    public func createEncryptingStreamTransform(localAci: Aci, tx: DBReadTransaction) throws -> EncryptingStreamTransform {
        let (encryptionKey, _) = try buildEncryptionMaterial(localAci: localAci, tx: tx)
        return try EncryptingStreamTransform(iv: Randomness.generateRandomBytes(16), encryptionKey: encryptionKey)
    }

    public func createDecryptingStreamTransform(localAci: Aci, tx: DBReadTransaction) throws -> DecryptingStreamTransform {
        let (encryptionKey, _) = try buildEncryptionMaterial(localAci: localAci, tx: tx)
        return try DecryptingStreamTransform(encryptionKey: encryptionKey)
    }

    public func createHmacGeneratingStreamTransform(localAci: Aci, tx: DBReadTransaction) throws -> HmacStreamTransform {
        let (_, hmacKey) = try buildEncryptionMaterial(localAci: localAci, tx: tx)
        return try HmacStreamTransform(hmacKey: hmacKey, operation: .generate)
    }

    public func createHmacValidatingStreamTransform(localAci: Aci, tx: DBReadTransaction) throws -> HmacStreamTransform {
        let (_, hmacKey) = try buildEncryptionMaterial(localAci: localAci, tx: tx)
        return try HmacStreamTransform(hmacKey: hmacKey, operation: .validate)
    }

    public func mediaEncryptionMetadata(
        mediaName: String,
        type: MediaTierEncryptionType,
        tx: any DBReadTransaction
    ) throws -> MediaTierEncryptionMetadata {
        guard let backupKey = svr.data(for: .backupKey, transaction: tx) else {
            throw MessageBackupKeyMaterialError.missingMasterKey
        }

        let (info, length) = {
            switch type {
            case .attachment:
                (Constants.MessageBackupMediaEncryptionInfoString, Constants.MessageBackupMediaEncryptionDataLength)
            case .thumbnail:
                (Constants.MessageBackupThumbnailEncryptionInfoString, Constants.MessageBackupThumbnailEncryptionDataLength)
            }
        }()

        let mediaId = try self.mediaId(mediaName: mediaName, type: type, backupKey: backupKey)

        let keyBytes = try buildBackupEncryptionMaterial(
            salt: mediaId,
            info: info,
            length: length,
            backupKey: backupKey
        )

        guard keyBytes.count == length else {
            throw MessageBackupKeyMaterialError.invalidEncryptionKey
        }

        switch type {
        case .attachment:
            return MediaTierEncryptionMetadata(
                type: type,
                mediaId: mediaId,
                hmacKey: Data(Array(keyBytes[0..<32])),
                aesKey: Data(Array(keyBytes[32..<64])),
                iv: Data(Array(keyBytes[64..<80]))
            )
        case .thumbnail:
            return MediaTierEncryptionMetadata(
                type: type,
                mediaId: mediaId,
                hmacKey: Data(Array(keyBytes[32..<64])),
                aesKey: Data(Array(keyBytes[0..<32])),
                iv: Randomness.generateRandomBytes(16)
            )
        }
    }

    public func mediaId(
        mediaName: String,
        type: MediaTierEncryptionType,
        backupKey: SVR.DerivedKeyData
    ) throws -> Data {
        guard let mediaNameData = mediaName.data(using: .utf8) else {
            owsFailDebug("Failed to encode data")
            throw MessageBackupKeyMaterialError.invalidKeyInfo
        }

        let info = {
            switch type {
            case .attachment:
                Constants.MessageBackupMediaEncryptionInfoString
            case .thumbnail:
                Constants.MessageBackupThumbnailEncryptionInfoString
            }
        }()

        let mediaId = Data(try buildBackupEncryptionMaterial(
            salt: mediaNameData,
            info: Constants.MessageBackupMediaIdInfoString,
            length: Constants.MessageBackupMediaIdDataLength,
            backupKey: backupKey
        ))
        return mediaId
    }

    private func buildEncryptionMaterial(localAci: Aci, tx: DBReadTransaction) throws -> (encryptionKey: Data, hmacKey: Data) {
        let keyBytes = try buildBackupEncryptionMaterial(
            salt: try backupID(localAci: localAci, tx: tx),
            info: Constants.MessageBackupEncryptionInfoString,
            length: Constants.MessageBackupEncryptionDataLength,
            tx: tx
        )
        guard keyBytes.count == Constants.MessageBackupEncryptionDataLength else {
            throw MessageBackupKeyMaterialError.invalidEncryptionKey
        }
        return (encryptionKey: Data(Array(keyBytes[32..<64])), hmacKey: Data(Array(keyBytes[0..<32])))
    }

    private func buildBackupEncryptionMaterial(
        salt: ContiguousBytes,
        info: String,
        length: Int,
        tx: DBReadTransaction
    ) throws -> [UInt8] {
        guard let backupKey = svr.data(for: .backupKey, transaction: tx) else {
            throw MessageBackupKeyMaterialError.missingMasterKey
        }
        return try buildBackupEncryptionMaterial(
            salt: salt,
            info: info,
            length: length,
            backupKey: backupKey
        )
    }

    private func buildBackupEncryptionMaterial(
        salt: ContiguousBytes,
        info: String,
        length: Int,
        backupKey: SVR.DerivedKeyData
    ) throws -> [UInt8] {
        guard backupKey.type == .backupKey else {
            throw OWSAssertionError("Wrong key provided")
        }

        guard let infoData = info.data(using: .utf8) else {
            owsFailDebug("Failed to encode data")
            throw MessageBackupKeyMaterialError.invalidKeyInfo
        }

        let keyBytes = try hkdf(
            outputLength: length,
            inputKeyMaterial: backupKey.rawData,
            salt: salt,
            info: infoData
        )

        guard keyBytes.count == length else {
            throw MessageBackupKeyMaterialError.invalidEncryptionKey
        }

        return keyBytes
    }
}
