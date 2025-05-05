//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

private let batchSize: Int = 100
private let tsNextPrekeyIdKey = "TSStorageInternalSettingsNextPreKeyId"

public class PreKeyStoreImpl {

    private let keyStore: KeyValueStore
    private let metadataStore: KeyValueStore

    init(for identity: OWSIdentity) {
        switch identity {
        case .aci:
            keyStore = KeyValueStore(collection: "TSStorageManagerPreKeyStoreCollection")
            metadataStore = KeyValueStore(collection: "TSStorageInternalSettingsCollection")
        case .pni:
            keyStore = KeyValueStore(collection: "TSStorageManagerPNIPreKeyStoreCollection")
            metadataStore = KeyValueStore(collection: "TSStorageManagerPNIPreKeyMetadataCollection")
        }
    }

    func generatePreKeyRecords(tx: DBWriteTransaction) -> [SignalServiceKit.PreKeyRecord] {
        var preKeyRecords: [SignalServiceKit.PreKeyRecord] = []
        var preKeyId = nextPreKeyId(transaction: tx)

        Logger.info("building \(batchSize) new preKeys starting from preKeyId: \(preKeyId)")
        for _ in 0..<batchSize {
            let keyPair = ECKeyPair.generateKeyPair()
            let record = SignalServiceKit.PreKeyRecord(id: preKeyId, keyPair: keyPair, createdAt: Date(), replacedAt: nil)
            preKeyRecords.append(record)
            preKeyId += 1
        }

        metadataStore.setInt(Int(preKeyId), key: tsNextPrekeyIdKey, transaction: tx)
        return preKeyRecords
    }

    func storePreKeyRecords(_ preKeyRecords: [SignalServiceKit.PreKeyRecord], tx: DBWriteTransaction) {
        for record in preKeyRecords {
            keyStore.setPreKeyRecord(record, key: keyValueStoreKey(int: Int(record.id)), transaction: tx)
        }
    }

    func loadPreKey(_ preKeyId: Int32, transaction: DBReadTransaction) -> SignalServiceKit.PreKeyRecord? {
        keyStore.preKeyRecord(key: keyValueStoreKey(int: Int(preKeyId)), transaction: transaction)
    }

    func storePreKey(_ preKeyId: Int32, preKeyRecord: SignalServiceKit.PreKeyRecord, transaction: DBWriteTransaction) {
        keyStore.setPreKeyRecord(preKeyRecord, key: keyValueStoreKey(int: Int(preKeyId)), transaction: transaction)
    }

    func removePreKey(_ preKeyId: Int32, transaction: DBWriteTransaction) {
        Logger.info("Removing prekeyID: \(preKeyId)")
        keyStore.removeValue(forKey: keyValueStoreKey(int: Int(preKeyId)), transaction: transaction)
    }

    private func keyValueStoreKey(int: Int) -> String {
        return NSNumber(value: int).stringValue
    }

    func setReplacedAtToNowIfNil(exceptFor exceptForPreKeyRecords: [SignalServiceKit.PreKeyRecord], tx: DBWriteTransaction) {
        let exceptForKeys = Set(exceptForPreKeyRecords.map { keyValueStoreKey(int: Int($0.id)) })
        keyStore.allKeys(transaction: tx).forEach { key in autoreleasepool {
            if exceptForKeys.contains(key) {
                return
            }
            let record = keyStore.getObject(key, ofClass: SignalServiceKit.PreKeyRecord.self, transaction: tx)
            guard let record, record.replacedAt == nil else {
                return
            }
            record.setReplacedAtToNow()
            storePreKey(record.id, preKeyRecord: record, transaction: tx)
        }}
    }

    func cullPreKeyRecords(gracePeriod: TimeInterval, tx: DBWriteTransaction) {
        keyStore.allKeys(transaction: tx).forEach { key in autoreleasepool {
            let record = keyStore.getObject(key, ofClass: SignalServiceKit.PreKeyRecord.self, transaction: tx)
            let shouldRemove = { () -> Bool in
                guard let record else {
                    // Whatever's in the db is garbage, so remove it.
                    return true
                }
                guard let replacedAt = record.replacedAt else {
                    // It hasn't been replaced yet, so we can't remove it.
                    return false
                }
                return fabs(replacedAt.timeIntervalSinceNow) > (PreKeyManagerImpl.Constants.maxUnacknowledgedSessionAge + gracePeriod)
            }()
            if shouldRemove {
                Logger.info("Removing pre key \(record?.id as Optional), createdAt \(record?.createdAt as Optional), replacedAt \(record?.replacedAt as Optional)")
                keyStore.removeValue(forKey: key, transaction: tx)
            }
        }}
    }

    public func removeAll(tx: DBWriteTransaction) {
        Logger.warn("")

        keyStore.removeAll(transaction: tx)
        metadataStore.removeAll(transaction: tx)
    }

    private func nextPreKeyId(transaction: DBReadTransaction) -> Int32 {
        var lastPreKeyId = metadataStore.getInt(tsNextPrekeyIdKey, defaultValue: 0, transaction: transaction)
        if lastPreKeyId < 0 || lastPreKeyId > Int32.max {
            lastPreKeyId = 0
        }
        // FIXME: Why are the integer types just all over the board here for the pre key ids?
        return Int32(PreKeyId.nextPreKeyId(lastPreKeyId: UInt32(lastPreKeyId), minimumCapacity: UInt32(batchSize)))
    }

    #if TESTABLE_BUILD

    func count(tx: DBReadTransaction) -> Int {
        return keyStore.allKeys(transaction: tx).count
    }

    #endif
}

extension PreKeyStoreImpl: LibSignalClient.PreKeyStore {
    enum Error: Swift.Error {
        case noPreKeyWithId(UInt32)
    }

    public func loadPreKey(id: UInt32, context: StoreContext) throws -> LibSignalClient.PreKeyRecord {
        guard let preKey = self.loadPreKey(Int32(bitPattern: id), transaction: context.asTransaction) else {
            throw Error.noPreKeyWithId(id)
        }
        let keyPair = preKey.keyPair.identityKeyPair
        return try .init(id: UInt32(bitPattern: preKey.id),
                         publicKey: keyPair.publicKey,
                         privateKey: keyPair.privateKey)
    }

    public func storePreKey(_ record: LibSignalClient.PreKeyRecord, id: UInt32, context: StoreContext) throws {
        // This isn't used today. If it's used in the future, `replacedAt` will
        // need to be handled (though it seems likely that nil would be an
        // acceptable default).
        owsAssertDebug(CurrentAppContext().isRunningTests, "This can't be used for updating existing records.")

        let keyPair = IdentityKeyPair(
            publicKey: try record.publicKey(),
            privateKey: try record.privateKey()
        )
        self.storePreKey(
            Int32(bitPattern: id),
            preKeyRecord: SignalServiceKit.PreKeyRecord(
                id: Int32(bitPattern: id),
                keyPair: ECKeyPair(keyPair),
                createdAt: Date(),
                replacedAt: nil
            ),
            transaction: context.asTransaction
        )
    }

    public func removePreKey(id: UInt32, context: StoreContext) throws {
        self.removePreKey(Int32(bitPattern: id), transaction: context.asTransaction)
    }

}

extension KeyValueStore {
    fileprivate func preKeyRecord(key: String, transaction: DBReadTransaction) -> SignalServiceKit.PreKeyRecord? {
        return getObject(key, ofClass: SignalServiceKit.PreKeyRecord.self, transaction: transaction)
    }

    fileprivate func setPreKeyRecord(_ record: SignalServiceKit.PreKeyRecord, key: String, transaction: DBWriteTransaction) {
        setObject(record, key: key, transaction: transaction)
    }
}
