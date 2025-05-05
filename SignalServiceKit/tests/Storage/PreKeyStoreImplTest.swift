//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable import SignalServiceKit

class PreKeyStoreImplTest: XCTestCase {
    private var mockDB: InMemoryDB!
    private var aciPreKeyStore: PreKeyStoreImpl!
    private var pniPreKeyStore: PreKeyStoreImpl!

    override func setUp() {
        super.setUp()
        mockDB = InMemoryDB()
        aciPreKeyStore = PreKeyStoreImpl(for: .aci)
        pniPreKeyStore = PreKeyStoreImpl(for: .pni)
    }

    func testGeneratingAndStoringPreKeys() {
        let generatedKeys = mockDB.write { aciPreKeyStore.generatePreKeyRecords(tx: $0) }
        XCTAssertEqual(generatedKeys.count, 100)

        mockDB.write { tx in
            aciPreKeyStore.storePreKeyRecords(generatedKeys, tx: tx)
        }

        let lastPreKeyRecord = generatedKeys.last!
        let firstPreKeyRecord = generatedKeys.first!

        mockDB.read { tx in
            XCTAssertEqual(
                aciPreKeyStore.loadPreKey(lastPreKeyRecord.id, transaction: tx)?.keyPair.publicKey,
                lastPreKeyRecord.keyPair.publicKey
            )

            XCTAssertEqual(
                aciPreKeyStore.loadPreKey(firstPreKeyRecord.id, transaction: tx)?.keyPair.publicKey,
                firstPreKeyRecord.keyPair.publicKey
            )

            XCTAssertNil(pniPreKeyStore.loadPreKey(firstPreKeyRecord.id, transaction: tx))
        }
    }

    func testRemovingPreKeys() {
        let generatedKeys = mockDB.write { aciPreKeyStore.generatePreKeyRecords(tx: $0) }
        XCTAssertEqual(generatedKeys.count, 100)

        let lastPreKeyRecord = generatedKeys.last!
        let firstPreKeyRecord = generatedKeys.first!

        mockDB.write { tx in
            aciPreKeyStore.storePreKeyRecords(generatedKeys, tx: tx)
            pniPreKeyStore.storePreKeyRecords(generatedKeys, tx: tx)
            aciPreKeyStore.removePreKey(lastPreKeyRecord.id, transaction: tx)
        }

        mockDB.read { tx in
            XCTAssertNil(aciPreKeyStore.loadPreKey(lastPreKeyRecord.id, transaction: tx))
            XCTAssertNotNil(aciPreKeyStore.loadPreKey(firstPreKeyRecord.id, transaction: tx))
            XCTAssertNotNil(pniPreKeyStore.loadPreKey(lastPreKeyRecord.id, transaction: tx))
            XCTAssertNotNil(pniPreKeyStore.loadPreKey(firstPreKeyRecord.id, transaction: tx))
        }
    }
}
