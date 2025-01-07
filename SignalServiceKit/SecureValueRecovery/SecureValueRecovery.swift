//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation
import LibSignalClient

public enum SVR {

    static let maximumKeyAttempts: UInt32 = 10
    static let masterKeyLengthBytes: UInt = 32

    public enum SVRError: Error, Equatable {
        case assertion
        case invalidPin(remainingAttempts: UInt32)
        case backupMissing
    }

    public enum PinType: Int {
        case numeric = 1
        case alphanumeric = 2

        public init(forPin pin: String) {
            let normalizedPin = SVRUtil.normalizePin(pin)
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

        /// The key required to decrypt the Storage Service manifest with the
        /// given version.
        ///
        /// - Note
        /// The manifest contains identifiers and additional key data that are
        /// used to locate and decrypt Storage Service records.
        case storageServiceManifest(version: UInt64)

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
        case legacy_storageServiceRecord(identifier: StorageService.StorageIdentifier)

        /// The root key used for reads and writes to encrypted backups. NOT the same
        /// as the Backup ID Material, that is derived from the backup key.
        /// Referred to often as Kb (subscript b).
        case backupKey

        public static let backupKeyLength = 32
    }

    /// An auth credential is needed to talk to the SVR server.
    /// This defines how we should get that auth credential
    public indirect enum AuthMethod: Equatable {
        /// Explicitly provide an auth credential to use directly with SVR.
        /// note: if it fails, will fall back to the backup or implicit if unset.
        case svrAuth(SVRAuthCredential, backup: AuthMethod?)
        /// Get an SVR auth credential from the chat server first with the
        /// provided credentials, then use it to talk to the SVR server.
        case chatServerAuth(AuthedAccount)
        /// Use whatever SVR auth credential we have cached; if unavailable or
        /// if invalid, falls back to getting a SVR auth credential from the chat server
        /// with the chat server auth credentials we have cached.
        case implicit
    }

    public enum RestoreKeysResult {
        case success
        case invalidPin(remainingAttempts: UInt32)
        // This could mean there was never a backup, or it's been
        // deleted due to using up all pin attempts.
        case backupMissing
        case networkError(Error)
        // Some other issue.
        case genericError(Error)
    }

    public struct DerivedKeyData {
        /// Can never be empty data; instances would fail to initialize.
        public let rawData: Data
        public let type: DerivedKey

        internal init?(_ rawData: Data?, _ type: DerivedKey) {
            guard let rawData, !rawData.isEmpty else {
                return nil
            }
            self.rawData = rawData
            self.type = type
        }

        public var canonicalStringRepresentation: String {
            switch type {
            case .storageService, .storageServiceManifest, .legacy_storageServiceRecord, .registrationRecoveryPassword:
                return rawData.base64EncodedString()
            case .registrationLock:
                return rawData.hexadecimalString
            case .backupKey:
                owsFailDebug("No know uses for canonical string representation")
                return rawData.base64EncodedString()
            }
        }
    }

    public enum ApplyDerivedKeyResult {
        case success(Data)
        case masterKeyMissing
        //  Error encrypting or decrypting
        case cryptographyError(Error)
    }
}

public protocol SecureValueRecovery {

    /// Indicates whether or not we have a master key locally
    func hasMasterKey(transaction: DBReadTransaction) -> Bool

    /// Indicates whether or not we have a master key stored in SVR
    func hasBackedUpMasterKey(transaction: DBReadTransaction) -> Bool

    /// The pin type used (e.g. numeric, alphanumeric)
    func currentPinType(transaction: DBReadTransaction) -> SVR.PinType?

    /// Indicates whether your pin is valid when compared to your stored keys.
    /// This is a local verification and does not make any requests to the SVR.
    /// Callback will happen on the main thread.
    func verifyPin(_ pin: String, resultHandler: @escaping (Bool) -> Void)

    /// Loads the users key, if any, from the SVR into the database.
    func restoreKeys(pin: String, authMethod: SVR.AuthMethod) -> Guarantee<SVR.RestoreKeysResult>

    /// Loads the users key, if any, from the SVR into the database, then backs them up again.
    func restoreKeysAndBackup(pin: String, authMethod: SVR.AuthMethod) -> Guarantee<SVR.RestoreKeysResult>

    /// Backs up the user's master key to SVR and stores it locally in the database.
    /// If the user doesn't have a master key already a new one is generated.
    func generateAndBackupKeys(pin: String, authMethod: SVR.AuthMethod) -> Promise<Void>

    /// Remove the keys locally from the device and from the SVR,
    /// they will not be able to be restored.
    func deleteKeys() -> Promise<Void>

    func warmCaches()

    /// Removes the SVR keys locally from the device, they can still be
    /// restored from the server if you know the pin.
    func clearKeys(transaction: DBWriteTransaction)

    func storeSyncedMasterKey(
        data: Data,
        authedDevice: AuthedDevice,
        updateStorageService: Bool,
        transaction: DBWriteTransaction
    )

    func masterKeyDataForKeysSyncMessage(tx: DBReadTransaction) -> Data?

    /// When we fail to decrypt information on storage service on a linked device, we assume the storage
    /// service key (or master key it is derived from) we have synced from the primary is wrong/out-of-date, and wipe it.
    func clearSyncedStorageServiceKey(transaction: DBWriteTransaction)

    /// Rotate the master key and _don't_ back it up to the SVR server, in effect switching to a
    /// local-only master key and disabling PIN usage for backup restoration.
    func useDeviceLocalMasterKey(authedAccount: AuthedAccount, transaction: DBWriteTransaction)
}
