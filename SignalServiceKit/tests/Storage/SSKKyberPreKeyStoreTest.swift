//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable import SignalServiceKit

// LastResort
//

class KyberPreKeyStoreTest: XCTestCase {
    var keyValueStoreFactory: KeyValueStoreFactory!
    var dateProvider: DateProvider!
    var currentDate = Date()
    var db = MockDB()

    var identityKey: ECKeyPair!
    var kyberPreKeyStore: SSKKyberPreKeyStore!

    override func setUp() {
        keyValueStoreFactory = InMemoryKeyValueStoreFactory()
        dateProvider = { return self.currentDate }
        identityKey = ECKeyPair.generateKeyPair()
        kyberPreKeyStore = SSKKyberPreKeyStore(
            for: .aci,
            keyValueStoreFactory: keyValueStoreFactory,
            dateProvider: dateProvider
        )
    }

    func testCreate() {
        let key = try! self.db.write { tx in
            try self.kyberPreKeyStore.generateLastResortKyberPreKey(
                signedBy: self.identityKey,
                tx: tx
            )
        }

        XCTAssert(
            try! self.identityKey.keyPair.publicKey.verifySignature(
                message: Data(key.keyPair.publicKey.serialize()),
                signature: key.signature
            )
        )
        XCTAssertNotNil(key)
    }

    func testEncodeDecode() {
        let record = try! self.db.write { tx in
            try self.kyberPreKeyStore.generateLastResortKyberPreKey(
                signedBy: self.identityKey,
                tx: tx
            )
        }

        XCTAssertNotNil(record)

        let jsonData = try! JSONEncoder().encode(record)
        let decodedRecord = try! JSONDecoder().decode(KyberPreKeyRecord.self, from: jsonData)

        XCTAssertEqual(record.id, decodedRecord.id)
        XCTAssert(
            try self.identityKey.keyPair.publicKey.verifySignature(
                message: Data(decodedRecord.keyPair.publicKey.serialize()),
                signature: decodedRecord.signature
            )
        )
    }

    func testGenerateIncrementsNextId() {
        let metadataStore = keyValueStoreFactory.keyValueStore(
            collection: SSKKyberPreKeyStore.Constants.ACI.metadataStoreCollection
        )

        db.write { tx in
            metadataStore.setInt32(500, key: SSKKyberPreKeyStore.Constants.lastKeyId, transaction: tx)
        }

        let records = try! self.db.write { tx in
            try self.kyberPreKeyStore.generateKyberPreKeyRecords(
                count: 25,
                signedBy: self.identityKey,
                tx: tx
            )
        }

        XCTAssertEqual(records.first!.id, 501)
        XCTAssertEqual(records.last!.id, 525)

        let nextId = db.read { tx in
            metadataStore.getInt32(SSKKyberPreKeyStore.Constants.lastKeyId, transaction: tx)
        }
        XCTAssertEqual(nextId!, 525)
    }

    func testLastResortId() {
        let metadataStore = keyValueStoreFactory.keyValueStore(
            collection: SSKKyberPreKeyStore.Constants.ACI.metadataStoreCollection
        )

        db.write { tx in
            metadataStore.setInt32(
                SSKKyberPreKeyStore.Constants.maxKeyId - 1,
                key: SSKKyberPreKeyStore.Constants.lastKeyId,
                transaction: tx
            )
        }

        let record1 = try! self.db.write { tx in
            try self.kyberPreKeyStore.generateLastResortKyberPreKey(signedBy: identityKey, tx: tx)
        }

        XCTAssertEqual(record1.id, SSKKyberPreKeyStore.Constants.maxKeyId)

        let record2 = try! self.db.write { tx in
            try self.kyberPreKeyStore.generateLastResortKyberPreKey(signedBy: identityKey, tx: tx)
        }

        XCTAssertEqual(record2.id, 1)
    }

    // check that prekeyIds overflow in batches
    func testPreKeyIdOverFlow() {
        let metadataStore = keyValueStoreFactory.keyValueStore(
            collection: SSKKyberPreKeyStore.Constants.ACI.metadataStoreCollection
        )

        let batchCount: Int32 = 50
        db.write { tx in
            let lastKeyId: Int32 = SSKKyberPreKeyStore.Constants.maxKeyId - batchCount + 1
            metadataStore.setInt32(lastKeyId, key: SSKKyberPreKeyStore.Constants.lastKeyId, transaction: tx)
        }

        let records = try! self.db.write { tx in
            try self.kyberPreKeyStore.generateKyberPreKeyRecords(
                count: 50,
                signedBy: self.identityKey,
                tx: tx
            )
        }

        XCTAssertEqual(records.first!.id, 1)
        XCTAssertEqual(records.last!.id, 50)

        let nextId = db.read { tx in
            metadataStore.getInt32(SSKKyberPreKeyStore.Constants.lastKeyId, transaction: tx)
        }
        XCTAssertEqual(nextId!, 50)
    }

    // MARK: OneTime keys

   // Ensure that keys aren't marked as last resort
    func testOneTimeKeysNotMarkedAsLastResort() {
        let key = try! self.db.write { tx in
            try self.kyberPreKeyStore.generateKyberPreKeyRecords(
                count: 1,
                signedBy: self.identityKey,
                tx: tx
            ).first
        }

        XCTAssertNotNil(key)
        XCTAssert(
            try! self.identityKey.keyPair.publicKey.verifySignature(
                message: Data(key!.keyPair.publicKey.serialize()),
                signature: key!.signature
            )
        )
        XCTAssertFalse(key!.isLastResort)
    }

    func testGenerateDoesNotStore() {
        let key = try! self.db.write { tx in
            try self.kyberPreKeyStore.generateKyberPreKeyRecords(
                count: 1,
                signedBy: self.identityKey,
                tx: tx
            ).first
        }

        let keyStore = keyValueStoreFactory.keyValueStore(
            collection: SSKKyberPreKeyStore.Constants.ACI.keyStoreCollection
        )

        let fetchedKey = self.db.read { tx in
            keyStore.getObject(
                forKey: kyberPreKeyStore.key(for: key!.id),
                transaction: tx
            )
        }
        XCTAssertNil(fetchedKey)
    }

    // test that storing a batch of keys is reflected in storage
    func testGenerateAndStoreBatch() {
        let records = try! self.db.write { tx in
            let records = try self.kyberPreKeyStore.generateKyberPreKeyRecords(
                count: 5,
                signedBy: self.identityKey,
                tx: tx
            )

            try! self.kyberPreKeyStore.storeKyberPreKeyRecords(records: records, tx: tx)

            return records
        }

        let keyStore = keyValueStoreFactory.keyValueStore(
            collection: SSKKyberPreKeyStore.Constants.ACI.keyStoreCollection
        )

        self.db.read { tx in
            for record in records {
                let fetchedRecord = keyStore.getObject(
                    forKey: kyberPreKeyStore.key(for: record.id),
                    transaction: tx
                )
                XCTAssertNotNil(fetchedRecord)
            }
        }
    }

    // MARK: - LastResort
    func testMarkedAsLastResort() {
        // test that storing a batch of keys is reflected in storage
        let lastResortKey = try! self.db.write { tx in
            try self.kyberPreKeyStore.generateLastResortKyberPreKey(
                signedBy: self.identityKey,
                tx: tx
            )
        }

        XCTAssertNotNil(lastResortKey)
        XCTAssertTrue(lastResortKey.isLastResort)

        let keyStore = keyValueStoreFactory.keyValueStore(
            collection: SSKKyberPreKeyStore.Constants.ACI.keyStoreCollection
        )

        let fetchedKey = self.db.read { tx in
            keyStore.getObject(
                forKey: kyberPreKeyStore.key(for: lastResortKey.id),
                transaction: tx
            )
        }
        XCTAssertNil(fetchedKey)
    }

    // test that storing a batch of keys is reflected in storage
    func testLastResortFetching() {
        let lastResortKey = try! self.db.write { tx in
            let lastResortKey = try self.kyberPreKeyStore.generateLastResortKyberPreKey(
                signedBy: self.identityKey,
                tx: tx
            )

            try! self.kyberPreKeyStore.storeLastResortPreKeyAndMarkAsCurrent(
                record: lastResortKey,
                tx: tx
            )

            return lastResortKey
        }

        let keyStore = keyValueStoreFactory.keyValueStore(
            collection: SSKKyberPreKeyStore.Constants.ACI.keyStoreCollection
        )

        self.db.read { tx in
            // Check the raw record was stored
            let fetchedRecord = keyStore.getObject(
                forKey: kyberPreKeyStore.key(for: lastResortKey.id),
                transaction: tx
            )
            XCTAssertNotNil(fetchedRecord)

            // Check the record deserializes correctly
            let fetchedKey = self.kyberPreKeyStore.getLastResortKyberPreKey(tx: tx)
            XCTAssertNotNil(fetchedKey)
            XCTAssertTrue(fetchedKey!.isLastResort)
            XCTAssertEqual(fetchedKey!.id, lastResortKey.id)
        }
    }

    // Test that generating a last resort doesn't affect the current last resort id
    //      Same with storing
    func testGeneratingLastResortDoesNotReplaceCurrent() {
        let lastResortKey = try! self.db.write { tx in
            let lastResortKey = try self.kyberPreKeyStore.generateLastResortKyberPreKey(
                signedBy: self.identityKey,
                tx: tx
            )

            try! self.kyberPreKeyStore.storeLastResortPreKeyAndMarkAsCurrent(
                record: lastResortKey,
                tx: tx
            )

            return lastResortKey
        }

        let newLastResortKey = try! self.db.write { tx in
            return try self.kyberPreKeyStore.generateLastResortKyberPreKey(
                signedBy: self.identityKey,
                tx: tx
            )
        }

        self.db.read { tx in
            // Check the record deserializes correctly
            let fetchedKey = self.kyberPreKeyStore.getLastResortKyberPreKey(tx: tx)
            XCTAssertNotNil(fetchedKey)
            XCTAssertEqual(fetchedKey!.id, lastResortKey.id)
            XCTAssertNotEqual(fetchedKey!.id, newLastResortKey.id)
        }
    }

    func testMarkAsUsedOneTime () {
        let records = try! self.db.write { tx in
            let records = try self.kyberPreKeyStore.generateKyberPreKeyRecords(
                count: 5,
                signedBy: self.identityKey,
                tx: tx
            )

            try! self.kyberPreKeyStore.storeKyberPreKeyRecords(records: records, tx: tx)

            return records
        }

        let firstRecord = records.first!
        try! self.db.write { tx in
            try self.kyberPreKeyStore.markKyberPreKeyUsed(id: firstRecord.id, tx: tx)
        }

        let keyStore = keyValueStoreFactory.keyValueStore(
            collection: SSKKyberPreKeyStore.Constants.ACI.keyStoreCollection
        )

        self.db.read { tx in
            for record in records {
                let fetchedRecord = keyStore.getObject(
                    forKey: kyberPreKeyStore.key(for: record.id),
                    transaction: tx
                )
                if record.id == firstRecord.id {
                    XCTAssertNil(fetchedRecord)
                } else {
                    XCTAssertNotNil(fetchedRecord)
                }
            }
        }
    }

    func testMarkAsUsedLastResort() {
        let lastResortKey = try! self.db.write { tx in
            let lastResortKey = try self.kyberPreKeyStore.generateLastResortKyberPreKey(
                signedBy: self.identityKey,
                tx: tx
            )

            try! self.kyberPreKeyStore.storeLastResortPreKeyAndMarkAsCurrent(
                record: lastResortKey,
                tx: tx
            )

            return lastResortKey
        }

        try! self.db.write { tx in
            try self.kyberPreKeyStore.markKyberPreKeyUsed(id: lastResortKey.id, tx: tx)
        }

        self.db.read { tx in
            let fetchedKey = self.kyberPreKeyStore.getLastResortKyberPreKey(tx: tx)
            XCTAssertNotNil(fetchedKey)
        }
    }

    func testPniStoreIsSeparate() {

        let pniIdentityKey = ECKeyPair.generateKeyPair()
        let pniKyberPreKeyStore = SSKKyberPreKeyStore(
            for: .pni,
            keyValueStoreFactory: keyValueStoreFactory,
            dateProvider: dateProvider
        )

        func generateKeys(keyStore: SSKKyberPreKeyStore, identityKey: ECKeyPair) -> ([KyberPreKeyRecord], KyberPreKeyRecord) {
            return try! self.db.write { tx in
                let records = try keyStore.generateKyberPreKeyRecords(
                    count: 10,
                    signedBy: identityKey,
                    tx: tx
                )

                try! keyStore.storeKyberPreKeyRecords(records: records, tx: tx)

                let lastResort = try keyStore.generateLastResortKyberPreKey(
                    signedBy: identityKey,
                    tx: tx)

                try! keyStore.storeLastResortPreKeyAndMarkAsCurrent(record: lastResort, tx: tx)

                return (records, lastResort)
            }
        }

        let (aciRecords, aciLastResort) = generateKeys(keyStore: kyberPreKeyStore, identityKey: identityKey)
        let (pniRecords, pniLastResort) = generateKeys(keyStore: pniKyberPreKeyStore, identityKey: pniIdentityKey)

        let aciKeyStore = keyValueStoreFactory.keyValueStore(
            collection: SSKKyberPreKeyStore.Constants.ACI.keyStoreCollection
        )

        let pniKeyStore = keyValueStoreFactory.keyValueStore(
            collection: SSKKyberPreKeyStore.Constants.PNI.keyStoreCollection
        )

        self.db.read { tx in

            // make sure no PNI one-time keys in ACI store
            for record in aciRecords {
                let aciRecord = aciKeyStore.getObject(forKey: kyberPreKeyStore.key(for: record.id), transaction: tx)
                let pniRecord = pniKeyStore.getObject(forKey: kyberPreKeyStore.key(for: record.id), transaction: tx)

                XCTAssertNotNil(aciRecord)
                XCTAssertNil(pniRecord)
            }

            // make sure no ACI one-time keys in PNI store
            for record in pniRecords {
                let aciRecord = aciKeyStore.getObject(forKey: kyberPreKeyStore.key(for: record.id), transaction: tx)
                let pniRecord = pniKeyStore.getObject(forKey: kyberPreKeyStore.key(for: record.id), transaction: tx)

                XCTAssertNil(aciRecord)
                XCTAssertNotNil(pniRecord)
            }

            // make sure no PNI last resort keys in ACI store
            let aciLastResortRecord1 = aciKeyStore.getObject(forKey: kyberPreKeyStore.key(for: aciLastResort.id), transaction: tx)
            let pniLastResortRecord1 = pniKeyStore.getObject(forKey: kyberPreKeyStore.key(for: aciLastResort.id), transaction: tx)
                XCTAssertNotNil(aciLastResortRecord1)
                XCTAssertNil(pniLastResortRecord1)

            // make sure no ACI last resort keys in PNI store
            let aciLastResortRecord2 = aciKeyStore.getObject(forKey: kyberPreKeyStore.key(for: pniLastResort.id), transaction: tx)
            let pniLastResortRecord2 = pniKeyStore.getObject(forKey: kyberPreKeyStore.key(for: pniLastResort.id), transaction: tx)
                XCTAssertNil(aciLastResortRecord2)
                XCTAssertNotNil(pniLastResortRecord2)
        }
    }

    func testCullOneTimeKeys() {
        currentDate = Date(
            timeIntervalSinceNow: -(SSKKyberPreKeyStore.Constants.oneTimeKeyExpirationInterval + 1)
        )
        try! self.db.write { tx in
            let records = try self.kyberPreKeyStore.generateKyberPreKeyRecords(
                count: 5,
                signedBy: self.identityKey,
                tx: tx
            )
            try self.kyberPreKeyStore.storeKyberPreKeyRecords(records: records, tx: tx)
        }

        currentDate = Date()

        let currentRecords = try! self.db.write { tx in
            let records = try self.kyberPreKeyStore.generateKyberPreKeyRecords(
                count: 5,
                signedBy: self.identityKey,
                tx: tx
            )

            try self.kyberPreKeyStore.storeKyberPreKeyRecords(records: records, tx: tx)
            return records
        }

        let keyStore = keyValueStoreFactory.keyValueStore(
            collection: SSKKyberPreKeyStore.Constants.ACI.keyStoreCollection
        )

        let numRecords = self.db.read { tx in
            keyStore.allKeys(transaction: tx).count
        }
        XCTAssertEqual(numRecords, 10)

        self.db.write { tx in
            try! self.kyberPreKeyStore.cullOneTimePreKeyRecords(tx: tx)
        }

        let recordsAfterCull: [KyberPreKeyRecord] = self.db.read { tx in
            try! keyStore.allCodableValues(transaction: tx).filter { !$0.isLastResort }
        }

        let sortedExpectedRecords = currentRecords.sorted { $0.id < $1.id }
        let sortedFoundRecords = recordsAfterCull.sorted { $0.id < $1.id }
        XCTAssertEqual(sortedExpectedRecords.count, sortedFoundRecords.count)
        zip(sortedFoundRecords, sortedExpectedRecords).forEach {
            XCTAssertEqual($0.id, $1.id)
        }

        XCTAssertEqual(recordsAfterCull.count, 5)
    }

    func testCullLastResortKeys() {
        currentDate = Date(
            timeIntervalSinceNow: -(SSKKyberPreKeyStore.Constants.lastResortKeyExpirationInterval + 1)
        )

        let expiredLastResort = try! self.db.write { tx in
            let record = try self.kyberPreKeyStore.generateLastResortKyberPreKey(signedBy: self.identityKey, tx: tx)
            try self.kyberPreKeyStore.storeLastResortPreKeyAndMarkAsCurrent(record: record, tx: tx)
            return record
        }

        currentDate = Date(
            timeIntervalSinceNow: -(SSKKyberPreKeyStore.Constants.lastResortKeyExpirationInterval - 1)
        )

        let oldUnexpiredLastResort = try! self.db.write { tx in
            let record = try self.kyberPreKeyStore.generateLastResortKyberPreKey(signedBy: self.identityKey, tx: tx)
            try self.kyberPreKeyStore.storeLastResortPreKeyAndMarkAsCurrent(record: record, tx: tx)
            return record
        }

        currentDate = Date()

        let currentLastResort = try! self.db.write { tx in
            let record = try self.kyberPreKeyStore.generateLastResortKyberPreKey(signedBy: self.identityKey, tx: tx)
            try self.kyberPreKeyStore.storeLastResortPreKeyAndMarkAsCurrent(record: record, tx: tx)
            return record
        }

        let keyStore = keyValueStoreFactory.keyValueStore(
            collection: SSKKyberPreKeyStore.Constants.ACI.keyStoreCollection
        )

        self.db.write { tx in
            try! self.kyberPreKeyStore.cullLastResortPreKeyRecords(tx: tx)
        }

        let recordsAfterCull: [KyberPreKeyRecord] = self.db.read { tx in
            try! keyStore.allCodableValues(transaction: tx).filter { $0.isLastResort }
        }

        XCTAssertEqual(recordsAfterCull.count, 2)

        let sortedFoundRecords = recordsAfterCull.sorted { $0.id < $1.id }

        XCTAssertNotNil(recordsAfterCull.firstIndex(where: { $0.id == oldUnexpiredLastResort.id }))
        XCTAssertNotNil(recordsAfterCull.firstIndex(where: { $0.id == currentLastResort.id }))
    }
}
