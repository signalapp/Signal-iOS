//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public protocol SignalPreKeyStore: LibSignalClient.PreKeyStore {
    func generatePreKeyRecords(tx: DBWriteTransaction) -> [SignalServiceKit.PreKeyRecord]

    func storePreKeyRecords(_ records: [SignalServiceKit.PreKeyRecord], tx: DBWriteTransaction)

    func setReplacedAtToNowIfNil(exceptFor preKeyRecords: [SignalServiceKit.PreKeyRecord], tx: DBWriteTransaction)

    func cullPreKeyRecords(gracePeriod: TimeInterval, tx: DBWriteTransaction)

    func removeAll(tx: DBWriteTransaction)
}

extension SSKPreKeyStore: SignalPreKeyStore {
    public func storePreKeyRecords(_ records: [SignalServiceKit.PreKeyRecord], tx: DBWriteTransaction) {
        storePreKeyRecords(records, transaction: tx)
    }

    public func setReplacedAtToNowIfNil(exceptFor preKeyRecords: [PreKeyRecord], tx: DBWriteTransaction) {
        setReplacedAtToNowIfNil(exceptFor: preKeyRecords, transaction: tx)
    }

    public func cullPreKeyRecords(gracePeriod: TimeInterval, tx: DBWriteTransaction) {
        cullPreKeyRecords(gracePeriod: gracePeriod, transaction: tx)
    }

    public func generatePreKeyRecords(tx: DBWriteTransaction) -> [SignalServiceKit.PreKeyRecord] {
        generatePreKeyRecords(transaction: tx)
    }

    public func removeAll(tx: DBWriteTransaction) {
        removeAll(tx)
    }
}
