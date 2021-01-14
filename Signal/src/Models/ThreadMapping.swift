//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public enum ThreadMappingChange: Int {
    case delete, insert, update, move
}

@objc
public class ThreadMappingSectionChange: NSObject {

    @objc
    public let type: ThreadMappingChange

    @objc
    public let index: UInt

    init(type: ThreadMappingChange, index: UInt) {
        self.type = type
        self.index = index
    }
}

@objc
public class ThreadMappingRowChange: NSObject {

    @objc
    public let type: ThreadMappingChange

    @objc
    public let uniqueRowId: String

    /// Will be nil for inserts
    @objc
    public let oldIndexPath: IndexPath?

    /// Will be nil for deletes
    @objc
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

@objc
public class ThreadMappingDiff: NSObject {

    @objc
    let sectionChanges: [ThreadMappingSectionChange]

    @objc
    let rowChanges: [ThreadMappingRowChange]

    init(sectionChanges: [ThreadMappingSectionChange], rowChanges: [ThreadMappingRowChange]) {
        self.sectionChanges = sectionChanges
        self.rowChanges = rowChanges
    }
}

// MARK: -

@objc
class ThreadMapping: NSObject {

    // MARK: - Dependencies

    private var threadReadCache: ThreadReadCache {
        SSKEnvironment.shared.modelReadCaches.threadReadCache
    }

    // MARK: -

    private var pinnedThreads = OrderedDictionary<String, TSThread>()
    private var unpinnedThreads: [TSThread] = []

    private let pinnedSection: Int = ConversationListViewControllerSection.pinned.rawValue
    private let unpinnedSection: Int = ConversationListViewControllerSection.unpinned.rawValue

    @objc
    let numberOfSections: Int = 1

    @objc
    var archiveCount: UInt = 0

    @objc
    var inboxCount: UInt = 0

    @objc
    var hasPinnedAndUnpinnedThreads: Bool { !pinnedThreads.orderedKeys.isEmpty && !unpinnedThreads.isEmpty }

    @objc
    var pinnedThreadIds: [String] { pinnedThreads.orderedKeys }

    @objc(indexPathForUniqueId:)
    func indexPath(uniqueId: String) -> IndexPath? {
        if let index = (unpinnedThreads.firstIndex { $0.uniqueId == uniqueId}) {
            return IndexPath(item: index, section: unpinnedSection)
        } else if let index = (pinnedThreads.orderedKeys.firstIndex { $0 == uniqueId}) {
            return IndexPath(item: index, section: pinnedSection)
        } else {
            return nil
        }
    }

    @objc
    func numberOfItems(inSection section: Int) -> Int {
        if section == pinnedSection {
            return pinnedThreads.count
        } else if section == unpinnedSection {
            return unpinnedThreads.count
        } else {
            owsFailDebug("section had unexpected value: \(section)")
            return 0
        }
    }

    @objc(threadForIndexPath:)
    func thread(indexPath: IndexPath) -> TSThread? {
        switch indexPath.section {
        case pinnedSection:
            return pinnedThreads.orderedValues[safe: indexPath.item]
        case unpinnedSection:
            return unpinnedThreads[safe: indexPath.item]
        default:
            owsFailDebug("Unexpected index path \(indexPath)")
            return nil
        }
    }

    @objc(indexPathAfterThread:)
    func indexPath(after thread: TSThread?) -> IndexPath? {
        let isPinnedThread: Bool
        if let thread = thread, pinnedThreads.orderedKeys.contains(thread.uniqueId) {
            isPinnedThread = true
        } else {
            isPinnedThread = false
        }

        let section = isPinnedThread ? pinnedSection : unpinnedSection
        let threadsInSection = isPinnedThread ? pinnedThreads.orderedValues : unpinnedThreads

        guard !threadsInSection.isEmpty else { return nil }

        let firstIndexPath = IndexPath(item: 0, section: section)

        guard let thread = thread else { return firstIndexPath }
        guard let index = threadsInSection.firstIndex(where: { $0.uniqueId == thread.uniqueId}) else { return firstIndexPath }

        if index < (threadsInSection.count - 1) {
            return IndexPath(item: index + 1, section: section)
        } else {
            return nil
        }
    }

    @objc(indexPathBeforeThread:)
    func indexPath(before thread: TSThread?) -> IndexPath? {
        let isPinnedThread: Bool
        if let thread = thread, pinnedThreads.orderedKeys.contains(thread.uniqueId) {
            isPinnedThread = true
        } else {
            isPinnedThread = false
        }

        let section = isPinnedThread ? pinnedSection : unpinnedSection
        let threadsInSection = isPinnedThread ? pinnedThreads.orderedValues : unpinnedThreads

        guard !threadsInSection.isEmpty else { return nil }

        let lastIndexPath = IndexPath(item: threadsInSection.count - 1, section: section)

        guard let thread = thread else { return lastIndexPath }
        guard let index = threadsInSection.firstIndex(where: { $0.uniqueId == thread.uniqueId}) else { return lastIndexPath }

        if index > 0 {
            return IndexPath(item: index - 1, section: section)
        } else {
            return nil
        }
    }

    let threadFinder = AnyThreadFinder()

    @objc
    func updateSwallowingErrors(isViewingArchive: Bool, transaction: SDSAnyReadTransaction) {
        do {
            try update(isViewingArchive: isViewingArchive, transaction: transaction)
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    func update(isViewingArchive: Bool, transaction: SDSAnyReadTransaction) throws {
        try Bench(title: "update thread mapping (\(isViewingArchive ? "archive" : "inbox"))") {
            archiveCount = try threadFinder.visibleThreadCount(isArchived: true, transaction: transaction)
            inboxCount = try threadFinder.visibleThreadCount(isArchived: false, transaction: transaction)
            try self.loadThreads(isViewingArchive: isViewingArchive, transaction: transaction)
        }
    }

    private func loadThreads(isViewingArchive: Bool, transaction: SDSAnyReadTransaction) throws {

        var pinnedThreads = [TSThread]()
        var threads = [TSThread]()

        var pinnedThreadIds = PinnedThreadManager.pinnedThreadIds

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
        var threadIdToModelMap: [String: TSThread] = threadReadCache.getThreadsIfInCache(forUniqueIds: threadIds,
                                                                                         transaction: transaction)
        var threadsToLoad = Set(threadIds)
        threadsToLoad.subtract(threadIdToModelMap.keys)

        // 3. Bulk load any threads that are not in the cache in a
        //    single query.
        //
        // NOTE: There's an upper bound on how long SQL queries should be.
        //       We use kMaxIncrementalRowChanges to limit query size.
        guard threadsToLoad.count <= UIDatabaseObserver.kMaxIncrementalRowChanges else {
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

    @objc
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

    @objc
    func updateAndCalculateDiff(isViewingArchive: Bool,
                                updatedItemIds allUpdatedItemIds: Set<String>,
                                transaction: SDSAnyReadTransaction) throws -> ThreadMappingDiff {

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
        try update(isViewingArchive: isViewingArchive, transaction: transaction)
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

        return ThreadMappingDiff(sectionChanges: [], rowChanges: rowChanges)
    }

    // For performance reasons, the database modification notifications are used
    // to determine which items were modified.  If YapDatabase ever changes the
    // structure or semantics of these notifications, we'll need to update this
    // code to reflect that.
    @objc
    public func updatedYapItemIds(forNotifications notifications: [NSNotification]) -> Set<String> {
        // We'll move this into the Yap adapter when addressing updates/observation
        let viewName: String = TSThreadDatabaseViewExtensionName

        var updatedItemIds = Set<String>()
        for notification in notifications {
            // Unpack the YDB notification, looking for row changes.
            guard let userInfo =
                notification.userInfo else {
                    owsFailDebug("Missing userInfo.")
                    continue
            }
            guard let viewChangesets =
                userInfo[YapDatabaseExtensionsKey] as? NSDictionary else {
                    // No changes for any views, skip.
                    continue
            }
            guard let changeset =
                viewChangesets[viewName] as? NSDictionary else {
                    // No changes for this view, skip.
                    continue
            }
            // This constant matches a private constant in YDB.
            let changeset_key_changes: String = "changes"
            guard let changesetChanges = changeset[changeset_key_changes] as? [Any] else {
                owsFailDebug("Missing changeset changes.")
                continue
            }
            for change in changesetChanges {
                if change as? YapDatabaseViewSectionChange != nil {
                    // Ignore.
                } else if let rowChange = change as? YapDatabaseViewRowChange {
                    updatedItemIds.insert(rowChange.collectionKey.key)
                } else {
                    owsFailDebug("Invalid change: \(type(of: change)).")
                    continue
                }
            }
        }

        return updatedItemIds
    }
}

extension Collection where Element: Equatable {
    func firstIndexAsInt(of element: Element) -> Int? {
        guard let index = firstIndex(of: element) else { return nil }
        return distance(from: startIndex, to: index)
    }
}
