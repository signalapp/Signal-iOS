//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import LibSignalClient

/// Responsible for deriving key data for keys downstream of the SVR master key.
public protocol SVRKeyDeriver {

    func isKeyAvailable(_ key: SVR.DerivedKey, tx: DBReadTransaction) -> Bool

    /// Reads and derives key data for the given key type.
    func data(for key: SVR.DerivedKey, tx: DBReadTransaction) -> SVR.DerivedKeyData?

    func encrypt(
        keyType: SVR.DerivedKey,
        data: Data,
        tx: DBReadTransaction
    ) -> SVR.ApplyDerivedKeyResult

    func decrypt(
        keyType: SVR.DerivedKey,
        encryptedData: Data,
        tx: DBReadTransaction
    ) -> SVR.ApplyDerivedKeyResult
}

struct SVRKeyDeriverImpl: SVRKeyDeriver {
    private let localStorage: SVRLocalStorageInternal

    init(localStorage: SVRLocalStorageInternal) {
        self.localStorage = localStorage
    }

    // MARK: -

    public func isKeyAvailable(_ key: SVR.DerivedKey, tx: DBReadTransaction) -> Bool {
        return data(for: key, tx: tx) != nil
    }

    func data(for key: SVR.DerivedKey, tx: DBReadTransaction) -> SVR.DerivedKeyData? {
        func withMasterKey(_ handler: (Data) -> SVR.DerivedKeyData?) -> SVR.DerivedKeyData? {
            guard let masterKey = self.localStorage.getMasterKey(tx) else {
                return nil
            }
            return handler(masterKey)
        }

        func withStorageServiceKey(_ handler: (SVR.DerivedKeyData) -> SVR.DerivedKeyData?) -> SVR.DerivedKeyData? {
            // Linked devices have the master key, synced from the primary.
            // This was not the case historically (2023 and earlier), but since then
            // we sync keys in provisioning and via sync message on app launch.
            guard
                let masterKey = self.localStorage.getMasterKey(tx),
                let storageServiceKey = deriveStorageServiceKey(masterKey: masterKey)
            else {
                return nil
            }
            return handler(storageServiceKey)
        }

        switch key {
        case .registrationLock:
            return withMasterKey(deriveReglockKey(masterKey:))
        case .registrationRecoveryPassword:
            return withMasterKey(deriveRegRecoveryPwKey(masterKey:))
        case .storageService:
            return withStorageServiceKey { $0 }
        case .storageServiceManifest(let version):
            return withStorageServiceKey { deriveStorageServiceManifestKey(version: version, storageServiceKey: $0) }
        case .legacy_storageServiceRecord(let identifier):
            return withStorageServiceKey { deriveStorageServiceRecordKey(identifier: identifier, storageServiceKey: $0) }
        case .backupKey:
            return withMasterKey(deriveBackupKey(masterKey:))
        }
    }

    // MARK: -

    func deriveReglockKey(masterKey: Data) -> SVR.DerivedKeyData? {
        return SVR.DerivedKeyData(keyType: .registrationLock, dataToDeriveFrom: masterKey)
    }

    func deriveStorageServiceKey(masterKey: Data) -> SVR.DerivedKeyData? {
        return SVR.DerivedKeyData(keyType: .storageService, dataToDeriveFrom: masterKey)
    }

    private func deriveRegRecoveryPwKey(masterKey: Data) -> SVR.DerivedKeyData? {
        return SVR.DerivedKeyData(keyType: .registrationRecoveryPassword, dataToDeriveFrom: masterKey)
    }

    private func deriveBackupKey(masterKey: Data) -> SVR.DerivedKeyData? {
        guard FeatureFlags.messageBackupFileAlpha else {
            owsFail("Internal only")
        }

        return SVR.DerivedKeyData(keyType: .backupKey, dataToDeriveFrom: masterKey)
    }

    private func deriveStorageServiceManifestKey(version: UInt64, storageServiceKey: SVR.DerivedKeyData) -> SVR.DerivedKeyData? {
        let keyType: SVR.DerivedKey = .storageServiceManifest(version: version)
        return SVR.DerivedKeyData(keyType: keyType, dataToDeriveFrom: storageServiceKey.rawData)
    }

    private func deriveStorageServiceRecordKey(identifier: StorageService.StorageIdentifier, storageServiceKey: SVR.DerivedKeyData) -> SVR.DerivedKeyData? {
        let keyType: SVR.DerivedKey = .legacy_storageServiceRecord(identifier: identifier)
        return SVR.DerivedKeyData(keyType: keyType, dataToDeriveFrom: storageServiceKey.rawData)
    }

    // MARK: -

    public func encrypt(
        keyType: SVR.DerivedKey,
        data: Data,
        tx: DBReadTransaction
    ) -> SVR.ApplyDerivedKeyResult {
        guard let keyData = self.data(for: keyType, tx: tx) else {
            return .masterKeyMissing
        }
        do {
            return .success(try Aes256GcmEncryptedData.encrypt(data, key: keyData.rawData).concatenate())
        } catch let error {
            return .cryptographyError(error)
        }
    }

    public func decrypt(
        keyType: SVR.DerivedKey,
        encryptedData: Data,
        tx: DBReadTransaction
    ) -> SVR.ApplyDerivedKeyResult {
        guard let keyData = self.data(for: keyType, tx: tx) else {
            return .masterKeyMissing
        }
        do {
            return .success(try Aes256GcmEncryptedData(concatenated: encryptedData).decrypt(key: keyData.rawData))
        } catch let error {
            return .cryptographyError(error)
        }
    }
}

private extension SVR.DerivedKeyData {
    init?(keyType: SVR.DerivedKey, dataToDeriveFrom: Data) {
        self.init(
            keyType.derivedData(from: dataToDeriveFrom),
            keyType
        )
    }
}

// MARK: -

private extension SVR.DerivedKey {
    private var infoString: String {
        switch self {
        case .registrationLock:
            return "Registration Lock"
        case .registrationRecoveryPassword:
            return "Registration Recovery"
        case .storageService:
            return "Storage Service Encryption"
        case .storageServiceManifest(let version):
            return "Manifest_\(version)"
        case .legacy_storageServiceRecord(let identifier):
            return "Item_\(identifier.data.base64EncodedString())"
        case .backupKey:
            return "20231003_Signal_Backups_GenerateBackupKey"
        }
    }

    func derivedData(from dataToDeriveFrom: Data) -> Data? {
        guard let infoData = infoString.data(using: .utf8) else {
            owsFailDebug("Failed to encode data")
            return nil
        }

        switch self {
        case
                .registrationLock,
                .registrationRecoveryPassword,
                .storageService,
                .storageServiceManifest,
                .legacy_storageServiceRecord:
            return Data(HMAC<SHA256>.authenticationCode(
                for: infoData,
                using: SymmetricKey(data: dataToDeriveFrom)
            ))
        case .backupKey:
            guard
                let bytes = try? hkdf(
                    outputLength: Self.backupKeyLength,
                    inputKeyMaterial: dataToDeriveFrom,
                    salt: Data(),
                    info: infoData
                )
            else {
                return nil
            }
            return Data(bytes)
        }
    }
}
