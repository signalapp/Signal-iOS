//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

enum ThreadMappingChange: Int {
    case delete, insert, update, move
}

// MARK: -

struct ThreadMappingSectionChange {
    public let type: ThreadMappingChange
    public let index: UInt
}

// MARK: -

struct ThreadMappingRowChange {

    public let type: ThreadMappingChange

    public let uniqueRowId: String

    /// Will be nil for inserts
    public let oldIndexPath: IndexPath?

    /// Will be nil for deletes
    public let newIndexPath: IndexPath?

    init(type: ThreadMappingChange, uniqueRowId: String, oldIndexPath: IndexPath?, newIndexPath: IndexPath?) {
        #if DEBUG
        switch type {
        case .delete:
            assert(oldIndexPath != nil)
            assert(newIndexPath == nil)
        case .insert:
            assert(oldIndexPath == nil)
            assert(newIndexPath != nil)
        case .update:
            assert(oldIndexPath != nil)
            assert(newIndexPath == nil)
        case .move:
            assert(oldIndexPath != nil)
            assert(newIndexPath != nil)
        }
        #endif

        self.type = type
        self.uniqueRowId = uniqueRowId
        self.oldIndexPath = oldIndexPath
        self.newIndexPath = newIndexPath
    }
}

// MARK: -

struct ThreadMappingDiff {
    public let renderState: HVRenderState
    public let sectionChanges: [ThreadMappingSectionChange]
    public let rowChanges: [ThreadMappingRowChange]
}

// MARK: -

// TODO: Rewrite/Drastically simplify
public class ThreadMapping: NSObject {

    private var pinnedThreads = OrderedDictionary<String, TSThread>()
    private var unpinnedThreads: [TSThread] = []

    private let pinnedSection: Int = HomeViewSection.pinned.rawValue
    private let unpinnedSection: Int = HomeViewSection.unpinned.rawValue

    private let numberOfSections: Int = 1

    private var archiveCount: UInt = 0

    private var inboxCount: UInt = 0

    private var hasPinnedAndUnpinnedThreads: Bool { !pinnedThreads.isEmpty && !unpinnedThreads.isEmpty }

    private var pinnedThreadIds: [String] { pinnedThreads.orderedKeys }

    private let threadFinder = AnyThreadFinder()

    func updateSwallowingErrors(isViewingArchive: Bool, transaction: SDSAnyReadTransaction) -> HVRenderState? {
        AssertIsOnMainThread()

        do {
            return try update(isViewingArchive: isViewingArchive, transaction: transaction)
        } catch {
            owsFailDebug("error: \(error)")
            return nil
        }
    }

    private func update(isViewingArchive: Bool, transaction: SDSAnyReadTransaction) throws -> HVRenderState? {
        AssertIsOnMainThread()

        return try Bench(title: "update thread mapping (\(isViewingArchive ? "archive" : "inbox"))") {
            archiveCount = try threadFinder.visibleThreadCount(isArchived: true, transaction: transaction)
            inboxCount = try threadFinder.visibleThreadCount(isArchived: false, transaction: transaction)
            try self.loadThreads(isViewingArchive: isViewingArchive, transaction: transaction)
            return HVRenderState(pinnedThreads: self.pinnedThreads,
                                 unpinnedThreads: self.unpinnedThreads,
                                 archiveCount: self.archiveCount,
                                 inboxCount: self.inboxCount)
        }
    }

    private func loadThreads(isViewingArchive: Bool, transaction: SDSAnyReadTransaction) throws {

        var pinnedThreads = [TSThread]()
        var threads = [TSThread]()

        let pinnedThreadIds = PinnedThreadManager.pinnedThreadIds

        defer {
            // Pinned threads are always ordered in the order they were pinned.
            if isViewingArchive {
                self.pinnedThreads = OrderedDictionary()
            } else {
                let existingPinnedThreadIds = pinnedThreads.map { $0.uniqueId }
                self.pinnedThreads = OrderedDictionary(
                    keyValueMap: Dictionary(uniqueKeysWithValues: pinnedThreads.map { ($0.uniqueId, $0) }),
                    orderedKeys: pinnedThreadIds.filter { existingPinnedThreadIds.contains($0) }
                )
            }
            self.unpinnedThreads = threads
        }

        // This method is a perf hotspot. To improve perf, we try to leverage
        // the model cache. If any problems arise, we fall back to using
        // threadFinder.enumerateVisibleThreads() which is robust but expensive.
        func loadWithoutCache() throws {
            try self.threadFinder.enumerateVisibleThreads(isArchived: isViewingArchive, transaction: transaction) { thread in
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
        guard !threadIds.isEmpty else { return }

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
            return
        }

        if !threadsToLoad.isEmpty {
            let loadedThreads = try threadFinder.threads(withThreadIds: threadsToLoad, transaction: transaction)
            guard loadedThreads.count == threadsToLoad.count else {
                owsFailDebug("Loading threads failed.")
                try loadWithoutCache()
                return
            }
            for thread in loadedThreads {
                threadIdToModelMap[thread.uniqueId] = thread
            }
        }

        guard threadIds.count == threadIdToModelMap.count else {
            owsFailDebug("Missing threads.")
            try loadWithoutCache()
            return
        }

        // 4. Build the ordered list of threads.
        for threadId in threadIds {
            guard let thread = threadIdToModelMap[threadId] else {
                owsFailDebug("Couldn't read thread: \(threadId)")
                try loadWithoutCache()
                return
            }

            if pinnedThreadIds.contains(thread.uniqueId) {
                pinnedThreads.append(thread)
            } else {
                threads.append(thread)
            }
        }
    }

    func updateAndCalculateDiffSwallowingErrors(isViewingArchive: Bool,
                                                updatedItemIds: Set<String>,
                                                transaction: SDSAnyReadTransaction) -> ThreadMappingDiff? {
        do {
            return try updateAndCalculateDiff(isViewingArchive: isViewingArchive,
                                              updatedItemIds: updatedItemIds,
                                              transaction: transaction)
        } catch {
            owsFailDebug("error: \(error)")
            return nil
        }
    }

    private func updateAndCalculateDiff(isViewingArchive: Bool,
                                        updatedItemIds allUpdatedItemIds: Set<String>,
                                        transaction: SDSAnyReadTransaction) throws -> ThreadMappingDiff? {

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

        let oldPinnedThreadIds: [String] = pinnedThreads.orderedKeys
        let oldUnpinnedThreadIds: [String] = unpinnedThreads.map { $0.uniqueId }
        guard let renderState = try update(isViewingArchive: isViewingArchive,
                                           transaction: transaction) else {
            owsFailDebug("Could not update.")
            return nil
        }
        let newPinnedThreadIds: [String] = pinnedThreads.orderedKeys
        let newUnpinnedThreadIds: [String] = unpinnedThreads.map { $0.uniqueId }

        let allNewThreadIds = Set(newPinnedThreadIds + newUnpinnedThreadIds)

        // We want to be economical and issue as few changes as possible.
        // We can skip some "moves".  E.g. if we "delete" the first item,
        // we don't need to explicitly "move" the other items up an index.
        // In an effort to use as few "moves" as possible, we calculate
        // the "naive" ordering that will occur after the "deletes" and
        // "inserts," then only "move up" items that are not in their
        // final position.  We leverage the fact that items in the
        // conversation view only move upwards when modified.
        var naivePinnedThreadIdOrdering = oldPinnedThreadIds
        var naiveUnpinnedThreadIdOrdering = oldUnpinnedThreadIds

        var rowChanges: [ThreadMappingRowChange] = []

        // 1. Deletes - Always perform deletes before inserts and updates.
        //
        // * The indexPath for deletes uses pre-update indices.
        // * We use `reversed` to ensure that items
        //   are deleted in reverse order, to avoid confusion around
        //   each deletion affecting the indices of subsequent deletions.
        let deletedThreadIds = (oldPinnedThreadIds + oldUnpinnedThreadIds)
            .filter { !newPinnedThreadIds.contains($0) && !newUnpinnedThreadIds.contains($0) }
        for deletedThreadId in deletedThreadIds.reversed() {
            let wasPinned = oldPinnedThreadIds.contains(deletedThreadId)
            let oldThreadIds = wasPinned ? oldPinnedThreadIds : oldUnpinnedThreadIds
            let oldSection = wasPinned ? pinnedSection : unpinnedSection

            guard let oldIndex = oldThreadIds.firstIndexAsInt(of: deletedThreadId) else {
                throw OWSAssertionError("oldIndex was unexpectedly nil")
            }

            owsAssertDebug(newPinnedThreadIds.firstIndexAsInt(of: deletedThreadId) == nil)
            owsAssertDebug(newUnpinnedThreadIds.firstIndexAsInt(of: deletedThreadId) == nil)

            rowChanges.append(ThreadMappingRowChange(type: .delete,
                                                     uniqueRowId: deletedThreadId,
                                                     oldIndexPath: IndexPath(row: oldIndex, section: oldSection),
                                                     newIndexPath: nil))

            func updateNaiveThreadIdOrdering(_ naiveThreadIdOrdering: inout [String]) throws {
                if oldIndex >= 0 && oldIndex < naiveThreadIdOrdering.count {
                    owsAssertDebug(naiveThreadIdOrdering[oldIndex] == deletedThreadId)
                    naiveThreadIdOrdering.remove(at: oldIndex)
                } else {
                    throw OWSAssertionError("Could not delete item.")
                }
            }

            // Update naive ordering to reflect the delete.
            if wasPinned {
                try updateNaiveThreadIdOrdering(&naivePinnedThreadIdOrdering)
            } else {
                try updateNaiveThreadIdOrdering(&naiveUnpinnedThreadIdOrdering)
            }
        }

        // 2. Inserts - Always perform inserts before updates.
        //
        // * The indexPath for inserts uses post-update indices.
        // * We insert in ascending order.
        let insertedThreadIds = (newPinnedThreadIds + newUnpinnedThreadIds)
            .filter { !oldPinnedThreadIds.contains($0) && !oldUnpinnedThreadIds.contains($0) }
        for insertedThreadId in insertedThreadIds {
            let isPinned = newPinnedThreadIds.contains(insertedThreadId)
            let newThreadIds = isPinned ? newPinnedThreadIds : newUnpinnedThreadIds
            let newSection = isPinned ? pinnedSection : unpinnedSection

            owsAssertDebug(oldPinnedThreadIds.firstIndexAsInt(of: insertedThreadId) == nil)
            owsAssertDebug(oldUnpinnedThreadIds.firstIndexAsInt(of: insertedThreadId) == nil)

            guard let newIndex = newThreadIds.firstIndexAsInt(of: insertedThreadId) else {
                throw OWSAssertionError("newIndex was unexpectedly nil")
            }
            rowChanges.append(ThreadMappingRowChange(type: .insert,
                                               uniqueRowId: insertedThreadId,
                                               oldIndexPath: nil,
                                               newIndexPath: IndexPath(row: newIndex, section: newSection)))

            func updateNaiveThreadIdOrdering(_ naiveThreadIdOrdering: inout [String]) throws {
                if newIndex >= 0 && newIndex <= naiveThreadIdOrdering.count {
                    naiveThreadIdOrdering.insert(insertedThreadId, at: newIndex)
                } else {
                    throw OWSAssertionError("Could not insert item.")
                }
            }

            // Update naive ordering to reflect the insert.
            if isPinned {
                try updateNaiveThreadIdOrdering(&naivePinnedThreadIdOrdering)
            } else {
                try updateNaiveThreadIdOrdering(&naiveUnpinnedThreadIdOrdering)
            }
        }

        // 3. Moves
        //
        // * As noted above, we only need to "move" items whose
        //   naive ordering doesn't reflect the final ordering.
        // * The old indexPath for moves uses pre-update indices.
        // * The new indexPath for moves uses post-update indices.
        // * We move in ascending "new" order.
        guard allNewThreadIds == Set<String>(naivePinnedThreadIdOrdering + naiveUnpinnedThreadIdOrdering) else {
            throw OWSAssertionError("Could not map contents.")
        }

        // We first check for items that moved to a new section (e.g.
        // was pinned and is no longer pinned) because we want to perform
        // one "move" animation for it. We don't need to reload these cells
        // because the cell contents do not change between being pinned
        // and unpinned. Using an insert and delete will result in a
        // strange animation when moving to a different section.
        let newlyPinnedThreadIds = Array(Set(newPinnedThreadIds).subtracting(oldPinnedThreadIds))
        let newlyUnpinnedThreadIds = Array(Set(newUnpinnedThreadIds).subtracting(oldUnpinnedThreadIds))
        let movedToNewSectionThreadIds = newlyPinnedThreadIds + newlyUnpinnedThreadIds

        for threadId in movedToNewSectionThreadIds {
            let isPinned = newPinnedThreadIds.contains(threadId)
            let wasPinned = oldPinnedThreadIds.contains(threadId)
            let oldThreadIds = wasPinned ? oldPinnedThreadIds : oldUnpinnedThreadIds
            let newThreadIds = isPinned ? newPinnedThreadIds : newUnpinnedThreadIds

            guard let oldIndex = oldThreadIds.firstIndexAsInt(of: threadId) else {
                continue
            }
            guard let newIndex = newThreadIds.firstIndexAsInt(of: threadId) else {
                throw OWSAssertionError("newIndex was unexpectedly nil.")
            }

            let oldSection = wasPinned ? pinnedSection : unpinnedSection
            let newSection = isPinned ? pinnedSection : unpinnedSection

            rowChanges.append(ThreadMappingRowChange(type: .move,
                                                     uniqueRowId: threadId,
                                                     oldIndexPath: IndexPath(row: oldIndex, section: oldSection),
                                                     newIndexPath: IndexPath(row: newIndex, section: newSection)))

            // Update naive ordering.
            if wasPinned {
                guard let naiveIndex = naivePinnedThreadIdOrdering.firstIndexAsInt(of: threadId) else {
                    throw OWSAssertionError("Missing naive index")
                }
                naivePinnedThreadIdOrdering.remove(at: naiveIndex)
            } else {
                guard let naiveIndex = naiveUnpinnedThreadIdOrdering.firstIndexAsInt(of: threadId) else {
                    throw OWSAssertionError("Missing naive index")
                }
                naiveUnpinnedThreadIdOrdering.remove(at: naiveIndex)
            }

            if isPinned {
                if newIndex >= 0 && newIndex <= naivePinnedThreadIdOrdering.count {
                    naivePinnedThreadIdOrdering.insert(threadId, at: newIndex)
                } else {
                    throw OWSAssertionError("Could not insert item.")
                }
            } else {
                if newIndex >= 0 && newIndex <= naiveUnpinnedThreadIdOrdering.count {
                    naiveUnpinnedThreadIdOrdering.insert(threadId, at: newIndex)
                } else {
                    throw OWSAssertionError("Could not insert item.")
                }
            }
        }

        // We then check for items that moved within the same section.
        // UICollectionView cannot reload and move an item in the same
        // PerformBatchUpdates, so ConversationListViewController
        // performs these moves using an insert and a delete to ensure
        // that the moved item is reloaded. This is how UICollectionView
        // performs reloads internally.

        var movedThreadIds = [String]()
        let possiblyMovedWithinSectionThreadIds = allNewThreadIds
            .subtracting(insertedThreadIds)
            .subtracting(deletedThreadIds)
            .subtracting(movedToNewSectionThreadIds)

        for threadId in possiblyMovedWithinSectionThreadIds {
            let isPinned = newPinnedThreadIds.contains(threadId)
            let wasPinned = oldPinnedThreadIds.contains(threadId)

            owsAssertDebug(isPinned == wasPinned)

            let section = isPinned ? pinnedSection : unpinnedSection

            let oldThreadIds = wasPinned ? oldPinnedThreadIds : oldUnpinnedThreadIds
            let newThreadIds = isPinned ? newPinnedThreadIds : newUnpinnedThreadIds

            guard let oldIndex = oldThreadIds.firstIndexAsInt(of: threadId) else {
                continue
            }
            guard let newIndex = newThreadIds.firstIndexAsInt(of: threadId) else {
                throw OWSAssertionError("newIndex was unexpectedly nil.")
            }

            let naiveThreadIdOrdering = wasPinned ? naivePinnedThreadIdOrdering : naiveUnpinnedThreadIdOrdering

            guard let naiveIndex = naiveThreadIdOrdering.firstIndexAsInt(of: threadId) else {
                throw OWSAssertionError("threadId not in newThreadIdOrdering.")
            }
            guard newIndex != naiveIndex || isPinned != wasPinned else {
                continue
            }

            rowChanges.append(ThreadMappingRowChange(type: .move,
                                                     uniqueRowId: threadId,
                                                     oldIndexPath: IndexPath(row: oldIndex, section: section),
                                                     newIndexPath: IndexPath(row: newIndex, section: section)))
            movedThreadIds.append(threadId)

            func updateNaiveThreadIdOrdering(_ naiveThreadIdOrdering: inout [String]) throws {
                naiveThreadIdOrdering.remove(at: naiveIndex)

                if newIndex >= 0 && newIndex <= naiveThreadIdOrdering.count {
                    naiveThreadIdOrdering.insert(threadId, at: newIndex)
                } else {
                    throw OWSAssertionError("Could not insert item.")
                }
            }

            // Update naive ordering.
            if isPinned {
                try updateNaiveThreadIdOrdering(&naivePinnedThreadIdOrdering)
            } else {
                try updateNaiveThreadIdOrdering(&naiveUnpinnedThreadIdOrdering)
            }
        }

        func logThreadIds(_ threadIds: [String], name: String) {
            Logger.verbose("\(name)[\(threadIds.count)]: \(threadIds.joined(separator: "\n"))")
        }

        // Once the moves are complete, the new ordering should be correct.
        guard newPinnedThreadIds == naivePinnedThreadIdOrdering else {
            logThreadIds(newPinnedThreadIds, name: "newPinnedThreadIds")
            logThreadIds(oldPinnedThreadIds, name: "oldPinnedThreadIds")
            logThreadIds(newUnpinnedThreadIds, name: "newUnpinnedThreadIds")
            logThreadIds(oldUnpinnedThreadIds, name: "oldUnpinnedThreadIds")
            logThreadIds(newlyPinnedThreadIds, name: "newlyPinnedThreadIds")
            logThreadIds(newlyUnpinnedThreadIds, name: "newlyUnpinnedThreadIds")
            logThreadIds(naivePinnedThreadIdOrdering, name: "naivePinnedThreadIdOrdering")
            logThreadIds(naiveUnpinnedThreadIdOrdering, name: "naiveUnpinnedThreadIdOrdering")
            logThreadIds(insertedThreadIds, name: "insertedThreadIds")
            logThreadIds(deletedThreadIds, name: "deletedThreadIds")
            logThreadIds(movedToNewSectionThreadIds, name: "movedToNewSectionThreadIds")
            logThreadIds(Array(possiblyMovedWithinSectionThreadIds), name: "possiblyMovedWithinSectionThreadIds")
            logThreadIds(movedThreadIds, name: "movedThreadIds")
            throw OWSAssertionError("Could not reorder pinned contents.")
        }

        guard newUnpinnedThreadIds == naiveUnpinnedThreadIdOrdering else {
            logThreadIds(newPinnedThreadIds, name: "newPinnedThreadIds")
            logThreadIds(oldPinnedThreadIds, name: "oldPinnedThreadIds")
            logThreadIds(newUnpinnedThreadIds, name: "newUnpinnedThreadIds")
            logThreadIds(oldUnpinnedThreadIds, name: "oldUnpinnedThreadIds")
            logThreadIds(newlyPinnedThreadIds, name: "newlyPinnedThreadIds")
            logThreadIds(newlyUnpinnedThreadIds, name: "newlyUnpinnedThreadIds")
            logThreadIds(naivePinnedThreadIdOrdering, name: "naivePinnedThreadIdOrdering")
            logThreadIds(naiveUnpinnedThreadIdOrdering, name: "naiveUnpinnedThreadIdOrdering")
            logThreadIds(insertedThreadIds, name: "insertedThreadIds")
            logThreadIds(deletedThreadIds, name: "deletedThreadIds")
            logThreadIds(movedToNewSectionThreadIds, name: "movedToNewSectionThreadIds")
            logThreadIds(Array(possiblyMovedWithinSectionThreadIds), name: "possiblyMovedWithinSectionThreadIds")
            logThreadIds(movedThreadIds, name: "movedThreadIds")
            throw OWSAssertionError("Could not reorder unpinned contents.")
        }

        // 4. Updates
        //
        // * The indexPath for updates uses pre-update indices.
        // * We cannot and should not update any item that was inserted, deleted or moved.
        // * Updated items that also moved use "move" changes (above).
        let updatedThreadIds = updatedItemIds
            .subtracting(insertedThreadIds)
            .subtracting(deletedThreadIds)
            .subtracting(movedToNewSectionThreadIds)
            .subtracting(movedThreadIds)
        for updatedThreadId in updatedThreadIds {
            let wasPinned = oldPinnedThreadIds.contains(updatedThreadId)
            let oldThreadIds = wasPinned ? oldPinnedThreadIds : oldUnpinnedThreadIds
            let oldSection = wasPinned ? pinnedSection : unpinnedSection

            guard let oldIndex = oldThreadIds.firstIndexAsInt(of: updatedThreadId) else {
                throw OWSAssertionError("oldIndex was unexpectedly nil")
            }
            rowChanges.append(ThreadMappingRowChange(type: .update,
                                                     uniqueRowId: updatedThreadId,
                                                     oldIndexPath: IndexPath(row: oldIndex, section: oldSection),
                                                     newIndexPath: nil))
        }

        return ThreadMappingDiff(renderState: renderState,
                                 sectionChanges: [],
                                 rowChanges: rowChanges)
    }
}

extension Collection where Element: Equatable {
    func firstIndexAsInt(of element: Element) -> Int? {
        guard let index = firstIndex(of: element) else { return nil }
        return distance(from: startIndex, to: index)
    }
}
