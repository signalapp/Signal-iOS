//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension Notification.Name {
    public static let callServicePreferencesDidChange = Notification.Name("CallServicePreferencesDidChange")
}

public struct CallServiceSettingsStore {
    private enum Keys {
        // This used to be called "high bandwidth", but "data" is more accurate.
        static let highDataPreferenceKey = "HighBandwidthPreferenceKey"
    }

    private let keyValueStore = KeyValueStore(collection: "CallService")

    public init() {}

    public func setHighDataInterfaces(_ interfaceSet: NetworkInterfaceSet, tx: DBWriteTransaction) {
        Logger.info("Updating preferred low data interfaces: \(interfaceSet.rawValue)")

        self.keyValueStore.setUInt(
            interfaceSet.rawValue,
            key: Keys.highDataPreferenceKey,
            transaction: tx,
        )

        tx.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(
                name: Notification.Name.callServicePreferencesDidChange,
                object: nil,
            )
        }
    }

    public func highDataNetworkInterfaces(tx: DBReadTransaction) -> NetworkInterfaceSet {
        guard
            let highDataPreference = keyValueStore.getUInt(
                Keys.highDataPreferenceKey,
                transaction: tx,
            )
        else {
            return .wifiAndCellular
        }

        return NetworkInterfaceSet(rawValue: highDataPreference)
    }
}
