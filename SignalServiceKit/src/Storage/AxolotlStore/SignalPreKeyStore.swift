//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public protocol SignalPreKeyStore: LibSignalClient.PreKeyStore {
    func generatePreKeyRecords() -> [SignalServiceKit.PreKeyRecord]

    func storePreKeyRecords(_ records: [SignalServiceKit.PreKeyRecord], tx: DBWriteTransaction)

    func removeAll(tx: DBWriteTransaction)

    func cullPreKeyRecords(tx: DBWriteTransaction)

}

extension SSKPreKeyStore: SignalPreKeyStore {
    public func storePreKeyRecords(_ records: [SignalServiceKit.PreKeyRecord], tx: DBWriteTransaction) {
        storePreKeyRecords(records, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func removeAll(tx: DBWriteTransaction) {
        removeAll(SDSDB.shimOnlyBridge(tx))
    }

    public func cullPreKeyRecords(tx: DBWriteTransaction) {
        cullPreKeyRecords(transaction: SDSDB.shimOnlyBridge(tx))
    }
}
