//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class DeletedCallRecordStoreTest: XCTestCase {
    private var inMemoryDB: InMemoryDB!
    private var deletedCallRecordStore: ExplainingDeletedCallRecordStoreImpl!

    override func setUp() {
        inMemoryDB = InMemoryDB()
        deletedCallRecordStore = ExplainingDeletedCallRecordStoreImpl()
    }

    private func insertThread() -> Int64 {
        let thread = TSThread(uniqueId: UUID().uuidString)

        inMemoryDB.write { tx in
            try! thread.asRecord().insert(tx.db)
        }

        return thread.sqliteRowId!
    }

    /// Asserts that the latest fetch explanation in the call record store
    /// contains the given string.
    private func assertExplanation(contains substring: String) {
        guard let explanation = deletedCallRecordStore.lastExplanation else {
            XCTFail("Missing explanation!")
            return
        }

        XCTAssertTrue(
            explanation.contains(substring),
            "\(explanation) did not contain \(substring)!"
        )
    }

    // MARK: -

    func testFetchByCallIdUsesIndex() {
        _ = inMemoryDB.read { tx in
            deletedCallRecordStore.fetch(
                callId: 1234,
                conversationId: .thread(threadRowId: 6789),
                tx: tx
            )
        }

        assertExplanation(contains: "DeletedCallRecord_threadRowId_callId")
    }

    func testInsertAndFetchContains() {
        let threadRowId = insertThread()

        let inserted = DeletedCallRecord(
            callId: 1234,
            conversationId: .thread(threadRowId: threadRowId),
            deletedAtTimestamp: 9
        )

        inMemoryDB.write { tx in
            deletedCallRecordStore.insert(
                deletedCallRecord: inserted,
                tx: tx
            )
        }

        inMemoryDB.read(block: { tx in
            XCTAssertTrue(deletedCallRecordStore.contains(
                callId: 1234,
                conversationId: .thread(threadRowId: threadRowId),
                tx: tx
            ))
        })
    }

    func testDelete() {
        let threadRowId = insertThread()
        let record = DeletedCallRecord(
            callId: 1234,
            conversationId: .thread(threadRowId: threadRowId),
            deletedAtTimestamp: 9
        )

        inMemoryDB.write { tx in
            deletedCallRecordStore.insert(
                deletedCallRecord: record,
                tx: tx
            )
        }

        inMemoryDB.write { tx in
            deletedCallRecordStore.delete(
                expiredDeletedCallRecord: record,
                tx: tx
            )
        }

        inMemoryDB.read(block: { tx in
            XCTAssertFalse(deletedCallRecordStore.contains(
                callId: 1234,
                conversationId: .thread(threadRowId: threadRowId),
                tx: tx
            ))
        })
    }

    // MARK: -

    func testNextDeletedRecordUsesIndex() {
        let records: [DeletedCallRecord] = [
            .init(callId: 2, conversationId: .thread(threadRowId: insertThread()), deletedAtTimestamp: 2),
            .init(callId: 1, conversationId: .thread(threadRowId: insertThread()), deletedAtTimestamp: 1),
            .init(callId: 3, conversationId: .thread(threadRowId: insertThread()), deletedAtTimestamp: 3),
        ]

        inMemoryDB.write { tx in
            for record in records {
                deletedCallRecordStore.insert(
                    deletedCallRecord: record,
                    tx: tx
                )
            }
        }

        let nextDeletedRecord = inMemoryDB.read { tx in
            deletedCallRecordStore.nextDeletedRecord(tx: tx)
        }

        assertExplanation(contains: "DeletedCallRecord_deletedAtTimestamp")

        XCTAssertNotNil(nextDeletedRecord)
        XCTAssertEqual(nextDeletedRecord!.callId, 1)
        XCTAssertEqual(nextDeletedRecord!.deletedAtTimestamp, 1)
    }

    // MARK: -

    func testUpdateWithMergedThread() {
        let fromThreadRowId = insertThread()
        let toThreadRowId = insertThread()

        let deletedCallRecord = DeletedCallRecord(
            callId: .maxRandom,
            conversationId: .thread(threadRowId: fromThreadRowId),
            deletedAtTimestamp: 9
        )

        inMemoryDB.write { tx in
            deletedCallRecordStore.insert(
                deletedCallRecord: deletedCallRecord,
                tx: tx
            )
        }

        inMemoryDB.read { tx in
            XCTAssertTrue(deletedCallRecordStore.contains(
                callId: deletedCallRecord.callId,
                conversationId: .thread(threadRowId: fromThreadRowId),
                tx: tx
            ))
        }

        inMemoryDB.write { tx in
            deletedCallRecordStore.updateWithMergedThread(
                fromThreadRowId: fromThreadRowId,
                intoThreadRowId: toThreadRowId,
                tx: tx
            )
        }

        inMemoryDB.read { tx in
            XCTAssertFalse(deletedCallRecordStore.contains(
                callId: deletedCallRecord.callId,
                conversationId: .thread(threadRowId: fromThreadRowId),
                tx: tx
            ))

            XCTAssertTrue(deletedCallRecordStore.contains(
                callId: deletedCallRecord.callId,
                conversationId: .thread(threadRowId: toThreadRowId),
                tx: tx
            ))
        }
    }
}
