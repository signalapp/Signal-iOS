//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import LibSignalClient

/// Old values were encoded in a redundant {"masterKey": ...} structure.
public struct DeprecatedMasterKey: Codable {
    public let masterKey: MasterKey

    public init(masterKey: MasterKey) {
        self.masterKey = masterKey
    }
}

public struct MasterKey: Codable {

    public enum Constants {
        public static let byteLength: UInt = 32 /* bytes */
    }

    public let rawData: Data

    init() {
        self.rawData = Randomness.generateRandomBytes(Constants.byteLength)
    }

    init(data: Data) throws {
        guard data.count == Constants.byteLength else {
            throw OWSGenericError("MasterKey must be \(Constants.byteLength), not \(data.count)")
        }
        self.rawData = data
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(data: container.decode(Data.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawData)
    }

    public func data(for key: SVR.DerivedKey) -> SVR.DerivedKeyData {
        func withStorageServiceKey(_ handler: (SVR.DerivedKeyData) -> SVR.DerivedKeyData) -> SVR.DerivedKeyData {
            // Linked devices have the master key, synced from the primary.
            // This was not the case historically (2023 and earlier), but since then
            // we sync keys in provisioning and via sync message on app launch.
            let storageServiceKey = SVR.DerivedKeyData(keyType: .storageService, dataToDeriveFrom: rawData)
            return handler(storageServiceKey)
        }

        switch key {
        case .loggingKey:
            return SVR.DerivedKeyData(keyType: .loggingKey, dataToDeriveFrom: rawData)
        case .registrationLock:
            return SVR.DerivedKeyData(keyType: .registrationLock, dataToDeriveFrom: rawData)
        case .registrationRecoveryPassword:
            return SVR.DerivedKeyData(keyType: .registrationRecoveryPassword, dataToDeriveFrom: rawData)
        case .storageService:
            return withStorageServiceKey { $0 }
        case .storageServiceManifest(let version):
            return withStorageServiceKey {
                return SVR.DerivedKeyData(
                    keyType: .storageServiceManifest(version: version),
                    dataToDeriveFrom: $0.rawData,
                )
            }
        case .legacy_storageServiceRecord(let identifier):
            return withStorageServiceKey {
                return SVR.DerivedKeyData(
                    keyType: .legacy_storageServiceRecord(identifier: identifier),
                    dataToDeriveFrom: $0.rawData,
                )
            }
        }
    }

    // MARK: -

    public func encrypt(
        keyType: SVR.DerivedKey,
        data: Data,
    ) throws -> Data {
        let keyData = self.data(for: keyType)
        return try Aes256GcmEncryptedData.encrypt(data, key: keyData.rawData).concatenate()
    }

    public func decrypt(
        keyType: SVR.DerivedKey,
        encryptedData: Data,
    ) throws -> Data {
        let keyData = self.data(for: keyType)
        return try Aes256GcmEncryptedData(concatenated: encryptedData).decrypt(key: keyData.rawData)
    }
}

private extension SVR.DerivedKeyData {
    init(keyType: SVR.DerivedKey, dataToDeriveFrom: Data) {
        self.init(
            rawData: keyType.derivedData(from: dataToDeriveFrom),
            type: keyType,
        )
    }
}

// MARK: -

private extension SVR.DerivedKey {
    private var infoString: String {
        switch self {
        case .loggingKey:
            return "Logging Key"
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
        }
    }

    func derivedData(from dataToDeriveFrom: Data) -> Data {
        let infoData = Data(infoString.utf8)
        switch self {
        case
            .loggingKey,
            .registrationLock,
            .registrationRecoveryPassword,
            .storageService,
            .storageServiceManifest,
            .legacy_storageServiceRecord:
            return Data(HMAC<SHA256>.authenticationCode(
                for: infoData,
                using: SymmetricKey(data: dataToDeriveFrom),
            ))
        }
    }
}
