//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public protocol SignalKyberPreKeyStore: LibSignalClient.KyberPreKeyStore {
    func getLastResortKyberPreKey(
        tx: DBReadTransaction
    ) -> SignalServiceKit.KyberPreKeyRecord?

    func generateLastResortKyberPreKey(
        signedBy keyPair: ECKeyPair,
        tx: DBWriteTransaction
    ) throws -> SignalServiceKit.KyberPreKeyRecord

    func generateKyberPreKeyRecords(
        count: Int,
        signedBy keyPair: ECKeyPair,
        tx: DBWriteTransaction
    ) throws -> [SignalServiceKit.KyberPreKeyRecord]

    func storeLastResortPreKeyAndMarkAsCurrent(
        record: SignalServiceKit.KyberPreKeyRecord,
        tx: DBWriteTransaction
    ) throws

    func storeKyberPreKeyRecords(
        records: [SignalServiceKit.KyberPreKeyRecord],
        tx: DBWriteTransaction
    ) throws

    func storeKyberPreKey(
        record: SignalServiceKit.KyberPreKeyRecord,
        tx: DBWriteTransaction
    ) throws

    func cullLastResortPreKeyRecords(tx: DBWriteTransaction) throws

    func removeLastResortPreKey(
        record: SignalServiceKit.KyberPreKeyRecord,
        tx: DBWriteTransaction
    )

    func cullOneTimePreKeyRecords(tx: DBWriteTransaction) throws

    func setLastSuccessfulPreKeyRotationDate(
        _ date: Date,
        tx: DBWriteTransaction
    )

    func getLastSuccessfulPreKeyRotationDate(
        tx: DBReadTransaction
    ) -> Date?

#if TESTABLE_BUILD
    func removeAll(tx: DBWriteTransaction)
#endif
}

public struct KyberPreKeyRecord: Codable {

    enum CodingKeys: String, CodingKey {
        case keyData
        case isLastResort
    }

    public let signature: Data
    public let generatedAt: Date
    public let id: Int32
    public let keyPair: KEMKeyPair
    public let isLastResort: Bool

    public init(
        _ id: Int32,
        keyPair: KEMKeyPair,
        signature: Data,
        generatedAt: Date,
        isLastResort: Bool
    ) {
        self.id = id
        self.keyPair = keyPair
        self.signature = signature
        self.generatedAt = generatedAt
        self.isLastResort = isLastResort
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        let record = try LibSignalClient.KyberPreKeyRecord(
            id: UInt32(bitPattern: id),
            timestamp: generatedAt.ows_millisecondsSince1970,
            keyPair: keyPair,
            signature: signature
        )

        try container.encode(isLastResort, forKey: .isLastResort)
        try container.encode(Data(record.serialize()), forKey: .keyData)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let isLastResort = try container.decode(Bool.self, forKey: .isLastResort)
        let keyData = try container.decode(Data.self, forKey: .keyData)

        let record = try LibSignalClient.KyberPreKeyRecord(bytes: keyData)
        self.id = Int32(bitPattern: record.id)
        self.keyPair = record.keyPair
        self.signature = Data(record.signature)
        self.generatedAt = Date(millisecondsSince1970: record.timestamp)
        self.isLastResort = isLastResort
    }
}

public class SSKKyberPreKeyStore: SignalKyberPreKeyStore {

    internal enum Constants {
        internal enum ACI {
            static let keyStoreCollection = "SSKKyberPreKeyStoreACIKeyStore"
            static let metadataStoreCollection = "SSKKyberPreKeyStoreACIMetadataStore"
        }

        internal enum PNI {
            static let keyStoreCollection = "SSKKyberPreKeyStorePNIKeyStore"
            static let metadataStoreCollection = "SSKKyberPreKeyStorePNIMetadataStore"
        }

        static let currentLastResortKeyId = "currentLastResortKeyId"
        static let lastKeyId = "lastKeyId"
        static let maxKeyId: Int32 = 0xFFFFFF

        static let lastKeyRotationDate = "lastKeyRotationDate"

        static let oneTimeKeyExpirationInterval = kDayInterval * 90
        static let lastResortKeyExpirationInterval = kDayInterval * 30
    }

    let identity: OWSIdentity

    // Store both one-time and last resort keys
    private let keyStore: KeyValueStore

    // Store current last resort ID
    private let metadataStore: KeyValueStore

    private let dateProvider: DateProvider

    public init(
        for identity: OWSIdentity,
        keyValueStoreFactory: KeyValueStoreFactory,
        dateProvider: @escaping DateProvider
    ) {
        self.identity = identity
        self.dateProvider = dateProvider

        switch identity {
        case .aci:
            self.keyStore = keyValueStoreFactory.keyValueStore(collection: Constants.ACI.keyStoreCollection)
            self.metadataStore = keyValueStoreFactory.keyValueStore(collection: Constants.ACI.metadataStoreCollection)
        case .pni:
            self.keyStore = keyValueStoreFactory.keyValueStore(collection: Constants.PNI.keyStoreCollection)
            self.metadataStore = keyValueStoreFactory.keyValueStore(collection: Constants.PNI.metadataStoreCollection)
        }
    }

    private func nextKyberPreKeyId(ensureCapacity count: Int32 = 1, tx: DBReadTransaction) -> Int32 {
        let lastKyberPreKeyId = metadataStore.getInt32(Constants.lastKeyId, defaultValue: 0, transaction: tx)
        if lastKyberPreKeyId < 1 {
            return 1 + Int32.random(in: 0...(Constants.maxKeyId - (count + 1)))
        } else if lastKyberPreKeyId > Constants.maxKeyId - count {
            return 1
        } else {
            return lastKyberPreKeyId + 1
        }
    }

    private func generateKyberPreKeyRecord(
        id: Int32,
        signedBy identityKeyPair: ECKeyPair,
        isLastResort: Bool,
        tx: DBWriteTransaction
    ) throws -> KyberPreKeyRecord {
        let keyPair = KEMKeyPair.generate()
        let signature = try Ed25519.sign(Data(keyPair.publicKey.serialize()), with: identityKeyPair)

        let record = KyberPreKeyRecord(
            id,
            keyPair: keyPair,
            signature: signature,
            generatedAt: dateProvider(),
            isLastResort: isLastResort
        )

        return record
    }

    // One-Time prekeys

    public func generateKyberPreKeyRecords(
        count: Int,
        signedBy keyPair: ECKeyPair,
        tx: DBWriteTransaction
    ) throws -> [KyberPreKeyRecord] {
        var nextKeyId = nextKyberPreKeyId(ensureCapacity: Int32(count), tx: tx)
        let records = try (0..<count).map { _ in
            let record = try generateKyberPreKeyRecord(
                id: nextKeyId,
                signedBy: keyPair,
                isLastResort: false,
                tx: tx
            )
            nextKeyId += 1
            return record
        }
        metadataStore.setInt32(nextKeyId - 1, key: Constants.lastKeyId, transaction: tx)
        return records
    }

    // Last Resort Keys

    public func generateLastResortKyberPreKey(
        signedBy keyPair: ECKeyPair,
        tx: DBWriteTransaction
    ) throws -> SignalServiceKit.KyberPreKeyRecord {
        let keyId = nextKyberPreKeyId(tx: tx)
        let record = try generateKyberPreKeyRecord(
            id: keyId,
            signedBy: keyPair,
            isLastResort: true,
            tx: tx
        )
        metadataStore.setInt32(keyId, key: Constants.lastKeyId, transaction: tx)
        return record
    }

    // Mark as current
    public func storeLastResortPreKeyAndMarkAsCurrent(record: KyberPreKeyRecord, tx: DBWriteTransaction) throws {
        try storeKyberPreKey(record: record, tx: tx)
        self.metadataStore.setInt32(record.id, key: Constants.currentLastResortKeyId, transaction: tx)
    }

    private func getLastResortKyberPreKeyId(tx: DBReadTransaction) -> Int32? {
        return self.metadataStore.getInt32(Constants.currentLastResortKeyId, transaction: tx)
    }

    public func getLastResortKyberPreKey(tx: DBReadTransaction) -> SignalServiceKit.KyberPreKeyRecord? {
        guard
            let lastResortId = getLastResortKyberPreKeyId(tx: tx),
            let record = loadKyberPreKey(id: lastResortId, tx: tx),
            record.isLastResort
        else {
            return nil
        }
        return record
    }

    // MARK: - LibSignalClient.KyberPreKeyStore conformance

    public func loadKyberPreKey(id: Int32, tx: DBReadTransaction) -> SignalServiceKit.KyberPreKeyRecord? {
        try? self.keyStore.getCodableValue(forKey: key(for: id), transaction: tx)
    }

    public func storeKyberPreKeyRecords(records: [KyberPreKeyRecord], tx: DBWriteTransaction) throws {
        for record in records {
            try storeKyberPreKey(record: record, tx: tx)
        }
    }

    public func storeKyberPreKey(record: SignalServiceKit.KyberPreKeyRecord, tx: DBWriteTransaction) throws {
        try self.keyStore.setCodable(record, key: key(for: record.id), transaction: tx)
    }

    public func markKyberPreKeyUsed(id: Int32, tx: DBWriteTransaction) throws {
        // fetch the key, see if it's was a last resort.
        // if not, remove the key from the list of uses (or mark it as used?)
        guard let record = loadKyberPreKey(id: id, tx: tx) else { throw Error.noKyberPreKeyWithId(UInt32(id)) }
        if !record.isLastResort {
            self.keyStore.removeValue(forKey: key(for: id), transaction: tx)
        }
    }

#if TESTABLE_BUILD
    public func removeAll(tx: DBWriteTransaction) {
        self.keyStore.removeAll(transaction: tx)
        self.metadataStore.removeAll(transaction: tx)
    }
#endif
}

extension SSKKyberPreKeyStore {
    internal func key(for id: Int32) -> String {
        return NSNumber(value: id).stringValue
    }
}

extension SSKKyberPreKeyStore: LibSignalClient.KyberPreKeyStore {
    enum Error: Swift.Error {
        case noKyberPreKeyWithId(UInt32)
        case noKyberLastResortKey
    }

    public func loadKyberPreKey(
        id: UInt32,
        context: LibSignalClient.StoreContext
    ) throws -> LibSignalClient.KyberPreKeyRecord {
        guard let preKey = self.loadKyberPreKey(
            id: Int32(bitPattern: id),
            tx: context.asTransaction.asV2Read
        ) else {
            throw Error.noKyberPreKeyWithId(id)
        }

        return try LibSignalClient.KyberPreKeyRecord(
            id: UInt32(bitPattern: preKey.id),
            timestamp: preKey.generatedAt.ows_millisecondsSince1970,
            keyPair: preKey.keyPair,
            signature: preKey.signature
        )
    }

    // This method isn't used in practice, so it doesn't matter
    // if this is a one time or last resort Kyber key
    public func storeKyberPreKey(
        _ record: LibSignalClient.KyberPreKeyRecord,
        id: UInt32,
        context: LibSignalClient.StoreContext
    ) throws {
        let record = SignalServiceKit.KyberPreKeyRecord(
            Int32(id),
            keyPair: record.keyPair,
            signature: Data(record.signature),
            generatedAt: Date(millisecondsSince1970: record.timestamp),
            isLastResort: false
        )
        try self.storeKyberPreKey(record: record, tx: context.asTransaction.asV2Write)
    }

    public func markKyberPreKeyUsed(id: UInt32, context: StoreContext) throws {
        try self.markKyberPreKeyUsed(id: Int32(bitPattern: id), tx: context.asTransaction.asV2Write)
    }

    public func setLastSuccessfulPreKeyRotationDate(_ date: Date, tx: DBWriteTransaction) {
        self.metadataStore.setDate(date, key: Constants.lastKeyRotationDate, transaction: tx)
    }

    public func getLastSuccessfulPreKeyRotationDate(tx: DBReadTransaction) -> Date? {
        self.metadataStore.getDate(Constants.lastKeyRotationDate, transaction: tx)
    }

    public func cullOneTimePreKeyRecords(tx: DBWriteTransaction) throws {

        // get all keys
        // filter by isLastResort = false
        // remove all keys older than 90 days

        let recordsToRemove: [KyberPreKeyRecord] = try self.keyStore
            .allCodableValues(transaction: tx)
            .filter { record in
                guard !record.isLastResort else { return false }
                let keyAge = dateProvider().timeIntervalSince(record.generatedAt)
                return keyAge >= Constants.oneTimeKeyExpirationInterval
            }

        let keysToRemove = recordsToRemove.map { key(for: $0.id) }
        self.keyStore.removeValues(forKeys: keysToRemove, transaction: tx)
    }

    public func cullLastResortPreKeyRecords(tx: DBWriteTransaction) throws {

        // get a list of keys
        // get the current key
        // don't touch the current
        // remove all others older than 30 days
        guard let currentLastResort = getLastResortKyberPreKey(tx: tx) else { return }

        let recordsToRemove: [KyberPreKeyRecord] = try self.keyStore
            .allCodableValues(transaction: tx)
            .filter { record in
                guard record.isLastResort else { return false }
                guard record.id != currentLastResort.id else { return false }
                let keyAge = dateProvider().timeIntervalSince(record.generatedAt)
                return keyAge >= Constants.lastResortKeyExpirationInterval
            }

        let keysToRemove = recordsToRemove.map { key(for: $0.id) }
        self.keyStore.removeValues(forKeys: keysToRemove, transaction: tx)
    }

    public func removeLastResortPreKey(
        record: SignalServiceKit.KyberPreKeyRecord,
        tx: DBWriteTransaction
    ) {
        self.keyStore.removeValue(forKey: key(for: record.id), transaction: tx)
    }
}
