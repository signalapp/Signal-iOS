//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import XCTest

@testable import SignalServiceKit

final class CallRecordStoreTest: XCTestCase {
    private var mockStatusTransitionManager: MockCallRecordStatusTransitionManager!

    private var inMemoryDB = InMemoryDB()
    private var callRecordStore: ExplainingCallRecordStoreImpl!

    override func setUp() {
        mockStatusTransitionManager = MockCallRecordStatusTransitionManager()

        callRecordStore = ExplainingCallRecordStoreImpl(
            statusTransitionManager: mockStatusTransitionManager
        )
    }

    private func makeCallRecord(
        callStatus: CallRecord.CallStatus = .individual(.pending)
    ) -> CallRecord {
        let (threadRowId, interactionRowId) = insertThreadAndInteraction()

        return CallRecord(
            callId: .maxRandom,
            interactionRowId: interactionRowId,
            threadRowId: threadRowId,
            callType: .audioCall,
            callDirection: .outgoing,
            callStatus: callStatus,
            timestamp: .maxRandomInt64Compat
        )
    }

    private func insertThreadAndInteraction() -> (threadRowId: Int64, interactionRowId: Int64) {
        let thread = TSThread(uniqueId: UUID().uuidString)
        let interaction = TSInteraction(uniqueId: UUID().uuidString, thread: thread)

        inMemoryDB.write { tx in
            try! thread.asRecord().insert(InMemoryDB.shimOnlyBridge(tx).db)
            try! interaction.asRecord().insert(InMemoryDB.shimOnlyBridge(tx).db)
        }

        return (thread.sqliteRowId!, interaction.sqliteRowId!)
    }

    // MARK: - Fetches use indices

    func testFetchByCallIdUsesIndex() {
        _ = inMemoryDB.read { tx in
            callRecordStore.fetch(
                callId: 1234,
                threadRowId: 6789,
                db: InMemoryDB.shimOnlyBridge(tx).db
            )
        }

        assertExplanation(contains: "index_call_record_on_callId_and_threadId")
    }

    func testFetchByInteractionRowIdUsesIndex() {
        _ = inMemoryDB.read { tx in
            callRecordStore.fetch(interactionRowId: 1234, db: InMemoryDB.shimOnlyBridge(tx).db)
        }

        assertExplanation(contains: "sqlite_autoindex_CallRecord_1")
    }

    /// Asserts that the latest fetch explanation in the call record store
    /// contains the given string.
    private func assertExplanation(contains substring: String) {
        guard let explanation = callRecordStore.lastExplanation else {
            XCTFail("Missing explanation!")
            return
        }

        XCTAssertTrue(
            explanation.contains(substring),
            "\(explanation) did not contain \(substring)!"
        )
    }

    // MARK: - Insert and fetch

    func testInsertAndFetch() {
        let callRecord = makeCallRecord()

        inMemoryDB.write { tx in
            XCTAssertTrue(callRecordStore.insert(callRecord: callRecord, db: InMemoryDB.shimOnlyBridge(tx).db))
        }

        let fetchedByCallId = inMemoryDB.read { tx in
            callRecordStore.fetch(
                callId: callRecord.callId,
                threadRowId: callRecord.threadRowId,
                db: InMemoryDB.shimOnlyBridge(tx).db
            )!
        }

        XCTAssertTrue(callRecord.matches(fetchedByCallId))

        let fetchedByInteractionRowId = inMemoryDB.read { tx in
            callRecordStore.fetch(interactionRowId: callRecord.interactionRowId, db: InMemoryDB.shimOnlyBridge(tx).db)!
        }

        XCTAssertTrue(callRecord.matches(fetchedByInteractionRowId))
    }

    // MARK: - updateRecordStatusIfAllowed

    func testUpdateRecordStatus_allowed() {
        let callRecord = makeCallRecord(callStatus: .group(.generic))

        inMemoryDB.write { tx in
            XCTAssertTrue(callRecordStore.insert(callRecord: callRecord, db: InMemoryDB.shimOnlyBridge(tx).db))
        }

        inMemoryDB.write { tx in
            callRecordStore.updateRecordStatusIfAllowed(
                callRecord: callRecord,
                newCallStatus: .group(.joined),
                db: InMemoryDB.shimOnlyBridge(tx).db
            )
        }

        let fetched = inMemoryDB.read { tx in
            callRecordStore.fetch(
                callId: callRecord.callId,
                threadRowId: callRecord.threadRowId,
                db: InMemoryDB.shimOnlyBridge(tx).db
            )!
        }

        XCTAssertEqual(callRecord.callStatus, .group(.joined))
        XCTAssertTrue(callRecord.matches(fetched))
    }

    func testUpdateRecordStatus_notAllowed() {
        mockStatusTransitionManager.shouldAllowStatusTransition = false

        let callRecord = makeCallRecord(callStatus: .group(.generic))

        inMemoryDB.write { tx in
            XCTAssertTrue(callRecordStore.insert(callRecord: callRecord, db: InMemoryDB.shimOnlyBridge(tx).db))
        }

        inMemoryDB.write { tx in
            _ = callRecordStore.updateRecordStatusIfAllowed(
                callRecord: callRecord,
                newCallStatus: .group(.joined),
                db: InMemoryDB.shimOnlyBridge(tx).db
            )
        }

        let fetched = inMemoryDB.read { tx in
            callRecordStore.fetch(
                callId: callRecord.callId,
                threadRowId: callRecord.threadRowId,
                db: InMemoryDB.shimOnlyBridge(tx).db
            )!
        }

        XCTAssertEqual(callRecord.callStatus, .group(.generic))
        XCTAssertTrue(callRecord.matches(fetched))
    }

    // MARK: - updateWithMergedThread

    func testUpdateWithMergedThread() {
        let callRecord = makeCallRecord()
        let (newThreadRowId, _) = insertThreadAndInteraction()

        inMemoryDB.write { tx in
            XCTAssertTrue(callRecordStore.insert(callRecord: callRecord, db: InMemoryDB.shimOnlyBridge(tx).db))
        }

        inMemoryDB.write { tx in
            callRecordStore.updateWithMergedThread(
                fromThreadRowId: callRecord.threadRowId,
                intoThreadRowId: newThreadRowId,
                db: InMemoryDB.shimOnlyBridge(tx).db
            )
        }

        let fetched = inMemoryDB.read { tx in
            callRecordStore.fetch(
                callId: callRecord.callId,
                threadRowId: newThreadRowId,
                db: InMemoryDB.shimOnlyBridge(tx).db
            )!
        }

        XCTAssertTrue(fetched.matches(
            callRecord,
            overridingThreadRowId: newThreadRowId
        ))
    }

    // MARK: - Deletion cascades

    func testDeletingInteractionDeletesCallRecord() {
        let callRecord = makeCallRecord()

        inMemoryDB.write { tx in
            XCTAssertTrue(callRecordStore.insert(callRecord: callRecord, db: InMemoryDB.shimOnlyBridge(tx).db))
        }

        inMemoryDB.write { tx in
            let db = InMemoryDB.shimOnlyBridge(tx).db
            db.executeHandlingErrors(sql: """
                DELETE FROM model_TSInteraction
                WHERE id = \(callRecord.interactionRowId)
            """, arguments: .init())
        }

        inMemoryDB.read { tx in
            XCTAssertNil(callRecordStore.fetch(
                callId: callRecord.callId,
                threadRowId: callRecord.threadRowId,
                db: InMemoryDB.shimOnlyBridge(tx).db
            ))
        }
    }

    /// Per the DB schema, we cannot delete the thread if any call records still
    /// exist. This should never happen in practice - we only delete a thread
    /// during thread merges, and we'll already have moved over the thread ID if
    /// that happens.
    func testDeletingThreadFailsIfCallRecordExtant() throws {
        let callRecord = makeCallRecord()

        inMemoryDB.write { tx in
            XCTAssertTrue(callRecordStore.insert(callRecord: callRecord, db: InMemoryDB.shimOnlyBridge(tx).db))
        }

        try inMemoryDB.write { tx in
            let deleteThreadSql = """
                DELETE FROM model_TSThread
                WHERE id = \(callRecord.threadRowId)
            """

            XCTAssertThrowsError(
                try InMemoryDB.shimOnlyBridge(tx).db.execute(sql: deleteThreadSql)
            ) { error in
                guard let error = error as? GRDB.DatabaseError else {
                    XCTFail("Unexpected error!")
                    return
                }

                XCTAssertEqual(error.resultCode, .SQLITE_CONSTRAINT)
                XCTAssertEqual(error.extendedResultCode, .SQLITE_CONSTRAINT_TRIGGER)
            }
        }
    }
}

// MARK: - Mocks

private extension CallRecord {
    func matches(
        _ other: CallRecord,
        overridingThreadRowId: Int64? = nil
    ) -> Bool {
        if
            id == other.id,
            callId == other.callId,
            interactionRowId == other.interactionRowId,
            threadRowId == (overridingThreadRowId ?? other.threadRowId),
            callType == other.callType,
            callDirection == other.callDirection,
            callStatus == other.callStatus
        {
            return true
        }

        return false
    }
}

private final class MockCallRecordStatusTransitionManager: CallRecordStatusTransitionManager {
    var shouldAllowStatusTransition = true

    func isStatusTransitionAllowed(from _: CallRecord.CallStatus, to _: CallRecord.CallStatus) -> Bool {
        return shouldAllowStatusTransition
    }
}
