//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public protocol SignalSignedPreKeyStore: LibSignalClient.SignedPreKeyStore {

    func currentSignedPreKey(tx: DBReadTransaction) -> SignalServiceKit.SignedPreKeyRecord?
    func currentSignedPreKeyId(tx: DBReadTransaction) -> Int?

    func generateSignedPreKey(signedBy: ECKeyPair) -> SignalServiceKit.SignedPreKeyRecord
    func generateRandomSignedRecord() -> SignalServiceKit.SignedPreKeyRecord

    func storeSignedPreKey(
        _ signedPreKeyId: Int32,
        signedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord,
        tx: DBWriteTransaction
    )

    func storeSignedPreKeyAsAcceptedAndCurrent(
           signedPreKeyId: Int32,
           signedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord,
           tx: DBWriteTransaction
    )

    func cullSignedPreKeyRecords(tx: DBWriteTransaction)

    func incrementPreKeyUpdateFailureCount(tx: DBWriteTransaction)
    func getPreKeyUpdateFailureCount(tx: DBReadTransaction) -> Int32
    func getFirstPreKeyUpdateFailureDate(tx: DBReadTransaction) -> Date?
    func clearPreKeyUpdateFailureCount(tx: DBWriteTransaction)

    // MARK: - Testing
#if TESTABLE_BUILD

    func removeAll(tx: DBWriteTransaction)

    func setPrekeyUpdateFailureCount(
        _ count: Int,
        firstFailureDate: Date,
        tx: DBWriteTransaction
    )

#endif
}

extension SSKSignedPreKeyStore: SignalSignedPreKeyStore {

    public func generateSignedPreKey(signedBy: ECKeyPair) -> SignalServiceKit.SignedPreKeyRecord {
        SSKSignedPreKeyStore.generateSignedPreKey(signedBy: signedBy)
    }

    public func currentSignedPreKey(tx: DBReadTransaction) -> SignalServiceKit.SignedPreKeyRecord? {
        currentSignedPreKey(with: SDSDB.shimOnlyBridge(tx))
    }

    public func currentSignedPreKeyId(tx: DBReadTransaction) -> Int? {
        currentSignedPrekeyId(with: SDSDB.shimOnlyBridge(tx))?.intValue
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

    public func storeSignedPreKeyAsAcceptedAndCurrent(
        signedPreKeyId: Int32,
        signedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord,
        tx: DBWriteTransaction
    ) {
        storeSignedPreKeyAsAcceptedAndCurrent(
            signedPreKeyId: signedPreKeyId,
            signedPreKeyRecord: signedPreKeyRecord,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func cullSignedPreKeyRecords(tx: DBWriteTransaction) {
        cullSignedPreKeyRecords(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func incrementPreKeyUpdateFailureCount(tx: DBWriteTransaction) {
        incrementPrekeyUpdateFailureCount(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func getPreKeyUpdateFailureCount(tx: DBReadTransaction) -> Int32 {
        prekeyUpdateFailureCount(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func getFirstPreKeyUpdateFailureDate(tx: DBReadTransaction) -> Date? {
        firstPrekeyUpdateFailureDate(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func clearPreKeyUpdateFailureCount(tx: DBWriteTransaction) {
        clearPrekeyUpdateFailureCount(transaction: SDSDB.shimOnlyBridge(tx))
    }

    // MARK: - Testing

#if TESTABLE_BUILD

    public func removeAll(tx: DBWriteTransaction) {
        removeAll(SDSDB.shimOnlyBridge(tx))
    }

    public func setPrekeyUpdateFailureCount(
        _ count: Int,
        firstFailureDate: Date,
        tx: DBWriteTransaction
    ) {
        setPrekeyUpdateFailureCount(
            count,
            firstFailureDate: firstFailureDate,
            transaction: SDSDB.shimOnlyBridge(tx))
    }

#endif
}
