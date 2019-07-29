//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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
            assert(newIndexPath != nil)
            assert(oldIndexPath == newIndexPath)
        case .move:
            assert(oldIndexPath != nil)
            assert(newIndexPath != nil)
            assert(oldIndexPath != newIndexPath)
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

    private let kSection: Int = HomeViewControllerSection.conversations.rawValue

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
        archiveCount = try threadFinder.threadCount(isArchived: true, transaction: transaction)
        inboxCount = try threadFinder.threadCount(isArchived: false, transaction: transaction)
        var newThreads: [TSThread] = []
        try threadFinder.enumerateThreads(isArchived: isViewingArchive, transaction: transaction) { thread in
            newThreads.append(thread)
        }
        threads = newThreads
    }

    @objc
    func updateAndCalculateDiffSwallowingErrors(isViewingArchive: Bool,
                                                updatedItemIds: Set<String>,
                                                transaction: SDSAnyReadTransaction) -> ThreadMappingDiff {
        do {
            return try updateAndCalculateDiff(isViewingArchive: isViewingArchive,
                                              updatedItemIds: updatedItemIds,
                                              transaction: transaction)
        } catch {
            owsFailDebug("error: \(error)")
            return ThreadMappingDiff(sectionChanges: [], rowChanges: [])
        }
    }

    func assertionError(_ description: String) -> Error {
        return OWSErrorMakeAssertionError(description)
    }

    @objc
    func updateAndCalculateDiff(isViewingArchive: Bool,
                                updatedItemIds: Set<String>,
                                transaction: SDSAnyReadTransaction) throws -> ThreadMappingDiff {

        let oldThreadIds: [String] = threads.map { $0.uniqueId! }
        try update(isViewingArchive: isViewingArchive, transaction: transaction)
        let newThreadIds: [String] = threads.map { $0.uniqueId! }

        var rowChanges: [ThreadMappingRowChange] = []

        // 1. Deletes - Always perform deletes before inserts and updates.
        //
        // NOTE: We use `reversed` to ensure that items
        //       are deleted in reverse order, to avoid confusion around
        //       each deletion affecting the indices of subsequent deletions.
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
        }

        // 2. Inserts - Always perform inserts before updates.
        //
        // NOTE: We DO NOT use `reversed`
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
        }

        let exlusivelyUpdatedThreadIds = updatedItemIds.subtracting(insertedThreadIds).subtracting(deletedThreadIds)
        for updatedThreadId in exlusivelyUpdatedThreadIds {
            guard let oldIndex = oldThreadIds.firstIndexAsInt(of: updatedThreadId) else {
                throw assertionError("oldIndex was unexpectedly nil")
            }
            guard let newIndex = newThreadIds.firstIndexAsInt(of: updatedThreadId) else {
                throw assertionError("oldIndex was unexpectedly nil")
            }
            if oldIndex != newIndex {
                rowChanges.append(ThreadMappingRowChange(type: .move,
                                                   uniqueRowId: updatedThreadId,
                                                   oldIndexPath: IndexPath(row: oldIndex, section: kSection),
                                                   newIndexPath: IndexPath(row: newIndex, section: kSection)))
            } else {
                rowChanges.append(ThreadMappingRowChange(type: .update,
                                                   uniqueRowId: updatedThreadId,
                                                   oldIndexPath: IndexPath(row: oldIndex, section: kSection),
                                                   newIndexPath: IndexPath(row: newIndex, section: kSection)))
            }
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
