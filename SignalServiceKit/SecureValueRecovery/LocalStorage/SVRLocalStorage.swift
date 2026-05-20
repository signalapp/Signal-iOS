//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Stores state related to SVR independent of enclave; e.g. do we have backups at all,
/// what type is our pin, etc.
struct SVRLocalStorage {
    private let svrKvStore: KeyValueStore

    init() {
        // Collection name must not be changed; matches that historically kept in KeyBackupServiceImpl.
        self.svrKvStore = KeyValueStore(collection: "kOWSKeyBackupService_Keys")
    }

    // MARK: - Getters

    func getNeedsMasterKeyBackup(_ transaction: DBReadTransaction) -> Bool {
        return svrKvStore.getBool(Keys.needsMasterKeyBackup, defaultValue: false, transaction: transaction)
    }

    func getIsMasterKeyBackedUp(_ transaction: DBReadTransaction) -> Bool {
        return svrKvStore.getBool(Keys.isMasterKeyBackedUp, defaultValue: false, transaction: transaction)
    }

    func getPinType(_ transaction: DBReadTransaction) -> SVR.PinType? {
        guard let raw = svrKvStore.getInt(Keys.pinType, transaction: transaction) else {
            return nil
        }
        return SVR.PinType(rawValue: raw)
    }

    func getSVR2MrEnclaveStringValue(_ transaction: DBReadTransaction) -> String? {
        return svrKvStore.getString(Keys.svr2MrEnclaveStringValue, transaction: transaction)
    }

    // MARK: - Setters

    func setNeedsMasterKeyBackup(_ value: Bool, _ transaction: DBWriteTransaction) {
        return svrKvStore.setBool(value, key: Keys.needsMasterKeyBackup, transaction: transaction)
    }

    func setIsMasterKeyBackedUp(_ value: Bool, _ transaction: DBWriteTransaction) {
        svrKvStore.setBool(value, key: Keys.isMasterKeyBackedUp, transaction: transaction)
    }

    func setPinType(_ value: SVR.PinType, _ transaction: DBWriteTransaction) {
        svrKvStore.setInt(value.rawValue, key: Keys.pinType, transaction: transaction)
    }

    func setSVR2MrEnclaveStringValue(_ value: String?, _ transaction: DBWriteTransaction) {
        svrKvStore.setString(value, key: Keys.svr2MrEnclaveStringValue, transaction: transaction)
    }

    // MARK: - Clearing Keys

    func clearSVRKeys(_ transaction: DBWriteTransaction) {
        svrKvStore.removeValues(
            forKeys: [
                Keys.pinType,
                Keys.isMasterKeyBackedUp,
                Keys.syncedStorageServiceKey,
                Keys.legacy_svr1EnclaveName,
                Keys.svr2MrEnclaveStringValue,
                Keys.needsMasterKeyBackup,
            ],
            transaction: transaction,
        )
    }

    func clearStorageServiceKeys(_ transaction: DBWriteTransaction) {
        svrKvStore.removeValue(forKey: Keys.syncedStorageServiceKey, transaction: transaction)
    }

    // MARK: - Cleanup

    func cleanupDeadKeys(_ transaction: DBWriteTransaction) {
        svrKvStore.removeValues(
            forKeys: [
                Keys.legacy_svr1EnclaveName,
            ],
            transaction: transaction,
        )
    }

    // MARK: - Identifiers

    private enum Keys {
        // These must not change, they match what was historically in KeyBackupServiceImpl.
        static let pinType = "pinType"
        static let isMasterKeyBackedUp = "isMasterKeyBackedUp"
        static let needsMasterKeyBackup = "needsMasterKeyBackup"
        static let syncedStorageServiceKey = "Storage Service Encryption"
        // Kept around because its existence indicates we had an svr1 backup.
        // TODO: Remove after Nov 1, 2024
        static let legacy_svr1EnclaveName = "enclaveName"
        static let svr2MrEnclaveStringValue = "svr2_mrenclaveStringValue"
    }
}
