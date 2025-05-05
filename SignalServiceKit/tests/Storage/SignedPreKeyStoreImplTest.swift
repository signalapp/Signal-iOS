//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable import SignalServiceKit

final class SignedPreKeyStoreImplTest: XCTestCase {
    func testPniStoreIsSeparate() {
        let aciStore = SignedPreKeyStoreImpl(for: .aci)
        let pniStore = SignedPreKeyStoreImpl(for: .pni)
        let mockDB = InMemoryDB()

        let days: Int32 = 3
        let lastPreKeyId = days

        for i in 0...days { // 4 signed keys are generated, one per day from now until 3 days ago.
            let secondsAgo = TimeInterval(i - days) * .day
            assert(secondsAgo <= 0, "Time in past must be negative")
            let generatedAt = Date(timeIntervalSinceNow: secondsAgo)
            let record = SignedPreKeyRecord(
                id: i,
                keyPair: ECKeyPair.generateKeyPair(),
                signature: Data(),
                generatedAt: generatedAt,
                replacedAt: nil
            )
            mockDB.write { transaction in
                aciStore.storeSignedPreKey(i, signedPreKeyRecord: record, tx: transaction)
            }
        }

        mockDB.read { tx in
            XCTAssertNotNil(aciStore.loadSignedPreKey(lastPreKeyId, transaction: tx))
        }

        for i in 0...days { // 4 signed keys are generated, one per day from now until 3 days ago.
            let secondsAgo = TimeInterval(i - days) * .day
            assert(secondsAgo <= 0, "Time in past must be negative")
            let generatedAt = Date(timeIntervalSinceNow: secondsAgo)
            let record = SignedPreKeyRecord(
                id: i,
                keyPair: ECKeyPair.generateKeyPair(),
                signature: Data(),
                generatedAt: generatedAt,
                replacedAt: nil
            )
            mockDB.write { transaction in
                pniStore.storeSignedPreKey(i, signedPreKeyRecord: record, tx: transaction)
            }
        }

        mockDB.read { tx in
            XCTAssertNotNil(pniStore.loadSignedPreKey(lastPreKeyId, transaction: tx))
        }

        mockDB.write { transaction in
            aciStore.removeSignedPreKey(signedPreKeyId: lastPreKeyId, tx: transaction)
        }

        mockDB.read { tx in
            XCTAssertNil(aciStore.loadSignedPreKey(lastPreKeyId, transaction: tx))
            XCTAssertNotNil(pniStore.loadSignedPreKey(lastPreKeyId, transaction: tx))
        }
    }
}
