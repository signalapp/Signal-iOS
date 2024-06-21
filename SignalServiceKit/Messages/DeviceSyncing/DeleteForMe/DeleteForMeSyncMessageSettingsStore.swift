//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// A store for settings related to `DeleteForMe` sync messages.
public protocol DeleteForMeSyncMessageSettingsStore {
    /// Is sending a `DeleteForMe` sync message enabled?
    ///
    /// Sending starts disabled, and is enabled if we learn that the all of the
    /// local user's devices have the `deleteSync` capability enabled. Since
    /// capabilities are "sticky" and do not support downgrading, once sending
    /// is enabled it will not later be disabled.
    ///
    /// - Note
    /// This check can safely be removed once all clients in the wild support
    /// sending delete syncs; specifically, 90d after send support is released.
    func isSendingEnabled(tx: any DBReadTransaction) -> Bool

    /// Enable sending `DeleteForMe` sync messages.
    func enableSending(tx: any DBWriteTransaction)
}

final class DeleteForMeSyncMessageSettingsStoreImpl: DeleteForMeSyncMessageSettingsStore {
    private enum StoreKeys {
        static let isSendingEnabled = "isSendingEnabled"
    }

    private let keyValueStore: KeyValueStore

    init(keyValueStoreFactory: KeyValueStoreFactory) {
        self.keyValueStore = keyValueStoreFactory.keyValueStore(collection: "DeleteForMeSyncMessageSettingsStoreImpl")
    }

    func isSendingEnabled(tx: any DBReadTransaction) -> Bool {
        // TODO: [DeleteForMe] We can remove this method, and its callers, 90d after delete-sync support ships.
        return keyValueStore.hasValue(StoreKeys.isSendingEnabled, transaction: tx)
    }

    func enableSending(tx: any DBWriteTransaction) {
        keyValueStore.setBool(true, key: StoreKeys.isSendingEnabled, transaction: tx)
    }
}
