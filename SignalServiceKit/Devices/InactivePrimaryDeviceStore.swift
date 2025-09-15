//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension Notification.Name {
    public static let inactivePrimaryDeviceChanged = Notification.Name("inactivePrimaryDeviceChanged")
}

public class InactivePrimaryDeviceStore: NSObject {
    private enum StoreKeys {
        static let hasInactivePrimaryDeviceAlert: String = "hasInactivePrimaryDevice"
    }

    private let kvStore: KeyValueStore

    public override init() {
        self.kvStore = KeyValueStore(collection: "InactivePrimaryDeviceStore")
    }

    public func setValueForInactivePrimaryDeviceAlert(
        value: Bool,
        transaction: DBWriteTransaction
    ) {
        kvStore.setBool(
            value,
            key: StoreKeys.hasInactivePrimaryDeviceAlert,
            transaction: transaction
        )
    }

    public func valueForInactivePrimaryDeviceAlert(transaction: DBReadTransaction) -> Bool {
        return kvStore.getBool(
            StoreKeys.hasInactivePrimaryDeviceAlert,
            transaction: transaction
        ) ?? false
    }
}
