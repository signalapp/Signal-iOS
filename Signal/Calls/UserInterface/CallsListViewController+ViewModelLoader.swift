//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

extension CallsListViewController {
    /// Responsible for loading ``CallViewModel``s from disk and persisting them
    /// in-memory.
    ///
    /// This type will maintain an ordered list of references to every
    /// ``CallViewModel`` it has ever loaded, as well as a bounded in-memory
    /// cache of full view models. It exposes methods for paging forwards and
    /// backwards in time, which results in updates to the currently-cached view
    /// models as well as additions to the loaded view model references as
    /// appropriate.
    ///
    /// Callers should inspect ``loadedViewModelReferences`` for a comprehensive
    /// list of all view models this instance is aware of, and use
    /// ``getCachedViewModel(loadedViewModelReferenceIndex:)`` to request a full
    /// view model for the reference at the given index in
    /// ``loadedViewModelReferences``.
    ///
    /// Note that in the event of a "cache miss" when requesting a full view
    /// model from this type, it is the callers responsibility to instruct this
    /// type to load models to refill the cache such that the next request
    /// results in a cache hit.
    struct ViewModelLoader {
        typealias CreateCallViewModelBlock = (
            _ primaryCallRecord: CallRecord,
            _ coalescedCallRecords: [CallRecord],
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
        private let createCallViewModelBlock: CreateCallViewModelBlock
        private let fetchCallRecordBlock: FetchCallRecordBlock
        private let viewModelPageSize: UInt
        private let maxCachedViewModelCount: Int
        private let maxCoalescedCallsInOneViewModel: UInt

        init(
            callRecordLoader: CallRecordLoader,
            createCallViewModelBlock: @escaping CreateCallViewModelBlock,
            fetchCallRecordBlock: @escaping FetchCallRecordBlock,
            viewModelPageSize: UInt = 50,
            maxCachedViewModelCount: Int = 150,
            maxCoalescedCallsInOneViewModel: UInt = 50
        ) {
            owsPrecondition(
                maxCachedViewModelCount >= viewModelPageSize,
                "Must be able to cache at least one page of view models!"
            )

            self.callRecordLoader = callRecordLoader
            self.createCallViewModelBlock = createCallViewModelBlock
            self.fetchCallRecordBlock = fetchCallRecordBlock
            self.viewModelPageSize = viewModelPageSize
            self.maxCachedViewModelCount = maxCachedViewModelCount
            self.maxCoalescedCallsInOneViewModel = maxCoalescedCallsInOneViewModel

            self.loadedViewModelReferences = IdentifierIndexedArray(elements: [])
            self.cachedViewModels = IdentifierIndexedArray(elements: [])
        }

        // MARK: - Loaded view model references

        /// All the view model references we've loaded thus far.
        private(set) var loadedViewModelReferences: IdentifierIndexedArray<CallViewModel.Reference>

        /// Returns a view model reference matching the given one, with any of
        /// the given call record IDs removed. If the resulting reference would
        /// contain no call record IDs, `nil` is returned.
        private func dropCallRecordIds(
            _ idsToDrop: Set<CallRecord.ID>,
            fromViewModelReference viewModelReference: CallViewModel.Reference
        ) -> CallViewModel.Reference? {
            var containedCallRecordIds: [CallRecord.ID] = viewModelReference.containedIds

            let countBefore = containedCallRecordIds.count
            containedCallRecordIds.removeAll { idsToDrop.contains($0) }

            guard countBefore != containedCallRecordIds.count else {
                // Nothing was dropped, keep the same view model reference.
                return viewModelReference
            }

            if containedCallRecordIds.isEmpty {
                return nil
            } else if containedCallRecordIds.count == 1 {
                return .singleCall(containedCallRecordIds.first!)
            } else {
                return .coalescedCalls(
                    primary: containedCallRecordIds.first!,
                    coalesced: Array(containedCallRecordIds.dropFirst())
                )
            }
        }

        // MARK: - Cached view models

        /// All the hydrated view models we currently have loaded.
        private var cachedViewModels: IdentifierIndexedArray<CallViewModel>

        /// Returns the cached view model corresponding to the view model
        /// reference at the given index into ``loadedViewModelReferences``, if
        /// one is cached.
        ///
        /// - SeeAlso ``loadUntilCached(loadedViewModelReferenceIndex:tx:)``
        func getCachedViewModel(loadedViewModelReferenceIndex index: Int) -> CallViewModel? {
            guard let viewModelReference = loadedViewModelReferences[safe: index] else {
                return nil
            }

            return getCachedViewModel(reference: viewModelReference)
        }

        /// Returns whether a view model is cached corresponding to the view
        /// model reference at the given index into
        /// ``loadedViewModelReferences``.
        func hasCachedViewModel(loadedViewModelReferenceIndex index: Int) -> Bool {
            return getCachedViewModel(loadedViewModelReferenceIndex: index) != nil
        }

        private func getCachedViewModel(reference: CallViewModel.Reference) -> CallViewModel? {
            return cachedViewModels[id: reference.primaryId]
        }

        /// Merges the given view models into the view model cache in the given
        /// direction, dropping models from the other end of the cache if
        /// necessary.
        private mutating func mergeIntoCachedViewModels(
            newViewModels: [CallViewModel],
            direction: LoadDirection
        ) {
            if newViewModels.isEmpty { return }

            let mergedCachedViewModels: [CallViewModel] = {
                let combinedViewModels: [CallViewModel] = {
                    switch direction {
                    case .older: return cachedViewModels.allElements + newViewModels
                    case .newer: return newViewModels + cachedViewModels.allElements
                    }
                }()

                if combinedViewModels.count <= maxCachedViewModelCount {
                    return combinedViewModels
                } else {
                    switch direction {
                    case .older: return Array(combinedViewModels.suffix(maxCachedViewModelCount))
                    case .newer: return Array(combinedViewModels.prefix(maxCachedViewModelCount))
                    }
                }
            }()

            cachedViewModels = IdentifierIndexedArray(elements: mergedCachedViewModels)
        }

        /// Returns a view model reference matching the given one, with any
        /// should-be-dropped call record IDs removed. If the resulting
        /// reference contains no call record IDs, `nil` is returned.
        private func dropCallRecordIds(
            _ idsToDrop: Set<CallRecord.ID>,
            fromViewModel viewModel: CallViewModel,
            tx: DBReadTransaction
        ) -> CallViewModel? {
            var containedCallRecords = viewModel.allCallRecords

            let countBefore = containedCallRecords.count
            containedCallRecords.removeAll { idsToDrop.contains($0.id) }

            guard countBefore != containedCallRecords.count else {
                // Nothing was dropped, keep the same view model.
                return viewModel
            }

            if containedCallRecords.isEmpty {
                return nil
            } else {
                return createCallViewModelBlock(
                    containedCallRecords.first!,
                    Array(containedCallRecords.dropFirst()),
                    tx
                )
            }
        }

        // MARK: - Load more

        /// Repeatedly loads pages of view models until a cached view model is
        /// available for the given loaded view model reference index.
        ///
        /// This method is safe to call for any valid loaded view model
        /// reference index.
        ///
        /// - Note
        /// This may result in multiple synchronous page loads if necessary. For
        /// example, if view models are cached for rows in range `(500, 600)`
        /// and this method is called for row 10, all the rows between row 500
        /// and row 10 will be loaded.
        ///
        /// This behavior should be fine in practice, since loading a page is a
        /// fast operation.
        mutating func loadUntilCached(
            loadedViewModelReferenceIndex index: Int,
            tx: DBReadTransaction
        ) {
            guard
                !hasCachedViewModel(loadedViewModelReferenceIndex: index),
                !cachedViewModels.isEmpty
            else { return }

            guard let cachedViewModelReferenceIndices = cachedViewModelReferenceIndices() else {
                owsFail("Missing cached view model indices, but we checked above for empty cached view models!")
            }

            let loadDirection: LoadDirection = {
                if index > cachedViewModelReferenceIndices.last {
                    return .older
                } else if index < cachedViewModelReferenceIndices.first {
                    return .newer
                }

                owsFail("Row index is in the cached range, but somehow we didn't have a cached model. How did that happen?")
            }()

            while true {
                if hasCachedViewModel(loadedViewModelReferenceIndex: index) {
                    break
                }

                _ = loadMore(direction: loadDirection, tx: tx)
            }
        }

        /// Load a page of calls in the requested direction.
        ///
        /// This method may load brand new view models; it may page view models
        /// into this loader's cache for view model references it had loaded in
        /// the past; or it may do a combination of both.
        ///
        /// - Returns
        /// Whether changes were made to ``loadedViewModelReferences`` as a
        /// result of this load.
        mutating func loadMore(
            direction loadDirection: LoadDirection,
            tx: DBReadTransaction
        ) -> Bool {
            var viewModelsToLoadCount = viewModelPageSize

            let rehydratedCount = rehydrateLoadedViewModelReferencesIntoCache(
                maxCount: viewModelsToLoadCount,
                direction: loadDirection,
                tx: tx
            )

            owsPrecondition(rehydratedCount <= viewModelsToLoadCount)
            viewModelsToLoadCount -= rehydratedCount

            if viewModelsToLoadCount == 0 {
                /// We've loaded all the calls we need to, simply by rehydrating
                /// already-loaded view model references.
                return false
            }

            switch (loadDirection, cachedViewModels.count) {
            case (.older, _), (.newer, 0):
                /// If we're asked to load newer calls, but we don't have any
                /// calls loaded yet, do an "older" load since they're gonna be
                /// equivalent.

                let brandNewViewModels = loadBrandNewViewModelsOlder(
                    maxCount: viewModelsToLoadCount, tx: tx
                )

                if brandNewViewModels.isEmpty {
                    return false
                }

                loadedViewModelReferences.append(
                    newElements: brandNewViewModels.map { $0.reference }
                )
                mergeIntoCachedViewModels(
                    newViewModels: brandNewViewModels,
                    direction: .older
                )

                return true
            case (.newer, _):
                guard let newestCachedViewModel = cachedViewModels.first else {
                    owsFail("Non-zero cached view model count, but missing first view model!")
                }

                let loadResult = loadBrandNewViewModelsNewer(
                    maxCount: viewModelsToLoadCount,
                    currentNewestViewModel: newestCachedViewModel,
                    tx: tx
                )

                switch loadResult {
                case .nothingLoaded:
                    return false
                case .coalescedIntoCurrentNewest(let updatedNewestViewModel):
                    /// If we coalesced newly-loaded view models into the
                    /// existing most-recent call, replace that call
                    /// in-place and let callers know things changed.

                    loadedViewModelReferences.replace(
                        elementAtIndex: 0, with: updatedNewestViewModel.reference
                    )
                    cachedViewModels.replace(
                        elementAtIndex: 0, with: updatedNewestViewModel
                    )

                    return true
                case .loaded(let newViewModels):
                    owsPrecondition(newViewModels.count > 0)

                    loadedViewModelReferences.prepend(
                        newElements: newViewModels.map { $0.reference }
                    )
                    mergeIntoCachedViewModels(
                        newViewModels: newViewModels,
                        direction: .newer
                    )

                    return true
                }
            }
        }

        // MARK: - Rehydration

        /// "Rehydrate" already-loaded view model references that we know about
        /// in the direction we want to load, and add the rehydrated view models
        /// to our cache.
        ///
        /// Rehydration will begin with the next already-loaded view model
        /// reference without a corresponding view model in the cache, in the
        /// given direction. For example, if we've loaded view model references
        /// for rows `[0, 100]`, have cached view models for `[25, 75]`, the
        /// first rehydrated view model will be at index 24 or 76.
        ///
        /// - Parameter maxCount
        /// The max number of view models to rehydrate.
        /// - Returns
        /// The actual number of view models rehydrated. This may be lower than
        /// the max if while rehydrating we run out of already-loaded view model
        /// references in the given direction.
        private mutating func rehydrateLoadedViewModelReferencesIntoCache(
            maxCount: UInt,
            direction loadDirection: LoadDirection,
            tx: DBReadTransaction
        ) -> UInt {
            let cachedViewModelReferenceIndices: CachedViewModelReferenceIndices? = cachedViewModelReferenceIndices()

            /// Collect any view model references we've already loaded, in the
            /// given direction, for which we don't have a loaded view model.
            let loadedViewModelReferencesToHydrate: [CallViewModel.Reference] = {
                guard let cachedViewModelReferenceIndices else { return [] }

                var referencesToHydrate = [CallViewModel.Reference]()

                switch loadDirection {
                case .older:
                    var indexToHydrate = cachedViewModelReferenceIndices.last + 1
                    while
                        indexToHydrate < loadedViewModelReferences.count,
                        referencesToHydrate.count < maxCount
                    {
                        referencesToHydrate.append(loadedViewModelReferences[index: indexToHydrate])
                        indexToHydrate += 1
                    }
                case .newer:
                    var indexToHydrate = cachedViewModelReferenceIndices.first - 1
                    while
                        indexToHydrate >= 0,
                        referencesToHydrate.count < maxCount
                    {
                        referencesToHydrate.insert(loadedViewModelReferences[index: indexToHydrate], at: 0)
                        indexToHydrate -= 1
                    }
                }

                return referencesToHydrate
            }()

            let rehydratedViewModels = loadedViewModelReferencesToHydrate.map { viewModelReference in
                hydrate(viewModelReference: viewModelReference, tx: tx)
            }

            mergeIntoCachedViewModels(
                newViewModels: rehydratedViewModels,
                direction: loadDirection
            )

            return UInt(rehydratedViewModels.count)
        }

        /// Hydrates a full view model from the given reference.
        private func hydrate(
            viewModelReference: CallViewModel.Reference,
            tx: DBReadTransaction
        ) -> CallViewModel {
            switch viewModelReference {
            case .singleCall(let id):
                guard let primaryCallRecord = fetchCallRecordBlock(id, tx) else {
                    owsFail("Missing call record for single-call view model!")
                }

                return createCallViewModelBlock(primaryCallRecord, [], tx)
            case .coalescedCalls(let primaryId, let coalescedIds):
                guard let primaryCallRecord = fetchCallRecordBlock(primaryId, tx) else {
                    owsFail("Missing primary call record for coalesced-call view model!")
                }

                let coalescedCallRecords = coalescedIds.map { coalescedId -> CallRecord in
                    guard let coalescedCallRecord = fetchCallRecordBlock(coalescedId, tx) else {
                        owsFail("Missing coalesced call record for coalesced-call view model!")
                    }

                    return coalescedCallRecord
                }

                return createCallViewModelBlock(primaryCallRecord, coalescedCallRecords, tx)
            }
        }

        // MARK: - Brand new models, older

        /// Loads brand new view models older than the last cached view model.
        ///
        /// - Important
        /// This method must only be called if our current view model cache
        /// includes the oldest loaded view model reference. If this is not the
        /// case, callers should first rehydrate older loaded view model
        /// references until it is and then call this method.
        ///
        /// - Returns
        /// View models not yet loaded in this loader's lifetime. No more than
        /// `maxCount` view models will be returned, although note that due to
        /// coalescing this may correspond to more than `maxCount` call records
        /// having been loaded.
        private func loadBrandNewViewModelsOlder(
            maxCount: UInt,
            tx: DBReadTransaction
        ) -> [CallViewModel] {
            owsPrecondition(
                cachedViewModels.isEmpty || cachedViewModels.last!.reference == loadedViewModelReferences.last!,
                "Unexpectedly loading brand new view models, but last loaded view model reference does not have a cached view model!"
            )

            let oldestLoadedCallTimestamp: UInt64? = cachedViewModels.last.map { oldestViewModel in
                return oldestViewModel.oldestContainedTimestamp
            }

            let newCallRecordsCursor: CallRecordCursor = callRecordLoader.loadCallRecords(
                loadDirection: .olderThan(
                    oldestCallTimestamp: oldestLoadedCallTimestamp
                ),
                tx: tx
            )

            /// Collate groups of call records that will each correspond to a
            /// single view model, with the first call in the group being the
            /// primary and all subsequent calls being coalesced under the
            /// primary.
            var groupedCallRecordsForViewModels = [[CallRecord]]()
            var callRecordsForNextViewModel = [CallRecord]()
            while true {
                if groupedCallRecordsForViewModels.count == maxCount {
                    /// If we've reached the max view model count simply bail,
                    /// even if we started a grouping for another view model.
                    break
                }

                guard let nextCallRecord = try? newCallRecordsCursor.next() else {
                    /// We may have run out of call records while assembling a
                    /// group for the next view model. If so, we want to commit
                    /// the grouping as it is.
                    if !callRecordsForNextViewModel.isEmpty {
                        groupedCallRecordsForViewModels.append(callRecordsForNextViewModel)
                    }

                    break
                }

                if callRecordsForNextViewModel.isEmpty {
                    /// Start the first view model grouping.
                    callRecordsForNextViewModel.append(nextCallRecord)
                } else if
                    callRecordsForNextViewModel.first!.isValidCoalescingAnchor(for: nextCallRecord),
                    callRecordsForNextViewModel.count < maxCoalescedCallsInOneViewModel
                {
                    /// Build on the current new view model grouping.
                    callRecordsForNextViewModel.append(nextCallRecord)
                } else {
                    /// Finish the current view model grouping, and start the
                    /// next one.
                    groupedCallRecordsForViewModels.append(callRecordsForNextViewModel)
                    callRecordsForNextViewModel = [nextCallRecord]
                }
            }

            owsPrecondition(
                groupedCallRecordsForViewModels.allSatisfy { !$0.isEmpty },
                "Had an empty grouping for a view model. How did this happen?"
            )

            return groupedCallRecordsForViewModels.map { callRecords -> CallViewModel in
                return createCallViewModelBlock(
                    callRecords.first!,
                    Array(callRecords.dropFirst()),
                    tx
                )
            }
        }

        // MARK: - Brand new models, newer

        private enum LoadBrandNewViewModelsNewerResult {
            /// No new view models were loaded.
            case nothingLoaded

            /// New view models were loaded.
            /// - Note
            /// The contained `newViewModels` are ordered descending by
            /// their primary call record's timestamp.
            case loaded(newViewModels: [CallViewModel])

            /// New calls were loaded, but were coalesced into the existing
            /// newest (by timestamp) view model.
            case coalescedIntoCurrentNewest(updatedNewestViewModel: CallViewModel)
        }

        /// Loads brand new view models newer than the first cached view model.
        ///
        /// - Note
        /// Unlike when loading brand new older view models, we do not generally
        /// coalesce the newer calls loaded by this method.
        ///
        /// In general usage, this type expects to start empty and monotonically
        /// load older calls; finding a brand-new newer call implies the call
        /// was inserted after our initial load. Finding a single brand-new
        /// newer call is expected in the case where a new call starts, but it
        /// is unexpected to find multiple brand-new newer calls at once.
        ///
        /// Consequently, we will coalesce a single brand-new newer call into
        /// the given `currentNewestViewModel`, so as to support the "new call"
        /// scenario. However, if multiple brand-new newer calls are found, they
        /// will each be transformed into their own view models.
        ///
        /// Users are unlikely to encounter this limitation in practice, and the
        /// effect is simply that calls that should have coalesced are not until
        /// the next time we load-from-empty. In return, we are able to simplify
        /// this code as a result.
        ///
        /// - Important
        /// This method must only be called if our current view model cache
        /// includes the newest loaded view model reference. If this is not the
        /// case, callers should first rehydrate newer loaded view model
        /// references until it is and then call this method.
        ///
        /// - Parameter currentNewestViewModel
        /// The current newest view model from our cache. This must correspond
        /// to the newest loaded view model reference – see above.
        ///
        /// - Returns
        /// The result of loading newer calls.
        private func loadBrandNewViewModelsNewer(
            maxCount: UInt,
            currentNewestViewModel: CallViewModel,
            tx: DBReadTransaction
        ) -> LoadBrandNewViewModelsNewerResult {
            owsPrecondition(currentNewestViewModel.reference == loadedViewModelReferences.first)

            let newCallRecordsCursor: CallRecordCursor = callRecordLoader.loadCallRecords(
                loadDirection: .newerThan(
                    newestCallTimestamp: currentNewestViewModel.newestContainedTimestamp
                ),
                tx: tx
            )

            guard let pageOfNewCallRecordsAsc = try? newCallRecordsCursor.drain(
                maxResults: maxCount
            ) else {
                return .nothingLoaded
            }

            /// The call records we get back from our cursor will be ordered
            /// ascending, but we'll ultimately need them sorted descending to
            /// merge into `cachedViewModels` and `loadedViewModelReferences`.
            ///
            /// We'll reverse them here, and return them ordered descending, to
            /// make things easier on our callers.
            owsPrecondition(pageOfNewCallRecordsAsc.isSortedByTimestamp(.ascending))
            let pageOfNewCallRecords = pageOfNewCallRecordsAsc.reversed()

            if pageOfNewCallRecords.isEmpty {
                return .nothingLoaded
            } else if
                pageOfNewCallRecords.count == 1,
                let singleNewCallRecord = pageOfNewCallRecords.first,
                singleNewCallRecord.isValidCoalescingAnchor(for: currentNewestViewModel.primaryCallRecord)
            {
                let updatedNewestViewModel = createCallViewModelBlock(
                    singleNewCallRecord,
                    [currentNewestViewModel.primaryCallRecord] + currentNewestViewModel.coalescedCallRecords,
                    tx
                )

                return .coalescedIntoCurrentNewest(updatedNewestViewModel: updatedNewestViewModel)
            } else {
                let uncoalescedViewModels: [CallViewModel] = pageOfNewCallRecords
                    .map { callRecord in createCallViewModelBlock(callRecord, [], tx) }

                return .loaded(newViewModels: uncoalescedViewModels)
            }
        }

        // MARK: -

        /// Represents the bounding indices of the currently-cached view models
        /// within ``loadedViewModelReferences``.
        private struct CachedViewModelReferenceIndices {
            let first: Int
            let last: Int
        }

        /// Computes the bounding indices of the currently-cached view models
        /// within ``loadedViewModelReferences``.
        private func cachedViewModelReferenceIndices() -> CachedViewModelReferenceIndices? {
            func getRowIndex(cachedViewModel: CallViewModel?) -> Int? {
                return cachedViewModel.flatMap {
                    return loadedViewModelReferences.index(forId: $0.reference.primaryId)
                }
            }

            guard
                let firstCachedViewModelRowIndex = getRowIndex(cachedViewModel: cachedViewModels.first),
                let lastCachedViewModelRowIndex = getRowIndex(cachedViewModel: cachedViewModels.last)
            else {
                return nil
            }

            return CachedViewModelReferenceIndices(
                first: firstCachedViewModelRowIndex,
                last: lastCachedViewModelRowIndex
            )
        }

        // MARK: -

        /// Drops any calls with the given IDs from the loaded view model
        /// references and view model cache.
        ///
        /// - Important
        /// ``loadedViewModelReferences`` may have changed as a result of
        /// calling this method.
        mutating func dropCalls(
            matching callRecordIdsToDrop: [CallRecord.ID],
            tx: DBReadTransaction
        ) {
            let callRecordIdsToDrop = Set(callRecordIdsToDrop)

            let droppedViewModelReferences = loadedViewModelReferences.allElements
                .compactMap { viewModelReference in
                    return dropCallRecordIds(callRecordIdsToDrop, fromViewModelReference: viewModelReference)
                }

            let droppedCachedViewModels = cachedViewModels.allElements
                .compactMap { viewModel in
                    return dropCallRecordIds(callRecordIdsToDrop, fromViewModel: viewModel, tx: tx)
                }

            loadedViewModelReferences = IdentifierIndexedArray(elements: droppedViewModelReferences)
            cachedViewModels = IdentifierIndexedArray(elements: droppedCachedViewModels)
        }

        /// Refreshes cached view models containing any of the given IDs. If no
        /// cached view models contain a given ID, that ID is ignored.
        ///
        /// - Returns
        /// References for any view models that were refreshed. Note that this
        /// will not include any IDs that were ignored.
        mutating func refreshViewModels(
            callRecordIds callRecordIdsForWhichToRefreshViewModels: [CallRecord.ID],
            tx: DBReadTransaction
        ) -> [CallViewModel.Reference] {
            func refreshIfPossible(_ callRecord: CallRecord) -> CallRecord {
                return fetchCallRecordBlock(callRecord.id, tx) ?? callRecord
            }

            /// The given call record IDs may not have a cached view model, in
            /// which case there's nothing to refresh. Multiple call record IDs
            /// may also point to the same cached view model, which only needs
            /// to be refreshed once since we'll re-fetch all the call records
            /// when refreshing each view model anyway.
            let cachedViewModelIndicesToRefresh: Set<Int> = Set(
                callRecordIdsForWhichToRefreshViewModels.compactMap { callRecordId -> Int? in
                    return cachedViewModels.index(forId: callRecordId)
                }
            )

            var refreshedViewModelReferences = [CallViewModel.Reference]()
            for cachedViewModelIndex in cachedViewModelIndicesToRefresh {
                /// For each cached view model containing a call record we need
                /// to reload, we'll in fact reload all the call records
                /// associated with that view model. It's a tiny cost, and makes
                /// this code a lot simpler; the alternative being to dissect
                /// each view model to reload specific contained call records.
                let cachedViewModel = cachedViewModels[index: cachedViewModelIndex]

                let newPrimaryViewModel = refreshIfPossible(cachedViewModel.primaryCallRecord)
                let newCoalescedViewModels = cachedViewModel.coalescedCallRecords.map(refreshIfPossible(_:))
                let newCallViewModel = createCallViewModelBlock(
                    newPrimaryViewModel,
                    newCoalescedViewModels,
                    tx
                )

                /// We haven't changed any of the actual call record IDs in the
                /// view model, so we don't need to recompute indices.
                cachedViewModels.replace(
                    elementAtIndex: cachedViewModelIndex,
                    with: newCallViewModel
                )
                refreshedViewModelReferences.append(newCallViewModel.reference)
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
        guard
            threadRowId == otherCallRecord.threadRowId,
            callDirection == otherCallRecord.callDirection,
            callStatus.isMissedCall == otherCallRecord.callStatus.isMissedCall,
            callBeganDate.addingTimeInterval(-Constants.coalescingTimeWindow) < otherCallRecord.callBeganDate
        else { return false }

        return true
    }
}

// MARK: - ContainsIdentifiers

extension CallsListViewController.CallViewModel.Reference: ContainsIdentifiers {
    typealias ContainedIdType = CallRecord.ID

    var containedIds: [CallRecord.ID] {
        switch self {
        case .singleCall(let callRecordId): return [callRecordId]
        case .coalescedCalls(let primary, let coalesced): return [primary] + coalesced
        }
    }
}

extension CallsListViewController.CallViewModel: ContainsIdentifiers {
    typealias ContainedIdType = CallRecord.ID

    var containedIds: [CallRecord.ID] {
        return reference.containedIds
    }
}
