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
            try! thread.asRecord().insert(InMemoryDB.shimOnlyBridge(tx).db)
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
                threadRowId: 6789,
                db: InMemoryDB.shimOnlyBridge(tx).db
            )
        }

        assertExplanation(contains: "index_deleted_call_record_on_threadRowId_and_callId")
    }

    func testInsertAndFetchContains() {
        let threadRowId = insertThread()

        let inserted = DeletedCallRecord(
            callId: 1234,
            threadRowId: threadRowId,
            deletedAtTimestamp: 9
        )

        inMemoryDB.write { tx in
            deletedCallRecordStore.insert(
                deletedCallRecord: inserted,
                db: InMemoryDB.shimOnlyBridge(tx).db
            )
        }

        inMemoryDB.read(block: { tx in
            XCTAssertTrue(deletedCallRecordStore.contains(
                callId: 1234,
                threadRowId: threadRowId,
                db: InMemoryDB.shimOnlyBridge(tx).db
            ))
        })
    }

    // MARK: -

    func testUpdateWithMergedThread() {
        let fromThreadRowId = insertThread()
        let toThreadRowId = insertThread()

        let deletedCallRecord = DeletedCallRecord(
            callId: .maxRandom,
            threadRowId: fromThreadRowId,
            deletedAtTimestamp: 9
        )

        inMemoryDB.write { tx in
            deletedCallRecordStore.insert(
                deletedCallRecord: deletedCallRecord,
                db: InMemoryDB.shimOnlyBridge(tx).db
            )
        }

        inMemoryDB.read { tx in
            XCTAssertTrue(deletedCallRecordStore.contains(
                callId: deletedCallRecord.callId,
                threadRowId: fromThreadRowId,
                db: InMemoryDB.shimOnlyBridge(tx).db
            ))
        }

        inMemoryDB.write { tx in
            deletedCallRecordStore.updateWithMergedThread(
                fromThreadRowId: fromThreadRowId,
                intoThreadRowId: toThreadRowId,
                db: InMemoryDB.shimOnlyBridge(tx).db
            )
        }

        inMemoryDB.read { tx in
            XCTAssertFalse(deletedCallRecordStore.contains(
                callId: deletedCallRecord.callId,
                threadRowId: fromThreadRowId,
                db: InMemoryDB.shimOnlyBridge(tx).db
            ))

            XCTAssertTrue(deletedCallRecordStore.contains(
                callId: deletedCallRecord.callId,
                threadRowId: toThreadRowId,
                db: InMemoryDB.shimOnlyBridge(tx).db
            ))
        }
    }
}
