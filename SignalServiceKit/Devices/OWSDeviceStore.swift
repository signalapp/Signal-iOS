//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public protocol OWSDeviceStore {
    func fetchAll(tx: DBReadTransaction) -> [OWSDevice]
    func replaceAll(with newDevices: [OWSDevice], tx: DBWriteTransaction) -> Bool
    func remove(_ device: OWSDevice, tx: DBWriteTransaction)
    func setEncryptedName(_ encryptedName: String, for device: OWSDevice, tx: DBWriteTransaction)
}

public extension OWSDeviceStore {
    func hasLinkedDevices(tx: DBReadTransaction) -> Bool {
        return fetchAll(tx: tx).contains { $0.isLinkedDevice }
    }
}

class OWSDeviceStoreImpl: OWSDeviceStore {
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
}
