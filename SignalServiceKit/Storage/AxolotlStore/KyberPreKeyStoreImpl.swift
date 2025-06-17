//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

public struct KyberPreKeyRecord: Codable {

    enum CodingKeys: String, CodingKey {
        case keyData
        case isLastResort
        case replacedAt
    }

    public let signature: Data
    public let generatedAt: Date
    public var replacedAt: Date?
    public let id: UInt32
    public let keyPair: KEMKeyPair
    public let isLastResort: Bool

    public init(
        _ id: UInt32,
        keyPair: KEMKeyPair,
        signature: Data,
        generatedAt: Date,
        replacedAt: Date?,
        isLastResort: Bool
    ) {
        self.id = id
        self.keyPair = keyPair
        self.signature = signature
        self.generatedAt = generatedAt
        self.replacedAt = replacedAt
        self.isLastResort = isLastResort
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(isLastResort, forKey: .isLastResort)
        try container.encode(asLSCRecord().serialize(), forKey: .keyData)
        try container.encodeIfPresent(replacedAt, forKey: .replacedAt)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let isLastResort = try container.decode(Bool.self, forKey: .isLastResort)
        let keyData = try container.decode(Data.self, forKey: .keyData)
        let replacedAt = try container.decodeIfPresent(Date.self, forKey: .replacedAt)

        let record = try LibSignalClient.KyberPreKeyRecord(bytes: keyData)
        self.id = record.id
        self.keyPair = try record.keyPair()
        self.signature = record.signature
        self.generatedAt = Date(millisecondsSince1970: record.timestamp)
        self.replacedAt = replacedAt
        self.isLastResort = isLastResort
    }
}

public class KyberPreKeyStoreImpl: LibSignalClient.KyberPreKeyStore {

    internal enum Constants {
        internal enum ACI {
            static let keyStoreCollection = "SSKKyberPreKeyStoreACIKeyStore"
            static let metadataStoreCollection = "SSKKyberPreKeyStoreACIMetadataStore"
        }

        internal enum PNI {
            static let keyStoreCollection = "SSKKyberPreKeyStorePNIKeyStore"
            static let metadataStoreCollection = "SSKKyberPreKeyStorePNIMetadataStore"
        }

        static let lastKeyId = "lastKeyId"

        static let lastKeyRotationDate = "lastKeyRotationDate"
    }

    let identity: OWSIdentity

    // Store both one-time and last resort keys
    private let keyStore: KeyValueStore

    // Store current last resort ID
    private let metadataStore: KeyValueStore

    private let dateProvider: DateProvider

    public init(
        for identity: OWSIdentity,
        dateProvider: @escaping DateProvider,
    ) {
        self.identity = identity
        self.dateProvider = dateProvider

        switch identity {
        case .aci:
            self.keyStore = KeyValueStore(collection: Constants.ACI.keyStoreCollection)
            self.metadataStore = KeyValueStore(collection: Constants.ACI.metadataStoreCollection)
        case .pni:
            self.keyStore = KeyValueStore(collection: Constants.PNI.keyStoreCollection)
            self.metadataStore = KeyValueStore(collection: Constants.PNI.metadataStoreCollection)
        }
    }

    private func nextKyberPreKeyId(minimumCapacity: UInt32 = 1, tx: DBReadTransaction) -> UInt32 {
        return PreKeyId.nextPreKeyId(
            lastPreKeyId: UInt32(exactly: metadataStore.getInt32(Constants.lastKeyId, defaultValue: 0, transaction: tx)) ?? 0,
            minimumCapacity: minimumCapacity
        )
    }

    private func generateKyberPreKeyRecord(
        id: UInt32,
        signedBy identityKeyPair: ECKeyPair,
        isLastResort: Bool
    ) -> KyberPreKeyRecord {
        let keyPair = KEMKeyPair.generate()
        let signature = identityKeyPair.keyPair.privateKey.generateSignature(message: keyPair.publicKey.serialize())

        let record = KyberPreKeyRecord(
            id,
            keyPair: keyPair,
            signature: signature,
            generatedAt: dateProvider(),
            replacedAt: nil,
            isLastResort: isLastResort
        )

        return record
    }

    // One-Time prekeys

    public func generateKyberPreKeyRecords(
        count: Int,
        signedBy keyPair: ECKeyPair,
        tx: DBWriteTransaction
    ) -> [KyberPreKeyRecord] {
        var nextKeyId = nextKyberPreKeyId(minimumCapacity: UInt32(count), tx: tx)
        let records = (0..<count).map { _ in
            let record = generateKyberPreKeyRecord(
                id: nextKeyId,
                signedBy: keyPair,
                isLastResort: false
            )
            nextKeyId += 1
            return record
        }
        metadataStore.setInt32(Int32(nextKeyId - 1), key: Constants.lastKeyId, transaction: tx)
        return records
    }

    // Last Resort Keys

    public func generateLastResortKyberPreKey(
        signedBy keyPair: ECKeyPair,
        tx: DBWriteTransaction
    ) -> SignalServiceKit.KyberPreKeyRecord {
        let keyId = nextKyberPreKeyId(tx: tx)
        let record = generateKyberPreKeyRecord(
            id: keyId,
            signedBy: keyPair,
            isLastResort: true
        )
        metadataStore.setInt32(Int32(keyId), key: Constants.lastKeyId, transaction: tx)
        return record
    }

    /// Keys returned by this method should not be stored in the local
    /// KyberPreKeyStore since there is no guarantee the key ID is unique.
    public func generateLastResortKyberPreKeyForLinkedDevice(
        signedBy keyPair: ECKeyPair
    ) -> SignalServiceKit.KyberPreKeyRecord {
        return generateKyberPreKeyRecord(
            id: PreKeyId.random(),
            signedBy: keyPair,
            isLastResort: true
        )
    }

    public func storeLastResortPreKey(record: KyberPreKeyRecord, tx: DBWriteTransaction) throws {
        try storeKyberPreKey(record: record, tx: tx)
    }

    public func storeLastResortPreKeyFromLinkedDevice(record: KyberPreKeyRecord, tx: DBWriteTransaction) throws {
        try storeLastResortPreKey(record: record, tx: tx)
        metadataStore.setInt32(Int32(record.id), key: Constants.lastKeyId, transaction: tx)
    }

    // MARK: - LibSignalClient.KyberPreKeyStore conformance

    public func loadKyberPreKey(id: UInt32, tx: DBReadTransaction) -> SignalServiceKit.KyberPreKeyRecord? {
        try? self.keyStore.getCodableValue(forKey: key(for: id), transaction: tx)
    }

    public func storeKyberPreKeyRecords(records: [KyberPreKeyRecord], tx: DBWriteTransaction) throws {
        for record in records {
            try storeKyberPreKey(record: record, tx: tx)
        }
    }

    private func storeKyberPreKey(record: SignalServiceKit.KyberPreKeyRecord, tx: DBWriteTransaction) throws {
        try self.keyStore.setCodable(record, key: key(for: record.id), transaction: tx)
    }

    public func markKyberPreKeyUsed(id: UInt32, tx: DBWriteTransaction) throws {
        // fetch the key, see if it's was a last resort.
        // if not, remove the key from the list of uses (or mark it as used?)
        guard let record = loadKyberPreKey(id: id, tx: tx) else { throw Error.noKyberPreKeyWithId(id) }
        if !record.isLastResort {
            self.keyStore.removeValue(forKey: key(for: id), transaction: tx)
        }
    }

    public func removeAll(tx: DBWriteTransaction) {
        self.keyStore.removeAll(transaction: tx)
        self.metadataStore.removeAll(transaction: tx)
    }

    internal func key(for id: UInt32) -> String { "\(id)" }

    enum Error: Swift.Error {
        case noKyberPreKeyWithId(UInt32)
        case noKyberLastResortKey
    }

    public func loadKyberPreKey(
        id: UInt32,
        context: LibSignalClient.StoreContext
    ) throws -> LibSignalClient.KyberPreKeyRecord {
        guard let preKey = self.loadKyberPreKey(
            id: id,
            tx: context.asTransaction
        ) else {
            throw Error.noKyberPreKeyWithId(id)
        }

        return try LibSignalClient.KyberPreKeyRecord(
            id: preKey.id,
            timestamp: preKey.generatedAt.ows_millisecondsSince1970,
            keyPair: preKey.keyPair,
            signature: preKey.signature
        )
    }

    // This method isn't used in practice, so it doesn't matter if this is a
    // one time or last resort Kyber key. It also doesn't set replacedAt.
    public func storeKyberPreKey(
        _ record: LibSignalClient.KyberPreKeyRecord,
        id: UInt32,
        context: LibSignalClient.StoreContext
    ) throws {
        owsFailDebug("This method doesn't behave correctly.")
        let record = SignalServiceKit.KyberPreKeyRecord(
            id,
            keyPair: try record.keyPair(),
            signature: record.signature,
            generatedAt: Date(millisecondsSince1970: record.timestamp),
            replacedAt: nil,
            isLastResort: false
        )
        try self.storeKyberPreKey(record: record, tx: context.asTransaction)
    }

    public func markKyberPreKeyUsed(id: UInt32, context: StoreContext) throws {
        try self.markKyberPreKeyUsed(id: id, tx: context.asTransaction)
    }

    public func setLastSuccessfulRotationDate(_ date: Date, tx: DBWriteTransaction) {
        self.metadataStore.setDate(date, key: Constants.lastKeyRotationDate, transaction: tx)
    }

    public func getLastSuccessfulRotationDate(tx: DBReadTransaction) -> Date? {
        self.metadataStore.getDate(Constants.lastKeyRotationDate, transaction: tx)
    }

    public func setOneTimePreKeysReplacedAtToNowIfNil(
        exceptFor justUploadedOneTimePreKey: [KyberPreKeyRecord],
        tx: DBWriteTransaction
    ) throws {
        try setReplacedAtToNowIfNil(exceptFor: justUploadedOneTimePreKey, isLastResort: false, tx: tx)
    }

    public func cullOneTimePreKeyRecords(gracePeriod: TimeInterval, tx: DBWriteTransaction) {
        cullPreKeys(isLastResort: false, gracePeriod: gracePeriod, tx: tx)
    }

    public func setLastResortPreKeysReplacedAtToNowIfNil(
        exceptFor justUploadedLastResortPreKey: KyberPreKeyRecord,
        tx: DBWriteTransaction
    ) throws {
        try setReplacedAtToNowIfNil(exceptFor: [justUploadedLastResortPreKey], isLastResort: true, tx: tx)
    }

    public func cullLastResortPreKeyRecords(gracePeriod: TimeInterval, tx: DBWriteTransaction) {
        cullPreKeys(isLastResort: true, gracePeriod: gracePeriod, tx: tx)
    }

    private func setReplacedAtToNowIfNil(exceptFor preKeys: [KyberPreKeyRecord], isLastResort: Bool, tx: DBWriteTransaction) throws {
        let exceptForIds = Set(preKeys.map(\.id))
        for key in self.keyStore.allKeys(transaction: tx) {
            let record: KyberPreKeyRecord? = try self.keyStore.getCodableValue(forKey: key, transaction: tx)
            guard
                var record,
                record.isLastResort == isLastResort,
                !exceptForIds.contains(record.id),
                record.replacedAt == nil
            else {
                continue
            }
            record.replacedAt = dateProvider()
            try self.keyStore.setCodable(record, key: key, transaction: tx)
        }
    }

    private func cullPreKeys(isLastResort: Bool, gracePeriod: TimeInterval, tx: DBWriteTransaction) {
        for key in self.keyStore.allKeys(transaction: tx) {
            let record: KyberPreKeyRecord?
            do {
                record = try self.keyStore.getCodableValue(forKey: key, transaction: tx)
            } catch {
                owsFailDebug("Couldn't decode KyberPreKeyRecord: \(error)")
                record = nil
            }
            guard let record else {
                self.keyStore.removeValue(forKey: key, transaction: tx)
                continue
            }
            guard
                record.isLastResort == isLastResort,
                let replacedAt = record.replacedAt,
                dateProvider().timeIntervalSince(replacedAt) > (PreKeyManagerImpl.Constants.maxUnacknowledgedSessionAge + gracePeriod)
            else {
                continue
            }
            self.keyStore.removeValue(forKey: key, transaction: tx)
        }
    }

    public func removeLastResortPreKey(
        record: SignalServiceKit.KyberPreKeyRecord,
        tx: DBWriteTransaction
    ) {
        self.keyStore.removeValue(forKey: key(for: record.id), transaction: tx)
    }

    #if TESTABLE_BUILD

    func count(isLastResort: Bool, tx: DBReadTransaction) -> Int {
        let records: [KyberPreKeyRecord] = try! self.keyStore.allCodableValues(transaction: tx)
        return records.count(where: { $0.isLastResort == isLastResort })
    }

    #endif
}

extension LibSignalClient.KyberPreKeyRecord {
    func asSSKLastResortRecord() throws -> SignalServiceKit.KyberPreKeyRecord {
        return SignalServiceKit.KyberPreKeyRecord(
            self.id,
            keyPair: try self.keyPair(),
            signature: self.signature,
            generatedAt: Date(millisecondsSince1970: self.timestamp),
            replacedAt: nil,
            isLastResort: true
        )
    }
}

extension SignalServiceKit.KyberPreKeyRecord {
    func asLSCRecord() throws -> LibSignalClient.KyberPreKeyRecord {
        try LibSignalClient.KyberPreKeyRecord(
            id: self.id,
            timestamp: self.generatedAt.ows_millisecondsSince1970,
            keyPair: self.keyPair,
            signature: self.signature
        )
    }
}
