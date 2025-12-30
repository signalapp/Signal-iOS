//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

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
        return fetchAll(tx: tx).contains { $0.isLinkedDevice }
    }

    // MARK: -

    public func replaceAll(with newDevices: [OWSDevice], tx: DBWriteTransaction) -> Bool {
        let existingDevices = fetchAll(tx: tx)

        for existingDevice in existingDevices {
            do {
                try existingDevice.delete(tx.database)
            } catch {
                owsFailDebug("Failed to delete device! \(error)")
            }
        }

        for newDevice in newDevices {
            do {
                try newDevice.insert(tx.database)
            } catch {
                owsFailDebug("Failed to insert device! \(error)")
            }
        }

        let existingDeviceIds = Set(existingDevices.map { $0.deviceId })
        let newDeviceIds = Set(newDevices.map { $0.deviceId })
        return !newDeviceIds.symmetricDifference(existingDeviceIds).isEmpty
    }

    // MARK: -

    public func remove(_ device: OWSDevice, tx: DBWriteTransaction) {
        do {
            try device.delete(tx.database)
        } catch {
            owsFailDebug("Failed to delete device! \(error)")
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

        do {
            try device.update(tx.database)
        } catch {
            owsFailDebug("Failed to update device with new encryptedName! \(error)")
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
