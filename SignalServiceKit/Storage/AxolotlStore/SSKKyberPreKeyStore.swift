//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

public protocol SignalKyberPreKeyStore: LibSignalClient.KyberPreKeyStore {
    func generateLastResortKyberPreKey(
        signedBy keyPair: ECKeyPair,
        tx: DBWriteTransaction
    ) throws -> SignalServiceKit.KyberPreKeyRecord

    /// Keys returned by this method should not be stored in the local
    /// KyberPreKeyStore since there is no guarantee the key ID is unique.
    func generateLastResortKyberPreKeyForLinkedDevice(
        signedBy keyPair: ECKeyPair
    ) throws -> SignalServiceKit.KyberPreKeyRecord

    func storeLastResortPreKeyFromLinkedDevice(
        record: KyberPreKeyRecord,
        tx: DBWriteTransaction
    ) throws

    func generateKyberPreKeyRecords(
        count: Int,
        signedBy keyPair: ECKeyPair,
        tx: DBWriteTransaction
    ) throws -> [SignalServiceKit.KyberPreKeyRecord]

    func storeLastResortPreKey(
        record: SignalServiceKit.KyberPreKeyRecord,
        tx: DBWriteTransaction
    ) throws

    func storeKyberPreKeyRecords(
        records: [SignalServiceKit.KyberPreKeyRecord],
        tx: DBWriteTransaction
    ) throws

    func cullLastResortPreKeyRecords(
        justUploadedLastResortPreKey: KyberPreKeyRecord,
        tx: DBWriteTransaction
    ) throws

    func removeLastResortPreKey(
        record: SignalServiceKit.KyberPreKeyRecord,
        tx: DBWriteTransaction
    )

    func cullOneTimePreKeyRecords(tx: DBWriteTransaction) throws

    func setLastSuccessfulRotationDate(
        _ date: Date,
        tx: DBWriteTransaction
    )

    func getLastSuccessfulRotationDate(
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
    public let id: UInt32
    public let keyPair: KEMKeyPair
    public let isLastResort: Bool

    public init(
        _ id: UInt32,
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

        try container.encode(isLastResort, forKey: .isLastResort)
        try container.encode(Data(asLSCRecord().serialize()), forKey: .keyData)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let isLastResort = try container.decode(Bool.self, forKey: .isLastResort)
        let keyData = try container.decode(Data.self, forKey: .keyData)

        let record = try LibSignalClient.KyberPreKeyRecord(bytes: keyData)
        self.id = record.id
        self.keyPair = try record.keyPair()
        self.signature = Data(record.signature)
        self.generatedAt = Date(millisecondsSince1970: record.timestamp)
        self.isLastResort = isLastResort
    }
}

extension KyberPreKeyRecord: Equatable {
    public static func == (lhs: KyberPreKeyRecord, rhs: KyberPreKeyRecord) -> Bool {
        return (
            lhs.id == rhs.id
            && lhs.isLastResort == rhs.isLastResort
            && lhs.generatedAt == rhs.generatedAt
            && lhs.signature == rhs.signature
        )
    }
}

extension KyberPreKeyRecord: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(isLastResort)
        hasher.combine(generatedAt)
        hasher.combine(signature)
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

        static let lastKeyId = "lastKeyId"

        static let lastKeyRotationDate = "lastKeyRotationDate"

        static let oneTimeKeyExpirationInterval = kDayInterval * 90
    }

    let identity: OWSIdentity

    // Store both one-time and last resort keys
    private let keyStore: KeyValueStore

    // Store current last resort ID
    private let metadataStore: KeyValueStore

    private let dateProvider: DateProvider
    private let remoteConfigProvider: any RemoteConfigProvider

    public init(
        for identity: OWSIdentity,
        dateProvider: @escaping DateProvider,
        remoteConfigProvider: any RemoteConfigProvider
    ) {
        self.identity = identity
        self.dateProvider = dateProvider
        self.remoteConfigProvider = remoteConfigProvider

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
    ) throws -> KyberPreKeyRecord {
        let keyPair = KEMKeyPair.generate()
        let signature = Data(identityKeyPair.keyPair.privateKey.generateSignature(message: Data(keyPair.publicKey.serialize())))

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
        var nextKeyId = nextKyberPreKeyId(minimumCapacity: UInt32(count), tx: tx)
        let records = try (0..<count).map { _ in
            let record = try generateKyberPreKeyRecord(
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
    ) throws -> SignalServiceKit.KyberPreKeyRecord {
        let keyId = nextKyberPreKeyId(tx: tx)
        let record = try generateKyberPreKeyRecord(
            id: keyId,
            signedBy: keyPair,
            isLastResort: true
        )
        metadataStore.setInt32(Int32(keyId), key: Constants.lastKeyId, transaction: tx)
        return record
    }

    public func generateLastResortKyberPreKeyForLinkedDevice(
        signedBy keyPair: ECKeyPair
    ) throws -> SignalServiceKit.KyberPreKeyRecord {
        return try generateKyberPreKeyRecord(
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

#if TESTABLE_BUILD
    public func removeAll(tx: DBWriteTransaction) {
        self.keyStore.removeAll(transaction: tx)
        self.metadataStore.removeAll(transaction: tx)
    }
#endif
}

extension SSKKyberPreKeyStore {
    internal func key(for id: UInt32) -> String { "\(id)" }
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
            id: id,
            tx: context.asTransaction.asV2Read
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

    // This method isn't used in practice, so it doesn't matter
    // if this is a one time or last resort Kyber key
    public func storeKyberPreKey(
        _ record: LibSignalClient.KyberPreKeyRecord,
        id: UInt32,
        context: LibSignalClient.StoreContext
    ) throws {
        let record = SignalServiceKit.KyberPreKeyRecord(
            id,
            keyPair: try record.keyPair(),
            signature: Data(record.signature),
            generatedAt: Date(millisecondsSince1970: record.timestamp),
            isLastResort: false
        )
        try self.storeKyberPreKey(record: record, tx: context.asTransaction.asV2Write)
    }

    public func markKyberPreKeyUsed(id: UInt32, context: StoreContext) throws {
        try self.markKyberPreKeyUsed(id: id, tx: context.asTransaction.asV2Write)
    }

    public func setLastSuccessfulRotationDate(_ date: Date, tx: DBWriteTransaction) {
        self.metadataStore.setDate(date, key: Constants.lastKeyRotationDate, transaction: tx)
    }

    public func getLastSuccessfulRotationDate(tx: DBReadTransaction) -> Date? {
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

    public func cullLastResortPreKeyRecords(
        justUploadedLastResortPreKey: KyberPreKeyRecord,
        tx: DBWriteTransaction
    ) throws {
        // get a list of keys
        // don't touch what we just uploaded
        // remove all others older than N days

        let recordsToRemove: [KyberPreKeyRecord] = try self.keyStore
            .allCodableValues(transaction: tx)
            .filter { record in
                guard record.isLastResort else { return false }
                guard record.id != justUploadedLastResortPreKey.id else { return false }
                let keyAge = dateProvider().timeIntervalSince(record.generatedAt)
                return keyAge >= remoteConfigProvider.currentConfig().messageQueueTime
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

extension LibSignalClient.KyberPreKeyRecord {
    func asSSKLastResortRecord() throws -> SignalServiceKit.KyberPreKeyRecord {
        return SignalServiceKit.KyberPreKeyRecord(
            self.id,
            keyPair: try self.keyPair(),
            signature: Data(self.signature),
            generatedAt: Date(millisecondsSince1970: self.timestamp),
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
