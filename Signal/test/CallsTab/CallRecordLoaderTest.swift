//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import XCTest

@testable import Signal

final class CallRecordLoaderTest: XCTestCase {
    private var mockCallRecordQuerier: MockCallRecordQuerier!
    private var mockFullTextSearchFinder: MockFullTextSearchFinder!

    private var callRecordLoader: CallRecordLoader!

    override func setUp() {
        mockCallRecordQuerier = MockCallRecordQuerier()
        mockFullTextSearchFinder = MockFullTextSearchFinder()
    }

    private func setupCallRecordLoader(
        onlyLoadMissedCalls: Bool = false,
        searchTerm: String? = nil
    ) {
        callRecordLoader = CallRecordLoader(
            callRecordQuerier: mockCallRecordQuerier,
            fullTextSearchFinder: mockFullTextSearchFinder,
            configuration: CallRecordLoader.Configuration(
                onlyLoadMissedCalls: onlyLoadMissedCalls,
                searchTerm: searchTerm
            )
        )
    }

    private func loadRecords(loadDirection: CallRecordLoader.LoadDirection) -> [UInt64] {
        return MockDB().read { tx in
            callRecordLoader
                .loadCallRecords(loadDirection: loadDirection, pageSize: 3, tx: tx)
                .map { $0.callId }
        }
    }

    func testNothingMatching() {
        mockCallRecordQuerier.mockCallRecords = [
            .fixture(callId: 1), .fixture(callId: 2)
        ]

        mockFullTextSearchFinder.mockThreadRowIdsForSearchTerm = [:]

        setupCallRecordLoader(searchTerm: "han solo")
        XCTAssertEqual([], loadRecords(loadDirection: .older(oldestCallTimestamp: nil)))

        setupCallRecordLoader(onlyLoadMissedCalls: true)
        XCTAssertEqual([], loadRecords(loadDirection: .older(oldestCallTimestamp: nil)))

        setupCallRecordLoader()
        XCTAssertEqual([2, 1], loadRecords(loadDirection: .older(oldestCallTimestamp: nil)))
    }

    // MARK: Older

    func testGetOlderPage() {
        setupCallRecordLoader()

        mockCallRecordQuerier.mockCallRecords = [
            .fixture(callId: 1), .fixture(callId: 2), .fixture(callId: 3),
            .fixture(callId: 4), .fixture(callId: 5), .fixture(callId: 6),
            .fixture(callId: 7)
        ]

        XCTAssertEqual([7, 6, 5], loadRecords(loadDirection: .older(oldestCallTimestamp: nil)))
        XCTAssertEqual([4, 3, 2], loadRecords(loadDirection: .older(oldestCallTimestamp: 5)))
        XCTAssertEqual([1], loadRecords(loadDirection: .older(oldestCallTimestamp: 2)))
        XCTAssertEqual([], loadRecords(loadDirection: .older(oldestCallTimestamp: 1)))
    }

    func testGetOlderPageSearching() {
        setupCallRecordLoader(searchTerm: "boba fett")

        mockFullTextSearchFinder.mockThreadRowIdsForSearchTerm = [
            "boba fett": [1, 2]
        ]

        mockCallRecordQuerier.mockCallRecords = [
            .fixture(callId: 1),
            .fixture(callId: 2, threadRowId: 1), .fixture(callId: 3, threadRowId: 2),
            .fixture(callId: 4),
            .fixture(callId: 5, threadRowId: 2), .fixture(callId: 6, threadRowId: 1),
            .fixture(callId: 7),
        ]

        XCTAssertEqual([6, 5, 3], loadRecords(loadDirection: .older(oldestCallTimestamp: nil)))
        XCTAssertEqual([2], loadRecords(loadDirection: .older(oldestCallTimestamp: 3)))
        XCTAssertEqual([], loadRecords(loadDirection: .older(oldestCallTimestamp: 2)))
    }

    func testGetOlderPageForMissed() {
        setupCallRecordLoader(onlyLoadMissedCalls: true)

        mockCallRecordQuerier.mockCallRecords = [
            .fixture(callId: 1),
            .fixture(callId: 2, threadRowId: 1, callStatus: .group(.ringingMissed)),
            .fixture(callId: 3, threadRowId: 1),
            .fixture(callId: 4, threadRowId: 2, callStatus: .individual(.incomingMissed)),
            .fixture(callId: 5, threadRowId: 2, callStatus: .individual(.accepted)),
            .fixture(callId: 6, threadRowId: 2, callStatus: .individual(.incomingMissed)),
            .fixture(callId: 7, threadRowId: 2, callStatus: .individual(.incomingMissed)),
            .fixture(callId: 8, threadRowId: 1, callStatus: .group(.ringingMissed)),
            .fixture(callId: 9),
        ]

        XCTAssertEqual([8, 7, 6], loadRecords(loadDirection: .older(oldestCallTimestamp: nil)))
        XCTAssertEqual([4, 2], loadRecords(loadDirection: .older(oldestCallTimestamp: 6)))
        XCTAssertEqual([], loadRecords(loadDirection: .older(oldestCallTimestamp: 2)))
    }

    func testGetOlderPageForMissedSearching() {
        setupCallRecordLoader(onlyLoadMissedCalls: true, searchTerm: "darth vader")

        mockFullTextSearchFinder.mockThreadRowIdsForSearchTerm = [
            "darth vader": [1, 2]
        ]

        mockCallRecordQuerier.mockCallRecords = [
            .fixture(callId: 1),
            .fixture(callId: 2, threadRowId: 1, callStatus: .group(.ringingMissed)),
            .fixture(callId: 3, threadRowId: 1),
            .fixture(callId: 4, threadRowId: 1, callStatus: .group(.ringingMissed)),
            .fixture(callId: 5, threadRowId: 2, callStatus: .individual(.incomingMissed)),
            .fixture(callId: 6, threadRowId: 1, callStatus: .group(.ringingMissed)),
            .fixture(callId: 7, threadRowId: 1, callStatus: .group(.joined)),
            .fixture(callId: 8, threadRowId: 2, callStatus: .individual(.accepted)),
            .fixture(callId: 9, threadRowId: 2, callStatus: .individual(.incomingMissed)),
            .fixture(callId: 10, threadRowId: 2, callStatus: .individual(.incomingMissed)),
            .fixture(callId: 11, threadRowId: 1, callStatus: .group(.ringingMissed)),
            .fixture(callId: 12),
            .fixture(callId: 13, callStatus: .group(.ringingMissed)),
        ]

        XCTAssertEqual([11, 10, 9], loadRecords(loadDirection: .older(oldestCallTimestamp: nil)))
        XCTAssertEqual([6, 5, 4], loadRecords(loadDirection: .older(oldestCallTimestamp: 9)))
        XCTAssertEqual([2], loadRecords(loadDirection: .older(oldestCallTimestamp: 4)))
        XCTAssertEqual([], loadRecords(loadDirection: .older(oldestCallTimestamp: 2)))
    }

    // MARK: Newer

    func testGetNewerPage() {
        setupCallRecordLoader()

        mockCallRecordQuerier.mockCallRecords = [
            .fixture(callId: 1), .fixture(callId: 2), .fixture(callId: 3),
            .fixture(callId: 4), .fixture(callId: 5), .fixture(callId: 6),
            .fixture(callId: 7)
        ]

        XCTAssertEqual([3, 2, 1], loadRecords(loadDirection: .newer(newestCallTimestamp: 0)))
        XCTAssertEqual([6, 5, 4], loadRecords(loadDirection: .newer(newestCallTimestamp: 3)))
        XCTAssertEqual([7], loadRecords(loadDirection: .newer(newestCallTimestamp: 6)))
        XCTAssertEqual([], loadRecords(loadDirection: .newer(newestCallTimestamp: 7)))
    }

    func testGetNewerPageSearching() {
        setupCallRecordLoader(searchTerm: "boba fett")

        mockFullTextSearchFinder.mockThreadRowIdsForSearchTerm = [
            "boba fett": [1, 2]
        ]

        mockCallRecordQuerier.mockCallRecords = [
            .fixture(callId: 1),
            .fixture(callId: 2, threadRowId: 1), .fixture(callId: 3, threadRowId: 2),
            .fixture(callId: 4),
            .fixture(callId: 5, threadRowId: 2), .fixture(callId: 6, threadRowId: 1),
            .fixture(callId: 7),
        ]

        XCTAssertEqual([5, 3, 2], loadRecords(loadDirection: .newer(newestCallTimestamp: 0)))
        XCTAssertEqual([6], loadRecords(loadDirection: .newer(newestCallTimestamp: 5)))
        XCTAssertEqual([], loadRecords(loadDirection: .newer(newestCallTimestamp: 6)))
    }

    func testGetNewerPageForMissed() {
        setupCallRecordLoader(onlyLoadMissedCalls: true)

        mockCallRecordQuerier.mockCallRecords = [
            .fixture(callId: 1),
            .fixture(callId: 2, threadRowId: 1, callStatus: .group(.ringingMissed)),
            .fixture(callId: 3, threadRowId: 1),
            .fixture(callId: 4, threadRowId: 2, callStatus: .individual(.incomingMissed)),
            .fixture(callId: 5, threadRowId: 2, callStatus: .individual(.accepted)),
            .fixture(callId: 6, threadRowId: 2, callStatus: .individual(.incomingMissed)),
            .fixture(callId: 7, threadRowId: 2, callStatus: .individual(.incomingMissed)),
            .fixture(callId: 8, threadRowId: 1, callStatus: .group(.ringingMissed)),
            .fixture(callId: 9),
        ]

        XCTAssertEqual([6, 4, 2], loadRecords(loadDirection: .newer(newestCallTimestamp: 0)))
        XCTAssertEqual([8, 7], loadRecords(loadDirection: .newer(newestCallTimestamp: 6)))
        XCTAssertEqual([], loadRecords(loadDirection: .newer(newestCallTimestamp: 8)))
    }

    func testGetNewerPageForMissedSearching() {
        setupCallRecordLoader(onlyLoadMissedCalls: true, searchTerm: "darth vader")

        mockFullTextSearchFinder.mockThreadRowIdsForSearchTerm = [
            "darth vader": [1, 2]
        ]

        mockCallRecordQuerier.mockCallRecords = [
            .fixture(callId: 1),
            .fixture(callId: 2, threadRowId: 1, callStatus: .group(.ringingMissed)),
            .fixture(callId: 3, threadRowId: 1),
            .fixture(callId: 4, threadRowId: 1, callStatus: .group(.ringingMissed)),
            .fixture(callId: 5, threadRowId: 2, callStatus: .individual(.incomingMissed)),
            .fixture(callId: 6, threadRowId: 1, callStatus: .group(.ringingMissed)),
            .fixture(callId: 7, threadRowId: 1, callStatus: .group(.joined)),
            .fixture(callId: 8, threadRowId: 2, callStatus: .individual(.accepted)),
            .fixture(callId: 9, threadRowId: 2, callStatus: .individual(.incomingMissed)),
            .fixture(callId: 10, threadRowId: 2, callStatus: .individual(.incomingMissed)),
            .fixture(callId: 11, threadRowId: 1, callStatus: .group(.ringingMissed)),
            .fixture(callId: 12),
            .fixture(callId: 13, callStatus: .group(.ringingMissed)),
        ]

        XCTAssertEqual([5, 4, 2], loadRecords(loadDirection: .newer(newestCallTimestamp: 0)))
        XCTAssertEqual([10, 9, 6], loadRecords(loadDirection: .newer(newestCallTimestamp: 5)))
        XCTAssertEqual([11], loadRecords(loadDirection: .newer(newestCallTimestamp: 10)))
        XCTAssertEqual([], loadRecords(loadDirection: .newer(newestCallTimestamp: 11)))
    }
}

// MARK: - Mocks

private extension CallRecord {
    /// Creates a ``CallRecord`` with the given parameters. The record's
    /// timestamp will be equivalent to its call ID.
    static func fixture(
        callId: UInt64,
        threadRowId: Int64 = 0,
        callStatus: CallRecord.CallStatus = .group(.joined)
    ) -> CallRecord {
        return CallRecord(
            callId: callId,
            interactionRowId: 0,
            threadRowId: threadRowId,
            callType: .groupCall,
            callDirection: .incoming,
            callStatus: callStatus,
            callBeganTimestamp: callId
        )
    }
}

private class MockCallRecordQuerier: CallRecordQuerier {
    private class Cursor: CallRecordCursor {
        private var callRecords: [CallRecord] = []
        init(_ callRecords: [CallRecord]) { self.callRecords = callRecords }
        func next() throws -> CallRecord? { return callRecords.popFirst() }
    }

    var mockCallRecords: [CallRecord] = []

    private func applyOrdering(_ mockCallRecords: [CallRecord], ordering: FetchOrdering) -> [CallRecord] {
        switch ordering {
        case .descending:
            return mockCallRecords.sorted { $0.callBeganTimestamp > $1.callBeganTimestamp }
        case .descendingBefore(let timestamp):
            return mockCallRecords.filter { $0.callBeganTimestamp < timestamp }.sorted { $0.callBeganTimestamp > $1.callBeganTimestamp }
        case .ascendingAfter(let timestamp):
            return mockCallRecords.filter { $0.callBeganTimestamp > timestamp }.sorted { $0.callBeganTimestamp < $1.callBeganTimestamp }
        }
    }

    func fetchCursor(ordering: FetchOrdering, tx: DBReadTransaction) -> CallRecordCursor? {
        return Cursor(applyOrdering(mockCallRecords, ordering: ordering))
    }

    func fetchCursor(callStatus: CallRecord.CallStatus, ordering: FetchOrdering, tx: DBReadTransaction) -> CallRecordCursor? {
        return Cursor(applyOrdering(mockCallRecords.filter { $0.callStatus == callStatus }, ordering: ordering))
    }

    func fetchCursor(threadRowId: Int64, ordering: FetchOrdering, tx: DBReadTransaction) -> CallRecordCursor? {
        return Cursor(applyOrdering(mockCallRecords.filter { $0.threadRowId == threadRowId }, ordering: ordering))
    }

    func fetchCursor(threadRowId: Int64, callStatus: CallRecord.CallStatus, ordering: FetchOrdering, tx: DBReadTransaction) -> CallRecordCursor? {
        return Cursor(applyOrdering(mockCallRecords.filter { $0.callStatus == callStatus && $0.threadRowId == threadRowId }, ordering: ordering))
    }
}

private class MockFullTextSearchFinder: CallRecordLoader.Shims.FullTextSearchFinder {
    var mockThreadRowIdsForSearchTerm: [String: [Int64]]?

    func findThreadsMatching(searchTerm: String, maxSearchResults: UInt, tx: DBReadTransaction) -> [TSThread] {
        guard let mockThreadRowIdsForSearchTerm else {
            XCTFail("Mock not set!")
            return []
        }

        self.mockThreadRowIdsForSearchTerm = nil

        guard let threadRowIds = mockThreadRowIdsForSearchTerm[searchTerm] else {
            return []
        }

        return threadRowIds.map { threadRowId in
            let thread = TSThread(uniqueId: UUID().uuidString)
            thread.updateRowId(threadRowId)
            return thread
        }
    }
}

private extension Array {
    mutating func popFirst() -> Element? {
        let firstElement = first
        self = Array(dropFirst())
        return firstElement
    }
}
