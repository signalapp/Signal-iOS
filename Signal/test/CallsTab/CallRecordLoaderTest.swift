//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import XCTest

@testable import Signal

final class CallRecordLoaderTest: XCTestCase {
    private var mockCallRecordQuerier: MockCallRecordQuerier!
    private var mockDB: MockDB!
    private var mockFullTextSearchFinder: MockFullTextSearchFinder!

    private var callRecordLoader: CallRecordLoader!

    override func setUp() {
        mockCallRecordQuerier = MockCallRecordQuerier()
        mockDB = MockDB()
        mockFullTextSearchFinder = MockFullTextSearchFinder()
    }

    private func setupCallRecordLoader(
        presetCallRecords: [CallRecord] = [],
        onlyLoadMissedCalls: Bool = false,
        searchTerm: String? = nil
    ) {
        callRecordLoader = CallRecordLoader(
            callRecordQuerier: mockCallRecordQuerier,
            db: mockDB,
            fullTextSearchFinder: mockFullTextSearchFinder,
            configuration: CallRecordLoader.Configuration(
                onlyLoadMissedCalls: onlyLoadMissedCalls,
                searchTerm: searchTerm,
                pageSize: 3
            )
        )

        if !presetCallRecords.isEmpty {
            callRecordLoader.presetCallRecords(presetCallRecords)
        }
    }

    private func assertLoaded(_ callIds: [UInt64]) {
        XCTAssertEqual(callRecordLoader.loadedCallRecords.map { $0.callId }, callIds)
    }

    func testNothingMatching() {
        mockCallRecordQuerier.mockCallRecords = [
            .fixture(callId: 1), .fixture(callId: 2)
        ]

        setupCallRecordLoader(searchTerm: "han solo")
        XCTAssertFalse(callRecordLoader.loadCallRecords(loadDirection: .older))

        setupCallRecordLoader(onlyLoadMissedCalls: true)
        XCTAssertFalse(callRecordLoader.loadCallRecords(loadDirection: .older))

        setupCallRecordLoader()
        XCTAssertTrue(callRecordLoader.loadCallRecords(loadDirection: .older))
        assertLoaded([2, 1])
    }

    // MARK: Older

    func testGetOlderPage() {
        setupCallRecordLoader()

        mockCallRecordQuerier.mockCallRecords = [
            .fixture(callId: 1), .fixture(callId: 2), .fixture(callId: 3),
            .fixture(callId: 4), .fixture(callId: 5), .fixture(callId: 6),
            .fixture(callId: 7)
        ]

        XCTAssertTrue(callRecordLoader.loadCallRecords(loadDirection: .older))
        assertLoaded([7, 6, 5])
        XCTAssertTrue(callRecordLoader.loadCallRecords(loadDirection: .older))
        assertLoaded([7, 6, 5, 4, 3, 2])
        XCTAssertTrue(callRecordLoader.loadCallRecords(loadDirection: .older))
        assertLoaded([7, 6, 5, 4, 3, 2, 1])
        XCTAssertFalse(callRecordLoader.loadCallRecords(loadDirection: .older))
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

        XCTAssertTrue(callRecordLoader.loadCallRecords(loadDirection: .older))
        assertLoaded([6, 5, 3])
        XCTAssertTrue(callRecordLoader.loadCallRecords(loadDirection: .older))
        assertLoaded([6, 5, 3, 2])
        XCTAssertFalse(callRecordLoader.loadCallRecords(loadDirection: .older))
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

        XCTAssertTrue(callRecordLoader.loadCallRecords(loadDirection: .older))
        assertLoaded([8, 7, 6])
        XCTAssertTrue(callRecordLoader.loadCallRecords(loadDirection: .older))
        assertLoaded([8, 7, 6, 4, 2])
        XCTAssertFalse(callRecordLoader.loadCallRecords(loadDirection: .older))
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

        XCTAssertTrue(callRecordLoader.loadCallRecords(loadDirection: .older))
        assertLoaded([11, 10, 9])
        XCTAssertTrue(callRecordLoader.loadCallRecords(loadDirection: .older))
        assertLoaded([11, 10, 9, 6, 5, 4])
        XCTAssertTrue(callRecordLoader.loadCallRecords(loadDirection: .older))
        assertLoaded([11, 10, 9, 6, 5, 4, 2])
        XCTAssertFalse(callRecordLoader.loadCallRecords(loadDirection: .older))
    }

    // MARK: Newer

    func testGetNewerPage() {
        setupCallRecordLoader(presetCallRecords: [.fixture(callId: 0)])

        mockCallRecordQuerier.mockCallRecords = [
            .fixture(callId: 1), .fixture(callId: 2), .fixture(callId: 3),
            .fixture(callId: 4), .fixture(callId: 5), .fixture(callId: 6),
            .fixture(callId: 7)
        ]

        XCTAssertTrue(callRecordLoader.loadCallRecords(loadDirection: .newer))
        assertLoaded([3, 2, 1, 0])
        XCTAssertTrue(callRecordLoader.loadCallRecords(loadDirection: .newer))
        assertLoaded([6, 5, 4, 3, 2, 1, 0])
        XCTAssertTrue(callRecordLoader.loadCallRecords(loadDirection: .newer))
        assertLoaded([7, 6, 5, 4, 3, 2, 1, 0])
        XCTAssertFalse(callRecordLoader.loadCallRecords(loadDirection: .newer))
    }

    func testGetNewerPageSearching() {
        setupCallRecordLoader(presetCallRecords: [.fixture(callId: 0)], searchTerm: "boba fett")

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

        XCTAssertTrue(callRecordLoader.loadCallRecords(loadDirection: .newer))
        assertLoaded([5, 3, 2, 0])
        XCTAssertTrue(callRecordLoader.loadCallRecords(loadDirection: .newer))
        assertLoaded([6, 5, 3, 2, 0])
        XCTAssertFalse(callRecordLoader.loadCallRecords(loadDirection: .newer))
    }

    func testGetNewerPageForMissed() {
        setupCallRecordLoader(presetCallRecords: [.fixture(callId: 0)], onlyLoadMissedCalls: true)

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

        XCTAssertTrue(callRecordLoader.loadCallRecords(loadDirection: .newer))
        assertLoaded([6, 4, 2, 0])
        XCTAssertTrue(callRecordLoader.loadCallRecords(loadDirection: .newer))
        assertLoaded([8, 7, 6, 4, 2, 0])
        XCTAssertFalse(callRecordLoader.loadCallRecords(loadDirection: .newer))
    }

    func testGetNewerPageForMissedSearching() {
        setupCallRecordLoader(presetCallRecords: [.fixture(callId: 0)], onlyLoadMissedCalls: true, searchTerm: "darth vader")

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

        XCTAssertTrue(callRecordLoader.loadCallRecords(loadDirection: .newer))
        assertLoaded([5, 4, 2, 0])
        XCTAssertTrue(callRecordLoader.loadCallRecords(loadDirection: .newer))
        assertLoaded([10, 9, 6, 5, 4, 2, 0])
        XCTAssertTrue(callRecordLoader.loadCallRecords(loadDirection: .newer))
        assertLoaded([11, 10, 9, 6, 5, 4, 2, 0])
        XCTAssertFalse(callRecordLoader.loadCallRecords(loadDirection: .newer))
    }
}

// MARK: - Mocks

private extension CallRecord {
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
    var mockThreadRowIdsForSearchTerm: [String: [Int64]] = [:]

    func findThreadsMatching(searchTerm: String, maxSearchResults: UInt, tx: DBReadTransaction) -> [TSThread] {
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
