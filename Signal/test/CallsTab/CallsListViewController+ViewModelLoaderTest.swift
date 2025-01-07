//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

@testable import Signal

final class CallsListViewControllerViewModelLoaderTest: XCTestCase {
    typealias CallViewModel = CallsListViewController.CallViewModel
    typealias ViewModelLoader = CallsListViewController.ViewModelLoader

    private var viewModelLoader: ViewModelLoader!

    private var mockDB: InMemoryDB!
    private var mockCallRecordLoader: MockCallRecordLoader!
    private lazy var callViewModelForCallRecords: ViewModelLoader.CallViewModelForCallRecords! = {
        self.createCallViewModel(callRecords: $0, tx: $1)
    }
    private lazy var fetchCallRecordBlock: ViewModelLoader.FetchCallRecordBlock! = { (callRecordId, tx) -> CallRecord? in
        return self.mockCallRecordLoader.callRecordsById[callRecordId]
    }

    private func createCallViewModel(callRecords: [CallRecord], tx: DBReadTransaction) -> CallViewModel {
        let recipientType: CallViewModel.RecipientType = {
            switch callRecords.first!.callStatus {
            case .individual:
                return .individual(type: .video, contactThread: TSContactThread(
                    contactUUID: UUID().uuidString,
                    contactPhoneNumber: nil
                ))
            case .group:
                return .groupThread(groupId: Data(count: 32))
            case .callLink:
                fatalError()
            }
        }()

        let direction: CallViewModel.Direction = {
            if callRecords.first!.callStatus.isMissedCall {
                return .missed
            }

            switch callRecords.first!.callDirection {
            case .incoming: return .incoming
            case .outgoing: return .outgoing
            }
        }()

        return CallViewModel(
            reference: .callRecords(oldestId: callRecords.last!.id),
            callRecords: callRecords,
            title: "Hey, I just met you, and this is crazy, but here's my number, so call me maybe?",
            recipientType: recipientType,
            direction: direction,
            medium: .video,
            state: .inactive
        )
    }

    private func setUpViewModelLoader(
        viewModelPageSize: Int,
        maxCoalescedCallsInOneViewModel: Int = 100
    ) {
        viewModelLoader = ViewModelLoader(
            callLinkStore: CallLinkRecordStoreImpl(),
            callRecordLoader: mockCallRecordLoader,
            callViewModelForCallRecords: { self.callViewModelForCallRecords($0, $1) },
            callViewModelForUpcomingCallLink: { _, _ in owsFail("Not implemented.") },
            fetchCallRecordBlock: { self.fetchCallRecordBlock($0, $1) },
            shouldFetchUpcomingCallLinks: false,
            viewModelPageSize: viewModelPageSize,
            maxCoalescedCallsInOneViewModel: maxCoalescedCallsInOneViewModel
        )
    }

    private var loadedCallIds: [[UInt64]] {
        return (0..<viewModelLoader.totalCount).map {
            return viewModelLoader.modelReferences(at: $0).callRecordRowIds.map(\.callId)
        }
    }

    private func loadMore(direction: ViewModelLoader.LoadDirection) -> Bool {
        return mockDB.read { tx in
            let (hasChanges, _) = viewModelLoader.loadCallHistoryItemReferences(direction: direction, tx: tx)
            return hasChanges
        }
    }

    private func assertCached(loadedViewModelReferenceIndices: Range<Int>) {
        // Cache the default block, since we're gonna override it.
        let defaultFetchCallRecordBlock = fetchCallRecordBlock!

        var fetchedCallIds = [UInt64]()
        fetchCallRecordBlock = { callRecordId, tx -> CallRecord? in
            fetchedCallIds.append(callRecordId.callId)
            return defaultFetchCallRecordBlock(callRecordId, tx)
        }

        for index in loadedViewModelReferenceIndices {
            XCTAssertNotNil(
                viewModelLoader.viewModel(at: index, sneakyTransactionDb: mockDB),
                "Missing cached view model for index \(index)!"
            )
        }

        XCTAssertEqual(fetchedCallIds, [])
    }

    private func assertCachedCallIds(
        _ callIds: [UInt64],
        atLoadedViewModelReferenceIndex loadedViewModelReferenceIndex: Int
    ) {
        guard let cachedViewModel = viewModelLoader.viewModel(at: loadedViewModelReferenceIndex, sneakyTransactionDb: mockDB) else {
            XCTFail("Missing cached view model entirely!")
            return
        }

        XCTAssertEqual(callIds, cachedViewModel.callRecords.map { $0.callId })
    }

    private func assertLoadedCallIds(_ callIdsByReference: [UInt64]...) {
        var callIdsByReference = callIdsByReference

        for actualCallIds in loadedCallIds {
            let expectedCallIds = callIdsByReference.popFirst()
            XCTAssertEqual(expectedCallIds, actualCallIds)
        }
        XCTAssertTrue(callIdsByReference.isEmpty)
    }

    override func setUp() {
        mockDB = InMemoryDB()
        mockCallRecordLoader = MockCallRecordLoader()
    }

    func testLoadingNoCallRecords() {
        setUpViewModelLoader(viewModelPageSize: 10)

        XCTAssertFalse(loadMore(direction: .older))
        XCTAssertTrue(viewModelLoader.viewModelReferences().isEmpty)

        XCTAssertFalse(loadMore(direction: .newer))
        XCTAssertTrue(viewModelLoader.viewModelReferences().isEmpty)
    }

    func testBasicCoalescingRules() {
        setUpViewModelLoader(viewModelPageSize: 100)

        var timestamp = SequentialTimestampBuilder()

        mockCallRecordLoader.callRecords = [
            /// Yes coalescing if inside time window, same thread, same direction, same missed-call status.
            .fixture(callId: 99, timestamp: timestamp.uncoalescable(), threadRowId: 0, direction: .incoming, status: .group(.ringingMissed)),
            .fixture(callId: 98, timestamp: timestamp.coalescable(), threadRowId: 0, direction: .incoming, status: .group(.ringingMissedNotificationProfile)),
            .fixture(callId: 97, timestamp: timestamp.coalescable(), threadRowId: 0, direction: .incoming, status: .group(.ringingMissedNotificationProfile)),
            .fixture(callId: 96, timestamp: timestamp.coalescable(), threadRowId: 0, direction: .incoming, status: .group(.ringingMissed)),
            .fixture(callId: 95, timestamp: timestamp.coalescable(), threadRowId: 1, direction: .outgoing, status: .group(.ringingAccepted)),
            .fixture(callId: 94, timestamp: timestamp.coalescable(), threadRowId: 1, direction: .outgoing, status: .group(.ringingAccepted)),
            .fixture(callId: 93, timestamp: timestamp.coalescable(), threadRowId: 1, direction: .outgoing, status: .group(.ringingAccepted)),
            .fixture(callId: 92, timestamp: timestamp.coalescable(), threadRowId: 1, direction: .outgoing, status: .group(.ringingAccepted)),

            /// No coalescing outside of the time window.
            .fixture(callId: 0, timestamp: timestamp.uncoalescable(), threadRowId: 0, direction: .incoming, status: .group(.joined)),
            .fixture(callId: 1, timestamp: timestamp.uncoalescable(), threadRowId: 0, direction: .incoming, status: .group(.joined)),

            /// No coalescing across threads.
            .fixture(callId: 2, timestamp: timestamp.uncoalescable(), threadRowId: 1, direction: .incoming, status: .group(.joined)),
            .fixture(callId: 3, timestamp: timestamp.coalescable(), threadRowId: 2, direction: .incoming, status: .group(.joined)),

            /// No coalescing across direction.
            .fixture(callId: 4, timestamp: timestamp.uncoalescable(), threadRowId: 1, direction: .incoming, status: .group(.joined)),
            .fixture(callId: 5, timestamp: timestamp.coalescable(), threadRowId: 2, direction: .incoming, status: .group(.joined)),

            /// No coalescing across missed-call status.
            .fixture(callId: 6, timestamp: timestamp.uncoalescable(), threadRowId: 3, direction: .incoming, status: .individual(.incomingMissed)),
            .fixture(callId: 7, timestamp: timestamp.coalescable(), threadRowId: 3, direction: .incoming, status: .individual(.accepted)),

            /// No coalsecing if there's an intervening call.
            .fixture(callId: 8, timestamp: timestamp.uncoalescable(), threadRowId: 3, direction: .incoming, status: .individual(.incomingMissed)),
            .fixture(callId: 9, timestamp: timestamp.coalescable(), threadRowId: 3, direction: .incoming, status: .individual(.accepted)),
            .fixture(callId: 10, timestamp: timestamp.coalescable(), threadRowId: 3, direction: .incoming, status: .individual(.incomingMissed)),
        ]

        XCTAssertTrue(loadMore(direction: .older))
        XCTAssertEqual(loadedCallIds, [
            [99, 98, 97, 96],
            [95, 94, 93, 92],
            [0], [1], [2], [3], [4], [5], [6], [7], [8], [9], [10],
        ])
    }

    func testScrollingBackAndForthThroughMultiplePages() {
        var timestamp = SequentialTimestampBuilder()

        /// Add 9 call view models' worth of call records to the mock. The 0th,
        /// 3rd, and 6th will be a coalesced call view model.
        mockCallRecordLoader.callRecords = (1...9).flatMap { idx -> [CallRecord] in
            if idx % 3 == 0 {
                /// Add a coalescable pair of calls.
                return [
                    .fixture(callId: UInt64(idx), timestamp: timestamp.uncoalescable(), threadRowId: Int64(idx)),
                    .fixture(callId: UInt64(idx * 1000), timestamp: timestamp.coalescable(), threadRowId: Int64(idx))
                ]
            } else {
                /// Add a single uncoalescable call.
                return [
                    .fixture(callId: UInt64(idx), timestamp: timestamp.uncoalescable(), threadRowId: Int64(idx))
                ]
            }
        }

        setUpViewModelLoader(viewModelPageSize: 3)

        /// Scroll backwards three pages, thereby dropping the first-loaded view
        /// models.

        XCTAssertTrue(loadMore(direction: .older))
        assertLoadedCallIds([1], [2], [3, 3000])
        assertCachedCallIds([1], atLoadedViewModelReferenceIndex: 0)
        assertCached(loadedViewModelReferenceIndices: 0..<3)
        assertCachedCallIds([2], atLoadedViewModelReferenceIndex: 1)
        assertCachedCallIds([3, 3000], atLoadedViewModelReferenceIndex: 2)

        XCTAssertTrue(loadMore(direction: .older))
        assertLoadedCallIds([1], [2], [3, 3000], [4], [5], [6, 6000])
        assertCachedCallIds([1], atLoadedViewModelReferenceIndex: 0)
        assertCachedCallIds([2], atLoadedViewModelReferenceIndex: 1)
        assertCachedCallIds([3, 3000], atLoadedViewModelReferenceIndex: 2)
        assertCachedCallIds([4], atLoadedViewModelReferenceIndex: 3)
        assertCached(loadedViewModelReferenceIndices: 0..<6)
        assertCachedCallIds([5], atLoadedViewModelReferenceIndex: 4)
        assertCachedCallIds([6, 6000], atLoadedViewModelReferenceIndex: 5)

        XCTAssertTrue(loadMore(direction: .older))
        assertLoadedCallIds([1], [2], [3, 3000], [4], [5], [6, 6000], [7], [8], [9, 9000])
        assertCachedCallIds([4], atLoadedViewModelReferenceIndex: 3)
        assertCachedCallIds([5], atLoadedViewModelReferenceIndex: 4)
        assertCachedCallIds([6, 6000], atLoadedViewModelReferenceIndex: 5)
        assertCachedCallIds([7], atLoadedViewModelReferenceIndex: 6)
        assertCached(loadedViewModelReferenceIndices: 3..<9)
        assertCachedCallIds([8], atLoadedViewModelReferenceIndex: 7)
        assertCachedCallIds([9, 9000], atLoadedViewModelReferenceIndex: 8)

        XCTAssertFalse(loadMore(direction: .older))
        assertLoadedCallIds([1], [2], [3, 3000], [4], [5], [6, 6000], [7], [8], [9, 9000])
        assertCached(loadedViewModelReferenceIndices: 3..<9)
        assertCachedCallIds([4], atLoadedViewModelReferenceIndex: 3)
        assertCachedCallIds([5], atLoadedViewModelReferenceIndex: 4)
        assertCachedCallIds([6, 6000], atLoadedViewModelReferenceIndex: 5)
        assertCachedCallIds([7], atLoadedViewModelReferenceIndex: 6)
        assertCachedCallIds([8], atLoadedViewModelReferenceIndex: 7)
        assertCachedCallIds([9, 9000], atLoadedViewModelReferenceIndex: 8)

        /// Now, scroll forwards, thereby dropping the last-loaded view models.
        /// These loads won't load any brand-new calls, and will instead
        /// rehydrate already-loaded view model references.
        XCTAssertFalse(loadMore(direction: .newer))
        assertLoadedCallIds([1], [2], [3, 3000], [4], [5], [6, 6000], [7], [8], [9, 9000])
        assertCachedCallIds([1], atLoadedViewModelReferenceIndex: 0)
        assertCached(loadedViewModelReferenceIndices: 0..<6)
        assertCachedCallIds([2], atLoadedViewModelReferenceIndex: 1)
        assertCachedCallIds([3, 3000], atLoadedViewModelReferenceIndex: 2)
        assertCachedCallIds([4], atLoadedViewModelReferenceIndex: 3)
        assertCachedCallIds([5], atLoadedViewModelReferenceIndex: 4)
        assertCachedCallIds([6, 6000], atLoadedViewModelReferenceIndex: 5)

        XCTAssertFalse(loadMore(direction: .newer))
        assertLoadedCallIds([1], [2], [3, 3000], [4], [5], [6, 6000], [7], [8], [9, 9000])
        assertCached(loadedViewModelReferenceIndices: 0..<6)
        assertCachedCallIds([1], atLoadedViewModelReferenceIndex: 0)
        assertCachedCallIds([2], atLoadedViewModelReferenceIndex: 1)
        assertCachedCallIds([3, 3000], atLoadedViewModelReferenceIndex: 2)
        assertCachedCallIds([4], atLoadedViewModelReferenceIndex: 3)
        assertCachedCallIds([5], atLoadedViewModelReferenceIndex: 4)
        assertCachedCallIds([6, 6000], atLoadedViewModelReferenceIndex: 5)
    }

    /// Load a ton of calls, such that the cached view models have long ago
    /// dropped the first-loaded calls, and then simulate a super-fast scroll to
    /// the top, then the bottom, by loading until the first, then the last,
    /// calls are cached.
    func testLoadUntilCached() {
        setUpViewModelLoader(viewModelPageSize: 100)
        var timestamp = SequentialTimestampBuilder()

        mockCallRecordLoader.callRecords = (1...5000).flatMap { idx -> [CallRecord] in
            if idx % 4 == 0 {
                /// Add a coalescable triplet of calls.
                return [
                    .fixture(callId: UInt64(idx), timestamp: timestamp.uncoalescable(), threadRowId: Int64(idx)),
                    .fixture(callId: UInt64(idx + 5000), timestamp: timestamp.coalescable(), threadRowId: Int64(idx)),
                    .fixture(callId: UInt64(idx + 10000), timestamp: timestamp.coalescable(), threadRowId: Int64(idx)),
                ]
            } else {
                /// Add a single uncoalescable call.
                return [
                    .fixture(callId: UInt64(idx), timestamp: timestamp.uncoalescable(), threadRowId: Int64(idx))
                ]
            }
        }

        for _ in 0..<50 {
            XCTAssertTrue(loadMore(direction: .older))
        }
        XCTAssertFalse(loadMore(direction: .older))

        assertCachedCallIds([5000, 10000, 15000], atLoadedViewModelReferenceIndex: 4999)
        assertCached(loadedViewModelReferenceIndices: 4900..<5000)
        assertCachedCallIds([1], atLoadedViewModelReferenceIndex: 0)
        assertCached(loadedViewModelReferenceIndices: 0..<100)
        assertCachedCallIds([5000, 10000, 15000], atLoadedViewModelReferenceIndex: 4999)
        assertCached(loadedViewModelReferenceIndices: 4900..<5000)
    }

    func testNewerCallInserted() {
        setUpViewModelLoader(viewModelPageSize: 2)
        var timestamp = SequentialTimestampBuilder()

        let timestampToInsert0 = timestamp.uncoalescable()
        let timestampToInsert1 = timestamp.coalescable()
        let timestampToInsert2 = timestamp.coalescable()

        mockCallRecordLoader.callRecords = [
            .fixture(callId: 3, timestamp: timestamp.coalescable()),
            .fixture(callId: 4, timestamp: timestamp.coalescable()),
            .fixture(callId: 5, timestamp: timestamp.coalescable()),
            .fixture(callId: 6, timestamp: timestamp.uncoalescable())
        ]

        XCTAssertTrue(loadMore(direction: .newer))
        assertLoadedCallIds([3, 4, 5], [6])
        assertCachedCallIds([3, 4, 5], atLoadedViewModelReferenceIndex: 0)
        assertCached(loadedViewModelReferenceIndices: 0..<2)
        assertCachedCallIds([6], atLoadedViewModelReferenceIndex: 1)

        XCTAssertFalse(loadMore(direction: .newer))
        assertLoadedCallIds([3, 4, 5], [6])
        assertCached(loadedViewModelReferenceIndices: 0..<2)
        assertCachedCallIds([3, 4, 5], atLoadedViewModelReferenceIndex: 0)
        assertCachedCallIds([6], atLoadedViewModelReferenceIndex: 1)

        /// If we insert a single new call record that can be coalesced into the
        /// existing first view model, it should be merged into the existing
        /// view model.
        mockCallRecordLoader.callRecords.insert(.fixture(callId: 2, timestamp: timestampToInsert2), at: 0)
        XCTAssertTrue(loadMore(direction: .newer))
        assertLoadedCallIds([2, 3, 4, 5], [6])
        assertCachedCallIds([2, 3, 4, 5], atLoadedViewModelReferenceIndex: 0)
        assertCached(loadedViewModelReferenceIndices: 0..<2)
        assertCachedCallIds([6], atLoadedViewModelReferenceIndex: 1)

        mockCallRecordLoader.callRecords.insert(.fixture(callId: 1, timestamp: timestampToInsert1), at: 0)
        mockCallRecordLoader.callRecords.insert(.fixture(callId: 0, timestamp: timestampToInsert0), at: 0)
        XCTAssertTrue(loadMore(direction: .newer))
        assertLoadedCallIds([0], [1, 2, 3, 4, 5], [6])
        assertCachedCallIds([0], atLoadedViewModelReferenceIndex: 0)
        assertCached(loadedViewModelReferenceIndices: 0..<3)
        assertCachedCallIds([1, 2, 3, 4, 5], atLoadedViewModelReferenceIndex: 1)
        assertCachedCallIds([6], atLoadedViewModelReferenceIndex: 2)

        /// And now, finally, there's nothing new to load.
        XCTAssertFalse(loadMore(direction: .newer))
        assertLoadedCallIds([0], [1, 2, 3, 4, 5], [6])
        assertCached(loadedViewModelReferenceIndices: 0..<3)
        assertCachedCallIds([0], atLoadedViewModelReferenceIndex: 0)
        assertCachedCallIds([1, 2, 3, 4, 5], atLoadedViewModelReferenceIndex: 1)
        assertCachedCallIds([6], atLoadedViewModelReferenceIndex: 2)
    }

    func testRefreshingViewModels() {
        // Cache the default block, since we're gonna override it.
        let defaultFetchCallRecordBlock = fetchCallRecordBlock!

        setUpViewModelLoader(viewModelPageSize: 2)
        var timestamp = SequentialTimestampBuilder()

        let earlierTimestamp = timestamp.uncoalescable()

        mockCallRecordLoader.callRecords = [
            .fixture(callId: 0, timestamp: timestamp.uncoalescable()),
            .fixture(callId: 1, timestamp: timestamp.coalescable()),

            .fixture(callId: 2, timestamp: timestamp.uncoalescable()),
        ]

        XCTAssertTrue(loadMore(direction: .older))
        assertLoadedCallIds([0, 1], [2])
        assertCachedCallIds([0, 1], atLoadedViewModelReferenceIndex: 0)
        assertCached(loadedViewModelReferenceIndices: 0..<2)
        assertCachedCallIds([2], atLoadedViewModelReferenceIndex: 1)

        var fetchedCallIds = [UInt64]()
        fetchCallRecordBlock = { callRecordId, tx -> CallRecord? in
            fetchedCallIds.append(callRecordId.callId)
            return defaultFetchCallRecordBlock(callRecordId, tx)
        }

        let firstViewModelIds: [CallRecord.ID] = [
            .fixture(callId: 0),
            .fixture(callId: 1),
        ]

        for callRecordId in firstViewModelIds {
            /// Asking to recreate for either call record ID in a coalesced
            /// view model should re-fetch all the calls in the view model.
            XCTAssertEqual(
                viewModelLoader.invalidate(callLinkRowIds: [], callRecordIds: [callRecordId]),
                [.callRecords(oldestId: .fixture(callId: 1))]
            )
            assertCachedCallIds([0, 1], atLoadedViewModelReferenceIndex: 0)
            XCTAssertEqual(fetchedCallIds, [0, 1])
            fetchedCallIds = []
        }

        XCTAssertEqual(
            viewModelLoader.invalidate(callLinkRowIds: [], callRecordIds: [.fixture(callId: 2)]),
            [.callRecords(oldestId: .fixture(callId: 2))]
        )
        assertCachedCallIds([2], atLoadedViewModelReferenceIndex: 1)
        XCTAssertEqual(fetchedCallIds, [2])
        fetchedCallIds = []

        // Insert an earlier record that doesn't have a CallViewModel.
        mockCallRecordLoader.callRecords.insert(.fixture(callId: 3, timestamp: earlierTimestamp), at: 0)
        XCTAssertTrue(loadMore(direction: .newer))

        /// If we ask to recreate for a call record ID that's not part of
        /// any cached view models, it should be marked for reloading.
        fetchCallRecordBlock = { (_, _) in XCTFail("Unexpectedly tried to fetch!"); return nil }
        XCTAssertEqual(
            viewModelLoader.invalidate(callLinkRowIds: [], callRecordIds: [.fixture(callId: 3)]),
            [.callRecords(oldestId: .fixture(callId: 3))]
        )
        XCTAssertEqual(fetchedCallIds, [])
    }

    func testDroppingViewModels() {
        setUpViewModelLoader(viewModelPageSize: 6)
        var timestamp = SequentialTimestampBuilder()

        mockCallRecordLoader.callRecords = [
            /// We won't delete this one, but it'll have been paged out.
            .fixture(callId: 99, timestamp: timestamp.uncoalescable()),

            /// We'll page this out before deleting it.
            .fixture(callId: 98, timestamp: timestamp.uncoalescable()),

            /// We'll have this paged in and won't delete it; see the next one.
            .fixture(callId: 0, timestamp: timestamp.uncoalescable()),

            /// We'll delete this (while having it paged in), which will
            /// technically make `callId: 0`  coalescable with
            /// `callIds: [1, 2, 3]` below, since there won't be any intervening
            /// calls. However, deleting does not prompt re-coalescing.
            .fixture(callId: 97, timestamp: timestamp.coalescable(), threadRowId: 1),

            /// We'll delete the primary call record from this view model.
            .fixture(callId: 1, timestamp: timestamp.coalescable()),
            .fixture(callId: 2, timestamp: timestamp.coalescable()),
            .fixture(callId: 3, timestamp: timestamp.coalescable()),

            /// We'll delete a coalesced call record from this view model.
            .fixture(callId: 4, timestamp: timestamp.uncoalescable()),
            .fixture(callId: 5, timestamp: timestamp.coalescable()),
            .fixture(callId: 6, timestamp: timestamp.coalescable()),

            /// We'll delete all the call records from this view model.
            .fixture(callId: 7, timestamp: timestamp.uncoalescable()),
            .fixture(callId: 8, timestamp: timestamp.coalescable()),
            .fixture(callId: 9, timestamp: timestamp.coalescable()),

            /// We won't delete this one :)
            .fixture(callId: 10, timestamp: timestamp.uncoalescable()),
            .fixture(callId: 11, timestamp: timestamp.coalescable()),
        ]

        XCTAssertTrue(loadMore(direction: .older))
        assertLoadedCallIds([99], [98], [0], [97], [1, 2, 3], [4, 5, 6])
        assertCachedCallIds([99], atLoadedViewModelReferenceIndex: 0)
        assertCached(loadedViewModelReferenceIndices: 0..<6)

        XCTAssertTrue(loadMore(direction: .older))
        assertLoadedCallIds([99], [98], [0], [97], [1, 2, 3], [4, 5, 6], [7, 8, 9], [10, 11])
        assertCachedCallIds([7, 8, 9], atLoadedViewModelReferenceIndex: 6)
        assertCached(loadedViewModelReferenceIndices: 2..<8)

        mockDB.read { tx in
            viewModelLoader.dropCalls(
                matching: [
                    .fixture(callId: 98),
                    .fixture(callId: 97, threadRowId: 1),
                    .fixture(callId: 1),
                    .fixture(callId: 5),
                    .fixture(callId: 7),
                    .fixture(callId: 8),
                    .fixture(callId: 9),
                ],
                tx: tx
            )
        }

        assertLoadedCallIds(
            [99],
            [0],
            [2, 3],
            [4, 6],
            [10, 11]
        )
        assertCached(loadedViewModelReferenceIndices: 0..<2)
        assertCached(loadedViewModelReferenceIndices: 4..<5)
        assertCachedCallIds([0], atLoadedViewModelReferenceIndex: 1)
        assertCachedCallIds([2, 3], atLoadedViewModelReferenceIndex: 2)
        assertCached(loadedViewModelReferenceIndices: 0..<5)
        assertCachedCallIds([4, 6], atLoadedViewModelReferenceIndex: 3)
        assertCachedCallIds([10, 11], atLoadedViewModelReferenceIndex: 4)
    }

    func testMaxCoalescedCallsInOneViewModel() {
        setUpViewModelLoader(viewModelPageSize: 3, maxCoalescedCallsInOneViewModel: 3)
        var timestamp = SequentialTimestampBuilder()

        mockCallRecordLoader.callRecords = [
            .fixture(callId: 1, timestamp: timestamp.uncoalescable()),
            .fixture(callId: 2, timestamp: timestamp.coalescable()),
            .fixture(callId: 3, timestamp: timestamp.coalescable()),
            .fixture(callId: 4, timestamp: timestamp.coalescable()),
            .fixture(callId: 5, timestamp: timestamp.coalescable()),
            .fixture(callId: 6, timestamp: timestamp.coalescable()),
            .fixture(callId: 7, timestamp: timestamp.coalescable()),
        ]

        XCTAssertTrue(loadMore(direction: .older))
        assertLoadedCallIds([1, 2, 3], [4, 5, 6], [7])
    }
}

// MARK: - Mocks

private struct SequentialTimestampBuilder {
    private var current: UInt64 = Date().ows_millisecondsSince1970

    /// Generates a timestamp that is earlier than and coalescable with the
    /// previously-generated one.
    mutating func coalescable() -> UInt64 {
        current -= 1
        return current
    }

    /// Generates a timestamp earlier that is than and not coalescable with the
    /// previously-generated one.
    mutating func uncoalescable() -> UInt64 {
        let millisecondsOutsideCoalesceWindow = 4 * 1000 * UInt64(kHourInterval) + 1
        current -= millisecondsOutsideCoalesceWindow
        return current
    }
}

private extension CallRecord.ID {
    static func fixture(callId: UInt64, threadRowId: Int64 = 0) -> CallRecord.ID {
        return CallRecord.ID(
            conversationId: .thread(threadRowId: threadRowId),
            callId: callId
        )
    }
}

private extension CallRecord {
    static func fixture(
        callId: UInt64,
        timestamp: UInt64,
        callType: CallRecord.CallType? = nil,
        threadRowId: Int64 = 0,
        direction: CallRecord.CallDirection = .incoming,
        status: CallRecord.CallStatus = .group(.joined)
    ) -> CallRecord {
        return CallRecord(
            callId: callId,
            interactionRowId: 0,
            threadRowId: threadRowId,
            callType: callType ?? {
                switch status {
                case .individual: return .audioCall
                case .group: return .groupCall
                case .callLink: return .adHocCall
                }
            }(),
            callDirection: direction,
            callStatus: status,
            callBeganTimestamp: timestamp
        )
    }
}

private class MockCallRecordLoader: CallRecordLoader {
    private class Cursor: CallRecordCursor {
        private var callRecords: [CallRecord] = []

        init(_ callRecords: [CallRecord], direction: LoadDirection) {
            self.callRecords = callRecords
        }

        func next() throws -> CallRecord? { return callRecords.popFirst() }
    }

    var callRecords: [CallRecord] {
        get { callRecordsDescending }
        set {
            callRecordsDescending = newValue.sorted { $0.callBeganTimestamp > $1.callBeganTimestamp }
            callRecordsAscending = newValue.sorted { $0.callBeganTimestamp < $1.callBeganTimestamp }
            callRecordsById = Dictionary(
                newValue.map { ($0.id, $0) },
                uniquingKeysWith: { new, _ in return new}
            )
        }
    }

    private(set) var callRecordsById: [CallRecord.ID: CallRecord] = [:]
    private var callRecordsDescending: [CallRecord] = []
    private var callRecordsAscending: [CallRecord] = []

    private func applyLoadDirection(_ direction: LoadDirection) -> [CallRecord] {
        switch direction {
        case .olderThan(oldestCallTimestamp: nil):
            return callRecordsDescending
        case .olderThan(.some(let oldestCallTimestamp)):
            return callRecordsDescending.filter { $0.callBeganTimestamp < oldestCallTimestamp }
        case .newerThan(let newestCallTimestamp):
            return callRecordsAscending.filter { $0.callBeganTimestamp > newestCallTimestamp }
        }
    }

    func loadCallRecords(loadDirection: LoadDirection, tx: DBReadTransaction) -> CallRecordCursor {
        return Cursor(applyLoadDirection(loadDirection), direction: loadDirection)
    }
}
