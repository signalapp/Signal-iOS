//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public protocol OWSDeviceStore {
    func fetchAll(tx: DBReadTransaction) -> [OWSDevice]
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
}
