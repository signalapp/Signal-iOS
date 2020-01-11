//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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

    private var threads: [TSThread] = []

    private let kSection: Int = ConversationListViewControllerSection.conversations.rawValue

    @objc
    let numberOfSections: Int = 1

    @objc
    var archiveCount: UInt = 0

    @objc
    var inboxCount: UInt = 0

    @objc(indexPathForUniqueId:)
    func indexPath(uniqueId: String) -> IndexPath? {
        guard let index = (threads.firstIndex { $0.uniqueId == uniqueId}) else {
            return nil
        }
        return IndexPath(item: index, section: kSection)
    }

    @objc
    func numberOfItems(inSection section: Int) -> Int {
        guard section == kSection else {
            owsFailDebug("section had unexpected value: \(section)")
            return 0
        }
        return threads.count
    }

    @objc(threadForIndexPath:)
    func thread(indexPath: IndexPath) -> TSThread {
        assert(indexPath.item <= threads.count)
        return threads[indexPath.item]
    }

    @objc(indexPathAfterThread:)
    func indexPath(after thread: TSThread?) -> IndexPath? {
        guard !threads.isEmpty else { return nil }

        let firstIndexPath = IndexPath(item: 0, section: kSection)

        guard let thread = thread else { return firstIndexPath }
        guard let index = threads.firstIndex(where: { $0.uniqueId == thread.uniqueId}) else { return firstIndexPath }

        if index < (threads.count - 1) {
            return IndexPath(item: index + 1, section: kSection)
        } else {
            return nil
        }
    }

    @objc(indexPathBeforeThread:)
    func indexPath(before thread: TSThread?) -> IndexPath? {
        guard !threads.isEmpty else { return nil }

        let lastIndexPath = IndexPath(item: threads.count - 1, section: kSection)

        guard let thread = thread else { return lastIndexPath }
        guard let index = threads.firstIndex(where: { $0.uniqueId == thread.uniqueId}) else { return lastIndexPath }

        if index > 0 {
            return IndexPath(item: index - 1, section: kSection)
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
            var newThreads: [TSThread] = []
            try threadFinder.enumerateVisibleThreads(isArchived: isViewingArchive, transaction: transaction) { thread in
                newThreads.append(thread)
            }
            threads = newThreads
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

    func assertionError(_ description: String) -> Error {
        return OWSErrorMakeAssertionError(description)
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

        let oldThreadIds: [String] = threads.map { $0.uniqueId }
        try update(isViewingArchive: isViewingArchive, transaction: transaction)
        let newThreadIds: [String] = threads.map { $0.uniqueId }

        // We want to be economical and issue as few changes as possible.
        // We can skip some "moves".  E.g. if we "delete" the first item,
        // we don't need to explicitly "move" the other items up an index.
        // In an effort to use as few "moves" as possible, we calculate
        // the "naive" ordering that will occur after the "deletes" and
        // "inserts," then only "move up" items that are not in their
        // final position.  We leverage the fact that items in the
        // conversation view only move upwards when modified.
        var naiveThreadIdOrdering: [String] = oldThreadIds

        var rowChanges: [ThreadMappingRowChange] = []

        // 1. Deletes - Always perform deletes before inserts and updates.
        //
        // * The indexPath for deletes uses pre-update indices.
        // * We use `reversed` to ensure that items
        //   are deleted in reverse order, to avoid confusion around
        //   each deletion affecting the indices of subsequent deletions.
        let deletedThreadIds = oldThreadIds.filter { !newThreadIds.contains($0) }
        for deletedThreadId in deletedThreadIds.reversed() {
            guard let oldIndex = oldThreadIds.firstIndexAsInt(of: deletedThreadId) else {
                throw assertionError("oldIndex was unexpectedly nil")
            }
            assert(newThreadIds.firstIndexAsInt(of: deletedThreadId) == nil)
            rowChanges.append(ThreadMappingRowChange(type: .delete,
                                                     uniqueRowId: deletedThreadId,
                                                     oldIndexPath: IndexPath(row: oldIndex, section: kSection),
                                                     newIndexPath: nil))

            // Update naive ordering to reflect the delete.
            if oldIndex >= 0 && oldIndex < naiveThreadIdOrdering.count {
                assert(naiveThreadIdOrdering[oldIndex] == deletedThreadId)
                naiveThreadIdOrdering.remove(at: oldIndex)
            } else {
                throw assertionError("Could not delete item.")
            }
        }

        // 2. Inserts - Always perform inserts before updates.
        //
        // * The indexPath for inserts uses post-update indices.
        // * We insert in ascending order.
        let insertedThreadIds = newThreadIds.filter { !oldThreadIds.contains($0) }
        for insertedThreadId in insertedThreadIds {
            assert(oldThreadIds.firstIndexAsInt(of: insertedThreadId) == nil)
            guard let newIndex = newThreadIds.firstIndexAsInt(of: insertedThreadId) else {
                throw assertionError("newIndex was unexpectedly nil")
            }
            rowChanges.append(ThreadMappingRowChange(type: .insert,
                                               uniqueRowId: insertedThreadId,
                                               oldIndexPath: nil,
                                               newIndexPath: IndexPath(row: newIndex, section: kSection)))

            // Update naive ordering to reflect the insert.
            if newIndex >= 0 && newIndex <= naiveThreadIdOrdering.count {
                naiveThreadIdOrdering.insert(insertedThreadId, at: newIndex)
            } else {
                throw assertionError("Could not insert item.")
            }
        }

        // 3. Moves
        //
        // * As noted above, we only need to "move" items whose
        //   naive ordering doesn't reflect the final ordering.
        // * The old indexPath for moves uses pre-update indices.
        // * The new indexPath for moves uses post-update indices.
        // * UICollectionView cannot reload and move an item in the same
        //   PerformBatchUpdates, so ConversationListViewController
        //   performs moves using an insert and a delete to ensure that
        //   the moved item is reloaded.  This is how UICollectionView
        //   performs reloads internally.
        // * We move in ascending "new" order.
        guard Set<String>(newThreadIds) == Set<String>(naiveThreadIdOrdering) else {
            throw assertionError("Could not map contents.")
        }

        var movedThreadIds = [String]()
        for threadId in newThreadIds {
            guard let oldIndex = oldThreadIds.firstIndexAsInt(of: threadId) else {
                continue
            }
            guard let newIndex = newThreadIds.firstIndexAsInt(of: threadId) else {
                throw assertionError("newIndex was unexpectedly nil.")
            }
            guard let naiveIndex = naiveThreadIdOrdering.firstIndexAsInt(of: threadId) else {
                throw assertionError("threadId not in newThreadIdOrdering.")
            }
            guard newIndex != naiveIndex else {
                continue
            }
            rowChanges.append(ThreadMappingRowChange(type: .move,
                                                     uniqueRowId: threadId,
                                                     oldIndexPath: IndexPath(row: oldIndex, section: kSection),
                                                     newIndexPath: IndexPath(row: newIndex, section: kSection)))
            movedThreadIds.append(threadId)
            // Update naive ordering.
            naiveThreadIdOrdering.remove(at: naiveIndex)
            if newIndex >= 0 && newIndex <= naiveThreadIdOrdering.count {
                naiveThreadIdOrdering.insert(threadId, at: newIndex)
            } else {
                throw assertionError("Could not insert item.")
            }
        }
        // Once the moves are complete, the new ordering should be correct.
        guard newThreadIds == naiveThreadIdOrdering else {
            throw assertionError("Could not reorder contents.")
        }

        // 4. Updates
        //
        // * The indexPath for updates uses pre-update indices.
        // * We cannot and should not update any item that was inserted, deleted or moved.
        // * Updated items that also moved use "move" changes (above).
        let updatedThreadIds = updatedItemIds.subtracting(insertedThreadIds).subtracting(deletedThreadIds).subtracting(movedThreadIds)
        for updatedThreadId in updatedThreadIds {
            guard let oldIndex = oldThreadIds.firstIndexAsInt(of: updatedThreadId) else {
                throw assertionError("oldIndex was unexpectedly nil")
            }
            rowChanges.append(ThreadMappingRowChange(type: .update,
                                                     uniqueRowId: updatedThreadId,
                                                     oldIndexPath: IndexPath(row: oldIndex, section: kSection),
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
