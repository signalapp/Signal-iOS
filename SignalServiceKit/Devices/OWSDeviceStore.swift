//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public struct MostRecentlyLinkedDeviceDetails: Codable {
    public let linkedTime: Date
    public let notificationDelay: TimeInterval

    public var shouldRemindUserAfter: Date { linkedTime.addingTimeInterval(notificationDelay) }
}

// MARK: -

public struct OWSDeviceStore {
    private enum StoreKeys {
        static let mostRecentlyLinkedDeviceDetails: String = "mostRecentlyLinkedDeviceDetails"
    }

    private let kvStore: KeyValueStore

    init() {
        kvStore = KeyValueStore(collection: "DeviceStore")
    }

    // MARK: -

    public func fetchAll(tx: DBReadTransaction) -> [OWSDevice] {
        return failIfThrows {
            return try OWSDevice.fetchAll(tx.database)
        }
    }

    public func hasLinkedDevices(tx: DBReadTransaction) -> Bool {
        return fetchAll(tx: tx).contains { !$0.deviceId.isPrimary }
    }

    // MARK: -

    public func replaceAll(with newDevices: [OWSDevice], tx: DBWriteTransaction) -> Bool {
        let existingDevices = fetchAll(tx: tx)

        for existingDevice in existingDevices {
            failIfThrows {
                try existingDevice.delete(tx.database)
            }
        }

        var newDeviceIds = Set<DeviceId>()
        for var newDevice in newDevices {
            guard newDeviceIds.insert(newDevice.deviceId).inserted else {
                owsFailDebug("trying to insert device with duplicate id")
                continue
            }
            failIfThrows {
                try newDevice.insert(tx.database)
            }
        }

        return !newDeviceIds.symmetricDifference(existingDevices.map(\.deviceId)).isEmpty
    }

    // MARK: -

    public func remove(_ device: OWSDevice, tx: DBWriteTransaction) {
        failIfThrows {
            try device.delete(tx.database)
        }
    }

    // MARK: -

    public func setName(
        _ name: String,
        for device: OWSDevice,
        tx: DBWriteTransaction,
    ) {
        var device = device
        device.name = name

        failIfThrows {
            try device.update(tx.database)
        }
    }

    // MARK: -

    public func mostRecentlyLinkedDeviceDetails(
        tx: DBReadTransaction,
    ) -> MostRecentlyLinkedDeviceDetails? {
        do {
            return try kvStore.getCodableValue(
                forKey: StoreKeys.mostRecentlyLinkedDeviceDetails,
                transaction: tx,
            )
        } catch {
            owsFailDebug("Failed to get MostRecentlyLinkedDeviceDetails! \(error)")
            return nil
        }
    }

    public func setMostRecentlyLinkedDeviceDetails(
        linkedTime: Date,
        notificationDelay: TimeInterval,
        tx: DBWriteTransaction,
    ) {
        do {
            try kvStore.setCodable(
                MostRecentlyLinkedDeviceDetails(
                    linkedTime: linkedTime,
                    notificationDelay: notificationDelay,
                ),
                key: StoreKeys.mostRecentlyLinkedDeviceDetails,
                transaction: tx,
            )
        } catch {
            owsFailDebug("Failed to set MostRecentlyLinkedDeviceDetails!")
        }
    }

    public func clearMostRecentlyLinkedDeviceDetails(tx: DBWriteTransaction) {
        kvStore.removeValue(
            forKey: StoreKeys.mostRecentlyLinkedDeviceDetails,
            transaction: tx,
        )
    }
}
