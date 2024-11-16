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
    var dateProvider: DateProvider!
    var currentDate = Date()
    var db = InMemoryDB()

    var identityKey: ECKeyPair!
    var kyberPreKeyStore: SSKKyberPreKeyStore!

    override func setUp() {
        dateProvider = { return self.currentDate }
        identityKey = ECKeyPair.generateKeyPair()
        kyberPreKeyStore = SSKKyberPreKeyStore(
            for: .aci,
            dateProvider: dateProvider,
            remoteConfigProvider: MockRemoteConfigProvider()
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
        let metadataStore = KeyValueStore(
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
        let metadataStore = KeyValueStore(
            collection: SSKKyberPreKeyStore.Constants.ACI.metadataStoreCollection
        )

        db.write { tx in
            metadataStore.setInt32(
                0xFFFFFE,
                key: SSKKyberPreKeyStore.Constants.lastKeyId,
                transaction: tx
            )
        }

        let record1 = try! self.db.write { tx in
            try self.kyberPreKeyStore.generateLastResortKyberPreKey(signedBy: identityKey, tx: tx)
        }

        XCTAssertEqual(record1.id, 0xFFFFFF)

        let record2 = try! self.db.write { tx in
            try self.kyberPreKeyStore.generateLastResortKyberPreKey(signedBy: identityKey, tx: tx)
        }

        XCTAssertEqual(record2.id, 1)
    }

    // check that prekeyIds overflow in batches
    func testPreKeyIdOverFlow() {
        let metadataStore = KeyValueStore(
            collection: SSKKyberPreKeyStore.Constants.ACI.metadataStoreCollection
        )

        let batchCount: Int32 = 50
        db.write { tx in
            let lastKeyId: Int32 = 0x1000000 - batchCount
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

        let fetchedKey = self.db.read { tx in
            return kyberPreKeyStore.loadKyberPreKey(id: key!.id, tx: tx)
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

        self.db.read { tx in
            for record in records {
                let fetchedRecord = kyberPreKeyStore.loadKyberPreKey(id: record.id, tx: tx)
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

        let fetchedKey = self.db.read { tx in
            return kyberPreKeyStore.loadKyberPreKey(id: lastResortKey.id, tx: tx)
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

            try! self.kyberPreKeyStore.storeLastResortPreKey(
                record: lastResortKey,
                tx: tx
            )

            return lastResortKey
        }

        self.db.read { tx in
            // Check the record deserializes correctly
            let fetchedKey = self.kyberPreKeyStore.loadKyberPreKey(id: lastResortKey.id, tx: tx)
            XCTAssertNotNil(fetchedKey)
            XCTAssertTrue(fetchedKey!.isLastResort)
            XCTAssertEqual(fetchedKey!.id, lastResortKey.id)
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

        self.db.read { tx in
            for record in records {
                let fetchedRecord = kyberPreKeyStore.loadKyberPreKey(id: record.id, tx: tx)
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

            try! self.kyberPreKeyStore.storeLastResortPreKey(
                record: lastResortKey,
                tx: tx
            )

            return lastResortKey
        }

        try! self.db.write { tx in
            try self.kyberPreKeyStore.markKyberPreKeyUsed(id: lastResortKey.id, tx: tx)
        }

        self.db.read { tx in
            let fetchedKey = self.kyberPreKeyStore.loadKyberPreKey(id: lastResortKey.id, tx: tx)
            XCTAssertNotNil(fetchedKey)
        }
    }

    func testPniStoreIsSeparate() {

        let pniIdentityKey = ECKeyPair.generateKeyPair()
        let pniKyberPreKeyStore = SSKKyberPreKeyStore(
            for: .pni,
            dateProvider: dateProvider,
            remoteConfigProvider: MockRemoteConfigProvider()
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

                try! keyStore.storeLastResortPreKey(record: lastResort, tx: tx)

                return (records, lastResort)
            }
        }

        let (aciRecords, aciLastResort) = generateKeys(keyStore: kyberPreKeyStore, identityKey: identityKey)
        let (pniRecords, pniLastResort) = generateKeys(keyStore: pniKyberPreKeyStore, identityKey: pniIdentityKey)

        self.db.read { tx in

            // make sure no PNI one-time keys in ACI store
            for record in aciRecords {
                let aciRecord = kyberPreKeyStore.loadKyberPreKey(id: record.id, tx: tx)
                let pniRecord = pniKyberPreKeyStore.loadKyberPreKey(id: record.id, tx: tx)

                XCTAssertNotNil(aciRecord)
                XCTAssertNil(pniRecord)
            }

            // make sure no ACI one-time keys in PNI store
            for record in pniRecords {
                let aciRecord = kyberPreKeyStore.loadKyberPreKey(id: record.id, tx: tx)
                let pniRecord = pniKyberPreKeyStore.loadKyberPreKey(id: record.id, tx: tx)

                XCTAssertNil(aciRecord)
                XCTAssertNotNil(pniRecord)
            }

            // make sure no PNI last resort keys in ACI store
            let aciLastResortRecord1 = kyberPreKeyStore.loadKyberPreKey(id: aciLastResort.id, tx: tx)
            let pniLastResortRecord1 = pniKyberPreKeyStore.loadKyberPreKey(id: aciLastResort.id, tx: tx)
            XCTAssertNotNil(aciLastResortRecord1)
            XCTAssertNil(pniLastResortRecord1)

            // make sure no ACI last resort keys in PNI store
            let aciLastResortRecord2 = kyberPreKeyStore.loadKyberPreKey(id: pniLastResort.id, tx: tx)
            let pniLastResortRecord2 = pniKyberPreKeyStore.loadKyberPreKey(id: pniLastResort.id, tx: tx)
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

        let keyStore = KeyValueStore(
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
        let lastResortKeyExpirationInterval = MockRemoteConfigProvider().currentConfig().messageQueueTime

        currentDate = Date(
            timeIntervalSinceNow: -(lastResortKeyExpirationInterval + 1)
        )

        _ = try! self.db.write { tx in
            let record = try self.kyberPreKeyStore.generateLastResortKyberPreKey(signedBy: self.identityKey, tx: tx)
            try self.kyberPreKeyStore.storeLastResortPreKey(record: record, tx: tx)
            return record
        }

        currentDate = Date(
            timeIntervalSinceNow: -(lastResortKeyExpirationInterval - 1)
        )

        let oldUnexpiredLastResort = try! self.db.write { tx in
            let record = try self.kyberPreKeyStore.generateLastResortKyberPreKey(signedBy: self.identityKey, tx: tx)
            try self.kyberPreKeyStore.storeLastResortPreKey(record: record, tx: tx)
            return record
        }

        currentDate = Date(
            timeIntervalSinceNow: -(lastResortKeyExpirationInterval + 1)
        )

        let currentLastResort = try! self.db.write { tx in
            let record = try self.kyberPreKeyStore.generateLastResortKyberPreKey(signedBy: self.identityKey, tx: tx)
            try self.kyberPreKeyStore.storeLastResortPreKey(record: record, tx: tx)
            return record
        }

        let keyStore = KeyValueStore(
            collection: SSKKyberPreKeyStore.Constants.ACI.keyStoreCollection
        )

        currentDate = Date()

        self.db.write { tx in
            try! self.kyberPreKeyStore.cullLastResortPreKeyRecords(
                justUploadedLastResortPreKey: currentLastResort,
                tx: tx
            )
        }

        let recordsAfterCull: [KyberPreKeyRecord] = self.db.read { tx in
            try! keyStore.allCodableValues(transaction: tx).filter { $0.isLastResort }
        }

        XCTAssertEqual(recordsAfterCull.count, 2)
        XCTAssertNotNil(recordsAfterCull.firstIndex(where: { $0.id == oldUnexpiredLastResort.id }))
        XCTAssertNotNil(recordsAfterCull.firstIndex(where: { $0.id == currentLastResort.id }))
    }
}
