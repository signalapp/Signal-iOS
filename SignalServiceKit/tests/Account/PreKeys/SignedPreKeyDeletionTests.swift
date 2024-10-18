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

    func testSignedPreKeyDeletion() {
        let maxDaysAgo: Int = 55

        var justUploadedRecord: SignedPreKeyRecord!
        for daysAgo in stride(from: 0, through: maxDaysAgo, by: 5) {
            let secondsAgo: TimeInterval = Double(daysAgo - maxDaysAgo) * kDayInterval
            owsPrecondition(secondsAgo <= 0, "Time in past must be negative!")

            let record = SignedPreKeyRecord(
                id: Int32(daysAgo),
                keyPair: .generateKeyPair(),
                signature: Data(),
                generatedAt: Date(timeIntervalSinceNow: secondsAgo)
            )

            write { tx in
                signedPreKeyStore.storeSignedPreKey(
                    Int32(daysAgo),
                    signedPreKeyRecord: record,
                    tx: tx.asV2Write
                )
            }

            justUploadedRecord = record
        }

        write { tx in
            signedPreKeyStore.cullSignedPreKeyRecords(
                justUploadedSignedPreKey: justUploadedRecord,
                tx: tx.asV2Write
            )
        }

        XCTAssertNil(signedPreKeyStore.loadSignedPreKey(id: 0))
        XCTAssertNil(signedPreKeyStore.loadSignedPreKey(id: 5))
        XCTAssertNil(signedPreKeyStore.loadSignedPreKey(id: 10))
        XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(id: 15))
        XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(id: 20))
        XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(id: 25))
        XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(id: 30))
        XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(id: 35))
        XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(id: 40))
        XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(id: 45))
        XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(id: 50))
        XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(id: 55))
    }

    func testSignedPreKeyDeletionKeepsSomeOldKeys() {
        var justUploadedRecord: SignedPreKeyRecord!
        for idx in (1...5) {
            // All these keys will be considered "old", since they were created
            // more than N days ago.
            let secondsAgo: TimeInterval = Double(idx - 60) * kDayInterval
            owsPrecondition(secondsAgo <= 0, "Time in past must be negative!")

            let record = SignedPreKeyRecord(
                id: Int32(idx),
                keyPair: .generateKeyPair(),
                signature: Data(),
                generatedAt: Date(timeIntervalSinceNow: secondsAgo)
            )

            write { tx in
                signedPreKeyStore.storeSignedPreKey(
                    Int32(idx),
                    signedPreKeyRecord: record,
                    tx: tx.asV2Write
                )
            }

            justUploadedRecord = record
        }

        write { tx in
            signedPreKeyStore.cullSignedPreKeyRecords(
                justUploadedSignedPreKey: justUploadedRecord,
                tx: tx.asV2Write
            )
        }

        // We need to keep 3 "old" keys, plus the "current" key.
        XCTAssertNil(signedPreKeyStore.loadSignedPreKey(id: 1))
        XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(id: 2))
        XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(id: 3))
        XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(id: 4))
        XCTAssertNotNil(signedPreKeyStore.loadSignedPreKey(id: 5))
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
