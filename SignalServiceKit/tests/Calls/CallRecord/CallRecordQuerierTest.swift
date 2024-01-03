//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import XCTest

@testable import SignalServiceKit

final class CallRecordQuerierTest: XCTestCase {
    private var inMemoryDB: InMemoryDB!
    private var callRecordQuerier: ExplainingCallRecordQuerierImpl!

    /// The timestamp used to insert a new call record. Kept as a running total
    /// across the duration of a test.
    private var runningCallBeganTimestampForInsertedCallRecords: UInt64!

    override func setUp() {
        inMemoryDB = InMemoryDB()
        callRecordQuerier = ExplainingCallRecordQuerierImpl()

        runningCallBeganTimestampForInsertedCallRecords = 0
    }

    private func insertThread(db: Database) -> (thread: TSThread, threadRowId: Int64) {
        let thread = TSThread(uniqueId: UUID().uuidString)
        try! thread.asRecord().insert(db)
        return (thread, thread.sqliteRowId!)
    }

    private func insertInteraction(thread: TSThread, db: Database) -> Int64 {
        let interaction = TSInteraction(uniqueId: UUID().uuidString, thread: thread)
        try! interaction.asRecord().insert(db)
        return interaction.sqliteRowId!
    }

    /// Insert call records in descending order by timestamp.
    /// - Returns
    /// The row ID of the thread these call records are associated with.
    private func insertCallRecordsForThread(
        callStatuses: [CallRecord.CallStatus],
        knownThreadRowId: Int64? = nil
    ) -> Int64 {
        return inMemoryDB.write { tx -> Int64 in
            let db = InMemoryDB.shimOnlyBridge(tx).db

            let (thread, threadRowId): (TSThread, Int64) = {
                if let knownThreadRowId {
                    return (
                        try! TSThread.fromRecord(ThreadRecord.fetchOne(db, key: knownThreadRowId)!),
                        knownThreadRowId
                    )
                } else {
                    return insertThread(db: db)
                }
            }()

            for callStatus in callStatuses {
                let interactionRowId = insertInteraction(thread: thread, db: db)

                let callType: CallRecord.CallType = {
                    switch callStatus {
                    case .individual: return .videoCall
                    case .group: return .groupCall
                    }
                }()

                try! CallRecord(
                    callId: .maxRandom,
                    interactionRowId: interactionRowId,
                    threadRowId: threadRowId,
                    callType: callType,
                    callDirection: .incoming,
                    callStatus: callStatus,
                    callBeganTimestamp: runningCallBeganTimestampForInsertedCallRecords
                ).insert(db)

                runningCallBeganTimestampForInsertedCallRecords += 1
            }

            return threadRowId
        }
    }

    func testFetchAll() {
        func testCase(
            _ callRecords: [CallRecord],
            expectedStatuses: [CallRecord.CallStatus],
            expectedThreadRowIds: [Int64],
            sortDirection: SortDirection
        ) {
            assertExplanation(contains: "index_call_record_on_timestamp")
            XCTAssertEqual(callRecords.map { $0.callStatus }, expectedStatuses)
            XCTAssertEqual(callRecords.map { $0.threadRowId }, expectedThreadRowIds)
            XCTAssertTrue(callRecords.isSortedByTimestamp(sortDirection))
        }

        let threadRowId1 = insertCallRecordsForThread(callStatuses: [.group(.ringingDeclined), .group(.ringingMissed), .group(.ringingAccepted)])
        let threadRowId2 = insertCallRecordsForThread(callStatuses: [.group(.generic), .group(.joined), .group(.ringingMissed)])
        let threadRowId3 = insertCallRecordsForThread(callStatuses: [.individual(.accepted), .individual(.notAccepted)])

        inMemoryDB.read { tx in
            testCase(
                callRecordQuerier.fetchCursor(
                    ordering: .descending,
                    db: tx.database
                )!.drain(),
                expectedStatuses: [
                    .individual(.notAccepted), .individual(.accepted),
                    .group(.ringingMissed), .group(.joined), .group(.generic),
                    .group(.ringingAccepted), .group(.ringingMissed), .group(.ringingDeclined),
                ],
                expectedThreadRowIds: [
                    threadRowId3, threadRowId3,
                    threadRowId2, threadRowId2, threadRowId2,
                    threadRowId1, threadRowId1, threadRowId1,
                ],
                sortDirection: .descending
            )

            testCase(
                callRecordQuerier.fetchCursor(
                    ordering: .descendingBefore(timestamp: 4),
                    db: tx.database
                )!.drain(),
                expectedStatuses: [.group(.generic), .group(.ringingAccepted), .group(.ringingMissed), .group(.ringingDeclined)],
                expectedThreadRowIds: [threadRowId2, threadRowId1, threadRowId1, threadRowId1],
                sortDirection: .descending
            )

            testCase(
                callRecordQuerier.fetchCursor(
                    ordering: .ascendingAfter(timestamp: 4),
                    db: tx.database
                )!.drain(),
                expectedStatuses: [.group(.ringingMissed), .individual(.accepted), .individual(.notAccepted)],
                expectedThreadRowIds: [threadRowId2, threadRowId3, threadRowId3],
                sortDirection: .ascending
            )
        }
    }

    func testFetchByCallStatus() {
        func testCase(
            _ callRecords: [CallRecord],
            expectedThreadRowIds: [Int64],
            sortDirection: SortDirection
        ) {
            assertExplanation(contains: "index_call_record_on_status_and_timestamp")
            XCTAssertTrue(callRecords.allSatisfy { $0.callStatus == .group(.ringingMissed) })
            XCTAssertEqual(callRecords.map { $0.threadRowId }, expectedThreadRowIds)
            XCTAssertTrue(callRecords.isSortedByTimestamp(sortDirection))
        }

        let threadRowId1 = insertCallRecordsForThread(callStatuses: [.group(.generic), .group(.ringingMissed), .group(.ringingAccepted), .group(.ringingMissed)])
        let threadRowId2 = insertCallRecordsForThread(callStatuses: [.group(.joined), .group(.ringingMissed), .group(.ringingMissed), .group(.ringingMissed)])

        inMemoryDB.read { tx in
            testCase(
                callRecordQuerier.fetchCursor(
                    callStatus: .group(.ringingMissed),
                    ordering: .descending,
                    db: tx.database
                )!.drain(),
                expectedThreadRowIds: [threadRowId2, threadRowId2, threadRowId2, threadRowId1, threadRowId1],
                sortDirection: .descending
            )

            testCase(
                callRecordQuerier.fetchCursor(
                    callStatus: .group(.ringingMissed),
                    ordering: .descendingBefore(timestamp: 6),
                    db: tx.database
                )!.drain(),
                expectedThreadRowIds: [threadRowId2, threadRowId1, threadRowId1],
                sortDirection: .descending
            )

            testCase(
                callRecordQuerier.fetchCursor(
                    callStatus: .group(.ringingMissed),
                    ordering: .ascendingAfter(timestamp: 6),
                    db: tx.database
                )!.drain(),
                expectedThreadRowIds: [threadRowId2],
                sortDirection: .ascending
            )
        }
    }

    func testFetchByThreadRowId() {
        let threadRowId = insertCallRecordsForThread(callStatuses: [.group(.generic), .group(.joined)])
        _ = insertCallRecordsForThread(callStatuses: [.individual(.accepted), .individual(.incomingMissed)])
        _ = insertCallRecordsForThread(callStatuses: [.group(.ringingAccepted), .group(.ringingDeclined)], knownThreadRowId: threadRowId)

        func testCase(
            _ callRecords: [CallRecord],
            expectedStatuses: [CallRecord.CallStatus],
            sortDirection: SortDirection
        ) {
            assertExplanation(contains: "index_call_record_on_threadRowId_and_timestamp")
            XCTAssertEqual(callRecords.map { $0.callStatus }, expectedStatuses)
            XCTAssertTrue(callRecords.allSatisfy { $0.threadRowId == threadRowId })
            XCTAssertTrue(callRecords.isSortedByTimestamp(sortDirection))
        }

        inMemoryDB.read { tx in
            testCase(
                callRecordQuerier.fetchCursor(
                    threadRowId: threadRowId,
                    ordering: .descending,
                    db: tx.database
                )!.drain(),
                expectedStatuses: [
                    .group(.ringingDeclined), .group(.ringingAccepted),
                    .group(.joined), .group(.generic)
                ],
                sortDirection: .descending
            )

            testCase(
                callRecordQuerier.fetchCursor(
                    threadRowId: threadRowId,
                    ordering: .descendingBefore(timestamp: 5),
                    db: tx.database
                )!.drain(),
                expectedStatuses: [.group(.ringingAccepted), .group(.joined), .group(.generic)],
                sortDirection: .descending
            )

            testCase(
                callRecordQuerier.fetchCursor(
                    threadRowId: threadRowId,
                    ordering: .ascendingAfter(timestamp: 0),
                    db: tx.database
                )!.drain(),
                expectedStatuses: [.group(.joined), .group(.ringingAccepted), .group(.ringingDeclined)],
                sortDirection: .ascending
            )
        }
    }

    func testFetchByThreadRowIdAndCallStatus() {
        let threadRowId = insertCallRecordsForThread(callStatuses: [.group(.ringingMissed), .group(.generic), .group(.ringingMissed)])
        _ = insertCallRecordsForThread(callStatuses: [.group(.ringingMissed)])
        _ = insertCallRecordsForThread(callStatuses: [.group(.joined), .group(.ringingMissed), .group(.ringingDeclined), .group(.ringingMissed)], knownThreadRowId: threadRowId)

        func testCase(
            _ callRecords: [CallRecord],
            count: Int,
            sortDirection: SortDirection
        ) {
            assertExplanation(contains: "index_call_record_on_threadRowId_and_status_and_timestamp")
            XCTAssertEqual(callRecords.count, count)
            XCTAssertTrue(callRecords.allSatisfy { $0.callStatus == .group(.ringingMissed) })
            XCTAssertTrue(callRecords.allSatisfy { $0.threadRowId == threadRowId })
            XCTAssertTrue(callRecords.isSortedByTimestamp(sortDirection))
        }

        inMemoryDB.read { tx in
            testCase(
                callRecordQuerier.fetchCursor(
                    threadRowId: threadRowId,
                    callStatus: .group(.ringingMissed),
                    ordering: .descending,
                    db: tx.database
                )!.drain(),
                count: 4,
                sortDirection: .descending
            )

            testCase(
                callRecordQuerier.fetchCursor(
                    threadRowId: threadRowId,
                    callStatus: .group(.ringingMissed),
                    ordering: .descendingBefore(timestamp: 5),
                    db: tx.database
                )!.drain(),
                count: 2,
                sortDirection: .descending
            )

            testCase(
                callRecordQuerier.fetchCursor(
                    threadRowId: threadRowId,
                    callStatus: .group(.ringingMissed),
                    ordering: .ascendingAfter(timestamp: 5),
                    db: tx.database
                )!.drain(),
                count: 1,
                sortDirection: .ascending
            )
        }
    }

    /// Asserts that the latest fetch explanation in the call record querier
    /// contains the given string.
    private func assertExplanation(
        contains substring: String
    ) {
        guard let explanation = callRecordQuerier.lastExplanation else {
            XCTFail("Missing explanation!")
            return
        }

        callRecordQuerier.lastExplanation = nil

        XCTAssertTrue(
            explanation.contains(substring),
            "\(explanation) did not contain \(substring)!"
        )
    }
}

private extension DBReadTransaction {
    var database: Database {
        return InMemoryDB.shimOnlyBridge(self).db
    }
}

private extension RecordCursor {
    func drain() -> [Record] {
        var records = [Record]()

        while let next = try! next() {
            records.append(next)
        }

        return records
    }
}

private enum SortDirection {
    case ascending
    case descending

    func compareForSort(lhs: CallRecord, rhs: CallRecord) -> Bool {
        switch self {
        case .ascending:
            return lhs.callBeganTimestamp < rhs.callBeganTimestamp
        case .descending:
            return lhs.callBeganTimestamp > rhs.callBeganTimestamp
        }

    }
}

private extension Array<CallRecord> {
    func isSortedByTimestamp(_ direction: SortDirection) -> Bool {
        return sorted(by: direction.compareForSort(lhs:rhs:)).enumerated().allSatisfy { (idx, callRecord) in
            /// When sorted by timestamp descending the order should not have
            /// changed; i.e., each enumerated sorted call record is exactly the
            /// same as the unsorted call record in the same index.
            callRecord === self[idx]
        }
    }
}
