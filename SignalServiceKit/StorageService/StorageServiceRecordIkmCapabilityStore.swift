//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Stores values related to the migration of Storage Service record encryption
/// to use a scheme based on a `recordIkm` field stored in the Storage Service
/// manifest.
///
/// - SeeAlso ``StorageServiceRecordIkmMigrator``
public protocol StorageServiceRecordIkmCapabilityStore {
    func isRecordIkmCapable(tx: DBReadTransaction) -> Bool
    func setIsRecordIkmCapable(tx: DBWriteTransaction)
}

struct StorageServiceRecordIkmCapabilityStoreImpl: StorageServiceRecordIkmCapabilityStore {
    private enum StoreKeys {
        static let isRecordIkmCapable = "isRecordIkmCapable"
    }

    private let kvStore: KeyValueStore

    init() {
        kvStore = KeyValueStore(collection: "SSRecIkmCapStore")
    }

    // MARK: -

    func isRecordIkmCapable(tx: DBReadTransaction) -> Bool {
        // TODO: Once all clients in the wild must be `recordIkm`-capable, we can delete this method and assume true.
        return kvStore.getBool(StoreKeys.isRecordIkmCapable, defaultValue: false, transaction: tx)
    }

    func setIsRecordIkmCapable(tx: DBWriteTransaction) {
        kvStore.setBool(true, key: StoreKeys.isRecordIkmCapable, transaction: tx)
    }
}
