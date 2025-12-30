//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient

struct PreKeyStore {
    enum Error: Swift.Error {
        case noPreKeyWithId(UInt32)
    }

    let aciStore: PreKeyStoreForIdentity
    let pniStore: PreKeyStoreForIdentity

    init() {
        self.aciStore = PreKeyStoreForIdentity(identity: .aci)
        self.pniStore = PreKeyStoreForIdentity(identity: .pni)
    }

    func forIdentity(_ identity: OWSIdentity) -> PreKeyStoreForIdentity {
        switch identity {
        case .aci: aciStore
        case .pni: pniStore
        }
    }

    func removeAll(tx: DBWriteTransaction) {
        Logger.info("")
        failIfThrows {
            _ = try PreKey.deleteAll(tx.database)
        }
    }

    func allocatePreKeyIds(
        in metadataStore: KeyValueStore,
        lastPreKeyIdKey: String,
        count: Int,
        tx: DBWriteTransaction,
    ) -> ClosedRange<UInt32> {
        let lastPreKeyId = metadataStore.getInt(lastPreKeyIdKey, transaction: tx).flatMap(UInt32.init(exactly:))
        let preKeyIds = PreKeyId.nextPreKeyIds(lastPreKeyId: lastPreKeyId, count: count)
        metadataStore.setInt(Int(preKeyIds.upperBound), key: lastPreKeyIdKey, transaction: tx)
        return preKeyIds
    }

    func setReplacedAtIfNil(
        to now: Date,
        in namespace: PreKey.Namespace,
        identity: OWSIdentity,
        isOneTime: Bool,
        exceptFor exceptForPreKeyIds: [UInt32],
        tx: DBWriteTransaction,
    ) {
        let keyIdColumn = Column(PreKey.CodingKeys.keyId.rawValue)
        let replacedAtColumn = Column(PreKey.CodingKeys.replacedAt.rawValue)
        let isOneTimeColumn = Column(PreKey.CodingKeys.isOneTime.rawValue)
        failIfThrows {
            _ = try PreKey.baseQuery(in: namespace, identity: identity)
                .filter(isOneTimeColumn == isOneTime)
                .filter(replacedAtColumn == nil)
                .filter(!exceptForPreKeyIds.contains(keyIdColumn))
                .updateAll(tx.database, [replacedAtColumn.set(to: Int64(now.timeIntervalSince1970))])
        }
    }

    func cullPreKeys(gracePeriod: TimeInterval, tx: DBWriteTransaction) {
        let now = Date().timeIntervalSince1970
        let delay = PreKeyManagerImpl.Constants.maxUnacknowledgedSessionAge + gracePeriod
        let replacedAt = Column(PreKey.CodingKeys.replacedAt.rawValue)
        failIfThrows {
            var rowIds = [Int64]()
            let query = PreKey.filter(replacedAt < Int64(now - delay) || replacedAt > Int64(now + delay))
            let cursor = try query.fetchCursor(tx.database)
            while let preKey = try cursor.next() {
                Logger.info("removing prekey \(preKey.namespace) \(preKey.keyId), replacedAt \(preKey.replacedAt!)")
                rowIds.append(preKey.rowId)
            }
            for rowId in rowIds {
                try PreKey.deleteOne(tx.database, key: rowId)
            }
        }
    }
}

class PreKeyStoreForIdentity {
    private let identity: OWSIdentity

    init(identity: OWSIdentity) {
        self.identity = identity
    }

    private func baseQuery(in namespace: PreKey.Namespace) -> QueryInterfaceRequest<PreKey> {
        return PreKey.baseQuery(in: namespace, identity: self.identity)
    }

    func fetchPreKey(in namespace: PreKey.Namespace, for keyId: UInt32, tx: DBReadTransaction) -> PreKey? {
        failIfThrows {
            do {
                return try baseQuery(in: namespace)
                    .filter(Column(PreKey.CodingKeys.keyId.rawValue) == keyId)
                    .fetchOne(tx.database)
            } catch {
                throw error.grdbErrorForLogging
            }
        }
    }

    private func fetchSerializedRecord(in namespace: PreKey.Namespace, for keyId: UInt32, tx: DBReadTransaction) throws -> Data {
        let preKey = fetchPreKey(in: namespace, for: keyId, tx: tx)
        guard let serializedRecord = preKey?.serializedRecord else {
            throw PreKeyStore.Error.noPreKeyWithId(keyId)
        }
        return serializedRecord
    }

    func upsertPreKeyRecord(
        _ serializedRecord: Data,
        keyId: UInt32,
        in namespace: PreKey.Namespace,
        isOneTime: Bool,
        tx: DBWriteTransaction,
    ) {
        failIfThrows {
            do {
                // Key IDs intentionally aren't large enough to avoid conflicts when
                // sampling randomly. Clients don't generate conflicting keys, though
                // certain operations (e.g., change number) may produce harmless conflicts.
                // We use "OR REPLACE" to keep the latest key if such a conflict occurs.
                try tx.database.execute(
                    sql: """
                    INSERT OR REPLACE INTO \(PreKey.databaseTableName) (
                        \(PreKey.CodingKeys.namespace.rawValue),
                        \(PreKey.CodingKeys.identity.rawValue),
                        \(PreKey.CodingKeys.keyId.rawValue),
                        \(PreKey.CodingKeys.isOneTime.rawValue),
                        \(PreKey.CodingKeys.serializedRecord.rawValue)
                    ) VALUES (?, ?, ?, ?, ?)
                    """,
                    arguments: [namespace.rawValue, self.identity.rawValue, keyId, isOneTime, serializedRecord],
                )
            } catch {
                throw error.grdbErrorForLogging
            }
        }
    }

    func removePreKey(in namespace: PreKey.Namespace, keyId: UInt32, tx: DBWriteTransaction) {
        let keyIdColumn = Column(PreKey.CodingKeys.keyId.rawValue)
        failIfThrows {
            _ = try baseQuery(in: namespace).filter(keyIdColumn == keyId).deleteAll(tx.database)
        }
    }

#if TESTABLE_BUILD

    func fetchCount(in namespace: PreKey.Namespace, isOneTime: Bool, tx: DBReadTransaction) throws -> Int {
        return try baseQuery(in: namespace)
            .filter(Column(PreKey.CodingKeys.isOneTime.rawValue) == isOneTime)
            .fetchCount(tx.database)
    }

#endif
}

extension PreKeyStoreForIdentity: LibSignalClient.PreKeyStore {
    func loadPreKey(id: UInt32, context: any StoreContext) throws -> LibSignalClient.PreKeyRecord {
        return try LibSignalClient.PreKeyRecord(bytes: fetchSerializedRecord(in: .oneTime, for: id, tx: context.asTransaction))
    }

    func removePreKey(id: UInt32, context: any StoreContext) throws {
        removePreKey(in: .oneTime, keyId: id, tx: context.asTransaction)
    }

    func storePreKey(_ record: LibSignalClient.PreKeyRecord, id: UInt32, context: any StoreContext) throws {
        // This is currently unused (and needs `replacedAt` support).
        owsFail("Not supported.")
    }
}

extension PreKeyStoreForIdentity: LibSignalClient.SignedPreKeyStore {
    func loadSignedPreKey(id: UInt32, context: any StoreContext) throws -> LibSignalClient.SignedPreKeyRecord {
        return try LibSignalClient.SignedPreKeyRecord(bytes: fetchSerializedRecord(in: .signed, for: id, tx: context.asTransaction))
    }

    func storeSignedPreKey(_ record: LibSignalClient.SignedPreKeyRecord, id: UInt32, context: any StoreContext) throws {
        // This is currently unused (and needs `replacedAt` support).
        owsFail("Not supported.")
    }
}

extension PreKeyStoreForIdentity: LibSignalClient.KyberPreKeyStore {
    func loadKyberPreKey(id: UInt32, context: any StoreContext) throws -> LibSignalClient.KyberPreKeyRecord {
        return try LibSignalClient.KyberPreKeyRecord(bytes: fetchSerializedRecord(in: .kyber, for: id, tx: context.asTransaction))
    }

    func markKyberPreKeyUsed(id keyId: UInt32, signedPreKeyId: UInt32, baseKey: PublicKey, context: any StoreContext) throws {
        let tx = context.asTransaction
        guard let preKey = fetchPreKey(in: .kyber, for: keyId, tx: tx) else {
            throw PreKeyStore.Error.noPreKeyWithId(keyId)
        }
        if preKey.isOneTime {
            removePreKey(in: .kyber, keyId: keyId, tx: tx)
        } else {
            do {
                try KyberPreKeyUseRecord(
                    kyberRowId: preKey.rowId,
                    signedPreKeyIdentity: self.identity,
                    signedPreKeyId: signedPreKeyId,
                    baseKey: baseKey.serialize(),
                ).insert(tx.database)
            } catch {
                let error = error.grdbErrorForLogging
                switch error {
                case DatabaseError.SQLITE_CONSTRAINT:
                    throw error
                default:
                    failIfThrows { throw error }
                }
            }
        }
    }

    func storeKyberPreKey(_ record: LibSignalClient.KyberPreKeyRecord, id: UInt32, context: any StoreContext) throws {
        // This is currently unused and can't be implemented properly.
        owsFail("Not supported.")
    }
}

#if TESTABLE_BUILD

protocol WritablePreKeyStore {
    func storePreKey(_ record: LibSignalClient.PreKeyRecord, replacedAt: Date?, context: any StoreContext) throws
}

extension WritablePreKeyStore where Self: LibSignalClient.PreKeyStore {
    func storePreKey(_ record: LibSignalClient.PreKeyRecord, replacedAt: Date?, context: any StoreContext) throws {
        try storePreKey(record, id: record.id, context: context)
    }
}

extension PreKeyStoreForIdentity: WritablePreKeyStore {
    func storePreKey(_ record: LibSignalClient.PreKeyRecord, replacedAt: Date?, context: any StoreContext) throws {
        owsPrecondition(replacedAt == nil)
        upsertPreKeyRecord(record.serialize(), keyId: record.id, in: .oneTime, isOneTime: true, tx: context.asTransaction)
    }
}

protocol WritableSignedPreKeyStore {
    func storeSignedPreKey(_ record: LibSignalClient.SignedPreKeyRecord, replacedAt: Date?, context: any StoreContext) throws
}

extension WritableSignedPreKeyStore where Self: LibSignalClient.SignedPreKeyStore {
    func storeSignedPreKey(_ record: LibSignalClient.SignedPreKeyRecord, replacedAt: Date?, context: any StoreContext) throws {
        owsPrecondition(replacedAt == nil)
        try storeSignedPreKey(record, id: record.id, context: context)
    }
}

extension PreKeyStoreForIdentity: WritableSignedPreKeyStore {
    func storeSignedPreKey(_ record: LibSignalClient.SignedPreKeyRecord, replacedAt: Date?, context: any StoreContext) throws {
        upsertPreKeyRecord(record.serialize(), keyId: record.id, in: .signed, isOneTime: false, tx: context.asTransaction)
    }
}

protocol WritableKyberPreKeyStore {
    func storeKyberPreKey(_ record: LibSignalClient.KyberPreKeyRecord, isOneTime: Bool, replacedAt: Date?, context: any StoreContext) throws
}

extension WritableKyberPreKeyStore where Self: LibSignalClient.KyberPreKeyStore {
    func storeKyberPreKey(_ record: LibSignalClient.KyberPreKeyRecord, isOneTime: Bool, replacedAt: Date?, context: any StoreContext) throws {
        try storeKyberPreKey(record, id: record.id, context: context)
    }
}

extension PreKeyStoreForIdentity: WritableKyberPreKeyStore {
    func storeKyberPreKey(_ record: LibSignalClient.KyberPreKeyRecord, isOneTime: Bool, replacedAt: Date?, context: any StoreContext) throws {
        owsPrecondition(replacedAt == nil)
        upsertPreKeyRecord(record.serialize(), keyId: record.id, in: .kyber, isOneTime: isOneTime, tx: context.asTransaction)
    }
}

#endif
