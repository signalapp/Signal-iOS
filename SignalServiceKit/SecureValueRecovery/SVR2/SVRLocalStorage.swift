//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Stores state related to SVR independent of enclave; e.g. do we have backups at all,
/// what type is our pin, etc.
internal class SVRLocalStorage {

    private let keyValueStore: KeyValueStore

    internal init(
        keyValueStoreFactory: KeyValueStoreFactory
    ) {
        // Collection name must not be changed; matches that historically kept in KeyBackupServiceImpl.
        self.keyValueStore = keyValueStoreFactory.keyValueStore(collection: "kOWSKeyBackupService_Keys")
    }

    // MARK: - Getters

    internal func getIsMasterKeyBackedUp(_ transaction: DBReadTransaction) -> Bool {
        return keyValueStore.getBool(Keys.isMasterKeyBackedUp, defaultValue: false, transaction: transaction)
    }

    internal func getMasterKey(_ transaction: DBReadTransaction) -> Data? {
        return keyValueStore.getData(Keys.masterKey, transaction: transaction)
    }

    internal func getPinType(_ transaction: DBReadTransaction) -> SVR.PinType? {
        guard let raw = keyValueStore.getInt(Keys.pinType, transaction: transaction) else {
            return nil
        }
        return SVR.PinType(rawValue: raw)
    }

    internal func getEncodedPINVerificationString(_ transaction: DBReadTransaction) -> String? {
        return keyValueStore.getString(Keys.encodedPINVerificationString, transaction: transaction)
    }

    // Linked devices get the storage service key and store it locally. The primary doesn't do this.
    internal func getSyncedStorageServiceKey(_ transaction: DBReadTransaction) -> Data? {
        return keyValueStore.getData(Keys.syncedStorageServiceKey, transaction: transaction)
    }

    internal func getSVR1EnclaveName(_ transaction: DBReadTransaction) -> String? {
        return keyValueStore.getString(Keys.svr1EnclaveName, transaction: transaction)
    }

    internal func getSVR2EnclaveName(_ transaction: DBReadTransaction) -> String? {
        return keyValueStore.getString(Keys.svr2EnclaveName, transaction: transaction)
    }

    // MARK: - Setters

    internal func setIsMasterKeyBackedUp(_ value: Bool, _ transaction: DBWriteTransaction) {
        keyValueStore.setBool(value, key: Keys.isMasterKeyBackedUp, transaction: transaction)
    }

    internal func setMasterKey(_ value: Data, _ transaction: DBWriteTransaction) {
        keyValueStore.setData(value, key: Keys.masterKey, transaction: transaction)
    }

    internal func setPinType(_ value: SVR.PinType, _ transaction: DBWriteTransaction) {
        keyValueStore.setInt(value.rawValue, key: Keys.pinType, transaction: transaction)
    }

    internal func setEncodedPINVerificationString(_ value: String, _ transaction: DBWriteTransaction) {
        keyValueStore.setString(value, key: Keys.encodedPINVerificationString, transaction: transaction)
    }

    // Linked devices get the storage service key and store it locally. The primary doesn't do this.
    internal func setSyncedStorageServiceKey(_ value: Data?, _ transaction: DBWriteTransaction) {
        keyValueStore.setData(value, key: Keys.syncedStorageServiceKey, transaction: transaction)
    }

    internal func setSVR1EnclaveName(_ value: String, _ transaction: DBWriteTransaction) {
        keyValueStore.setString(value, key: Keys.svr1EnclaveName, transaction: transaction)
    }

    internal func setSVR2EnclaveName(_ value: String, _ transaction: DBWriteTransaction) {
        keyValueStore.setString(value, key: Keys.svr2EnclaveName, transaction: transaction)
    }

    // MARK: - Clearing Keys

    internal func clearKeys(_ transaction: DBWriteTransaction) {
        keyValueStore.removeValues(
            forKeys: [
                Keys.masterKey,
                Keys.pinType,
                Keys.encodedPINVerificationString,
                Keys.isMasterKeyBackedUp,
                Keys.syncedStorageServiceKey,
                Keys.svr1EnclaveName,
                Keys.svr2EnclaveName
            ],
            transaction: transaction
        )
    }

    // MARK: - Identifiers

    private enum Keys {
        // These must not change, they match what was historically in KeyBackupServiceImpl.
        static let masterKey = "masterKey"
        static let pinType = "pinType"
        static let encodedPINVerificationString = "encodedVerificationString"
        static let isMasterKeyBackedUp = "isMasterKeyBackedUp"
        static let syncedStorageServiceKey = "Storage Service Encryption"
        static let svr1EnclaveName = "enclaveName"
        static let svr2EnclaveName = "svr2_enclaveName"
    }
}
