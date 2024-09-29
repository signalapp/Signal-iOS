//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public protocol SignalSignedPreKeyStore: LibSignalClient.SignedPreKeyStore {

    func generateSignedPreKey(signedBy: ECKeyPair) -> SignalServiceKit.SignedPreKeyRecord
    func generateRandomSignedRecord() -> SignalServiceKit.SignedPreKeyRecord

    func storeSignedPreKey(
        _ signedPreKeyId: Int32,
        signedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord,
        tx: DBWriteTransaction
    )

    func cullSignedPreKeyRecords(
        justUploadedSignedPreKey: SignalServiceKit.SignedPreKeyRecord,
        tx: DBWriteTransaction
    )

    func removeSignedPreKey(
        _ signedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord,
        tx: DBWriteTransaction
    )

    func setLastSuccessfulRotationDate(_ date: Date, tx: DBWriteTransaction)
    func getLastSuccessfulRotationDate(tx: DBReadTransaction) -> Date?

    // MARK: - Testing
#if TESTABLE_BUILD

    func removeAll(tx: DBWriteTransaction)

#endif
}

extension SSKSignedPreKeyStore: SignalSignedPreKeyStore {

    public func generateSignedPreKey(signedBy: ECKeyPair) -> SignalServiceKit.SignedPreKeyRecord {
        SSKSignedPreKeyStore.generateSignedPreKey(signedBy: signedBy)
    }

    public func storeSignedPreKey(
        _ signedPreKeyId: Int32,
        signedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord,
        tx: DBWriteTransaction
    ) {
        storeSignedPreKey(
            signedPreKeyId,
            signedPreKeyRecord: signedPreKeyRecord,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func cullSignedPreKeyRecords(justUploadedSignedPreKey: SignalServiceKit.SignedPreKeyRecord, tx: DBWriteTransaction) {
        cullSignedPreKeyRecords(justUploadedSignedPreKey: justUploadedSignedPreKey, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func removeSignedPreKey(
        _ signedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord,
        tx: DBWriteTransaction
    ) {
        self.removeSignedPreKey(signedPreKeyRecord.id, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func setLastSuccessfulRotationDate(_ date: Date, tx: DBWriteTransaction) {
        setLastSuccessfulRotationDate(date, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func getLastSuccessfulRotationDate(tx: DBReadTransaction) -> Date? {
        getLastSuccessfulRotationDate(transaction: SDSDB.shimOnlyBridge(tx))
    }

    // MARK: - Testing

#if TESTABLE_BUILD

    public func removeAll(tx: DBWriteTransaction) {
        removeAll(transaction: SDSDB.shimOnlyBridge(tx))
    }

#endif
}
