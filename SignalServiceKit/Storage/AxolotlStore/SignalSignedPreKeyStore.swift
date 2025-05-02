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

    func setReplacedAtToNowIfNil(
        exceptFor justUploadedSignedPreKey: SignalServiceKit.SignedPreKeyRecord,
        tx: DBWriteTransaction
    )

    func cullSignedPreKeyRecords(gracePeriod: TimeInterval, tx: DBWriteTransaction)

    func removeSignedPreKey(
        _ signedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord,
        tx: DBWriteTransaction
    )

    func setLastSuccessfulRotationDate(_ date: Date, tx: DBWriteTransaction)
    func getLastSuccessfulRotationDate(tx: DBReadTransaction) -> Date?

    func removeAll(tx: DBWriteTransaction)
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
            transaction: tx
        )
    }

    public func setReplacedAtToNowIfNil(exceptFor justUploadedSignedPreKey: SignedPreKeyRecord, tx: DBWriteTransaction) {
        setReplacedAtToNowIfNil(exceptFor: justUploadedSignedPreKey, transaction: tx)
    }

    public func cullSignedPreKeyRecords(gracePeriod: TimeInterval, tx: DBWriteTransaction) {
        cullSignedPreKeyRecords(gracePeriod: gracePeriod, transaction: tx)
    }

    public func removeSignedPreKey(
        _ signedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord,
        tx: DBWriteTransaction
    ) {
        self.removeSignedPreKey(signedPreKeyRecord.id, transaction: tx)
    }

    public func setLastSuccessfulRotationDate(_ date: Date, tx: DBWriteTransaction) {
        setLastSuccessfulRotationDate(date, transaction: tx)
    }

    public func getLastSuccessfulRotationDate(tx: DBReadTransaction) -> Date? {
        getLastSuccessfulRotationDate(transaction: tx)
    }

    public func removeAll(tx: DBWriteTransaction) {
        removeAll(transaction: tx)
    }
}
