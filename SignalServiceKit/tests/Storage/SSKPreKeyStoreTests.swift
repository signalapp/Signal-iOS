//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable import SignalServiceKit

// MARK: - Helpers
extension SSKPreKeyStore {
    fileprivate func storePreKeyRecords(_ preKeyRecords: [PreKeyRecord]) {
        self.databaseStorage.write { transaction in
            storePreKeyRecords(preKeyRecords, transaction: transaction)
        }
    }

    fileprivate func loadPreKey(id: Int32) -> PreKeyRecord? {
        self.databaseStorage.read { transaction in
            loadPreKey(id, transaction: transaction)
        }
    }
}

class SSKPreKeyStoreTests: SSKBaseTestSwift {

    private var aciPreKeyStore: SSKPreKeyStore!
    private var pniPreKeyStore: SSKPreKeyStore!

    override func setUp() {
        super.setUp()
        aciPreKeyStore = SSKPreKeyStore(for: .aci)
        pniPreKeyStore = SSKPreKeyStore(for: .pni)
    }

    func testGeneratingAndStoringPreKeys() {
        let generatedKeys = aciPreKeyStore.generatePreKeyRecords()
        XCTAssertEqual(generatedKeys.count, 100)

        aciPreKeyStore.storePreKeyRecords(generatedKeys)

        let lastPreKeyRecord = generatedKeys.last!
        let firstPreKeyRecord = generatedKeys.first!

        XCTAssertEqual(
            aciPreKeyStore.loadPreKey(id: lastPreKeyRecord.id)?.keyPair.publicKey,
            lastPreKeyRecord.keyPair.publicKey
        )

        XCTAssertEqual(
            aciPreKeyStore.loadPreKey(id: firstPreKeyRecord.id)?.keyPair.publicKey,
            firstPreKeyRecord.keyPair.publicKey
        )

        XCTAssertNil(pniPreKeyStore.loadPreKey(id: firstPreKeyRecord.id))
    }

    func testRemovingPreKeys() {
        let generatedKeys = aciPreKeyStore.generatePreKeyRecords()
        XCTAssertEqual(generatedKeys.count, 100)

        aciPreKeyStore.storePreKeyRecords(generatedKeys)

        let lastPreKeyRecord = generatedKeys.last!
        let firstPreKeyRecord = generatedKeys.first!

        pniPreKeyStore.storePreKeyRecords(generatedKeys)

        self.databaseStorage.write { transaction in
            self.aciPreKeyStore.removePreKey(lastPreKeyRecord.id, transaction: transaction)
        }

        XCTAssertNil(aciPreKeyStore.loadPreKey(id: lastPreKeyRecord.id))
        XCTAssertNotNil(aciPreKeyStore.loadPreKey(id: firstPreKeyRecord.id))
        XCTAssertNotNil(pniPreKeyStore.loadPreKey(id: lastPreKeyRecord.id))
        XCTAssertNotNil(pniPreKeyStore.loadPreKey(id: firstPreKeyRecord.id))
    }
}
