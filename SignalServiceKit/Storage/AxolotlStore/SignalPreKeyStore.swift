//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public protocol SignalPreKeyStore: LibSignalClient.PreKeyStore {
    func generatePreKeyRecords() -> [SignalServiceKit.PreKeyRecord]

    func generatePreKeyRecords(tx: DBWriteTransaction) -> [SignalServiceKit.PreKeyRecord]

    func storePreKeyRecords(_ records: [SignalServiceKit.PreKeyRecord], tx: DBWriteTransaction)

    func cullPreKeyRecords(tx: DBWriteTransaction)

#if TESTABLE_BUILD
    func removeAll(tx: DBWriteTransaction)
#endif
}

extension SSKPreKeyStore: SignalPreKeyStore {
    public func storePreKeyRecords(_ records: [SignalServiceKit.PreKeyRecord], tx: DBWriteTransaction) {
        storePreKeyRecords(records, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func cullPreKeyRecords(tx: DBWriteTransaction) {
        cullPreKeyRecords(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func generatePreKeyRecords(tx: DBWriteTransaction) -> [SignalServiceKit.PreKeyRecord] {
        generatePreKeyRecords(transaction: SDSDB.shimOnlyBridge(tx))
    }

#if TESTABLE_BUILD
    public func removeAll(tx: DBWriteTransaction) {
        removeAll(SDSDB.shimOnlyBridge(tx))
    }
#endif
}
