//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public struct MessageBackupKeyMaterialImpl: MessageBackupKeyMaterial {

    private enum Constants {
        static let MessageBackupIdInfoString = "20231003_Signal_Backups_GenerateBackupId"
        static let MessageBackupIdLength = 16

        static let MessageBackupEncryptionInfoString = "20231003_Signal_Backups_EncryptMessageBackup"
        static let MessageBackupEncryptionDataLength = 80
    }

    private let svr: SecureValueRecovery
    private let tsAccountManager: TSAccountManager

    public init(svr: SecureValueRecovery, tsAccountManager: TSAccountManager) {
        self.svr = svr
        self.tsAccountManager = tsAccountManager
    }

    public func backupID(tx: DBReadTransaction) throws -> Data {
        guard let backupKey = svr.data(for: .backupKey, transaction: tx) else {
            throw MessageBackupKeyMaterialError.missingMasterKey
        }
        guard let localAci = tsAccountManager.localIdentifiers(tx: tx)?.aci else {
            throw MessageBackupKeyMaterialError.notRegistered
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

    public func createEncryptingStreamTransform(tx: DBReadTransaction) throws -> EncryptingStreamTransform {
        guard let backupKey = svr.data(for: .backupKey, transaction: tx) else {
            throw MessageBackupKeyMaterialError.missingMasterKey
        }
        let backupId = try backupID(tx: tx)
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

        guard keyBytes.count == 80 else {
            throw MessageBackupKeyMaterialError.invalidEncryptionKey
        }

        return try EncryptingStreamTransform(
            iv: Data(Array(keyBytes[64..<80])),
            encryptionKey: Data(Array(keyBytes[32..<64])),
            hmacKey: Data(Array(keyBytes[0..<32]))
        )
    }

    public func createDecryptingStreamTransform(tx: DBReadTransaction) throws -> DecryptingStreamTransform {
        guard let backupKey = svr.data(for: .backupKey, transaction: tx) else {
            throw MessageBackupKeyMaterialError.missingMasterKey
        }
        let backupId = try backupID(tx: tx)
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

        guard keyBytes.count == 80 else {
            throw MessageBackupKeyMaterialError.invalidEncryptionKey
        }

        return try DecryptingStreamTransform(
            iv: Data(Array(keyBytes[64..<80])),
            encryptionKey: Data(Array(keyBytes[32..<64])),
            hmacKey: Data(Array(keyBytes[0..<32]))
        )
    }
}
