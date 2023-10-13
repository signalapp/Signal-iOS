//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import XCTest

@testable import SignalServiceKit

final class CallRecordStoreTest: XCTestCase {
    private var mockStatusTransitionManager: MockCallRecordStatusTransitionManager!

    private var inMemoryDb = InMemoryDatabase()
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
            callStatus: callStatus
        )
    }

    private func insertThreadAndInteraction() -> (threadRowId: Int64, interactionRowId: Int64) {
        let thread = TSThread(uniqueId: UUID().uuidString)
        let interaction = TSInteraction(uniqueId: UUID().uuidString, thread: thread)

        inMemoryDb.write { db in
            try! thread.asRecord().insert(db)
            try! interaction.asRecord().insert(db)
        }

        return (thread.sqliteRowId!, interaction.sqliteRowId!)
    }

    // MARK: - Fetches use indices

    func testFetchByCallIdUsesIndex() {
        _ = inMemoryDb.read { db in
            callRecordStore.fetch(
                callId: 1234,
                threadRowId: 6789,
                db: db
            )
        }

        assertExplanation(contains: "index_call_record_on_callId_and_threadId")
    }

    func testFetchByInteractionRowIdUsesIndex() {
        _ = inMemoryDb.read { db in
            callRecordStore.fetch(interactionRowId: 1234, db: db)
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

        inMemoryDb.write { db in
            XCTAssertTrue(callRecordStore.insert(callRecord: callRecord, db: db))
        }

        let fetchedByCallId = inMemoryDb.read { db in
            callRecordStore.fetch(
                callId: callRecord.callId,
                threadRowId: callRecord.threadRowId,
                db: db
            )!
        }

        XCTAssertTrue(callRecord.matches(fetchedByCallId))

        let fetchedByInteractionRowId = inMemoryDb.read { db in
            callRecordStore.fetch(interactionRowId: callRecord.interactionRowId, db: db)!
        }

        XCTAssertTrue(callRecord.matches(fetchedByInteractionRowId))
    }

    // MARK: - updateRecordStatusIfAllowed

    func testUpdateRecordStatus_allowed() {
        let callRecord = makeCallRecord(callStatus: .group(.generic))

        inMemoryDb.write { db in
            XCTAssertTrue(callRecordStore.insert(callRecord: callRecord, db: db))
        }

        inMemoryDb.write { db in
            callRecordStore.updateRecordStatusIfAllowed(
                callRecord: callRecord,
                newCallStatus: .group(.joined),
                db: db
            )
        }

        let fetched = inMemoryDb.read { db in
            callRecordStore.fetch(
                callId: callRecord.callId,
                threadRowId: callRecord.threadRowId,
                db: db
            )!
        }

        XCTAssertEqual(callRecord.callStatus, .group(.joined))
        XCTAssertTrue(callRecord.matches(fetched))
    }

    func testUpdateRecordStatus_notAllowed() {
        mockStatusTransitionManager.shouldAllowStatusTransition = false

        let callRecord = makeCallRecord(callStatus: .group(.generic))

        inMemoryDb.write { db in
            XCTAssertTrue(callRecordStore.insert(callRecord: callRecord, db: db))
        }

        inMemoryDb.write { db in
            callRecordStore.updateRecordStatusIfAllowed(
                callRecord: callRecord,
                newCallStatus: .group(.joined),
                db: db
            )
        }

        let fetched = inMemoryDb.read { db in
            callRecordStore.fetch(
                callId: callRecord.callId,
                threadRowId: callRecord.threadRowId,
                db: db
            )!
        }

        XCTAssertEqual(callRecord.callStatus, .group(.generic))
        XCTAssertTrue(callRecord.matches(fetched))
    }

    // MARK: - updateWithMergedThread

    func testUpdateWithMergedThread() {
        let callRecord = makeCallRecord()
        let (newThreadRowId, _) = insertThreadAndInteraction()

        inMemoryDb.write { db in
            XCTAssertTrue(callRecordStore.insert(callRecord: callRecord, db: db))
        }

        inMemoryDb.write { db in
            callRecordStore.updateWithMergedThread(
                fromThreadRowId: callRecord.threadRowId,
                intoThreadRowId: newThreadRowId,
                db: db
            )
        }

        let fetched = inMemoryDb.read { db in
            callRecordStore.fetch(
                callId: callRecord.callId,
                threadRowId: newThreadRowId,
                db: db
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

        inMemoryDb.write { db in
            XCTAssertTrue(callRecordStore.insert(callRecord: callRecord, db: db))
        }

        inMemoryDb.write { db in
            db.executeHandlingErrors(sql: """
                DELETE FROM model_TSInteraction
                WHERE id = \(callRecord.interactionRowId)
            """, arguments: .init())
        }

        inMemoryDb.read { db in
            XCTAssertNil(callRecordStore.fetch(
                callId: callRecord.callId,
                threadRowId: callRecord.threadRowId,
                db: db
            ))
        }
    }

    /// Per the DB schema, we cannot delete the thread if any call records still
    /// exist. This should never happen in practice - we only delete a thread
    /// during thread merges, and we'll already have moved over the thread ID if
    /// that happens.
    func testDeletingThreadFailsIfCallRecordExtant() {
        let callRecord = makeCallRecord()

        inMemoryDb.write { db in
            XCTAssertTrue(callRecordStore.insert(callRecord: callRecord, db: db))
        }

        inMemoryDb.write { db in
            let deleteThreadSql = """
                DELETE FROM model_TSThread
                WHERE id = \(callRecord.threadRowId)
            """

            XCTAssertThrowsError(
                try db.execute(sql: deleteThreadSql)
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
