//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

extension CallsListViewController {
    /// Responsible for loading call links & call records from disk.
    ///
    /// (For the purposes of this type, a "call history item" is one or more
    /// ``CallRecord``s displayed as a single row in the UI. It might be a
    /// single ``CallRecord`` or multiple that have been coalesced. These may be
    /// individual calls, group calls, or call link calls. An "upcoming call
    /// link" is a call link that's never been used. A "call list item" refers
    /// to either of these.)
    ///
    /// This types loads call list items from disk & exposes an API that
    /// contains everything it has loaded. Internally, it performs caching &
    /// batching of the larger ``CallViewModel``s to reduce memory usage.
    /// However, these details are hidden from its public API.
    ///
    /// (In other words, callers should assume ``CallViewModel``s are available
    /// for every element in ``viewModelReferences()`` because this type handles
    /// batching & cache management behind the scenes.)
    ///
    /// When the on-disk values are changed, callers should invoke the
    /// appropriate methods on this type to fetch/update/remove/apply the
    /// changes. When the user scrolls to the bottom of the list, callers should
    /// request additional items.
    struct ViewModelLoader {
        typealias CallViewModelForUpcomingCallLink = (
            _ callLinkRecord: CallLinkRecord,
            _ tx: DBReadTransaction
        ) -> CallViewModel

        typealias CallViewModelForCallRecords = (
            _ callRecords: [CallRecord],
            _ tx: DBReadTransaction
        ) -> CallViewModel

        typealias FetchCallRecordBlock = (
            _ callRecordId: CallRecord.ID,
            _ tx: DBReadTransaction
        ) -> CallRecord?

        enum LoadDirection {
            case older
            case newer
        }

        private let callLinkStore: any CallLinkRecordStore
        private let callRecordLoader: CallRecordLoader
        private let callViewModelForCallRecords: CallViewModelForCallRecords
        private let callViewModelForUpcomingCallLink: CallViewModelForUpcomingCallLink
        private let fetchCallRecordBlock: FetchCallRecordBlock
        private let shouldFetchUpcomingCallLinks: Bool
        private let viewModelPageSize: Int
        private let maxCoalescedCallsInOneViewModel: Int

        init(
            callLinkStore: any CallLinkRecordStore,
            callRecordLoader: CallRecordLoader,
            callViewModelForCallRecords: @escaping CallViewModelForCallRecords,
            callViewModelForUpcomingCallLink: @escaping CallViewModelForUpcomingCallLink,
            fetchCallRecordBlock: @escaping FetchCallRecordBlock,
            shouldFetchUpcomingCallLinks: Bool,
            viewModelPageSize: Int = 50,
            maxCoalescedCallsInOneViewModel: Int = 50
        ) {
            self.callLinkStore = callLinkStore
            self.callRecordLoader = callRecordLoader
            self.callViewModelForCallRecords = callViewModelForCallRecords
            self.callViewModelForUpcomingCallLink = callViewModelForUpcomingCallLink
            self.fetchCallRecordBlock = fetchCallRecordBlock
            self.shouldFetchUpcomingCallLinks = shouldFetchUpcomingCallLinks
            self.viewModelPageSize = viewModelPageSize
            self.maxCoalescedCallsInOneViewModel = maxCoalescedCallsInOneViewModel

            self.callHistoryItemReferences = []
            self.upcomingCallLinkReferences = []
        }

        // MARK: - References

        private struct UpcomingCallLinkReference {
            let callLinkRoomId: Data

            var viewModel: CallViewModel?
            var viewModelReference: CallViewModel.Reference { .callLink(roomId: callLinkRoomId) }
        }

        private struct CallHistoryItemReference {
            let callRecordIds: NonEmptyArray<CallRecord.ID>

            init(callRecordIds: NonEmptyArray<CallRecord.ID>) {
                self.callRecordIds = callRecordIds
            }

            var viewModel: CallViewModel?
            var viewModelReference: CallViewModel.Reference {
                return .callRecords(primaryId: callRecordIds.first, coalescedIds: Array(callRecordIds.rawValue.dropFirst()))
            }
        }

        private var upcomingCallLinkReferences: [UpcomingCallLinkReference]

        /// The range of `callBeganTimestamp`s that have been loaded. If nil,
        /// nothing has been fetched yet (or there wasn't anything to fetch).
        private var callHistoryItemTimestampRange: ClosedRange<UInt64>?

        /// All the "call history items" we've loaded so far. This is generally
        /// equivalent to allCallItems.prefix(…).
        private var callHistoryItemReferences: [CallHistoryItemReference]

        var isEmpty: Bool { upcomingCallLinkReferences.isEmpty && callHistoryItemReferences.isEmpty }

        var totalCount: Int { upcomingCallLinkReferences.count + callHistoryItemReferences.count }

        /// All the references known by this type.
        ///
        /// This value should be used as a the data source for a table view.
        func viewModelReferences() -> [CallViewModel.Reference] {
            return upcomingCallLinkReferences.map(\.viewModelReference) + callHistoryItemReferences.map(\.viewModelReference)
        }

        func viewModelReference(at index: Int) -> CallViewModel.Reference {
            var internalIndex = index
            if internalIndex < upcomingCallLinkReferences.count {
                return upcomingCallLinkReferences[internalIndex].viewModelReference
            }
            internalIndex -= upcomingCallLinkReferences.count
            if internalIndex < callHistoryItemReferences.count {
                return callHistoryItemReferences[internalIndex].viewModelReference
            }
            owsFail("Must provide valid index.")
        }

        // MARK: - View Models

        /// Returns the view model at `index`.
        ///
        /// This fetches a new batch from the disk if `index` isn't yet loaded.
        mutating func viewModel(at index: Int, sneakyTransactionDb: any DB) -> CallViewModel? {
            if let alreadyFetched = _viewModel(at: index) {
                return alreadyFetched
            }
            sneakyTransactionDb.read { tx in self.loadUntilCached(at: index, tx: tx) }
            return _viewModel(at: index)
        }

        private func _viewModel(at index: Int) -> CallViewModel? {
            var internalIndex = index
            if internalIndex < upcomingCallLinkReferences.count {
                return upcomingCallLinkReferences[internalIndex].viewModel
            }
            internalIndex -= upcomingCallLinkReferences.count
            if internalIndex < callHistoryItemReferences.count {
                return callHistoryItemReferences[internalIndex].viewModel
            }
            return nil
        }

        // MARK: - Load more

        /// Loads a batch of view models surrounding `index`.
        ///
        /// This method is safe to call for any `index` less than `totalCount` or
        /// `viewModelReferences().count`.
        private mutating func loadUntilCached(at index: Int, tx: DBReadTransaction) {
            // Ensure the page that contains `index` has been loaded.
            let pageIndex = index / viewModelPageSize
            let pageRange = (pageIndex * viewModelPageSize)..<((pageIndex + 1) * viewModelPageSize)
            for index in pageRange {
                self.loadViewModel(at: index, tx: tx)
            }

            // Throw away cached view models if we have way too many.
            let adjacentRange = (
                max(0, pageRange.lowerBound - 2 * viewModelPageSize)
                ..< min(totalCount, pageRange.upperBound + 2 * viewModelPageSize)
            )
            for internalIndex in upcomingCallLinkReferences.indices {
                if adjacentRange.contains(internalIndex) {
                    continue
                }
                upcomingCallLinkReferences[internalIndex].viewModel = nil
            }
            for internalIndex in callHistoryItemReferences.indices {
                if adjacentRange.contains(internalIndex + upcomingCallLinkReferences.count) {
                    continue
                }
                callHistoryItemReferences[internalIndex].viewModel = nil
            }
        }

        mutating func reloadUpcomingCallLinkReferences(tx: DBReadTransaction) {
            guard shouldFetchUpcomingCallLinks else {
                return
            }
            let upcomingCallLinks: [CallLinkRecord]
            do {
                upcomingCallLinks = try callLinkStore.fetchUpcoming(earlierThan: nil, limit: 2048, tx: tx)
            } catch {
                Logger.warn("Couldn't fetch call links to show on the calls tab: \(error)")
                return
            }
            self.upcomingCallLinkReferences = upcomingCallLinks.map {
                return UpcomingCallLinkReference(callLinkRoomId: $0.roomId)
            }
        }

        /// Load a page of call history items in the requested direction.
        ///
        /// This method might fetch view models in a few circumstances.
        ///
        /// - Returns
        /// True if the owner of this type should schedule a reload (ie changes were
        /// made to call history items).
        mutating func loadCallHistoryItemReferences(
            direction loadDirection: LoadDirection,
            tx: DBReadTransaction
        ) -> Bool {
            var fetchResult: [NonEmptyArray<CallRecord>]
            let fetchDirection: LoadDirection
            switch (loadDirection, callHistoryItemTimestampRange) {
            case (.older, _), (.newer, nil):
                /// If we're asked to load newer calls, but we don't have any calls loaded
                /// yet, do an "older" load since they're gonna be equivalent.

                fetchDirection = .older
                fetchResult = loadOlderCallHistoryItemReferences(
                    olderThan: callHistoryItemTimestampRange?.lowerBound,
                    maxCount: viewModelPageSize,
                    tx: tx
                )
            case (.newer, let callHistoryItemTimestampRange?):
                fetchDirection = .newer
                fetchResult = loadNewerCallHistoryItemReferences(
                    newerThan: callHistoryItemTimestampRange.upperBound,
                    tx: tx
                ).map { NonEmptyArray(singleElement: $0) }
            }

            guard let newestGroup = fetchResult.first, let oldestGroup = fetchResult.last else {
                return false
            }

            // Expand `callHistoryItemTimestampRange` so that the next fetch elides existing items.
            let newestFetchedTimestamp: UInt64 = newestGroup.first.callBeganTimestamp
            let oldestFetchedTimestamp: UInt64 = oldestGroup.last.callBeganTimestamp

            if let callHistoryItemTimestampRange {
                self.callHistoryItemTimestampRange = (
                    min(callHistoryItemTimestampRange.lowerBound, oldestFetchedTimestamp)
                    ... max(callHistoryItemTimestampRange.upperBound, newestFetchedTimestamp)
                )
            } else {
                self.callHistoryItemTimestampRange = oldestFetchedTimestamp...newestFetchedTimestamp
            }

            // Special case: If we fetched newer records, and if the oldest one we
            // fetched can be merged with what we already have, do so. This handles the
            // common case of making a call while scrolled near the top of the Calls
            // Tab. If this code is removed, the app will behave properly, but calls
            // won't be coalesced until the a new loader is created.
            if
                fetchDirection == .newer,
                let oldestGroupOfNewCallRecords = fetchResult.last,
                let newestGroupOfOldCallRecords = callHistoryItemReferences.first?.viewModel?.callRecords,
                let oldestOldCallRecord = newestGroupOfOldCallRecords.last,
                oldestGroupOfNewCallRecords.first.isValidCoalescingAnchor(for: oldestOldCallRecord),
                (oldestGroupOfNewCallRecords.rawValue.count + newestGroupOfOldCallRecords.count) <= maxCoalescedCallsInOneViewModel
            {
                let combinedGroupOfCallRecords = oldestGroupOfNewCallRecords + newestGroupOfOldCallRecords
                callHistoryItemReferences[0] = CallHistoryItemReference(
                    callRecordIds: combinedGroupOfCallRecords.map(\.id)
                )
                fetchResult = fetchResult.dropLast()
            }

            let fetchedCallHistoryItemReferences = fetchResult.map {
                return CallHistoryItemReference(callRecordIds: $0.map(\.id))
            }

            switch fetchDirection {
            case .older:
                // swiftlint:disable shorthand_operator
                self.callHistoryItemReferences = self.callHistoryItemReferences + fetchedCallHistoryItemReferences
                // swiftlint:enable shorthand_operator
            case .newer:
                self.callHistoryItemReferences = fetchedCallHistoryItemReferences + self.callHistoryItemReferences
            }

            return true
        }

        // MARK: - Rehydration

        /// "Hydrate" (ie load) the view model at `index`.
        ///
        /// This is a no-op if it's already loaded.
        private mutating func loadViewModel(at index: Int, tx: DBReadTransaction) {
            var internalIndex = index
            if internalIndex < upcomingCallLinkReferences.count {
                let reference = upcomingCallLinkReferences[internalIndex]
                if reference.viewModel == nil {
                    let callLinkRecord: CallLinkRecord
                    do {
                        callLinkRecord = try callLinkStore.fetch(roomId: reference.callLinkRoomId, tx: tx) ?? {
                            owsFail("Missing call link for existing reference!")
                        }()
                    } catch {
                        owsFail("Couldn't fetch call link: \(error)")
                    }
                    upcomingCallLinkReferences[internalIndex].viewModel = callViewModelForUpcomingCallLink(callLinkRecord, tx)
                }
                return
            }
            internalIndex -= upcomingCallLinkReferences.count
            if internalIndex < callHistoryItemReferences.count {
                let reference = callHistoryItemReferences[internalIndex]
                if reference.viewModel == nil {
                    let callRecords = reference.callRecordIds.map {
                        guard let callRecord = fetchCallRecordBlock($0, tx) else {
                            owsFail("Missing call record for existing reference!")
                        }
                        return callRecord
                    }
                    callHistoryItemReferences[internalIndex].viewModel = callViewModelForCallRecords(callRecords.rawValue, tx)
                }
                return
            }
        }

        // MARK: - Newly-Fetched References

        /// Loads older call history items.
        ///
        /// - Returns
        /// Call history items computed by merging ``CallRecord``s. At most
        /// `maxCount` items will be returned, but more than `maxCount`
        /// ``CallRecord``s may be fetched due to coalescing.
        private func loadOlderCallHistoryItemReferences(
            olderThan oldestCallTimestamp: UInt64?,
            maxCount: Int,
            tx: DBReadTransaction
        ) -> [NonEmptyArray<CallRecord>] {
            let newCallRecordsCursor: CallRecordCursor = callRecordLoader.loadCallRecords(
                loadDirection: .olderThan(oldestCallTimestamp: oldestCallTimestamp),
                tx: tx
            )

            // Group call records that will be shown together in the UI.
            var callRecordsForNextGroup = [CallRecord]()

            var results = [NonEmptyArray<CallRecord>]()
            while let nextCallRecord = try? newCallRecordsCursor.next() {
                if let anchorCallRecord = callRecordsForNextGroup.first {
                    let canCoalesce: Bool = (
                        callRecordsForNextGroup.count < maxCoalescedCallsInOneViewModel
                        && anchorCallRecord.isValidCoalescingAnchor(for: nextCallRecord)
                    )
                    if !canCoalesce {
                        results.append(NonEmptyArray(callRecordsForNextGroup)!)
                        callRecordsForNextGroup = []
                        if results.count >= maxCount {
                            // Bail when we reach the limit.
                            break
                        }
                    }
                }

                callRecordsForNextGroup.append(nextCallRecord)
            }
            if let finalGroup = NonEmptyArray(callRecordsForNextGroup) {
                results.append(finalGroup)
            }
            return results
        }

        /// Loads newer call history items.
        ///
        /// - Note
        /// Unlike ``loadOlderCallHistoryItemReferences()``, this method doesn't
        /// coalesce its results.
        ///
        /// In general usage, this type expects to start empty and monotonically
        /// load older calls; finding a brand-new newer call implies the call was
        /// inserted after our initial load. Finding a single brand-new newer call
        /// is expected in the case where a new call starts, but it is unexpected to
        /// find multiple brand-new newer calls at once.
        ///
        /// Consequently, ``loadCallHistoryItemReferences()`` will sometimes
        /// coalesce a single brand-new newer call into already-fetched value to
        /// support the "new call" scenario. However, if multiple brand-new newer
        /// calls are found, the others won't be coalesced.
        ///
        /// Users are unlikely to encounter this limitation in practice, and the
        /// effect is simply that calls that should have coalesced are not until the
        /// next time we load-from-empty. In return, this code is simpler.
        private func loadNewerCallHistoryItemReferences(
            newerThan newestCallTimestamp: UInt64,
            tx: DBReadTransaction
        ) -> [CallRecord] {
            let newCallRecordsCursor: CallRecordCursor = callRecordLoader.loadCallRecords(
                loadDirection: .newerThan(newestCallTimestamp: newestCallTimestamp),
                tx: tx
            )

            // The call records we get back from our cursor will be ordered ascending,
            // but we need them to be sorted descending.
            //
            // We'll reverse them here to make things easier on our callers.
            return (try? newCallRecordsCursor.drain().reversed()) ?? []
        }

        // MARK: -

        /// Drops any calls with the given IDs from set of loaded objects.
        ///
        /// - Important
        /// ``viewModelReferences()``'s result may change after calling this method.
        mutating func dropCalls(
            matching callRecordIdsToDrop: [CallRecord.ID],
            tx: DBReadTransaction
        ) {
            let callRecordIdsToDrop = Set(callRecordIdsToDrop)

            // Remove any IDs that were dropped from the references.
            var callHistoryItemIndicesToRemove = IndexSet()
            for internalIndex in callHistoryItemReferences.indices {
                let reference = callHistoryItemReferences[internalIndex]
                guard reference.callRecordIds.rawValue.contains(where: { callRecordIdsToDrop.contains($0) }) else {
                    continue
                }
                if let callRecordIds = NonEmptyArray(reference.callRecordIds.rawValue.filter({ !callRecordIdsToDrop.contains($0) })) {
                    callHistoryItemReferences[internalIndex] = CallHistoryItemReference(
                        callRecordIds: callRecordIds
                    )
                } else {
                    callHistoryItemIndicesToRemove.insert(internalIndex)
                }
            }
            callHistoryItemReferences.remove(atOffsets: callHistoryItemIndicesToRemove)
        }

        /// Refreshes view models containing any of the given IDs. If no cached view
        /// models contain a given ID, that ID is ignored.
        ///
        /// - Returns
        /// References for any view models that were refreshed. Note that this will
        /// not include any IDs that were ignored.
        mutating func refreshViewModels(
            callRecordIds callRecordsIdsToRefresh: [CallRecord.ID],
            tx: DBReadTransaction
        ) -> [CallViewModel.Reference] {
            func refreshIfPossible(_ callRecord: CallRecord) -> CallRecord {
                return fetchCallRecordBlock(callRecord.id, tx) ?? callRecord
            }

            let callRecordsIdsToRefresh = Set(callRecordsIdsToRefresh)

            var refreshedViewModelReferences = [CallViewModel.Reference]()

            for internalIndex in callHistoryItemReferences.indices {
                guard let viewModel = callHistoryItemReferences[internalIndex].viewModel else {
                    continue
                }
                guard viewModel.callRecords.contains(where: { callRecordsIdsToRefresh.contains($0.id) }) else {
                    continue
                }
                let newCallRecords = viewModel.callRecords.map(refreshIfPossible(_:))
                let newViewModel = callViewModelForCallRecords(newCallRecords, tx)
                callHistoryItemReferences[internalIndex].viewModel = newViewModel
                refreshedViewModelReferences.append(newViewModel.reference)
            }

            return refreshedViewModelReferences
        }
    }
}

// MARK: -

private extension CallRecord {
    private enum Constants {
        /// A time interval representing a window within which two call records
        /// can be coalesced together.
        static let coalescingTimeWindow: TimeInterval = 4 * kHourInterval
    }

    /// Whether the given call record can be coalesced under this call record.
    func isValidCoalescingAnchor(for otherCallRecord: CallRecord) -> Bool {
        switch (conversationId, otherCallRecord.conversationId) {
        case (.thread(let threadRowId), .thread(let otherThreadRowId)) where threadRowId == otherThreadRowId:
            break
        case (.thread(_), .thread(_)):
            return false
        case (.callLink(_), _), (_, .callLink(_)):
            // Call links are never coalesced.
            return false
        }
        return (
            callDirection == otherCallRecord.callDirection
            && callStatus.isMissedCall == otherCallRecord.callStatus.isMissedCall
            && callBeganDate.addingTimeInterval(-Constants.coalescingTimeWindow) < otherCallRecord.callBeganDate
        )
    }
}

private struct NonEmptyArray<Element> {
    let rawValue: [Element]

    init?(_ rawValue: [Element]) {
        if rawValue.isEmpty {
            return nil
        }
        self.rawValue = rawValue
    }

    init(singleElement: Element) {
        self.rawValue = [singleElement]
    }

    var first: Element { self.rawValue.first! }

    var last: Element { self.rawValue.last! }

    func map<T, E>(_ transform: (Element) throws(E) -> T) throws(E) -> NonEmptyArray<T> where E: Error {
        return NonEmptyArray<T>(try self.rawValue.map(transform))!
    }

    static func + (lhs: Self, rhs: [Element]) -> Self {
        return Self(lhs.rawValue + rhs)!
    }
}
