//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public protocol OWSDeviceStore {
    func fetchAll(tx: DBReadTransaction) -> [OWSDevice]
    func replaceAll(with newDevices: [OWSDevice], tx: DBWriteTransaction) -> Bool
    func remove(_ device: OWSDevice, tx: DBWriteTransaction)
    func setEncryptedName(_ encryptedName: String, for device: OWSDevice, tx: DBWriteTransaction)

    func mostRecentlyLinkedDeviceDetails(tx: DBReadTransaction) throws -> MostRecentlyLinkedDeviceDetails?
    func setMostRecentlyLinkedDeviceDetails(
        linkedTime: Date,
        notificationDelay: TimeInterval,
        tx: DBWriteTransaction
    ) throws
    func clearMostRecentlyLinkedDeviceDetails(tx: DBWriteTransaction)
}

public extension OWSDeviceStore {
    func hasLinkedDevices(tx: DBReadTransaction) -> Bool {
        return fetchAll(tx: tx).contains { $0.isLinkedDevice }
    }
}

public struct MostRecentlyLinkedDeviceDetails: Codable {
    public let linkedTime: Date
    public let notificationDelay: TimeInterval

    public var shouldRemindUserAfter: Date { linkedTime.addingTimeInterval(notificationDelay) }
}

class OWSDeviceStoreImpl: OWSDeviceStore {

    private enum Constants {
        static let collectionName: String = "DeviceStore"
        static let mostRecentlyLinkedDeviceDetails: String = "mostRecentlyLinkedDeviceDetails"
    }

    private let keyValueStore: KeyValueStore

    init() {
        keyValueStore = KeyValueStore(collection: Constants.collectionName)
    }

    func fetchAll(tx: DBReadTransaction) -> [OWSDevice] {
        return OWSDevice.anyFetchAll(transaction: SDSDB.shimOnlyBridge(tx))
    }

    func replaceAll(with newDevices: [OWSDevice], tx: DBWriteTransaction) -> Bool {
        return OWSDevice.replaceAll(with: newDevices, transaction: SDSDB.shimOnlyBridge(tx))
    }

    func remove(_ device: OWSDevice, tx: DBWriteTransaction) {
        device.anyRemove(transaction: SDSDB.shimOnlyBridge(tx))
    }

    func setEncryptedName(_ encryptedName: String, for device: OWSDevice, tx: DBWriteTransaction) {
        device.anyUpdate(transaction: SDSDB.shimOnlyBridge(tx)) { device in
            device.encryptedName = encryptedName
        }
    }

    func mostRecentlyLinkedDeviceDetails(tx: any DBReadTransaction) throws -> MostRecentlyLinkedDeviceDetails? {
        try keyValueStore.getCodableValue(
            forKey: Constants.mostRecentlyLinkedDeviceDetails,
            transaction: tx
        )
    }

    func setMostRecentlyLinkedDeviceDetails(
        linkedTime: Date,
        notificationDelay: TimeInterval,
        tx: DBWriteTransaction
    ) throws {
        try keyValueStore.setCodable(
            MostRecentlyLinkedDeviceDetails(
                linkedTime: linkedTime,
                notificationDelay: notificationDelay
            ),
            key: Constants.mostRecentlyLinkedDeviceDetails,
            transaction: tx
        )
    }

    func clearMostRecentlyLinkedDeviceDetails(tx: any DBWriteTransaction) {
        keyValueStore.removeValue(
            forKey: Constants.mostRecentlyLinkedDeviceDetails,
            transaction: tx
        )
    }
}
