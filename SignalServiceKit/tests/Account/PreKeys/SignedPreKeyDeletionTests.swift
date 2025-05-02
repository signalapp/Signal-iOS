//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class SignedPreKeyDeletionTests: SSKBaseTest {
    private lazy var signedPreKeyStore: SSKSignedPreKeyStore = {
        return SSKSignedPreKeyStore(for: .aci)
    }()

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

            write { tx in
                signedPreKeyStore.storeSignedPreKey(
                    Int32(recordId),
                    signedPreKeyRecord: record,
                    tx: tx
                )
            }
        }
        write { tx in
            signedPreKeyStore.setReplacedAtToNowIfNil(exceptFor: currentRecord!, transaction: tx)
        }
        for recordId in 1...2 {
            let record = signedPreKeyStore.loadSignedPreKey(id: Int32(recordId))!
            XCTAssertNotNil(record.replacedAt)
        }
        for recordId in 3...3 {
            let record = signedPreKeyStore.loadSignedPreKey(id: Int32(recordId))!
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

            write { tx in
                signedPreKeyStore.storeSignedPreKey(
                    Int32(daysAgo),
                    signedPreKeyRecord: record,
                    tx: tx
                )
            }
        }

        write { tx in
            signedPreKeyStore.cullSignedPreKeyRecords(gracePeriod: 5 * .day, tx: tx)
        }

        XCTAssertNil(signedPreKeyStore.loadSignedPreKey(id: 0))
        XCTAssertNil(signedPreKeyStore.loadSignedPreKey(id: 5))
        XCTAssertNil(signedPreKeyStore.loadSignedPreKey(id: 10))
        XCTAssertNil(signedPreKeyStore.loadSignedPreKey(id: 15))
        XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(id: 20))
        XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(id: 25))
        XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(id: 30))
        XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(id: 35))
        XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(id: 40))
        XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(id: 45))
        XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(id: 50))
        XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(id: 55))
    }
}

// MARK: -

private extension SSKSignedPreKeyStore {
    func loadSignedPreKey(id: Int32) -> SignedPreKeyRecord? {
        return SSKEnvironment.shared.databaseStorageRef.read { tx in
            return loadSignedPreKey(id, transaction: tx)
        }
    }
}
