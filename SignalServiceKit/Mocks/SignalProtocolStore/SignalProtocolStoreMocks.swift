//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

#if TESTABLE_BUILD

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
    func mightContainSession(for recipient: SignalRecipient, tx: DBReadTransaction) -> Bool { false }
    func mergeRecipient(_ recipient: SignalRecipient, into targetRecipient: SignalRecipient, tx: DBWriteTransaction) { }
    func archiveAllSessions(for serviceId: ServiceId, tx: DBWriteTransaction) { }
    func archiveAllSessions(for address: SignalServiceAddress, tx: DBWriteTransaction) { }
    func archiveSession(for serviceId: ServiceId, deviceId: UInt32, tx: DBWriteTransaction) { }
    func loadSession(for serviceId: ServiceId, deviceId: UInt32, tx: DBReadTransaction) throws -> LibSignalClient.SessionRecord? { nil }
    func loadSession(for address: ProtocolAddress, context: StoreContext) throws -> LibSignalClient.SessionRecord? { nil }
    func resetSessionStore(tx: DBWriteTransaction) { }
    func deleteAllSessions(for serviceId: ServiceId, tx: DBWriteTransaction) { }
    func deleteAllSessions(for recipientUniqueId: RecipientUniqueId, tx: DBWriteTransaction) { }
    func removeAll(tx: DBWriteTransaction) { }
    func loadExistingSessions(for addresses: [ProtocolAddress], context: StoreContext) throws -> [LibSignalClient.SessionRecord] { [] }
    func storeSession(_ record: LibSignalClient.SessionRecord, for address: ProtocolAddress, context: StoreContext) throws { }
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
        let keyPair = ECKeyPair.generateKeyPair()
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

    private(set) var lastSuccessfulRotationDate: Date?

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

    func generateSignedPreKey(signedBy: ECKeyPair) -> SignalServiceKit.SignedPreKeyRecord {
        let newKey = SSKSignedPreKeyStore.generateSignedPreKey(signedBy: signedBy)
        generatedSignedPreKeys.append(newKey)
        return newKey
    }

    func generateRandomSignedRecord() -> SignalServiceKit.SignedPreKeyRecord {
        let identityKeyPair = ECKeyPair.generateKeyPair()
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

    func cullSignedPreKeyRecords(
        justUploadedSignedPreKey: SignalServiceKit.SignedPreKeyRecord,
        tx: DBWriteTransaction
    ) {}

    func removeSignedPreKey(
        _ signedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord,
        tx: SignalServiceKit.DBWriteTransaction
    ) {}

    // MARK: - Testing

    func removeAll(tx: DBWriteTransaction) {
        generatedSignedPreKeys.removeAll()
    }

    internal func setPrekeyUpdateFailureCount(
        _ count: Int,
        firstFailureDate: Date,
        tx: DBWriteTransaction
    ) { }

    func setLastSuccessfulRotationDate(_ date: Date, tx: SignalServiceKit.DBWriteTransaction) {
        lastSuccessfulRotationDate = date
    }

    func getLastSuccessfulRotationDate(tx: SignalServiceKit.DBReadTransaction) -> Date? {
        return lastSuccessfulRotationDate
    }
}

internal class MockKyberPreKeyStore: SignalKyberPreKeyStore {

    private(set) var nextKeyId: UInt32 = 0
    var identityKeyPair = ECKeyPair.generateKeyPair()
    var dateProvider: DateProvider

    private(set) var lastSuccessfulRotationDate: Date?

    private(set) var lastResortRecords = [SignalServiceKit.KyberPreKeyRecord]()
    private(set) var didStoreLastResortRecord = false

    private(set) var oneTimeRecords = [SignalServiceKit.KyberPreKeyRecord]()
    private(set) var didStoreOneTimeRecords = false

    private(set) var usedOneTimeRecords = [SignalServiceKit.KyberPreKeyRecord]()

    init(dateProvider: @escaping DateProvider) {
        self.dateProvider = dateProvider
    }

    func generateLastResortKyberPreKey(signedBy keyPair: ECKeyPair, tx: DBWriteTransaction) throws -> SignalServiceKit.KyberPreKeyRecord {
        let record = try generateKyberPreKey(signedBy: keyPair, isLastResort: true)
        lastResortRecords.append(record)
        return record
    }

    func generateLastResortKyberPreKeyForLinkedDevice(signedBy keyPair: ECKeyPair) throws -> SignalServiceKit.KyberPreKeyRecord {
        let record = try generateKyberPreKey(signedBy: keyPair, isLastResort: true)
        lastResortRecords.append(record)
        return record
    }

    func storeLastResortPreKeyFromLinkedDevice(record: KyberPreKeyRecord, tx: DBWriteTransaction) throws { }

    func generateKyberPreKeyRecords(count: Int, signedBy keyPair: ECKeyPair, tx: DBWriteTransaction) throws -> [SignalServiceKit.KyberPreKeyRecord] {
        let records = try (0..<count).map { _ in
            try generateKyberPreKey(signedBy: keyPair, isLastResort: false)
        }
        oneTimeRecords.append(contentsOf: records)
        return records
    }

    func generateKyberPreKey(signedBy keyPair: ECKeyPair, isLastResort: Bool) throws -> SignalServiceKit.KyberPreKeyRecord {

        let keyPair = KEMKeyPair.generate()
        let signature = Data(identityKeyPair.keyPair.privateKey.generateSignature(message: Data(keyPair.publicKey.serialize())))

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
        let signature = Data(identityKeyPair.keyPair.privateKey.generateSignature(message: Data(keyPair.publicKey.serialize())))
        return try LibSignalClient.KyberPreKeyRecord(
            id: keyId,
            timestamp: Date().ows_millisecondsSince1970,
            keyPair: keyPair,
            signature: signature
        )
    }

    public func storeLastResortPreKey(record: SignalServiceKit.KyberPreKeyRecord, tx: DBWriteTransaction) throws {
        didStoreLastResortRecord = true
    }

    func storeKyberPreKeyRecords(records: [SignalServiceKit.KyberPreKeyRecord], tx: DBWriteTransaction) throws {
        didStoreOneTimeRecords = true
    }
    func storeKyberPreKey(_ record: LibSignalClient.KyberPreKeyRecord, id: UInt32, context: LibSignalClient.StoreContext) throws { }

    func markKyberPreKeyUsed(id: UInt32, context: LibSignalClient.StoreContext) throws {
        guard let index = oneTimeRecords.firstIndex(where: { $0.id == id }) else { return }
        let record = oneTimeRecords.remove(at: index)
        usedOneTimeRecords.append(record)
    }

    func cullOneTimePreKeyRecords(tx: DBWriteTransaction) { }

    func cullLastResortPreKeyRecords(justUploadedLastResortPreKey: KyberPreKeyRecord, tx: DBWriteTransaction) {}

    func removeLastResortPreKey(
        record: SignalServiceKit.KyberPreKeyRecord,
        tx: SignalServiceKit.DBWriteTransaction
    ) {}

    func setLastSuccessfulRotationDate(_ date: Date, tx: SignalServiceKit.DBWriteTransaction) {
        lastSuccessfulRotationDate = date
    }

    func getLastSuccessfulRotationDate(tx: SignalServiceKit.DBReadTransaction) -> Date? {
        return lastSuccessfulRotationDate
    }

    func removeAll(tx: DBWriteTransaction) { }
}

#endif
