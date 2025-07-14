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
    case reloadTable
    case noChanges
}

// MARK: -

public class CLVLoader {

    static func loadRenderStateForReset(viewInfo: CLVViewInfo, transaction: DBReadTransaction) -> CLVLoadResult {
        AssertIsOnMainThread()

        do {
            let renderState = try Self.loadRenderStateInternal(viewInfo: viewInfo, transaction: transaction)
            return CLVLoadResult.renderStateForReset(renderState: renderState)
        } catch {
            owsFailDebug("error: \(error)")
            return .reloadTable
        }
    }

    private static func loadRenderStateInternal(viewInfo: CLVViewInfo, transaction: DBReadTransaction) throws -> CLVRenderState {
        let threadFinder = ThreadFinder()
        let isViewingArchive = viewInfo.chatListMode == .archive

        let pinnedThreadUniqueIds = DependenciesBridge.shared.pinnedThreadStore
            .pinnedThreadIds(tx: transaction)

        let visibleThreadUniqueIds: [String]
        if FeatureFlags.moveDraftsUpChatList {
            if isViewingArchive {
                visibleThreadUniqueIds = try threadFinder.internal_visibleArchivedThreadIds(transaction: transaction)
            } else {
                visibleThreadUniqueIds = try threadFinder.internal_visibleInboxThreadIds(
                    filteredBy: viewInfo.inboxFilter,
                    requiredVisibleThreadIds: viewInfo.requiredVisibleThreadIds,
                    transaction: transaction
                )
            }
        } else {
            if isViewingArchive {
                visibleThreadUniqueIds = try threadFinder.visibleArchivedThreadIds(transaction: transaction)
            } else {
                visibleThreadUniqueIds = try threadFinder.visibleInboxThreadIds(
                    filteredBy: viewInfo.inboxFilter,
                    requiredVisibleThreadIds: viewInfo.requiredVisibleThreadIds,
                    transaction: transaction
                )
            }
        }

        var pinnedThreadUniqueIdsToRender = Set<String>()
        var unpinnedThreadUniqueIdsForRender = [String]()
        for threadUniqueId in visibleThreadUniqueIds {
            if !isViewingArchive && pinnedThreadUniqueIds.contains(threadUniqueId) {
                pinnedThreadUniqueIdsToRender.insert(threadUniqueId)
            } else {
                unpinnedThreadUniqueIdsForRender.append(threadUniqueId)
            }
        }

        // Preserve the order from pinnedThreadUniqueIds
        let orderedPinnedThreadUniqueIdsForRender = pinnedThreadUniqueIds.filter(pinnedThreadUniqueIdsToRender.contains(_:))

        return CLVRenderState(
            viewInfo: viewInfo,
            pinnedThreadUniqueIds: orderedPinnedThreadUniqueIdsForRender,
            unpinnedThreadUniqueIds: unpinnedThreadUniqueIdsForRender
        )
    }

    static func loadRenderStateAndDiff(viewInfo: CLVViewInfo,
                                       updatedItemIds: Set<String>,
                                       lastRenderState: CLVRenderState,
                                       transaction: DBReadTransaction) -> CLVLoadResult {
        do {
            return try loadRenderStateAndDiffInternal(
                viewInfo: viewInfo,
                updatedItemIds: updatedItemIds,
                lastRenderState: lastRenderState,
                transaction: transaction
            )
        } catch {
            owsFailDebug("Error: \(error)")
            // Fail over to reloading the table view with a new render state.
            return loadRenderStateForReset(viewInfo: viewInfo, transaction: transaction)
        }
    }

    static func newRenderStateWithViewInfo(_ viewInfo: CLVViewInfo, lastRenderState: CLVRenderState) -> CLVLoadResult {
        .renderStateWithRowChanges(
            renderState: CLVRenderState(
                viewInfo: viewInfo,
                pinnedThreadUniqueIds: lastRenderState.pinnedThreadUniqueIds,
                unpinnedThreadUniqueIds: lastRenderState.unpinnedThreadUniqueIds
            ),
            rowChanges: []
        )
    }

    private static func loadRenderStateAndDiffInternal(viewInfo: CLVViewInfo,
                                                       updatedItemIds allUpdatedItemIds: Set<String>,
                                                       lastRenderState: CLVRenderState,
                                                       transaction: DBReadTransaction) throws -> CLVLoadResult {

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

        let newRenderState = try Self.loadRenderStateInternal(viewInfo: viewInfo, transaction: transaction)

        let oldPinnedThreadIds: [String] = lastRenderState.pinnedThreadUniqueIds
        let oldUnpinnedThreadIds: [String] = lastRenderState.unpinnedThreadUniqueIds
        let newPinnedThreadIds: [String] = newRenderState.pinnedThreadUniqueIds
        let newUnpinnedThreadIds: [String] = newRenderState.unpinnedThreadUniqueIds

        struct CLVBatchUpdateValue: BatchUpdateValue {
            let threadUniqueId: String

            var batchUpdateId: String { threadUniqueId }
        }

        let oldPinnedValues = oldPinnedThreadIds.map { CLVBatchUpdateValue(threadUniqueId: $0) }
        let newPinnedValues = newPinnedThreadIds.map { CLVBatchUpdateValue(threadUniqueId: $0) }
        let oldUnpinnedValues = oldUnpinnedThreadIds.map { CLVBatchUpdateValue(threadUniqueId: $0) }
        let newUnpinnedValues = newUnpinnedThreadIds.map { CLVBatchUpdateValue(threadUniqueId: $0) }

        let pinnedChangedValues = newPinnedValues.filter { updatedItemIds.contains($0.threadUniqueId) }
        let unpinnedChangedValues = newUnpinnedValues.filter { updatedItemIds.contains($0.threadUniqueId) }

        let pinnedBatchUpdateItems: [BatchUpdate.Item] = try BatchUpdate.build(viewType: .uiTableView,
                                                                               oldValues: oldPinnedValues,
                                                                               newValues: newPinnedValues,
                                                                               changedValues: pinnedChangedValues)
        let unpinnedBatchUpdateItems: [BatchUpdate.Item] = try BatchUpdate.build(viewType: .uiTableView,
                                                                                 oldValues: oldUnpinnedValues,
                                                                                 newValues: newUnpinnedValues,
                                                                                 changedValues: unpinnedChangedValues)

        /// For a given batch update, build a `CLVRowChangeType` with an
        /// `IndexPath` in the appropriate section.
        ///
        /// The section index is looked up dynamically based on change type, from
        /// either the new or old render state (e.g., deletes use old index paths
        /// while insertions use new index paths).
        func rowChangeType(forBatchUpdateType batchUpdateType: BatchUpdateType, section: (CLVRenderState) -> Int) -> CLVRowChangeType {
            switch batchUpdateType {
            case .delete(let oldIndex):
                .delete(oldIndexPath: IndexPath(row: oldIndex, section: section(lastRenderState)))
            case .insert(let newIndex):
                .insert(newIndexPath: IndexPath(row: newIndex, section: section(newRenderState)))
            case .move(let oldIndex, let newIndex):
                .move(
                    oldIndexPath: IndexPath(row: oldIndex, section: section(lastRenderState)),
                    newIndexPath: IndexPath(row: newIndex, section: section(newRenderState))
                )
            case .update(let oldIndex, _):
                .update(oldIndexPath: IndexPath(row: oldIndex, section: section(lastRenderState)))
            }
        }

        func rowChanges(forBatchUpdateItems batchUpdateItems: [BatchUpdate<CLVBatchUpdateValue>.Item], section: (CLVRenderState) -> Int) -> [CLVRowChange] {
            batchUpdateItems.map { item in
                CLVRowChange(
                    type: rowChangeType(forBatchUpdateType: item.updateType, section: section),
                    threadUniqueId: item.value.threadUniqueId
                )
            }
        }

        let pinnedRowChanges = rowChanges(forBatchUpdateItems: pinnedBatchUpdateItems, section: { $0.sectionIndex(for: .pinned)! })
        let unpinnedRowChanges = rowChanges(forBatchUpdateItems: unpinnedBatchUpdateItems, section: { $0.sectionIndex(for: .unpinned)! })

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

        return .renderStateWithRowChanges(renderState: newRenderState, rowChanges: allRowChanges)
    }
}

// MARK: -

extension Collection where Element: Equatable {
    func firstIndexAsInt(of element: Element) -> Int? {
        guard let index = firstIndex(of: element) else { return nil }
        return distance(from: startIndex, to: index)
    }
}
