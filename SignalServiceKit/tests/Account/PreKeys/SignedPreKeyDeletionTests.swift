//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class SignedPreKeyDeletionTests: XCTestCase {
    private var mockDB: InMemoryDB!
    private var signedPreKeyStore: SignedPreKeyStoreImpl!

    override func setUp() {
        super.setUp()
        self.mockDB = InMemoryDB()
        self.signedPreKeyStore = SignedPreKeyStoreImpl(for: .aci)
    }

    func testReplacedAt() {
        var currentRecord: SignedPreKeyRecord?
        for recordId in 1...3 {
            let record = SignedPreKeyRecord(
                id: Int32(recordId),
                keyPair: .generateKeyPair(),
                signature: Data(),
                generatedAt: Date(),
                replacedAt: nil
            )
            currentRecord = record

            mockDB.write { tx in
                signedPreKeyStore.storeSignedPreKey(
                    Int32(recordId),
                    signedPreKeyRecord: record,
                    tx: tx
                )
            }
        }
        mockDB.write { tx in
            signedPreKeyStore.setReplacedAtToNowIfNil(exceptFor: currentRecord!, tx: tx)
        }
        for recordId in 1...2 {
            let record = mockDB.read { tx in signedPreKeyStore.loadSignedPreKey(Int32(recordId), transaction: tx) }!
            XCTAssertNotNil(record.replacedAt)
        }
        for recordId in 3...3 {
            let record = mockDB.read { tx in signedPreKeyStore.loadSignedPreKey(Int32(recordId), transaction: tx) }!
            XCTAssertNil(record.replacedAt)
        }
    }

    func testSignedPreKeyDeletion() {
        let maxDaysAgo: Int = 55

        for daysAgo in stride(from: 0, through: maxDaysAgo, by: 5) {
            let secondsAgo: TimeInterval = Double(daysAgo - maxDaysAgo) * .day
            owsPrecondition(secondsAgo <= 0, "Time in past must be negative!")

            let record = SignedPreKeyRecord(
                id: Int32(daysAgo),
                keyPair: .generateKeyPair(),
                signature: Data(),
                generatedAt: Date(timeIntervalSinceNow: secondsAgo),
                replacedAt: daysAgo == maxDaysAgo ? nil : Date(timeIntervalSinceNow: Double(daysAgo - maxDaysAgo + 5) * .day)
            )

            mockDB.write { tx in
                signedPreKeyStore.storeSignedPreKey(
                    Int32(daysAgo),
                    signedPreKeyRecord: record,
                    tx: tx
                )
            }
        }

        mockDB.write { tx in
            signedPreKeyStore.cullSignedPreKeyRecords(gracePeriod: 5 * .day, tx: tx)
        }

        mockDB.read { tx in
            XCTAssertNil(signedPreKeyStore.loadSignedPreKey(0, transaction: tx))
            XCTAssertNil(signedPreKeyStore.loadSignedPreKey(5, transaction: tx))
            XCTAssertNil(signedPreKeyStore.loadSignedPreKey(10, transaction: tx))
            XCTAssertNil(signedPreKeyStore.loadSignedPreKey(15, transaction: tx))
            XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(20, transaction: tx))
            XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(25, transaction: tx))
            XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(30, transaction: tx))
            XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(35, transaction: tx))
            XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(40, transaction: tx))
            XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(45, transaction: tx))
            XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(50, transaction: tx))
            XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(55, transaction: tx))
        }
    }
}
