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

    public func deriveLoggingKey() -> LoggingKey {
        return LoggingKey.deriveFrom(masterKey: self)
    }

    public func deriveRegistrationLock() -> RegistrationLock {
        return RegistrationLock.deriveFrom(masterKey: self)
    }

    public func deriveRegistrationRecoveryPassword() -> RegistrationRecoveryPassword {
        return RegistrationRecoveryPassword.deriveFrom(masterKey: self)
    }

    public func deriveStorageServiceKey() -> StorageServiceKey {
        return StorageServiceKey.deriveFrom(masterKey: self)
    }
}

// MARK: -

private func deriveKey(info: String, baseKey: Data) -> Data {
    let infoData = Data(info.utf8)
    return Data(HMAC<SHA256>.authenticationCode(
        for: infoData,
        using: SymmetricKey(data: baseKey),
    ))
}

// MARK: -

/// A key used to hash values used for logging.
public struct LoggingKey {
    public let rawData: Data

    private init(rawData: Data) {
        self.rawData = rawData
    }

    static func deriveFrom(masterKey: MasterKey) -> Self {
        return Self(rawData: deriveKey(info: "Logging Key", baseKey: masterKey.rawData))
    }
}

/// The key required to bypass reglock and register or change number
/// into an owned account.
public struct RegistrationLock: Equatable {
    public let rawData: Data

    private init(rawData: Data) {
        self.rawData = rawData
    }

    static func deriveFrom(masterKey: MasterKey) -> Self {
        return Self(rawData: deriveKey(info: "Registration Lock", baseKey: masterKey.rawData))
    }

    public var canonicalStringRepresentation: String {
        return self.rawData.hexadecimalString
    }

    public static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.rawData.ows_constantTimeIsEqual(to: rhs.rawData)
    }
}

/// The key required to bypass sms verification when registering for an account.
/// Independent from reglock; if reglock is present it is _also_ required, if not
/// this token is still required.
public struct RegistrationRecoveryPassword {
    public let rawData: Data

    private init(rawData: Data) {
        self.rawData = rawData
    }

    static func deriveFrom(masterKey: MasterKey) -> Self {
        return Self(rawData: deriveKey(info: "Registration Recovery", baseKey: masterKey.rawData))
    }

    public var canonicalStringRepresentation: String {
        return self.rawData.base64EncodedString()
    }
}

public struct StorageServiceKey {
    public let rawData: Data

    private init(rawData: Data) {
        self.rawData = rawData
    }

    static func deriveFrom(masterKey: MasterKey) -> Self {
        return Self(rawData: deriveKey(info: "Storage Service Encryption", baseKey: masterKey.rawData))
    }

    func deriveManifestKey(manifestVersion: UInt64) -> StorageServiceManifestKey {
        return StorageServiceManifestKey.deriveFrom(storageServiceKey: self, manifestVersion: manifestVersion)
    }

    func deriveLegacyRecordKey(itemIdentifier: StorageService.StorageIdentifier) -> LegacyStorageServiceRecordKey {
        return LegacyStorageServiceRecordKey.deriveFrom(storageServiceKey: self, itemIdentifier: itemIdentifier)
    }
}

/// The key required to decrypt the Storage Service manifest with the
/// given version.
///
/// - Note
/// The manifest contains identifiers and additional key data that are
/// used to locate and decrypt Storage Service records.
struct StorageServiceManifestKey {
    let rawData: Data

    private init(rawData: Data) {
        self.rawData = rawData
    }

    static func deriveFrom(storageServiceKey: StorageServiceKey, manifestVersion: UInt64) -> Self {
        return Self(rawData: deriveKey(info: "Manifest_\(manifestVersion)", baseKey: storageServiceKey.rawData))
    }
}

/// Today, Storage Service records are encrypted using a key stored in
/// the manifest. However, in the past they were encrypted using an
/// SVR-derived key. This case represents the key formerly used to
/// encrypt Storage Service records, which is preserved for the time
/// being so that records that have not yet been re-encrypted with the
/// new scheme can still be decrypted.
///
/// Once all Storage Service records should be encrypted using the new
/// scheme, we can remove this case.
///
/// - Important
/// This case should only be used for decryption, and never for
/// encryption!
struct LegacyStorageServiceRecordKey {
    let rawData: Data

    private init(rawData: Data) {
        self.rawData = rawData
    }

    static func deriveFrom(storageServiceKey: StorageServiceKey, itemIdentifier: StorageService.StorageIdentifier) -> Self {
        return Self(rawData: deriveKey(info: "Item_\(itemIdentifier.data.base64EncodedString())", baseKey: storageServiceKey.rawData))
    }
}
