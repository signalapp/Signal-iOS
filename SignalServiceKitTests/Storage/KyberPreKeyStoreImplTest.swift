//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient
import Testing

@testable import SignalServiceKit

struct KyberPreKeyStoreImplTest {
    @Test
    func testGenerate() throws {
        let now = Date(timeIntervalSince1970: 1234567890)
        let keyId = 42 as UInt32
        let identityKey = PrivateKey.generate()
        let kyberRecord = KyberPreKeyStoreImpl.generatePreKeyRecord(keyId: keyId, now: now, signedBy: identityKey)

        #expect(kyberRecord.id == keyId)
        #expect(kyberRecord.timestamp == now.ows_millisecondsSince1970)
        #expect(try identityKey.publicKey.verifySignature(
            message: kyberRecord.publicKey().serialize(),
            signature: kyberRecord.signature,
        ))
    }

    @Test
    func testStoreChangeNumber() {
        let db = InMemoryDB()
        let preKeyStore = PreKeyStore()
        let kyberStore = KyberPreKeyStoreImpl(for: .aci, dateProvider: { fatalError() }, preKeyStore: preKeyStore)

        db.write { tx in
            let preKeyId = kyberStore.allocatePreKeyIds(count: 1, tx: tx).first
            if preKeyId == 42 { _ = kyberStore.allocatePreKeyIds(count: 1, tx: tx) }

            let kyberRecord = KyberPreKeyStoreImpl.generatePreKeyRecord(keyId: 42, now: Date(), signedBy: .generate())
            kyberStore.storePreKeyRecords([kyberRecord], isLastResort: true, tx: tx)
            #expect(kyberStore.allocatePreKeyIds(count: 1, tx: tx).lowerBound != 43)

            kyberStore.storeLastResortPreKeyFromChangeNumber(kyberRecord, tx: tx)
            #expect(kyberStore.allocatePreKeyIds(count: 1, tx: tx).lowerBound == 43)
        }
    }

    @Test
    func testKyberPreKeyUsed() throws {
        let db = InMemoryDB()
        var now = Date()
        let preKeyStore = PreKeyStore()
        let kyberStore = KyberPreKeyStoreImpl(for: .aci, dateProvider: { now }, preKeyStore: preKeyStore)
        let baseKey = PrivateKey.generate().publicKey

        db.write { tx in
            kyberStore.storePreKeyRecords(
                [KyberPreKeyStoreImpl.generatePreKeyRecord(keyId: 1, now: now, signedBy: .generate())],
                isLastResort: false,
                tx: tx,
            )
            #expect(throws: Never.self, performing: {
                try preKeyStore.forIdentity(.aci).markKyberPreKeyUsed(id: 1, signedPreKeyId: 42, baseKey: baseKey, context: tx)
            })
            let thrownError = #expect(throws: PreKeyStore.Error.self, performing: {
                try preKeyStore.forIdentity(.aci).markKyberPreKeyUsed(id: 1, signedPreKeyId: 42, baseKey: baseKey, context: tx)
            })
            switch thrownError {
            case .noPreKeyWithId(_:):
                // This is expected.
                break
            default:
                Issue.record()
            }
        }
        db.write { tx in
            kyberStore.storePreKeyRecords(
                [KyberPreKeyStoreImpl.generatePreKeyRecord(keyId: 2, now: now, signedBy: .generate())],
                isLastResort: true,
                tx: tx,
            )
            #expect(throws: Never.self, performing: {
                try preKeyStore.forIdentity(.aci).markKyberPreKeyUsed(id: 2, signedPreKeyId: 42, baseKey: baseKey, context: tx)
            })
            let thrownError = #expect(throws: DatabaseError.self, performing: {
                try preKeyStore.forIdentity(.aci).markKyberPreKeyUsed(id: 2, signedPreKeyId: 42, baseKey: baseKey, context: tx)
            })
            switch thrownError {
            case .some(.SQLITE_CONSTRAINT):
                // This is expected.
                break
            default:
                Issue.record()
            }
        }
        try db.write { tx in
            let oldCount = try KyberPreKeyUseRecord.fetchCount(tx.database)
            #expect(oldCount == 1)

            now = Date(timeIntervalSinceNow: -90 * .day)
            kyberStore.setReplacedAtToNowIfNil(exceptFor: [], isLastResort: true, tx: tx)
            preKeyStore.cullPreKeys(gracePeriod: 0, tx: tx)

            let newCount = try KyberPreKeyUseRecord.fetchCount(tx.database)
            #expect(newCount == 0)
        }
    }
}
