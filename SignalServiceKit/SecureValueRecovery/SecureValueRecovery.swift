//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation
import LibSignalClient

public enum SVR {

    static let maximumKeyAttempts: UInt32 = 10

    public enum SVRError: Error, Equatable {
        case assertion
        case invalidPin(remainingAttempts: UInt32)
        case backupMissing
    }

    public enum KeysError: Error {
        case missingMasterKey
        case missingOrInvalidMRBK
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
        case success(MasterKey)
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

        public var canonicalStringRepresentation: String {
            switch type {
            case .storageService, .storageServiceManifest, .legacy_storageServiceRecord, .registrationRecoveryPassword:
                return rawData.base64EncodedString()
            case .registrationLock:
                return rawData.hexadecimalString
            }
        }
    }
}

public protocol SecureValueRecovery {

    /// Indicates whether or not we have a master key locally
    func hasMasterKey(transaction: DBReadTransaction) -> Bool

    /// Indicates whether or not we have a master key stored in SVR
    func hasBackedUpMasterKey(transaction: DBReadTransaction) -> Bool

    /// The pin type used (e.g. numeric, alphanumeric)
    func currentPinType(transaction: DBReadTransaction) -> SVR.PinType?

    /// Loads the users key, if any, from the SVR into the database.
    func restoreKeys(pin: String, authMethod: SVR.AuthMethod) -> Guarantee<SVR.RestoreKeysResult>

    /// Loads the users key, if any, from the SVR into the database, then backs them up again.
    func restoreKeysAndBackup(pin: String, authMethod: SVR.AuthMethod) -> Guarantee<SVR.RestoreKeysResult>

    /// Backs up the user's master key to SVR.
    func backupMasterKey(pin: String, masterKey: MasterKey, authMethod: SVR.AuthMethod) -> Promise<MasterKey>

    /// Remove the keys locally from the device and from the SVR,
    /// they will not be able to be restored.
    func deleteKeys() -> Promise<Void>

    func warmCaches()

    /// Removes the SVR keys locally from the device, they can still be
    /// restored from the server if you know the pin.
    func clearKeys(transaction: DBWriteTransaction)

    func storeKeys(
        fromKeysSyncMessage syncMessage: SSKProtoSyncMessageKeys,
        authedDevice: AuthedDevice,
        tx: DBWriteTransaction
    ) throws(SVR.KeysError)

    func storeKeys(
        fromProvisioningMessage provisioningMessage: LinkingProvisioningMessage,
        authedDevice: AuthedDevice,
        tx: DBWriteTransaction
    ) throws(SVR.KeysError)

    func handleMasterKeyUpdated(
        newMasterKey: MasterKey,
        disablePIN: Bool,
        tx: DBWriteTransaction,
    )
}
