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

    func setSVR2MrEnclaveStringValue(_ value: String?, _ transaction: DBWriteTransaction) {
        svrKvStore.setString(value, key: Keys.svr2MrEnclaveStringValue, transaction: transaction)
    }

    // MARK: - Clearing Keys

    func clearSVRKeys(_ transaction: DBWriteTransaction) {
        svrKvStore.removeValues(
            forKeys: [
                Keys.isMasterKeyBackedUp,
                Keys.svr2MrEnclaveStringValue,
                Keys.needsMasterKeyBackup,
            ],
            transaction: transaction,
        )
    }

    // MARK: - Identifiers

    private enum Keys {
        // These must not change, they match what was historically in KeyBackupServiceImpl.
        static let isMasterKeyBackedUp = "isMasterKeyBackedUp"
        static let needsMasterKeyBackup = "needsMasterKeyBackup"
        static let svr2MrEnclaveStringValue = "svr2_mrenclaveStringValue"
    }
}
