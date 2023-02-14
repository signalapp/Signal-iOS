//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum KBS {

    public enum KBSError: Error, Equatable {
        case assertion
        case invalidPin(triesRemaining: UInt32)
        case backupMissing
    }

    public enum PinType: Int {
        case numeric = 1
        case alphanumeric = 2

        public init(forPin pin: String) {
            let normalizedPin = KeyBackupService.normalizePin(pin)
            self = normalizedPin.digitsOnly() == normalizedPin ? .numeric : .alphanumeric
        }
    }

    public enum DerivedKey: Hashable {
        /// The key required to bypass reglock and register or change number
        /// into an owned account.
        case registrationLock
        /// The key required to bypass sms verification when registering for an account.
        /// Independent from reglock; if reglock is present it is _also_ required, if not
        /// this token is still required.
        case registrationRecoveryPassword
        case storageService

        case storageServiceManifest(version: UInt64)
        case storageServiceRecord(identifier: StorageService.StorageIdentifier)

        var rawValue: String {
            switch self {
            case .registrationLock:
                return "Registration Lock"
            case .registrationRecoveryPassword:
                return "Registration Recovery"
            case .storageService:
                return "Storage Service Encryption"
            case .storageServiceManifest(let version):
                return "Manifest_\(version)"
            case .storageServiceRecord(let identifier):
                return "Item_\(identifier.data.base64EncodedString())"
            }
        }

        static var syncableKeys: [DerivedKey] {
            return [
                .storageService
            ]
        }

        public func derivedData(from dataToDeriveFrom: Data) -> Data? {
            guard let data = rawValue.data(using: .utf8) else {
                owsFailDebug("Failed to encode data")
                return nil
            }

            return Cryptography.computeSHA256HMAC(data, key: dataToDeriveFrom)
        }
    }
}

public protocol KeyBackupServiceProtocol {

    /// Indicates whether or not we have a master key locally
    var hasMasterKey: Bool { get }

    var currentEnclave: KeyBackupEnclave { get }

    /// Indicates whether or not we have a master key stored in KBS
    var hasBackedUpMasterKey: Bool { get }

    func hasMasterKey(transaction: DBReadTransaction) -> Bool

    var currentPinType: KBS.PinType? { get }

    /// Indicates whether your pin is valid when compared to your stored keys.
    /// This is a local verification and does not make any requests to the KBS.
    func verifyPin(_ pin: String, resultHandler: @escaping (Bool) -> Void)

    // When changing number, we need to verify the PIN against the new number's KBS
    // record in order to generate a registration lock token. It's important that this
    // happens without touching any of the state we maintain around our account.
    func acquireRegistrationLockForNewNumber(with pin: String, and auth: KBSAuthCredential) -> Promise<String>

    /// Loads the users key, if any, from the KBS into the database.
    func restoreKeysAndBackup(with pin: String, and auth: KBSAuthCredential?) -> Promise<Void>

    func generateAndBackupKeys(with pin: String, rotateMasterKey: Bool) -> AnyPromise

    /// Backs up the user's master key to KBS and stores it locally in the database.
    /// If the user doesn't have a master key already a new one is generated.
    func generateAndBackupKeys(with pin: String, rotateMasterKey: Bool) -> Promise<Void>

    /// Remove the keys locally from the device and from the KBS,
    /// they will not be able to be restored.
    func deleteKeys() -> Promise<Void>

    // MARK: - Master Key Encryption

    func encrypt(keyType: KBS.DerivedKey, data: Data) throws -> Data

    func decrypt(keyType: KBS.DerivedKey, encryptedData: Data) throws -> Data

    func deriveRegistrationLockToken() -> String?

    static func normalizePin(_ pin: String) -> String

    func warmCaches()

    /// Removes the KBS keys locally from the device, they can still be
    /// restored from the server if you know the pin.
    func clearKeys(transaction: DBWriteTransaction)

    func storeSyncedKey(type: KBS.DerivedKey, data: Data?, transaction: DBWriteTransaction)

    func hasBackupKeyRequestFailed(transaction: DBReadTransaction) -> Bool

    func hasPendingRestoration(transaction: DBReadTransaction) -> Bool

    func recordPendingRestoration(transaction: DBWriteTransaction)

    func clearPendingRestoration(transaction: DBWriteTransaction)

    func setMasterKeyBackedUp(_ value: Bool, transaction: DBWriteTransaction)

    func useDeviceLocalMasterKey(transaction: DBWriteTransaction)

    func data(for key: KBS.DerivedKey) -> Data?

    func isKeyAvailable(_ key: KBS.DerivedKey) -> Bool
}

extension KeyBackupServiceProtocol {

    public func restoreKeysAndBackup(with pin: String) -> Promise<Void> {
        restoreKeysAndBackup(with: pin, and: nil)
    }
}
