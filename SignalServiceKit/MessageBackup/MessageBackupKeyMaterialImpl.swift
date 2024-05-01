//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

public struct MessageBackupKeyMaterialImpl: MessageBackupKeyMaterial {

    private enum Constants {
        static let MessageBackupIdInfoString = "20231003_Signal_Backups_GenerateBackupId"
        static let MessageBackupIdLength = 16

        static let MessageBackupEncryptionInfoString = "20231003_Signal_Backups_EncryptMessageBackup"
        static let MessageBackupEncryptionDataLength = 64

        static let MessageBackupPrivateKeyInfoString = "20231003_Signal_Backups_GenerateBackupIdKeyPair"
        static let MessageBackupPrivateKeyDataLength = 32
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
        guard let backupKey = svr.data(for: .backupKey, transaction: tx) else {
            throw MessageBackupKeyMaterialError.missingMasterKey
        }
        guard let infoData = Constants.MessageBackupIdInfoString.data(using: .utf8) else {
            owsFailDebug("Failed to encode data")
            throw MessageBackupKeyMaterialError.invalidKeyInfo
        }
        let keyBytes = try hkdf(
            outputLength: Constants.MessageBackupIdLength,
            inputKeyMaterial: backupKey.rawData,
            salt: localAci.serviceIdBinary,
            info: infoData
        )
        return Data(keyBytes)
    }

    public func backupPrivateKey(localAci: Aci, tx: DBReadTransaction) throws -> PrivateKey {
        guard let backupKey = svr.data(for: .backupKey, transaction: tx) else {
            throw MessageBackupKeyMaterialError.missingMasterKey
        }

        guard let infoData = Constants.MessageBackupPrivateKeyInfoString.data(using: .utf8) else {
            owsFailDebug("Failed to encode data")
            throw MessageBackupKeyMaterialError.invalidKeyInfo
        }

        let privateKeyBytes = try hkdf(
            outputLength: Constants.MessageBackupPrivateKeyDataLength,
            inputKeyMaterial: backupKey.rawData,
            salt: localAci.serviceIdBinary,
            info: infoData
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
        guard let backupKey = svr.data(for: .backupKey, transaction: tx) else {
            throw MessageBackupKeyMaterialError.missingMasterKey
        }
        let backupId = try backupID(localAci: localAci, tx: tx)
        guard let infoData = Constants.MessageBackupEncryptionInfoString.data(using: .utf8) else {
            owsFailDebug("Failed to encode data")
            throw MessageBackupKeyMaterialError.invalidKeyInfo
        }

        let keyBytes = try hkdf(
            outputLength: Constants.MessageBackupEncryptionDataLength,
            inputKeyMaterial: backupKey.rawData,
            salt: backupId,
            info: infoData
        )

        guard keyBytes.count == Constants.MessageBackupEncryptionDataLength else {
            throw MessageBackupKeyMaterialError.invalidEncryptionKey
        }

        return try EncryptingStreamTransform(
            iv: Randomness.generateRandomBytes(16),
            encryptionKey: Data(Array(keyBytes[32..<64])),
            hmacKey: Data(Array(keyBytes[0..<32]))
        )
    }

    public func createDecryptingStreamTransform(localAci: Aci, tx: DBReadTransaction) throws -> DecryptingStreamTransform {
        guard let backupKey = svr.data(for: .backupKey, transaction: tx) else {
            throw MessageBackupKeyMaterialError.missingMasterKey
        }
        let backupId = try backupID(localAci: localAci, tx: tx)
        guard let infoData = Constants.MessageBackupEncryptionInfoString.data(using: .utf8) else {
            owsFailDebug("Failed to encode data")
            throw MessageBackupKeyMaterialError.invalidKeyInfo
        }

        let keyBytes = try hkdf(
            outputLength: Constants.MessageBackupEncryptionDataLength,
            inputKeyMaterial: backupKey.rawData,
            salt: backupId,
            info: infoData
        )

        guard keyBytes.count == Constants.MessageBackupEncryptionDataLength else {
            throw MessageBackupKeyMaterialError.invalidEncryptionKey
        }

        return try DecryptingStreamTransform(
            encryptionKey: Data(Array(keyBytes[32..<64])),
            hmacKey: Data(Array(keyBytes[0..<32]))
        )
    }
}
