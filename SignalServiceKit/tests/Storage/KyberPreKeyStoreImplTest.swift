//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
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
}
