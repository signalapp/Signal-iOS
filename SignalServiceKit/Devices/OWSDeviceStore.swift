//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public protocol OWSDeviceStore {
    func fetchAll(tx: DBReadTransaction) -> [OWSDevice]
}

class OWSDeviceStoreImpl: OWSDeviceStore {
    func fetchAll(tx: DBReadTransaction) -> [OWSDevice] {
        return OWSDevice.anyFetchAll(transaction: SDSDB.shimOnlyBridge(tx))
    }
}
