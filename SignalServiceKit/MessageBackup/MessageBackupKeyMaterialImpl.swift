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

    public init(svr: SecureValueRecovery) {
        self.svr = svr
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

        guard keyBytes.count == 80 else {
            throw MessageBackupKeyMaterialError.invalidEncryptionKey
        }

        return try EncryptingStreamTransform(
            iv: Data(Array(keyBytes[64..<80])),
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
