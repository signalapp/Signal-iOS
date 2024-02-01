//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class CallRecordStoreTest: XCTestCase {
    private var inMemoryDB: InMemoryDB!
    private var mockDeletedCallRecordStore: MockDeletedCallRecordStore!

    private var callRecordStore: ExplainingCallRecordStoreImpl!

    override func setUp() {
        inMemoryDB = InMemoryDB()
        mockDeletedCallRecordStore = MockDeletedCallRecordStore()

        callRecordStore = ExplainingCallRecordStoreImpl(
            deletedCallRecordStore: mockDeletedCallRecordStore,
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
            callRecordStore.insert(callRecord: callRecord, db: InMemoryDB.shimOnlyBridge(tx).db)
        }

        let fetchedByCallId = inMemoryDB.read { tx in
            callRecordStore.fetch(
                callId: callRecord.callId,
                threadRowId: callRecord.threadRowId,
                db: InMemoryDB.shimOnlyBridge(tx).db
            ).unwrapped
        }

        XCTAssertTrue(callRecord.matches(fetchedByCallId))

        let fetchedByInteractionRowId = inMemoryDB.read { tx in
            callRecordStore.fetch(interactionRowId: callRecord.interactionRowId, db: InMemoryDB.shimOnlyBridge(tx).db)!
        }

        XCTAssertTrue(callRecord.matches(fetchedByInteractionRowId))
    }

    func testFetchWhenRecentlyDeleted() {
        let callId: UInt64 = 1234
        let threadRowId: Int64 = 5678

        mockDeletedCallRecordStore.deletedCallRecords.append(DeletedCallRecord(
            callId: callId,
            threadRowId: threadRowId,
            deletedAtTimestamp: 9
        ))

        inMemoryDB.read { tx in
            switch callRecordStore.fetch(
                callId: callId,
                threadRowId: threadRowId,
                db: InMemoryDB.shimOnlyBridge(tx).db
            ) {
            case .matchFound, .matchNotFound:
                XCTFail("Unexpected fetch result!")
            case .matchDeleted:
                // Test pass
                break
            }
        }
    }

    // MARK: - Delete

    func testDelete() {
        let callRecord1 = makeCallRecord()
        let callRecord2 = makeCallRecord()

        inMemoryDB.write { tx in
            callRecordStore.insert(callRecord: callRecord1, db: InMemoryDB.shimOnlyBridge(tx).db)
            callRecordStore.insert(callRecord: callRecord2, db: InMemoryDB.shimOnlyBridge(tx).db)
        }

        inMemoryDB.write { tx in
            callRecordStore.delete(callRecords: [callRecord1, callRecord2], db: InMemoryDB.shimOnlyBridge(tx).db)
        }

        inMemoryDB.read { tx in
            for callRecord in [callRecord1, callRecord2] {
                XCTAssertNil(callRecordStore.fetch(
                    interactionRowId: callRecord.interactionRowId,
                    db: InMemoryDB.shimOnlyBridge(tx).db
                ))

                switch callRecordStore.fetch(
                    callId: callRecord.callId,
                    threadRowId: callRecord.threadRowId,
                    db: InMemoryDB.shimOnlyBridge(tx).db
                ) {
                case .matchDeleted:
                    // Test pass
                    break
                case .matchFound, .matchNotFound:
                    XCTFail("Unexpected fetch result!")
                }
            }
        }

        XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 2)
        XCTAssertTrue(mockDeletedCallRecordStore.deletedCallRecords[0]
            .matches(callRecord: callRecord1))
        XCTAssertTrue(mockDeletedCallRecordStore.deletedCallRecords[1]
            .matches(callRecord: callRecord2))
    }

    // MARK: - updateRecordStatus

    func testUpdateRecordStatus() {
        let callRecord = makeCallRecord(callStatus: .group(.generic))

        inMemoryDB.write { tx in
            callRecordStore.insert(callRecord: callRecord, db: InMemoryDB.shimOnlyBridge(tx).db)
        }

        inMemoryDB.write { tx in
            callRecordStore.updateRecordStatus(
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
            ).unwrapped
        }

        XCTAssertEqual(callRecord.callStatus, .group(.joined))
        XCTAssertTrue(callRecord.matches(fetched))
    }

    // MARK: - updateWithMergedThread

    func testUpdateWithMergedThread() {
        let callRecord = makeCallRecord()
        let (newThreadRowId, _) = insertThreadAndInteraction()

        inMemoryDB.write { tx in
            callRecordStore.insert(callRecord: callRecord, db: InMemoryDB.shimOnlyBridge(tx).db)
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
            ).unwrapped
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
            callRecordStore.insert(callRecord: callRecord, db: InMemoryDB.shimOnlyBridge(tx).db)
        }

        inMemoryDB.write { tx in
            let db = InMemoryDB.shimOnlyBridge(tx).db
            db.executeHandlingErrors(sql: """
                DELETE FROM model_TSInteraction
                WHERE id = \(callRecord.interactionRowId)
            """, arguments: .init())
        }

        inMemoryDB.read { tx in
            switch callRecordStore.fetch(
                callId: callRecord.callId,
                threadRowId: callRecord.threadRowId,
                db: InMemoryDB.shimOnlyBridge(tx).db
            ) {
            case .matchNotFound:
                // Test pass
                break
            case .matchFound, .matchDeleted:
                XCTFail("Unexpectedly found remnants of record that should've been deleted!")
            }
        }
    }

    /// Per the DB schema, we cannot delete the thread if any call records still
    /// exist. This should never happen in practice - we only delete a thread
    /// during thread merges, and we'll already have moved over the thread ID if
    /// that happens.
    func testDeletingThreadFailsIfCallRecordExtant() throws {
        let callRecord = makeCallRecord()

        inMemoryDB.write { tx in
            callRecordStore.insert(callRecord: callRecord, db: InMemoryDB.shimOnlyBridge(tx).db)
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

private extension CallRecordStoreMaybeDeletedFetchResult {
    var unwrapped: CallRecord {
        switch self {
        case .matchNotFound, .matchDeleted:
            owsFail("Unwrap failed: \(self)")
        case .matchFound(let callRecord):
            return callRecord
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
}
