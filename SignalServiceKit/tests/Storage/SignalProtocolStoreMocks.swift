//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import LibSignalClient

internal class MockSignalProtocolStore: SignalProtocolStore {
    public var sessionStore: SignalSessionStore { mockSessionStore }
    public var preKeyStore: SignalPreKeyStore { mockPreKeyStore }
    public var signedPreKeyStore: SignalSignedPreKeyStore { mockSignedPreKeyStore }
    public var kyberPreKeyStore: SignalKyberPreKeyStore { mockKyberPreKeyStore }

    internal var mockSessionStore = MockSessionStore()
    internal var mockPreKeyStore = MockPreKeyStore()
    internal var mockSignedPreKeyStore = MockSignalSignedPreKeyStore()
    internal var mockKyberPreKeyStore = MockKyberPreKeyStore(dateProvider: Date.provider)
}

class MockSessionStore: SignalSessionStore {
    func containsActiveSession(for serviceId: UntypedServiceId, deviceId: Int32, tx: DBReadTransaction) -> Bool { false }
    func containsActiveSession(forAccountId accountId: String, deviceId: Int32, tx: DBReadTransaction) -> Bool { false }
    func archiveAllSessions(for address: SignalServiceAddress, tx: DBWriteTransaction) { }
    func archiveAllSessions(forAccountId accountId: String, tx: DBWriteTransaction) { }
    func archiveSession(for address: SignalServiceAddress, deviceId: Int32, tx: DBWriteTransaction) { }
    func loadSession(for address: SignalServiceAddress, deviceId: Int32, tx: DBReadTransaction) throws -> LibSignalClient.SessionRecord? { nil }
    func loadSession(for address: LibSignalClient.ProtocolAddress, context: LibSignalClient.StoreContext) throws -> LibSignalClient.SessionRecord? { nil }
    func resetSessionStore(tx: DBWriteTransaction) { }
    func deleteAllSessions(for address: SignalServiceAddress, tx: DBWriteTransaction) { }
    func removeAll(tx: DBWriteTransaction) { }
    func printAll(tx: DBReadTransaction) { }
    func loadExistingSessions(for addresses: [LibSignalClient.ProtocolAddress], context: LibSignalClient.StoreContext) throws -> [LibSignalClient.SessionRecord] { [] }
    func storeSession(_ record: LibSignalClient.SessionRecord, for address: LibSignalClient.ProtocolAddress, context: LibSignalClient.StoreContext) throws { }
}

public class MockPreKeyStore: SignalPreKeyStore {

    private(set) var preKeyId: Int32 = 0
    private(set) var records = [SignalServiceKit.PreKeyRecord]()
    private(set) var didStorePreKeyRecords = false

    public func generatePreKeyRecords() -> [SignalServiceKit.PreKeyRecord] {
        return generatePreKeyRecords(count: 100)
    }

    public func generatePreKeyRecords(tx: DBWriteTransaction) -> [SignalServiceKit.PreKeyRecord] {
        return generatePreKeyRecords(count: 100)
    }

    internal func generatePreKeyRecords(count: Int) -> [SignalServiceKit.PreKeyRecord] {
        var records = [SignalServiceKit.PreKeyRecord]()
        for _ in 0..<count {
            let record = generatePreKeyRecord()
            records.append(record)
        }
        self.records.append(contentsOf: records)
        return records
    }

    internal func generatePreKeyRecord() -> SignalServiceKit.PreKeyRecord {
        let keyPair = Curve25519.generateKeyPair()
        let record = SignalServiceKit.PreKeyRecord(
            id: preKeyId,
            keyPair: keyPair,
            createdAt: Date()
        )
        preKeyId += 1
        return record
    }

    public func storePreKeyRecords(_ records: [SignalServiceKit.PreKeyRecord], tx: DBWriteTransaction) {
        didStorePreKeyRecords = true
    }

    public func removeAll(tx: DBWriteTransaction) {
    }

    public func cullPreKeyRecords(tx: DBWriteTransaction) {
    }

    public func loadPreKey(id: UInt32, context: LibSignalClient.StoreContext) throws -> LibSignalClient.PreKeyRecord {
        let preKey = generatePreKeyRecord()
        return try LibSignalClient.PreKeyRecord(
            id: id,
            publicKey: preKey.keyPair.identityKeyPair.publicKey,
            privateKey: preKey.keyPair.identityKeyPair.privateKey
        )
    }

    public func storePreKey(_ record: LibSignalClient.PreKeyRecord, id: UInt32, context: LibSignalClient.StoreContext) throws {}

    public func removePreKey(id: UInt32, context: LibSignalClient.StoreContext) throws { }
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

internal class MockKyberPreKeyStore: SignalKyberPreKeyStore {

    private(set) var nextKeyId: Int32 = 0
    var identityKeyPair = Curve25519.generateKeyPair()
    var dateProvider: DateProvider

    private(set) var lastResortRecords = [SignalServiceKit.KyberPreKeyRecord]()
    private(set) var currentLastResortPreKey: SignalServiceKit.KyberPreKeyRecord!
    private(set) var didStoreLastResortRecord = false

    private(set) var oneTimeRecords = [SignalServiceKit.KyberPreKeyRecord]()
    private(set) var didStoreOneTimeRecords = false

    private(set) var usedOneTimeRecords = [SignalServiceKit.KyberPreKeyRecord]()

    init(dateProvider: @escaping DateProvider) {
        self.dateProvider = dateProvider
    }

    func getLastResortKyberPreKey(tx: DBReadTransaction) -> SignalServiceKit.KyberPreKeyRecord? {
        return currentLastResortPreKey
    }

    func generateLastResortKyberPreKey(signedBy keyPair: ECKeyPair, tx: DBWriteTransaction) throws -> SignalServiceKit.KyberPreKeyRecord {
        let record = try generateKyberPreKey(signedBy: keyPair, isLastResort: true, tx: tx)
        lastResortRecords.append(record)
        return record
    }

    func generateKyberPreKeyRecords(count: Int, signedBy keyPair: ECKeyPair, tx: DBWriteTransaction) throws -> [SignalServiceKit.KyberPreKeyRecord] {
        let records = try (0..<count).map { _ in
            try generateKyberPreKey(signedBy: keyPair, isLastResort: false, tx: tx)
        }
        oneTimeRecords.append(contentsOf: records)
        return records
    }

    func generateKyberPreKey(signedBy keyPair: ECKeyPair, isLastResort: Bool, tx: DBWriteTransaction) throws -> SignalServiceKit.KyberPreKeyRecord {

        let keyPair = KEMKeyPair.generate()
        let signature = try Ed25519.sign(Data(keyPair.publicKey.serialize()), with: identityKeyPair)

        let record = SignalServiceKit.KyberPreKeyRecord(
            nextKeyId,
            keyPair: keyPair,
            signature: signature,
            generatedAt: dateProvider(),
            isLastResort: isLastResort
        )
        return record
    }

    func loadKyberPreKey(id: UInt32, context: LibSignalClient.StoreContext) throws -> LibSignalClient.KyberPreKeyRecord {
        let keyId = self.nextKeyId
        self.nextKeyId += 1
        let keyPair = KEMKeyPair.generate()
        let signature = try Ed25519.sign(Data(keyPair.publicKey.serialize()), with: identityKeyPair)
        return try LibSignalClient.KyberPreKeyRecord(
            id: UInt32(bitPattern: keyId),
            timestamp: Date().ows_millisecondsSince1970,
            keyPair: keyPair,
            signature: signature
        )
    }

    public func storeLastResortPreKeyAndMarkAsCurrent(record: SignalServiceKit.KyberPreKeyRecord, tx: DBWriteTransaction) throws {
        currentLastResortPreKey = record
        didStoreLastResortRecord = true
    }

    func storeKyberPreKey(record: SignalServiceKit.KyberPreKeyRecord, tx: DBWriteTransaction) throws { }
    func storeKyberPreKeyRecords(records: [SignalServiceKit.KyberPreKeyRecord], tx: DBWriteTransaction) throws {
        didStoreOneTimeRecords = true
    }
    func storeKyberPreKey(_ record: LibSignalClient.KyberPreKeyRecord, id: UInt32, context: LibSignalClient.StoreContext) throws { }

    func markKyberPreKeyUsed(id: UInt32, context: LibSignalClient.StoreContext) throws {
        guard let index = oneTimeRecords.firstIndex(where: { $0.id == id }) else { return }
        let record = oneTimeRecords.remove(at: index)
        usedOneTimeRecords.append(record)
    }
}
