//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

enum HVRowChangeType {
    case delete(oldIndexPath: IndexPath)
    case insert(newIndexPath: IndexPath)
    case move(oldIndexPath: IndexPath, newIndexPath: IndexPath)
    case update(oldIndexPath: IndexPath)

    // MARK: -

    public var logSafeDescription: String {
        switch self {
        case .delete(let oldIndexPath):
            return "delete(oldIndexPath: \(oldIndexPath))"
        case .insert(let newIndexPath):
            return "insert(newIndexPath: \(newIndexPath))"
        case .move(let oldIndexPath, let newIndexPath):
            return "move(oldIndexPath: \(oldIndexPath), newIndexPath: \(newIndexPath))"
        case .update(let oldIndexPath):
            return "update(oldIndexPath: \(oldIndexPath))"
        }
    }
}

// MARK: -

struct HVRowChange {
    public let type: HVRowChangeType
    public let threadUniqueId: String

    init(type: HVRowChangeType, threadUniqueId: String) {
        self.type = type
        self.threadUniqueId = threadUniqueId
    }

    // MARK: -

    public var logSafeDescription: String {
        "\(type), \(threadUniqueId)"
    }
}

// MARK: -

enum HVLoadResult {
    case renderStateForReset(renderState: HVRenderState)
    case renderStateWithRowChanges(renderState: HVRenderState, rowChanges: [HVRowChange])
    case renderStateWithoutRowChanges(renderState: HVRenderState)
    case reloadTable
    case noChanges
}

// MARK: -

public class HVLoader: NSObject {

    static func loadRenderStateForReset(viewInfo: HVViewInfo,
                                        transaction: SDSAnyReadTransaction) -> HVLoadResult {
        AssertIsOnMainThread()

        do {
            return try Bench(title: "loadRenderState for reset (\(viewInfo.homeViewMode))") {
                let renderState = try Self.loadRenderStateInternal(viewInfo: viewInfo,
                                                                   transaction: transaction)
                return HVLoadResult.renderStateForReset(renderState: renderState)
            }
        } catch {
            owsFailDebug("error: \(error)")
            return .reloadTable
        }
    }

    private static func loadRenderStateInternal(viewInfo: HVViewInfo,
                                                transaction: SDSAnyReadTransaction) throws -> HVRenderState {

        let threadFinder = AnyThreadFinder()
        let isViewingArchive = viewInfo.homeViewMode == .archive

        var pinnedThreads = [TSThread]()
        var threads = [TSThread]()

        let pinnedThreadIds = PinnedThreadManager.pinnedThreadIds

        func buildRenderState() -> HVRenderState {
            // Pinned threads are always ordered in the order they were pinned.
            let pinnedThreadsFinal: OrderedDictionary<String, TSThread>
            if isViewingArchive {
                pinnedThreadsFinal = OrderedDictionary()
            } else {
                let existingPinnedThreadIds = pinnedThreads.map { $0.uniqueId }
                pinnedThreadsFinal = OrderedDictionary(
                    keyValueMap: Dictionary(uniqueKeysWithValues: pinnedThreads.map { ($0.uniqueId, $0) }),
                    orderedKeys: pinnedThreadIds.filter { existingPinnedThreadIds.contains($0) }
                )
            }
            let unpinnedThreadsFinal = threads

            return HVRenderState(viewInfo: viewInfo,
                                 pinnedThreads: pinnedThreadsFinal,
                                 unpinnedThreads: unpinnedThreadsFinal)
        }

        // This method is a perf hotspot. To improve perf, we try to leverage
        // the model cache. If any problems arise, we fall back to using
        // threadFinder.enumerateVisibleThreads() which is robust but expensive.
        func loadWithoutCache() throws {
            try threadFinder.enumerateVisibleThreads(isArchived: isViewingArchive, transaction: transaction) { thread in
                if pinnedThreadIds.contains(thread.uniqueId) {
                    pinnedThreads.append(thread)
                } else {
                    threads.append(thread)
                }
            }
        }

        // Loading the mapping from the cache has the following steps:
        //
        // 1. Fetch the uniqueIds for the visible threads.
        let threadIds = try threadFinder.visibleThreadIds(isArchived: isViewingArchive, transaction: transaction)
        guard !threadIds.isEmpty else {
            return buildRenderState()
        }

        // 2. Try to pull as many threads as possible from the cache.
        var threadIdToModelMap: [String: TSThread] = modelReadCaches.threadReadCache.getThreadsIfInCache(forUniqueIds: threadIds,
                                                                                                         transaction: transaction)
        var threadsToLoad = Set(threadIds)
        threadsToLoad.subtract(threadIdToModelMap.keys)

        // 3. Bulk load any threads that are not in the cache in a
        //    single query.
        //
        // NOTE: There's an upper bound on how long SQL queries should be.
        //       We use kMaxIncrementalRowChanges to limit query size.
        guard threadsToLoad.count <= DatabaseChangeObserver.kMaxIncrementalRowChanges else {
            try loadWithoutCache()
            return buildRenderState()
        }

        if !threadsToLoad.isEmpty {
            let loadedThreads = try threadFinder.threads(withThreadIds: threadsToLoad, transaction: transaction)
            guard loadedThreads.count == threadsToLoad.count else {
                owsFailDebug("Loading threads failed.")
                try loadWithoutCache()
                return buildRenderState()
            }
            for thread in loadedThreads {
                threadIdToModelMap[thread.uniqueId] = thread
            }
        }

        guard threadIds.count == threadIdToModelMap.count else {
            owsFailDebug("Missing threads.")
            try loadWithoutCache()
            return buildRenderState()
        }

        // 4. Build the ordered list of threads.
        for threadId in threadIds {
            guard let thread = threadIdToModelMap[threadId] else {
                owsFailDebug("Couldn't read thread: \(threadId)")
                try loadWithoutCache()
                return buildRenderState()
            }

            if pinnedThreadIds.contains(thread.uniqueId) {
                pinnedThreads.append(thread)
            } else {
                threads.append(thread)
            }
        }

        return buildRenderState()
    }

    static func loadRenderStateAndDiff(viewInfo: HVViewInfo,
                                       updatedItemIds: Set<String>,
                                       lastRenderState: HVRenderState,
                                       transaction: SDSAnyReadTransaction) -> HVLoadResult {
        do {
            return try loadRenderStateAndDiffInternal(viewInfo: viewInfo,
                                                      updatedItemIds: updatedItemIds,
                                                      lastRenderState: lastRenderState,
                                                      transaction: transaction)
        } catch {
            owsFailDebug("Error: \(error)")
            // Fail over to reloading the table view with a new render state.
            return loadRenderStateForReset(viewInfo: viewInfo, transaction: transaction)
        }
    }

    private static func loadRenderStateAndDiffInternal(viewInfo: HVViewInfo,
                                                       updatedItemIds allUpdatedItemIds: Set<String>,
                                                       lastRenderState: HVRenderState,
                                                       transaction: SDSAnyReadTransaction) throws -> HVLoadResult {

        // Ignore updates to non-visible threads.
        var updatedItemIds = Set<String>()
        for threadId in allUpdatedItemIds {
            guard let thread = TSThread.anyFetch(uniqueId: threadId, transaction: transaction) else {
                // Missing thread, it was deleted and should no longer be visible.
                continue
            }
            if thread.shouldThreadBeVisible {
                updatedItemIds.insert(threadId)
            }
        }

        let newRenderState = try Bench(title: "loadRenderState for diff (\(viewInfo.homeViewMode))") {
            try Self.loadRenderStateInternal(viewInfo: viewInfo, transaction: transaction)
        }

        let oldPinnedThreadIds: [String] = lastRenderState.pinnedThreads.orderedKeys
        let oldUnpinnedThreadIds: [String] = lastRenderState.unpinnedThreads.map { $0.uniqueId }
        let newPinnedThreadIds: [String] = newRenderState.pinnedThreads.orderedKeys
        let newUnpinnedThreadIds: [String] = newRenderState.unpinnedThreads.map { $0.uniqueId }

        struct HVBatchUpdateValue: BatchUpdateValue {
            let threadUniqueId: String

            var batchUpdateId: String { threadUniqueId }
            var logSafeDescription: String { threadUniqueId }
        }

        let oldPinnedValues = oldPinnedThreadIds.map { HVBatchUpdateValue(threadUniqueId: $0) }
        let newPinnedValues = newPinnedThreadIds.map { HVBatchUpdateValue(threadUniqueId: $0) }
        let oldUnpinnedValues = oldUnpinnedThreadIds.map { HVBatchUpdateValue(threadUniqueId: $0) }
        let newUnpinnedValues = newUnpinnedThreadIds.map { HVBatchUpdateValue(threadUniqueId: $0) }

        let pinnedChangedValues = newPinnedValues.filter { allUpdatedItemIds.contains($0.threadUniqueId) }
        let unpinnedChangedValues = newUnpinnedValues.filter { allUpdatedItemIds.contains($0.threadUniqueId) }

        let pinnedBatchUpdateItems: [BatchUpdate.Item] = try BatchUpdate.build(viewType: .uiTableView,
                                                                               oldValues: oldPinnedValues,
                                                                               newValues: newPinnedValues,
                                                                               changedValues: pinnedChangedValues)
        let unpinnedBatchUpdateItems: [BatchUpdate.Item] = try BatchUpdate.build(viewType: .uiTableView,
                                                                                 oldValues: oldUnpinnedValues,
                                                                                 newValues: newUnpinnedValues,
                                                                                 changedValues: unpinnedChangedValues)

        func rowChangeType(forBatchUpdateType batchUpdateType: BatchUpdateType,
                           homeViewSection: HomeViewSection) -> HVRowChangeType {
            switch batchUpdateType {
            case .delete(let oldIndex):
                return .delete(oldIndexPath: IndexPath(row: oldIndex, section: homeViewSection.rawValue))
            case .insert(let newIndex):
                return .insert(newIndexPath: IndexPath(row: newIndex, section: homeViewSection.rawValue))
            case .move(let oldIndex, let newIndex):
                return .move(oldIndexPath: IndexPath(row: oldIndex, section: homeViewSection.rawValue),
                             newIndexPath: IndexPath(row: newIndex, section: homeViewSection.rawValue))
            case .update(let oldIndex, _):
                return .update(oldIndexPath: IndexPath(row: oldIndex, section: homeViewSection.rawValue))
            }
        }
        func rowChanges(forBatchUpdateItems batchUpdateItems: [BatchUpdate<HVBatchUpdateValue>.Item],
                        homeViewSection: HomeViewSection) -> [HVRowChange] {
            batchUpdateItems.map { batchUpdateItem in
                HVRowChange(type: rowChangeType(forBatchUpdateType: batchUpdateItem.updateType,
                                                homeViewSection: homeViewSection),
                            threadUniqueId: batchUpdateItem.value.threadUniqueId)
            }
        }
        let pinnedRowChanges = rowChanges(forBatchUpdateItems: pinnedBatchUpdateItems,
                                          homeViewSection: .pinned)
        let unpinnedRowChanges = rowChanges(forBatchUpdateItems: unpinnedBatchUpdateItems,
                                            homeViewSection: .unpinned)

        var allRowChanges = pinnedRowChanges + unpinnedRowChanges

        // The "row change" logic above deals with the .pinned and
        // .unpinned sections separately.
        //
        // We need to special-case one kind of update: pinning and
        // unpinning, where a thread moves from one section to the
        // other.
        if pinnedRowChanges.count == 1,
           let pinnedRowChange = pinnedRowChanges.first,
           unpinnedRowChanges.count == 1,
           let unpinnedRowChange = unpinnedRowChanges.first,
           pinnedRowChange.threadUniqueId == unpinnedRowChange.threadUniqueId {

            switch pinnedRowChange.type {
            case .delete(let oldIndexPath):
                switch unpinnedRowChange.type {
                case .insert(let newIndexPath):
                    // Unpin: Move from .pinned to .unpinned section.
                    allRowChanges = [HVRowChange(type: .move(oldIndexPath: oldIndexPath,
                                                             newIndexPath: newIndexPath),
                                                 threadUniqueId: pinnedRowChange.threadUniqueId)]
                default:
                    owsFailDebug("Unexpected changes. pinnedRowChange: \(pinnedRowChange)")
                }
            case .insert(let newIndexPath):
                switch unpinnedRowChange.type {
                case .delete(let oldIndexPath):
                    // Pin: Move from .unpinned to .pinned section.
                    allRowChanges = [HVRowChange(type: .move(oldIndexPath: oldIndexPath,
                                                             newIndexPath: newIndexPath),
                                                 threadUniqueId: pinnedRowChange.threadUniqueId)]
                default:
                    owsFailDebug("Unexpected changes. pinnedRowChange: \(pinnedRowChange)")
                }
            default:
                owsFailDebug("Unexpected changes. pinnedRowChange: \(pinnedRowChange)")
            }
        }

        if allRowChanges.isEmpty {
            return .renderStateWithoutRowChanges(renderState: newRenderState)
        } else {
            return .renderStateWithRowChanges(renderState: newRenderState, rowChanges: allRowChanges)
        }
    }
}

// MARK: -

extension Collection where Element: Equatable {
    func firstIndexAsInt(of element: Element) -> Int? {
        guard let index = firstIndex(of: element) else { return nil }
        return distance(from: startIndex, to: index)
    }
}
