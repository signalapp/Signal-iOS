//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class CallRecordStoreTest: XCTestCase {
    private var inMemoryDB = InMemoryDB()
    private var callRecordStore: ExplainingCallRecordStoreImpl!

    override func setUp() {
        callRecordStore = ExplainingCallRecordStoreImpl(
            schedulers: TestSchedulers(scheduler: TestScheduler())
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
            callBeganTimestamp: .maxRandomInt64Compat
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

    // MARK: - updateRecordStatus

    func testUpdateRecordStatus() {
        let callRecord = makeCallRecord(callStatus: .group(.generic))

        inMemoryDB.write { tx in
            XCTAssertTrue(callRecordStore.insert(callRecord: callRecord, db: InMemoryDB.shimOnlyBridge(tx).db))
        }

        inMemoryDB.write { tx in
            XCTAssertTrue(callRecordStore.updateRecordStatus(
                callRecord: callRecord,
                newCallStatus: .group(.joined),
                db: InMemoryDB.shimOnlyBridge(tx).db
            ))
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

    // MARK: -

    func testDecodingStableRowSucceeds() throws {
        let (interaction1, thread1) = insertThreadAndInteraction()
        let (interaction2, thread2) = insertThreadAndInteraction()
        let (interaction3, thread3) = insertThreadAndInteraction()

        try inMemoryDB.write { tx in
            try InMemoryDB.shimOnlyBridge(tx).db.execute(sql: """
                INSERT INTO "CallRecord"
                ( "id", "callId", "interactionRowId", "threadRowId", "type", "direction", "status", "timestamp" )
                VALUES
                ( 1, 123, \(interaction1), \(thread1), 0, 0, 0, 1701299999 ),
                ( 2, 1234, \(interaction2), \(thread2), 2, 1, 6, 1701300000 );
            """)
        }

        try inMemoryDB.write { tx in
            try InMemoryDB.shimOnlyBridge(tx).db.execute(sql: """
                INSERT INTO "CallRecord"
                ( "id", "callId", "interactionRowId", "threadRowId", "type", "direction", "status", "timestamp", "groupCallRingerAci" )
                VALUES
                ( 3, 12345, \(interaction3), \(thread3), 2, 0, 8, 1701300001, X'c2459e888a6a474b80fd51a79923fd50' );
            """)
        }

        let expectedRecords: [CallRecord] = [
            .fixture(
                id: 1,
                callId: 123,
                interactionRowId: interaction1,
                threadRowId: thread1,
                callType: .audioCall,
                callDirection: .incoming,
                callStatus: .individual(.pending),
                callBeganTimestamp: 1701299999
            ),
            .fixture(
                id: 2,
                callId: 1234,
                interactionRowId: interaction2,
                threadRowId: thread2,
                callType: .groupCall,
                callDirection: .outgoing,
                callStatus: .group(.ringingAccepted),
                callBeganTimestamp: 1701300000
            ),
            .fixture(
                id: 3,
                callId: 12345,
                interactionRowId: interaction3,
                threadRowId: thread3,
                callType: .groupCall,
                callDirection: .incoming,
                callStatus: .group(.ringingMissed),
                groupCallRingerAci: Aci.constantForTesting("C2459E88-8A6A-474B-80FD-51A79923FD50"),
                callBeganTimestamp: 1701300001
            ),
        ]

        try inMemoryDB.read { tx throws in
            let actualCallRecords = try CallRecord.fetchAll(InMemoryDB.shimOnlyBridge(tx).db)
            XCTAssertEqual(actualCallRecords.count, expectedRecords.count)

            for (idx, actualCallRecord) in actualCallRecords.enumerated() {
                XCTAssertTrue(
                    actualCallRecord.matches(expectedRecords[idx])
                )
            }
        }
    }
}

// MARK: - Mocks

private extension CallRecord {
    static func fixture(
        id: Int64,
        callId: UInt64,
        interactionRowId: Int64,
        threadRowId: Int64,
        callType: CallType,
        callDirection: CallDirection,
        callStatus: CallStatus,
        groupCallRingerAci: Aci? = nil,
        callBeganTimestamp: UInt64
    ) -> CallRecord {
        let record = CallRecord(
            callId: callId,
            interactionRowId: interactionRowId,
            threadRowId: threadRowId,
            callType: callType,
            callDirection: callDirection,
            callStatus: callStatus,
            groupCallRingerAci: groupCallRingerAci,
            callBeganTimestamp: callBeganTimestamp
        )
        record.id = id

        return record
    }

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
            callStatus == other.callStatus,
            groupCallRingerAci == other.groupCallRingerAci,
            callBeganTimestamp == other.callBeganTimestamp
        {
            return true
        }

        return false
    }
}
