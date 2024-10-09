//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import XCTest

@testable import SignalServiceKit

final class CallRecordQuerierTest: XCTestCase {
    private typealias SortDirection = CallRecord.SortDirection

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
        let interaction = TSInteraction(timestamp: 0, receivedAtTimestamp: 0, thread: thread)
        try! interaction.asRecord().insert(db)
        return interaction.sqliteRowId!
    }

    /// Insert call records in descending order by timestamp.
    /// - Returns
    /// The row ID of the thread these call records are associated with.
    private func insertCallRecordsForThread(
        callStatuses: [CallRecord.CallStatus],
        unreadStatus: CallRecord.CallUnreadStatus? = nil,
        knownThreadRowId: Int64? = nil
    ) -> Int64 {
        return inMemoryDB.write { tx -> Int64 in
            let db = tx.db

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
                    case .callLink: return .adHocCall
                    }
                }()

                let callRecord = CallRecord(
                    callId: .maxRandom,
                    interactionRowId: interactionRowId,
                    threadRowId: threadRowId,
                    callType: callType,
                    callDirection: .incoming,
                    callStatus: callStatus,
                    callBeganTimestamp: runningCallBeganTimestampForInsertedCallRecords
                )

                if let unreadStatus {
                    callRecord.unreadStatus = unreadStatus
                }

                try! callRecord.insert(db)

                runningCallBeganTimestampForInsertedCallRecords += 1
            }

            return threadRowId
        }
    }

    func testFetchAll() {
        func testCase(
            _ callRecords: [CallRecord],
            expectedStatuses: [CallRecord.CallStatus],
            expectedThreadRowIds: [Int64]
        ) {
            assertExplanation(contains: "CallRecord_callBeganTimestamp")
            XCTAssertEqual(callRecords.map { $0.callStatus }, expectedStatuses)
            XCTAssertEqual(callRecords.map { $0.threadRowId }, expectedThreadRowIds)
        }

        let threadRowId1 = insertCallRecordsForThread(callStatuses: [.group(.ringingDeclined), .group(.ringingMissed), .group(.ringingAccepted)])
        let threadRowId2 = insertCallRecordsForThread(callStatuses: [.group(.generic), .group(.joined), .group(.ringingMissed)])
        let threadRowId3 = insertCallRecordsForThread(callStatuses: [.individual(.accepted), .individual(.notAccepted)])

        inMemoryDB.read { tx in
            testCase(
                try! callRecordQuerier.fetchCursor(
                    ordering: .descending,
                    tx: tx
                )!.drain(expectingSort: .descending),
                expectedStatuses: [
                    .individual(.notAccepted), .individual(.accepted),
                    .group(.ringingMissed), .group(.joined), .group(.generic),
                    .group(.ringingAccepted), .group(.ringingMissed), .group(.ringingDeclined),
                ],
                expectedThreadRowIds: [
                    threadRowId3, threadRowId3,
                    threadRowId2, threadRowId2, threadRowId2,
                    threadRowId1, threadRowId1, threadRowId1,
                ]
            )

            testCase(
                try! callRecordQuerier.fetchCursor(
                    ordering: .descendingBefore(timestamp: 4),
                    tx: tx
                )!.drain(expectingSort: .descending),
                expectedStatuses: [.group(.generic), .group(.ringingAccepted), .group(.ringingMissed), .group(.ringingDeclined)],
                expectedThreadRowIds: [threadRowId2, threadRowId1, threadRowId1, threadRowId1]
            )

            testCase(
                try! callRecordQuerier.fetchCursor(
                    ordering: .ascendingAfter(timestamp: 4),
                    tx: tx
                )!.drain(expectingSort: .ascending),
                expectedStatuses: [.group(.ringingMissed), .individual(.accepted), .individual(.notAccepted)],
                expectedThreadRowIds: [threadRowId2, threadRowId3, threadRowId3]
            )
        }
    }

    func testFetchByCallStatus() {
        func testCase(
            _ callRecords: [CallRecord],
            expectedThreadRowIds: [Int64]
        ) {
            assertExplanation(contains: "CallRecord_status_callBeganTimestamp")
            XCTAssertTrue(callRecords.allSatisfy { $0.callStatus == .group(.ringingMissed) })
            XCTAssertEqual(callRecords.map { $0.threadRowId }, expectedThreadRowIds)
        }

        let threadRowId1 = insertCallRecordsForThread(callStatuses: [.group(.generic), .group(.ringingMissed), .group(.ringingAccepted), .group(.ringingMissed)])
        let threadRowId2 = insertCallRecordsForThread(callStatuses: [.group(.joined), .group(.ringingMissed), .group(.ringingMissed), .group(.ringingMissed)])

        inMemoryDB.read { tx in
            testCase(
                try! callRecordQuerier.fetchCursor(
                    callStatus: .group(.ringingMissed),
                    ordering: .descending,
                    tx: tx
                )!.drain(expectingSort: .descending),
                expectedThreadRowIds: [threadRowId2, threadRowId2, threadRowId2, threadRowId1, threadRowId1]
            )

            testCase(
                try! callRecordQuerier.fetchCursor(
                    callStatus: .group(.ringingMissed),
                    ordering: .descendingBefore(timestamp: 6),
                    tx: tx
                )!.drain(expectingSort: .descending),
                expectedThreadRowIds: [threadRowId2, threadRowId1, threadRowId1]
            )

            testCase(
                try! callRecordQuerier.fetchCursor(
                    callStatus: .group(.ringingMissed),
                    ordering: .ascendingAfter(timestamp: 6),
                    tx: tx
                )!.drain(expectingSort: .ascending),
                expectedThreadRowIds: [threadRowId2]
            )
        }
    }

    func testFetchByThreadRowId() {
        let threadRowId = insertCallRecordsForThread(callStatuses: [.group(.generic), .group(.joined)])
        _ = insertCallRecordsForThread(callStatuses: [.individual(.accepted), .individual(.incomingMissed)])
        _ = insertCallRecordsForThread(callStatuses: [.group(.ringingAccepted), .group(.ringingDeclined)], knownThreadRowId: threadRowId)

        func testCase(
            _ callRecords: [CallRecord],
            expectedStatuses: [CallRecord.CallStatus]
        ) {
            assertExplanation(contains: "CallRecord_threadRowId_callBeganTimestamp")
            XCTAssertEqual(callRecords.map { $0.callStatus }, expectedStatuses)
            XCTAssertTrue(callRecords.allSatisfy { $0.threadRowId == threadRowId })
        }

        inMemoryDB.read { tx in
            testCase(
                try! callRecordQuerier.fetchCursor(
                    threadRowId: threadRowId,
                    ordering: .descending,
                    tx: tx
                )!.drain(expectingSort: .descending),
                expectedStatuses: [
                    .group(.ringingDeclined), .group(.ringingAccepted),
                    .group(.joined), .group(.generic)
                ]
            )

            testCase(
                try! callRecordQuerier.fetchCursor(
                    threadRowId: threadRowId,
                    ordering: .descendingBefore(timestamp: 5),
                    tx: tx
                )!.drain(expectingSort: .descending),
                expectedStatuses: [.group(.ringingAccepted), .group(.joined), .group(.generic)]
            )

            testCase(
                try! callRecordQuerier.fetchCursor(
                    threadRowId: threadRowId,
                    ordering: .ascendingAfter(timestamp: 0),
                    tx: tx
                )!.drain(expectingSort: .ascending),
                expectedStatuses: [.group(.joined), .group(.ringingAccepted), .group(.ringingDeclined)]
            )
        }
    }

    func testFetchByThreadRowIdAndCallStatus() {
        let threadRowId = insertCallRecordsForThread(callStatuses: [.group(.ringingMissed), .group(.generic), .group(.ringingMissed)])
        _ = insertCallRecordsForThread(callStatuses: [.group(.ringingMissed)])
        _ = insertCallRecordsForThread(callStatuses: [.group(.joined), .group(.ringingMissed), .group(.ringingDeclined), .group(.ringingMissed)], knownThreadRowId: threadRowId)

        func testCase(
            _ callRecords: [CallRecord],
            count: Int
        ) {
            assertExplanation(contains: "CallRecord_threadRowId_status_callBeganTimestamp")
            XCTAssertEqual(callRecords.count, count)
            XCTAssertTrue(callRecords.allSatisfy { $0.callStatus == .group(.ringingMissed) })
            XCTAssertTrue(callRecords.allSatisfy { $0.threadRowId == threadRowId })
        }

        inMemoryDB.read { tx in
            testCase(
                try! callRecordQuerier.fetchCursor(
                    threadRowId: threadRowId,
                    callStatus: .group(.ringingMissed),
                    ordering: .descending,
                    tx: tx
                )!.drain(expectingSort: .descending),
                count: 4
            )

            testCase(
                try! callRecordQuerier.fetchCursor(
                    threadRowId: threadRowId,
                    callStatus: .group(.ringingMissed),
                    ordering: .descendingBefore(timestamp: 5),
                    tx: tx
                )!.drain(expectingSort: .descending),
                count: 2
            )

            testCase(
                try! callRecordQuerier.fetchCursor(
                    threadRowId: threadRowId,
                    callStatus: .group(.ringingMissed),
                    ordering: .ascendingAfter(timestamp: 5),
                    tx: tx
                )!.drain(expectingSort: .ascending),
                count: 1
            )
        }
    }

    func testFetchUnreadByCallStatus() {
        _ = insertCallRecordsForThread(callStatuses: [.group(.ringingMissed)], unreadStatus: .unread)
        _ = insertCallRecordsForThread(callStatuses: [.group(.ringingMissed)], unreadStatus: .read)
        _ = insertCallRecordsForThread(callStatuses: [.group(.ringingMissed)], unreadStatus: .unread)
        _ = insertCallRecordsForThread(callStatuses: [.group(.ringingMissed)], unreadStatus: .read)
        _ = insertCallRecordsForThread(callStatuses: [.individual(.incomingMissed)], unreadStatus: .unread)
        _ = insertCallRecordsForThread(callStatuses: [.individual(.incomingMissed)], unreadStatus: .read)

        func testCase(
            _ callRecords: [CallRecord],
            count: Int
        ) {
            assertExplanation(contains: "CallRecord_callStatus_unreadStatus_callBeganTimestamp")
            XCTAssertEqual(callRecords.count, count)
            XCTAssertTrue(callRecords.allSatisfy { $0.callStatus == .group(.ringingMissed) })
            XCTAssertTrue(callRecords.allSatisfy { $0.unreadStatus == .unread })
        }

        inMemoryDB.read { tx in
            testCase(
                try! callRecordQuerier.fetchCursorForUnread(
                    callStatus: .group(.ringingMissed),
                    ordering: .descending,
                    tx: tx
                )!.drain(expectingSort: .descending),
                count: 2
            )
        }
    }

    func testFetchUnreadByCallStatusInConversation() {
        /// This is a contrived scenario, since we won't in practice have an
        /// unread `.group(.ringingDeclined)` call, but it's useful here to test
        /// that we're filtering on call status correctly.
        let threadRowId1 = insertCallRecordsForThread(callStatuses: [.group(.ringingMissed), .group(.ringingDeclined)], unreadStatus: .unread)
        _ = insertCallRecordsForThread(callStatuses: [.group(.ringingMissed)], unreadStatus: .read, knownThreadRowId: threadRowId1)
        _ = insertCallRecordsForThread(callStatuses: [.group(.ringingMissed)], unreadStatus: .unread)

        func testCase(
            _ callRecords: [CallRecord],
            threadRowId: Int64,
            count: Int
        ) {
            assertExplanation(contains: "CallRecord_threadRowId_callStatus_unreadStatus_callBeganTimestamp")
            XCTAssertEqual(callRecords.count, count)
            XCTAssertTrue(callRecords.allSatisfy { $0.threadRowId == threadRowId })
            XCTAssertTrue(callRecords.allSatisfy { $0.callStatus == .group(.ringingMissed) })
            XCTAssertTrue(callRecords.allSatisfy { $0.unreadStatus == .unread })
        }

        inMemoryDB.read { tx in
            testCase(
                try! callRecordQuerier.fetchCursorForUnread(
                    threadRowId: threadRowId1,
                    callStatus: .group(.ringingMissed),
                    ordering: .descending,
                    tx: tx
                )!.drain(expectingSort: .descending),
                threadRowId: threadRowId1,
                count: 1
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

// MARK: -

private extension CallRecordCursor {
    func drain(expectingSort sortDirection: CallRecord.SortDirection) throws -> [CallRecord] {
        let records = try drain()
        XCTAssertTrue(records.isSortedByTimestamp(sortDirection))
        return records
    }
}

// MARK: -

private extension CallRecord {
    var threadRowId: Int64 {
        switch conversationId {
        case .thread(let threadRowId):
            return threadRowId
        case .callLink(_):
            fatalError()
        }
    }

    var interactionRowId: Int64 {
        switch interactionReference {
        case .thread(threadRowId: _, let interactionRowId):
            return interactionRowId
        case .none:
            fatalError()
        }
    }
}
