//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

enum CLVRowChangeType {
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

struct CLVRowChange {
    public let type: CLVRowChangeType
    public let threadUniqueId: String

    init(type: CLVRowChangeType, threadUniqueId: String) {
        self.type = type
        self.threadUniqueId = threadUniqueId
    }

    // MARK: -

    public var logSafeDescription: String {
        "\(type), \(threadUniqueId)"
    }
}

// MARK: -

enum CLVLoadResult {
    case renderStateForReset(renderState: CLVRenderState)
    case renderStateWithRowChanges(renderState: CLVRenderState, rowChanges: [CLVRowChange])
    case renderStateWithoutRowChanges(renderState: CLVRenderState)
    case reloadTable
    case noChanges
}

// MARK: -

public class CLVLoader: Dependencies {

    static func loadRenderStateForReset(viewInfo: CLVViewInfo, transaction: SDSAnyReadTransaction) -> CLVLoadResult {
        AssertIsOnMainThread()

        do {
            let renderState = try Self.loadRenderStateInternal(viewInfo: viewInfo, transaction: transaction)
            return CLVLoadResult.renderStateForReset(renderState: renderState)
        } catch {
            owsFailDebug("error: \(error)")
            return .reloadTable
        }
    }

    private static func loadRenderStateInternal(viewInfo: CLVViewInfo,
                                                transaction: SDSAnyReadTransaction) throws -> CLVRenderState {

        let threadFinder = ThreadFinder()
        let isViewingArchive = viewInfo.chatListMode == .archive

        var pinnedThreads = [TSThread]()
        var threads = [TSThread]()

        let pinnedThreadIds = PinnedThreadManager.pinnedThreadIds

        func buildRenderState() -> CLVRenderState {
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

            return CLVRenderState(viewInfo: viewInfo,
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
            if DebugFlags.internalLogging {
                Logger.info("[Scroll Perf Debug] Loading without cache because too many incremental row changes.")
            }
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

            if !isViewingArchive && pinnedThreadIds.contains(thread.uniqueId) {
                pinnedThreads.append(thread)
            } else {
                threads.append(thread)
            }
        }

        return buildRenderState()
    }

    static func loadRenderStateAndDiff(viewInfo: CLVViewInfo,
                                       updatedItemIds: Set<String>,
                                       lastRenderState: CLVRenderState,
                                       transaction: SDSAnyReadTransaction) -> CLVLoadResult {
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

    private static func loadRenderStateAndDiffInternal(viewInfo: CLVViewInfo,
                                                       updatedItemIds allUpdatedItemIds: Set<String>,
                                                       lastRenderState: CLVRenderState,
                                                       transaction: SDSAnyReadTransaction) throws -> CLVLoadResult {

        // Ignore updates to non-visible threads.
        var updatedItemIds = Set<String>()
        for threadId in allUpdatedItemIds {
            guard let thread = TSThread.anyFetch(uniqueId: threadId, transaction: transaction) else {
                // Missing thread, it was deleted and should no longer be visible.
                continue
            }
            if DebugFlags.internalLogging {
                Logger.info("[Scroll Perf Debug] Thread triggering update: \(thread.uniqueId), isGV1: \(thread.isGroupV1Thread), isGV2: \(thread.isGroupV2Thread)")
            }
            if thread.shouldThreadBeVisible {
                updatedItemIds.insert(threadId)
            }
        }

        if DebugFlags.internalLogging {
            Logger.info("[Scroll Perf Debug] About to do loadRenderStateInternal")
        }
        let newRenderState = try Self.loadRenderStateInternal(viewInfo: viewInfo, transaction: transaction)

        let oldPinnedThreadIds: [String] = lastRenderState.pinnedThreads.orderedKeys
        let oldUnpinnedThreadIds: [String] = lastRenderState.unpinnedThreads.map { $0.uniqueId }
        let newPinnedThreadIds: [String] = newRenderState.pinnedThreads.orderedKeys
        let newUnpinnedThreadIds: [String] = newRenderState.unpinnedThreads.map { $0.uniqueId }

        struct CLVBatchUpdateValue: BatchUpdateValue {
            let threadUniqueId: String

            var batchUpdateId: String { threadUniqueId }
        }

        let oldPinnedValues = oldPinnedThreadIds.map { CLVBatchUpdateValue(threadUniqueId: $0) }
        let newPinnedValues = newPinnedThreadIds.map { CLVBatchUpdateValue(threadUniqueId: $0) }
        let oldUnpinnedValues = oldUnpinnedThreadIds.map { CLVBatchUpdateValue(threadUniqueId: $0) }
        let newUnpinnedValues = newUnpinnedThreadIds.map { CLVBatchUpdateValue(threadUniqueId: $0) }

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
                           chatListSection: ChatListSection) -> CLVRowChangeType {
            switch batchUpdateType {
            case .delete(let oldIndex):
                return .delete(oldIndexPath: IndexPath(row: oldIndex, section: chatListSection.rawValue))
            case .insert(let newIndex):
                return .insert(newIndexPath: IndexPath(row: newIndex, section: chatListSection.rawValue))
            case .move(let oldIndex, let newIndex):
                return .move(oldIndexPath: IndexPath(row: oldIndex, section: chatListSection.rawValue),
                             newIndexPath: IndexPath(row: newIndex, section: chatListSection.rawValue))
            case .update(let oldIndex, _):
                return .update(oldIndexPath: IndexPath(row: oldIndex, section: chatListSection.rawValue))
            }
        }
        func rowChanges(forBatchUpdateItems batchUpdateItems: [BatchUpdate<CLVBatchUpdateValue>.Item],
                        chatListSection: ChatListSection) -> [CLVRowChange] {
            batchUpdateItems.map { batchUpdateItem in
                CLVRowChange(type: rowChangeType(forBatchUpdateType: batchUpdateItem.updateType,
                                                 chatListSection: chatListSection),
                            threadUniqueId: batchUpdateItem.value.threadUniqueId)
            }
        }
        let pinnedRowChanges = rowChanges(forBatchUpdateItems: pinnedBatchUpdateItems,
                                          chatListSection: .pinned)
        let unpinnedRowChanges = rowChanges(forBatchUpdateItems: unpinnedBatchUpdateItems,
                                            chatListSection: .unpinned)

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
                    allRowChanges = [CLVRowChange(type: .move(oldIndexPath: oldIndexPath,
                                                             newIndexPath: newIndexPath),
                                                 threadUniqueId: pinnedRowChange.threadUniqueId)]
                default:
                    owsFailDebug("Unexpected changes. pinnedRowChange: \(pinnedRowChange)")
                }
            case .insert(let newIndexPath):
                switch unpinnedRowChange.type {
                case .delete(let oldIndexPath):
                    // Pin: Move from .unpinned to .pinned section.
                    allRowChanges = [CLVRowChange(type: .move(oldIndexPath: oldIndexPath,
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
