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
    func removeAll(tx: DBWriteTransaction)

    func setPrekeyUpdateFailureCount(
        _ count: Int,
        firstFailureDate: Date,
        tx: DBWriteTransaction
    )
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
}

internal class MockSignalSignedPreKeyStore: SignalSignedPreKeyStore {
    internal private(set) var generatedSignedPreKeys = [SignalServiceKit.SignedPreKeyRecord]()
    private var preKeyId: Int32 = 0
    private var currentSignedPreKey: SignalServiceKit.SignedPreKeyRecord?

    internal private(set) var storedSignedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord?
    internal private(set) var storedSignedPreKeyId: Int32?

    func loadSignedPreKey(id: UInt32, context: LibSignalClient.StoreContext) throws -> LibSignalClient.SignedPreKeyRecord {
        let signedPreKey = generateRandomSignedRecord()
        return try LibSignalClient.SignedPreKeyRecord(
            id: UInt32(signedPreKey.id),
            timestamp: signedPreKey.createdAt?.ows_millisecondsSince1970 ?? 0,
            privateKey: signedPreKey.keyPair.identityKeyPair.privateKey,
            signature: signedPreKey.signature)
    }

    func storeSignedPreKey(_ record: LibSignalClient.SignedPreKeyRecord, id: UInt32, context: LibSignalClient.StoreContext) throws {
    }

    func setCurrentSignedPreKey(_ newSignedPreKey: SignalServiceKit.SignedPreKeyRecord?) {
        currentSignedPreKey = newSignedPreKey
    }

    func currentSignedPreKey(tx: DBReadTransaction) -> SignalServiceKit.SignedPreKeyRecord? {
        currentSignedPreKey
    }

    func currentSignedPreKeyId(tx: DBReadTransaction) -> Int? {
        guard let currentSignedPreKey else { return nil }
        return Int(currentSignedPreKey.id)
    }

    func generateSignedPreKey(signedBy: ECKeyPair) -> SignalServiceKit.SignedPreKeyRecord {
        let newKey = SSKSignedPreKeyStore.generateSignedPreKey(signedBy: signedBy)
        generatedSignedPreKeys.append(newKey)
        return newKey
    }

    func generateRandomSignedRecord() -> SignalServiceKit.SignedPreKeyRecord {
        let identityKeyPair = Curve25519.generateKeyPair()
        return self.generateSignedPreKey(signedBy: identityKeyPair)
    }

    func storeSignedPreKey(
        _ signedPreKeyId: Int32,
        signedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord,
        tx: DBWriteTransaction
    ) {
        self.storedSignedPreKeyId = signedPreKeyId
        self.storedSignedPreKeyRecord = signedPreKeyRecord
    }

    func storeSignedPreKeyAsAcceptedAndCurrent(
           signedPreKeyId: Int32,
           signedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord,
           tx: DBWriteTransaction
    ) {
        self.storedSignedPreKeyId = signedPreKeyId
        self.storedSignedPreKeyRecord = signedPreKeyRecord
        self.currentSignedPreKey = signedPreKeyRecord
    }

    func cullSignedPreKeyRecords(tx: DBWriteTransaction) { }

    func incrementPreKeyUpdateFailureCount(tx: DBWriteTransaction) { }
    internal func getPreKeyUpdateFailureCount(tx: DBReadTransaction) -> Int32 { 0 }
    internal func getFirstPreKeyUpdateFailureDate(tx: DBReadTransaction) -> Date? { nil }
    internal func clearPreKeyUpdateFailureCount(tx: DBWriteTransaction) { }

    // MARK: - Testing

    func removeAll(tx: DBWriteTransaction) {
        generatedSignedPreKeys.removeAll()
    }

    internal func setPrekeyUpdateFailureCount(
        _ count: Int,
        firstFailureDate: Date,
        tx: DBWriteTransaction
    ) { }
}
