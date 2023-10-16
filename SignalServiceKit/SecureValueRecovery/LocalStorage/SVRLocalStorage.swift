//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol SVRLocalStorage {

    func getIsMasterKeyBackedUp(_ transaction: DBReadTransaction) -> Bool
}

public protocol SVRLocalStorageInternal: SVRLocalStorage {

    func getMasterKey(_ transaction: DBReadTransaction) -> Data?

    func getPinType(_ transaction: DBReadTransaction) -> SVR.PinType?

    func getEncodedPINVerificationString(_ transaction: DBReadTransaction) -> String?

    // Linked devices get the storage service key and store it locally. The primary doesn't do this.
    func getSyncedStorageServiceKey(_ transaction: DBReadTransaction) -> Data?

    func getSVR1EnclaveName(_ transaction: DBReadTransaction) -> String?

    func getSVR2MrEnclaveStringValue(_ transaction: DBReadTransaction) -> String?

    // MARK: - Setters

    func setIsMasterKeyBackedUp(_ value: Bool, _ transaction: DBWriteTransaction)

    func setMasterKey(_ value: Data?, _ transaction: DBWriteTransaction)

    func setPinType(_ value: SVR.PinType, _ transaction: DBWriteTransaction)

    func setEncodedPINVerificationString(_ value: String?, _ transaction: DBWriteTransaction)

    // Linked devices get the storage service key and store it locally. The primary doesn't do this.
    func setSyncedStorageServiceKey(_ value: Data?, _ transaction: DBWriteTransaction)

    // Linked devices get the backup key and store it locally. The primary doesn't do this.
    func setSyncedBackupKey(_ value: Data?, _ transaction: DBWriteTransaction)

    func setSVR1EnclaveName(_ value: String?, _ transaction: DBWriteTransaction)

    func setSVR2MrEnclaveStringValue(_ value: String?, _ transaction: DBWriteTransaction)

    // MARK: - Clearing Keys

    func clearKeys(_ transaction: DBWriteTransaction)

}

/// Stores state related to SVR independent of enclave; e.g. do we have backups at all,
/// what type is our pin, etc.
internal class SVRLocalStorageImpl: SVRLocalStorageInternal {

    private let keyValueStore: KeyValueStore

    public init(
        keyValueStoreFactory: KeyValueStoreFactory
    ) {
        // Collection name must not be changed; matches that historically kept in KeyBackupServiceImpl.
        self.keyValueStore = keyValueStoreFactory.keyValueStore(collection: "kOWSKeyBackupService_Keys")
    }

    // MARK: - Getters

    public func getIsMasterKeyBackedUp(_ transaction: DBReadTransaction) -> Bool {
        return keyValueStore.getBool(Keys.isMasterKeyBackedUp, defaultValue: false, transaction: transaction)
    }

    public func getMasterKey(_ transaction: DBReadTransaction) -> Data? {
        return keyValueStore.getData(Keys.masterKey, transaction: transaction)
    }

    public func getPinType(_ transaction: DBReadTransaction) -> SVR.PinType? {
        guard let raw = keyValueStore.getInt(Keys.pinType, transaction: transaction) else {
            return nil
        }
        return SVR.PinType(rawValue: raw)
    }

    public func getEncodedPINVerificationString(_ transaction: DBReadTransaction) -> String? {
        return keyValueStore.getString(Keys.encodedPINVerificationString, transaction: transaction)
    }

    // Linked devices get the storage service key and store it locally. The primary doesn't do this.
    // TODO: By 10/2024, we can remove this method. Starting in 10/2023, we started sending
    // master keys in syncs. A year later, any primary that has not yet delivered a master
    // key must not have launched and is therefore deregistered; we are ok to ignore the
    // storage service key and take the master key or bust.
    public func getSyncedStorageServiceKey(_ transaction: DBReadTransaction) -> Data? {
        return keyValueStore.getData(Keys.syncedStorageServiceKey, transaction: transaction)
    }

    public func getSVR1EnclaveName(_ transaction: DBReadTransaction) -> String? {
        return keyValueStore.getString(Keys.svr1EnclaveName, transaction: transaction)
    }

    public func getSVR2MrEnclaveStringValue(_ transaction: DBReadTransaction) -> String? {
        return keyValueStore.getString(Keys.svr2MrEnclaveStringValue, transaction: transaction)
    }

    // MARK: - Setters

    public func setIsMasterKeyBackedUp(_ value: Bool, _ transaction: DBWriteTransaction) {
        keyValueStore.setBool(value, key: Keys.isMasterKeyBackedUp, transaction: transaction)
    }

    public func setMasterKey(_ value: Data?, _ transaction: DBWriteTransaction) {
        keyValueStore.setData(value, key: Keys.masterKey, transaction: transaction)
    }

    public func setPinType(_ value: SVR.PinType, _ transaction: DBWriteTransaction) {
        keyValueStore.setInt(value.rawValue, key: Keys.pinType, transaction: transaction)
    }

    public func setEncodedPINVerificationString(_ value: String?, _ transaction: DBWriteTransaction) {
        keyValueStore.setString(value, key: Keys.encodedPINVerificationString, transaction: transaction)
    }

    // Linked devices get the storage service key and store it locally. The primary doesn't do this.
    public func setSyncedStorageServiceKey(_ value: Data?, _ transaction: DBWriteTransaction) {
        keyValueStore.setData(value, key: Keys.syncedStorageServiceKey, transaction: transaction)
    }

    // Linked devices get the backup key and store it locally. The primary doesn't do this.
    public func setSyncedBackupKey(_ value: Data?, _ transaction: DBWriteTransaction) {
        keyValueStore.setData(value, key: Keys.syncedBackupKey, transaction: transaction)
    }

    public func setSVR1EnclaveName(_ value: String?, _ transaction: DBWriteTransaction) {
        keyValueStore.setString(value, key: Keys.svr1EnclaveName, transaction: transaction)
    }

    public func setSVR2MrEnclaveStringValue(_ value: String?, _ transaction: DBWriteTransaction) {
        keyValueStore.setString(value, key: Keys.svr2MrEnclaveStringValue, transaction: transaction)
    }

    // MARK: - Clearing Keys

    public func clearKeys(_ transaction: DBWriteTransaction) {
        keyValueStore.removeValues(
            forKeys: [
                Keys.masterKey,
                Keys.pinType,
                Keys.encodedPINVerificationString,
                Keys.isMasterKeyBackedUp,
                Keys.syncedStorageServiceKey,
                Keys.svr1EnclaveName,
                Keys.svr2MrEnclaveStringValue
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
        static let syncedBackupKey = "Backup Key"
        static let svr1EnclaveName = "enclaveName"
        static let svr2MrEnclaveStringValue = "svr2_mrenclaveStringValue"
    }
}
