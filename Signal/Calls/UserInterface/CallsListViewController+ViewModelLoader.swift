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

        private let callRecordLoader: CallRecordLoader
        private let callViewModelForCallRecords: CallViewModelForCallRecords
        private let fetchCallRecordBlock: FetchCallRecordBlock
        private let viewModelPageSize: Int
        private let maxCachedViewModelCount: Int
        private let maxCoalescedCallsInOneViewModel: Int

        init(
            callRecordLoader: CallRecordLoader,
            callViewModelForCallRecords: @escaping CallViewModelForCallRecords,
            fetchCallRecordBlock: @escaping FetchCallRecordBlock,
            viewModelPageSize: Int = 50,
            maxCachedViewModelCount: Int = 150,
            maxCoalescedCallsInOneViewModel: Int = 50
        ) {
            owsPrecondition(
                maxCachedViewModelCount >= viewModelPageSize,
                "Must be able to cache at least one page of view models!"
            )

            self.callRecordLoader = callRecordLoader
            self.callViewModelForCallRecords = callViewModelForCallRecords
            self.fetchCallRecordBlock = fetchCallRecordBlock
            self.viewModelPageSize = viewModelPageSize
            self.maxCachedViewModelCount = maxCachedViewModelCount
            self.maxCoalescedCallsInOneViewModel = maxCoalescedCallsInOneViewModel

            self.callHistoryItemReferences = []
            self.viewModels = []
            self.viewModelOffset = 0
        }

        // MARK: - References

        private struct CallHistoryItemReference {
            let callRecordIds: NonEmptyArray<CallRecord.ID>

            init(callRecordIds: NonEmptyArray<CallRecord.ID>) {
                self.callRecordIds = callRecordIds
            }

            var viewModelReference: CallViewModel.Reference {
                return .callRecords(primaryId: callRecordIds.first, coalescedIds: Array(callRecordIds.rawValue.dropFirst()))
            }
        }

        /// The range of `callBeganTimestamp`s that have been loaded. If nil,
        /// nothing has been fetched yet (or there wasn't anything to fetch).
        private var callHistoryItemTimestampRange: ClosedRange<UInt64>?

        private var callHistoryItemReferences: [CallHistoryItemReference]

        var isEmpty: Bool { callHistoryItemReferences.isEmpty }

        var totalCount: Int { callHistoryItemReferences.count }

        /// All the references known by this type.
        ///
        /// This value should be used as a the data source for a table view.
        func viewModelReferences() -> [CallViewModel.Reference] {
            return callHistoryItemReferences.map(\.viewModelReference)
        }

        func viewModelReference(at index: Int) -> CallViewModel.Reference {
            return callHistoryItemReferences[index].viewModelReference
        }

        // MARK: - View Models

        /// Tracks the correspondance between `viewModels` and the references.
        ///
        /// The invariant is that
        ///     (upcomingCallLinkReferences + callHistoryItemReferences).dropFirst(viewModelOffset)
        /// will correspond with viewModels.
        private var viewModelOffset: Int

        private var viewModelRange: Range<Int> { viewModelOffset..<(viewModelOffset + viewModels.count) }

        /// All the hydrated view models we currently have loaded.
        private var viewModels: [CallViewModel]

        /// Returns the view model at `index`.
        ///
        /// This fetches a new batch from the disk if `index` isn't yet loaded.
        mutating func viewModel(at index: Int, sneakyTransactionDb: any DB) -> CallViewModel? {
            if let alreadyFetched = viewModels[safe: index - self.viewModelOffset] {
                return alreadyFetched
            }
            sneakyTransactionDb.read { tx in self.loadUntilCached(at: index, tx: tx) }
            return viewModels[safe: index - self.viewModelOffset]
        }

        // MARK: - Load more

        /// Loads a batch of view models surrounding `index`.
        ///
        /// This method is safe to call for any `index` less than `totalCount` or
        /// `viewModelReferences().count`.
        private mutating func loadUntilCached(at index: Int, tx: DBReadTransaction) {
            let viewModelRange = self.viewModelRange

            // For example, assume:
            // - viewModelPageSize=25,
            // - maxCachedViewModelCount=35,
            // - viewModelRange=[20, 40)

            // ... then newerRange will be [0, 20)
            let newerRange = max(0, viewModelRange.lowerBound - viewModelPageSize)..<viewModelRange.lowerBound
            // ... and if `index` is in that range ...
            if newerRange.contains(index) {
                let hydratedViewModels = self.hydrateViewModelReferences(inRange: newerRange, tx: tx)
                // ... we load 20 new items, have 40 total, and then drop the last 5.
                self.viewModels = Array((hydratedViewModels + self.viewModels).prefix(maxCachedViewModelCount))
                // The first item is now earlier because we added items to the beginning.
                self.viewModelOffset -= hydratedViewModels.count
                return
            }

            // ... then olderRange will be [40, 65) ...
            let olderRange = viewModelRange.upperBound..<(viewModelRange.upperBound + viewModelPageSize)
            // ... and if `index` is in that range ...
            if olderRange.contains(index) {
                let hydratedViewModels = self.hydrateViewModelReferences(inRange: olderRange, tx: tx)
                // ... we load 25 new items, have 45 total, and then drop the first 10.
                self.viewModels = Array((self.viewModels + hydratedViewModels).suffix(maxCachedViewModelCount))
                // The first item is now later because we dropped 20 + 25 - 35 = 10 items from the beginning.
                self.viewModelOffset += max(0, viewModelRange.count + hydratedViewModels.count - maxCachedViewModelCount)
                return
            }

            // ... otherwise we load a batch surrounding `index`
            // (if index=837, pageIndex=33, pageRange=[825, 850))
            let pageIndex = index / viewModelPageSize
            let pageRange = (pageIndex * viewModelPageSize)..<((pageIndex + 1) * viewModelPageSize)
            // ... and throw away all our items and jump directly to what we loaded.
            self.viewModels = self.hydrateViewModelReferences(inRange: pageRange, tx: tx)
            self.viewModelOffset = pageRange.lowerBound
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
                let newestGroupOfOldCallRecords = viewModels[safe: 0]?.callRecords,
                let oldestOldCallRecord = newestGroupOfOldCallRecords.last,
                oldestGroupOfNewCallRecords.first.isValidCoalescingAnchor(for: oldestOldCallRecord),
                (oldestGroupOfNewCallRecords.rawValue.count + newestGroupOfOldCallRecords.count) <= maxCoalescedCallsInOneViewModel
            {
                let combinedGroupOfCallRecords = oldestGroupOfNewCallRecords + newestGroupOfOldCallRecords
                callHistoryItemReferences[0] = CallHistoryItemReference(
                    callRecordIds: combinedGroupOfCallRecords.map(\.id)
                )
                viewModels[0] = callViewModelForCallRecords(
                    combinedGroupOfCallRecords.rawValue,
                    tx
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
                self.viewModelOffset += fetchedCallHistoryItemReferences.count
            }

            return true
        }

        // MARK: - Rehydration

        /// "Hydrate" (ie load) view models in `range`.
        ///
        /// This fetches new ``CallViewModel`` instances even if they're already
        /// loaded. Therefore, the caller shouldn't invoke this for already-loaded
        /// view models unless they are explicitly trying to reload them.
        private func hydrateViewModelReferences(
            inRange range: Range<Int>,
            tx: DBReadTransaction
        ) -> [CallViewModel] {
            var newViewModels = [CallViewModel]()

            var remainingRange = range
            newViewModels += callHistoryItemReferences[consume(upTo: callHistoryItemReferences.count, from: &remainingRange)].map { reference in
                let callRecords = reference.callRecordIds.map {
                    return fetchCallRecordBlock($0, tx)!
                }
                return callViewModelForCallRecords(callRecords.rawValue, tx)
            }

            return newViewModels
        }

        /// "Consume" `0..<bound` from `range`.
        ///
        /// Shifts `range` lower by `bound` and returns the overlap between
        /// `0..<bound` and the original `range`.
        ///
        /// Returns an arbitrary empty range when there's no overlap.
        private func consume(upTo bound: Int, from range: inout Range<Int>) -> Range<Int> {
            let result = min(range.lowerBound, bound)..<min(range.upperBound, bound)
            range = max(0, range.lowerBound - bound)..<max(0, range.upperBound - bound)
            return result
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

            var didTouchViewModels = false
            let callHistoryItemOffset = 0
            let viewModelRange = self.viewModelRange

            // Remove any IDs that were dropped from the references.
            var callHistoryItemIndicesToRemove = IndexSet()
            for index in callHistoryItemReferences.indices {
                let reference = callHistoryItemReferences[index]
                guard reference.callRecordIds.rawValue.contains(where: { callRecordIdsToDrop.contains($0) }) else {
                    continue
                }
                didTouchViewModels = didTouchViewModels || viewModelRange.contains(callHistoryItemOffset + index)
                if let callRecordIds = NonEmptyArray(reference.callRecordIds.rawValue.filter({ !callRecordIdsToDrop.contains($0) })) {
                    callHistoryItemReferences[index] = CallHistoryItemReference(
                        callRecordIds: callRecordIds
                    )
                } else {
                    callHistoryItemIndicesToRemove.insert(index)
                }
            }
            callHistoryItemReferences.remove(atOffsets: callHistoryItemIndicesToRemove)

            // Drop the view models if they overlap. We'll refetch them when needed.
            if didTouchViewModels {
                self.viewModels = []
                self.viewModelOffset = 0
            }
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

            for index in viewModels.indices {
                let viewModel = viewModels[index]
                guard viewModel.callRecords.contains(where: { callRecordsIdsToRefresh.contains($0.id) }) else {
                    continue
                }
                let newCallRecords = viewModel.callRecords.map(refreshIfPossible(_:))
                viewModels[index] = callViewModelForCallRecords(newCallRecords, tx)
                refreshedViewModelReferences.append(viewModels[index].reference)
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
