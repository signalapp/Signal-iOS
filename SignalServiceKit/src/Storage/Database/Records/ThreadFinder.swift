//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

public protocol ThreadFinder {
    associatedtype ReadTransaction

    func visibleThreadCount(isArchived: Bool, transaction: ReadTransaction) throws -> UInt
    func sortedVisibleThreads(isArchived: Bool, transaction: ReadTransaction) throws -> [TSThread]
}

public class AnyThreadFinder: ThreadFinder {
    public typealias ReadTransaction = SDSAnyReadTransaction

    let grdbAdapter: GRDBThreadFinder = GRDBThreadFinder()
    let yapAdapter: YAPDBThreadFinder = YAPDBThreadFinder()

    public init() { }

    public func visibleThreadCount(isArchived: Bool, transaction: SDSAnyReadTransaction) throws -> UInt {
        switch transaction.readTransaction {
        case .grdbRead(let grdb):
            return try grdbAdapter.visibleThreadCount(isArchived: isArchived, transaction: grdb)
        case .yapRead(let yap):
            return yapAdapter.visibleThreadCount(isArchived: isArchived, transaction: yap)
        }
    }

    public func sortedVisibleThreads(isArchived: Bool, transaction: SDSAnyReadTransaction) throws -> [TSThread] {
        switch transaction.readTransaction {
        case .grdbRead(let grdb):
            return try grdbAdapter.sortedVisibleThreads(isArchived: isArchived, transaction: grdb)
        case .yapRead(let yap):
            return yapAdapter.sortedVisibleThreads(isArchived: isArchived, transaction: yap)
        }
    }
}

struct YAPDBThreadFinder: ThreadFinder {
    typealias ReadTransaction = YapDatabaseReadTransaction

    func visibleThreadCount(isArchived: Bool, transaction: YapDatabaseReadTransaction) -> UInt {
        guard let view = ext(transaction) else {
            return 0
        }
        return view.numberOfItems(inGroup: group(isArchived: isArchived))
    }

    func sortedVisibleThreads(isArchived: Bool, transaction: YapDatabaseReadTransaction) -> [TSThread] {
        var result = [TSThread]()
        guard let view = ext(transaction) else {
            return []
        }
        view.safe_enumerateKeysAndObjects(inGroup: group(isArchived: isArchived),
                                          extensionName: type(of: self).extensionName,
                                          with: NSEnumerationOptions.reverse) { _, _, object, _, _ in
                                            guard let thread = object as? TSThread else {
                                                owsFailDebug("unexpected object: \(type(of: object))")
                                                return
                                            }
                                            result.append(thread)
        }
        // The YDB view is pre-sorted.
        return result
    }

    // MARK: -

    private static let extensionName: String = TSThreadDatabaseViewExtensionName

    private func group(isArchived: Bool) -> String {
        return isArchived ? TSArchiveGroup : TSInboxGroup
    }

    private func ext(_ transaction: YapDatabaseReadTransaction) -> YapDatabaseViewTransaction? {
        return transaction.safeViewTransaction(type(of: self).extensionName)
    }
}

struct GRDBThreadFinder: ThreadFinder {
    typealias ReadTransaction = GRDBReadTransaction

    static let cn = ThreadRecord.columnName

    func visibleThreadCount(isArchived: Bool, transaction: GRDBReadTransaction) throws -> UInt {
        return UInt(try sortedVisibleThreads(isArchived: isArchived, transaction: transaction).count)
    }

    func sortedVisibleThreads(isArchived: Bool, transaction: GRDBReadTransaction) throws -> [TSThread] {
        let longAgo = Date(timeIntervalSince1970: 0)
        let sortDateForThread: (TSThread) -> Date = { thread in
            if let lastInteraction = thread.lastInteractionForInbox(transaction: transaction.asAnyRead) {
                return lastInteraction.receivedAtDate()
            }
            guard let creationDate = thread.creationDate else {
                return longAgo
            }
            return creationDate
        }

        typealias SortableThread = (thread: TSThread, date: Date)
        var sortableThreads = [SortableThread]()
        // TODO: Find a performant way to pull the isThreadArchived() check and sorting into this query.
        let sql = """
            SELECT *
            FROM \(ThreadRecord.databaseTableName)
            WHERE \(threadColumn: .shouldThreadBeVisible) = 1
        """
        let arguments: StatementArguments = []

        try ThreadRecord.fetchCursor(transaction.database, sql: sql, arguments: arguments).forEach { threadRecord in
            let thread = try TSThread.fromRecord(threadRecord)
            let interactionFinder = InteractionFinder(threadUniqueId: thread.uniqueId)
            let mostRecentInteraction: TSInteraction? = interactionFinder.mostRecentInteractionForInbox(transaction: transaction.asAnyRead)
            let isThreadArchived = try self.isThreadArchived(thread: thread, mostRecentInteraction: mostRecentInteraction)
            guard isArchived == isThreadArchived else {
                return
            }
            sortableThreads.append(SortableThread(thread: thread, date: sortDateForThread(thread)))
        }
        sortableThreads.sort { (lhs, rhs) -> Bool in
            return lhs.date > rhs.date
        }
        return sortableThreads.map { sortableThread in
            sortableThread.thread
        }
    }

    func isThreadArchived(thread: TSThread, mostRecentInteraction: TSInteraction?) throws -> Bool {
        guard let archivedAsOfMessageSortId = thread.archivedAsOfMessageSortId else {
            // Thread was never archived.
            return false
        }
        guard let lastVisibleInteractionRowId = mostRecentInteraction?.sortId else {
            // Thread archived, no visible interactions.
            return true
        }
        // Thread is still archived if the most recent visible interaction is
        // from before when the thread was archived.
        return lastVisibleInteractionRowId <= archivedAsOfMessageSortId.int64Value
    }
}
