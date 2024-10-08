//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import XCTest

@testable import Signal

final class CallRecordLoaderTest: XCTestCase {
    private var mockCallRecordQuerier: MockCallRecordQuerier!

    private var callRecordLoader: CallRecordLoaderImpl!

    override func setUp() {
        mockCallRecordQuerier = MockCallRecordQuerier()
    }

    private func setupCallRecordLoader(
        onlyLoadMissedCalls: Bool = false,
        onlyMatchThreadRowIds: [Int64]? = nil
    ) {
        callRecordLoader = CallRecordLoaderImpl(
            callRecordQuerier: mockCallRecordQuerier,
            configuration: CallRecordLoaderImpl.Configuration(
                onlyLoadMissedCalls: onlyLoadMissedCalls,
                onlyMatchThreadRowIds: onlyMatchThreadRowIds
            )
        )
    }

    private func loadRecords(loadDirection: CallRecordLoader.LoadDirection) -> [UInt64] {
        return InMemoryDB().read { tx in
            try! callRecordLoader
                .loadCallRecords(loadDirection: loadDirection, tx: tx)
                .drain(maxResults: 3)
                .map { $0.callId }
        }
    }

    func testNothingMatching() {
        mockCallRecordQuerier.mockCallRecords = [
            .fixture(callId: 1), .fixture(callId: 2)
        ]

        setupCallRecordLoader(onlyMatchThreadRowIds: [1])
        XCTAssertEqual([], loadRecords(loadDirection: .olderThan(oldestCallTimestamp: nil)))

        setupCallRecordLoader(onlyLoadMissedCalls: true)
        XCTAssertEqual([], loadRecords(loadDirection: .olderThan(oldestCallTimestamp: nil)))

        setupCallRecordLoader()
        XCTAssertEqual([2, 1], loadRecords(loadDirection: .olderThan(oldestCallTimestamp: nil)))
    }

    // MARK: Older

    func testGetOlderPage() {
        setupCallRecordLoader()

        mockCallRecordQuerier.mockCallRecords = [
            .fixture(callId: 1), .fixture(callId: 2), .fixture(callId: 3),
            .fixture(callId: 4), .fixture(callId: 5), .fixture(callId: 6),
            .fixture(callId: 7)
        ]

        XCTAssertEqual([7, 6, 5], loadRecords(loadDirection: .olderThan(oldestCallTimestamp: nil)))
        XCTAssertEqual([4, 3, 2], loadRecords(loadDirection: .olderThan(oldestCallTimestamp: 5)))
        XCTAssertEqual([1], loadRecords(loadDirection: .olderThan(oldestCallTimestamp: 2)))
        XCTAssertEqual([], loadRecords(loadDirection: .olderThan(oldestCallTimestamp: 1)))
    }

    func testGetOlderPageSearching() {
        setupCallRecordLoader(onlyMatchThreadRowIds: [1, 2])

        mockCallRecordQuerier.mockCallRecords = [
            .fixture(callId: 1),
            .fixture(callId: 2, threadRowId: 1), .fixture(callId: 3, threadRowId: 2),
            .fixture(callId: 4),
            .fixture(callId: 5, threadRowId: 2), .fixture(callId: 6, threadRowId: 1),
            .fixture(callId: 7),
        ]

        XCTAssertEqual([6, 5, 3], loadRecords(loadDirection: .olderThan(oldestCallTimestamp: nil)))
        XCTAssertEqual([2], loadRecords(loadDirection: .olderThan(oldestCallTimestamp: 3)))
        XCTAssertEqual([], loadRecords(loadDirection: .olderThan(oldestCallTimestamp: 2)))
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
            .fixture(callId: 8, threadRowId: 1, callStatus: .group(.ringingMissedNotificationProfile)),
            .fixture(callId: 9),
        ]

        XCTAssertEqual([8, 7, 6], loadRecords(loadDirection: .olderThan(oldestCallTimestamp: nil)))
        XCTAssertEqual([4, 2], loadRecords(loadDirection: .olderThan(oldestCallTimestamp: 6)))
        XCTAssertEqual([], loadRecords(loadDirection: .olderThan(oldestCallTimestamp: 2)))
    }

    func testGetOlderPageForMissedSearching() {
        setupCallRecordLoader(onlyLoadMissedCalls: true, onlyMatchThreadRowIds: [1, 2])

        mockCallRecordQuerier.mockCallRecords = [
            .fixture(callId: 1),
            .fixture(callId: 2, threadRowId: 1, callStatus: .group(.ringingMissed)),
            .fixture(callId: 3, threadRowId: 1),
            .fixture(callId: 4, threadRowId: 1, callStatus: .group(.ringingMissedNotificationProfile)),
            .fixture(callId: 5, threadRowId: 2, callStatus: .individual(.incomingMissed)),
            .fixture(callId: 6, threadRowId: 1, callStatus: .group(.ringingMissed)),
            .fixture(callId: 7, threadRowId: 1, callStatus: .group(.joined)),
            .fixture(callId: 8, threadRowId: 2, callStatus: .individual(.accepted)),
            .fixture(callId: 9, threadRowId: 2, callStatus: .individual(.incomingMissed)),
            .fixture(callId: 10, threadRowId: 2, callStatus: .individual(.incomingMissed)),
            .fixture(callId: 11, threadRowId: 1, callStatus: .group(.ringingMissedNotificationProfile)),
            .fixture(callId: 12),
            .fixture(callId: 13, callStatus: .group(.ringingMissed)),
        ]

        XCTAssertEqual([11, 10, 9], loadRecords(loadDirection: .olderThan(oldestCallTimestamp: nil)))
        XCTAssertEqual([6, 5, 4], loadRecords(loadDirection: .olderThan(oldestCallTimestamp: 9)))
        XCTAssertEqual([2], loadRecords(loadDirection: .olderThan(oldestCallTimestamp: 4)))
        XCTAssertEqual([], loadRecords(loadDirection: .olderThan(oldestCallTimestamp: 2)))
    }

    // MARK: Newer

    func testGetNewerPage() {
        setupCallRecordLoader()

        mockCallRecordQuerier.mockCallRecords = [
            .fixture(callId: 1), .fixture(callId: 2), .fixture(callId: 3),
            .fixture(callId: 4), .fixture(callId: 5), .fixture(callId: 6),
            .fixture(callId: 7)
        ]

        XCTAssertEqual([1, 2, 3], loadRecords(loadDirection: .newerThan(newestCallTimestamp: 0)))
        XCTAssertEqual([4, 5, 6], loadRecords(loadDirection: .newerThan(newestCallTimestamp: 3)))
        XCTAssertEqual([7], loadRecords(loadDirection: .newerThan(newestCallTimestamp: 6)))
        XCTAssertEqual([], loadRecords(loadDirection: .newerThan(newestCallTimestamp: 7)))
    }

    func testGetNewerPageSearching() {
        setupCallRecordLoader(onlyMatchThreadRowIds: [1, 2])

        mockCallRecordQuerier.mockCallRecords = [
            .fixture(callId: 1),
            .fixture(callId: 2, threadRowId: 1), .fixture(callId: 3, threadRowId: 2),
            .fixture(callId: 4),
            .fixture(callId: 5, threadRowId: 2), .fixture(callId: 6, threadRowId: 1),
            .fixture(callId: 7),
        ]

        XCTAssertEqual([2, 3, 5], loadRecords(loadDirection: .newerThan(newestCallTimestamp: 0)))
        XCTAssertEqual([6], loadRecords(loadDirection: .newerThan(newestCallTimestamp: 5)))
        XCTAssertEqual([], loadRecords(loadDirection: .newerThan(newestCallTimestamp: 6)))
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
            .fixture(callId: 8, threadRowId: 1, callStatus: .group(.ringingMissedNotificationProfile)),
            .fixture(callId: 9),
        ]

        XCTAssertEqual([2, 4, 6], loadRecords(loadDirection: .newerThan(newestCallTimestamp: 0)))
        XCTAssertEqual([7, 8], loadRecords(loadDirection: .newerThan(newestCallTimestamp: 6)))
        XCTAssertEqual([], loadRecords(loadDirection: .newerThan(newestCallTimestamp: 8)))
    }

    func testGetNewerPageForMissedSearching() {
        setupCallRecordLoader(onlyLoadMissedCalls: true, onlyMatchThreadRowIds: [1, 2])

        mockCallRecordQuerier.mockCallRecords = [
            .fixture(callId: 1),
            .fixture(callId: 2, threadRowId: 1, callStatus: .group(.ringingMissed)),
            .fixture(callId: 3, threadRowId: 1),
            .fixture(callId: 4, threadRowId: 1, callStatus: .group(.ringingMissedNotificationProfile)),
            .fixture(callId: 5, threadRowId: 2, callStatus: .individual(.incomingMissed)),
            .fixture(callId: 6, threadRowId: 1, callStatus: .group(.ringingMissed)),
            .fixture(callId: 7, threadRowId: 1, callStatus: .group(.joined)),
            .fixture(callId: 8, threadRowId: 2, callStatus: .individual(.accepted)),
            .fixture(callId: 9, threadRowId: 2, callStatus: .individual(.incomingMissed)),
            .fixture(callId: 10, threadRowId: 2, callStatus: .individual(.incomingMissed)),
            .fixture(callId: 11, threadRowId: 1, callStatus: .group(.ringingMissedNotificationProfile)),
            .fixture(callId: 12),
            .fixture(callId: 13, callStatus: .group(.ringingMissed)),
        ]

        XCTAssertEqual([2, 4, 5], loadRecords(loadDirection: .newerThan(newestCallTimestamp: 0)))
        XCTAssertEqual([6, 9, 10], loadRecords(loadDirection: .newerThan(newestCallTimestamp: 5)))
        XCTAssertEqual([11], loadRecords(loadDirection: .newerThan(newestCallTimestamp: 10)))
        XCTAssertEqual([], loadRecords(loadDirection: .newerThan(newestCallTimestamp: 11)))
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
