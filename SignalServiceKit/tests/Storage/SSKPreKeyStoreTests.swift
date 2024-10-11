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
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            storePreKeyRecords(preKeyRecords, transaction: transaction)
        }
    }

    fileprivate func loadPreKey(id: Int32) -> PreKeyRecord? {
        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            loadPreKey(id, transaction: transaction)
        }
    }
}

class SSKPreKeyStoreTests: SSKBaseTest {

    private var aciPreKeyStore: SSKPreKeyStore!
    private var pniPreKeyStore: SSKPreKeyStore!

    override func setUp() {
        super.setUp()
        aciPreKeyStore = SSKPreKeyStore(for: .aci)
        pniPreKeyStore = SSKPreKeyStore(for: .pni)
    }

    func testGeneratingAndStoringPreKeys() {
        let generatedKeys = SSKEnvironment.shared.databaseStorageRef.write { aciPreKeyStore.generatePreKeyRecords(transaction: $0) }
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
        let generatedKeys = SSKEnvironment.shared.databaseStorageRef.write { aciPreKeyStore.generatePreKeyRecords(transaction: $0) }
        XCTAssertEqual(generatedKeys.count, 100)

        aciPreKeyStore.storePreKeyRecords(generatedKeys)

        let lastPreKeyRecord = generatedKeys.last!
        let firstPreKeyRecord = generatedKeys.first!

        pniPreKeyStore.storePreKeyRecords(generatedKeys)

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            self.aciPreKeyStore.removePreKey(lastPreKeyRecord.id, transaction: transaction)
        }

        XCTAssertNil(aciPreKeyStore.loadPreKey(id: lastPreKeyRecord.id))
        XCTAssertNotNil(aciPreKeyStore.loadPreKey(id: firstPreKeyRecord.id))
        XCTAssertNotNil(pniPreKeyStore.loadPreKey(id: lastPreKeyRecord.id))
        XCTAssertNotNil(pniPreKeyStore.loadPreKey(id: firstPreKeyRecord.id))
    }
}
