//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

public protocol ThreadFinder {
    associatedtype ReadTransaction

    func visibleThreadCount(isArchived: Bool, transaction: ReadTransaction) throws -> UInt
    func enumerateVisibleThreads(isArchived: Bool, transaction: ReadTransaction, block: @escaping (TSThread) -> Void) throws
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

    public func enumerateVisibleThreads(isArchived: Bool, transaction: SDSAnyReadTransaction, block: @escaping (TSThread) -> Void) throws {
        switch transaction.readTransaction {
        case .grdbRead(let grdb):
            try grdbAdapter.enumerateVisibleThreads(isArchived: isArchived, transaction: grdb, block: block)
        case .yapRead(let yap):
            yapAdapter.enumerateVisibleThreads(isArchived: isArchived, transaction: yap, block: block)
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

    func enumerateVisibleThreads(isArchived: Bool, transaction: YapDatabaseReadTransaction, block: @escaping (TSThread) -> Void) {
        guard let view = ext(transaction) else {
            return
        }
        view.safe_enumerateKeysAndObjects(inGroup: group(isArchived: isArchived),
                                          extensionName: type(of: self).extensionName,
                                          with: NSEnumerationOptions.reverse) { _, _, object, _, _ in
                                            guard let thread = object as? TSThread else {
                                                owsFailDebug("unexpected object: \(type(of: object))")
                                                return
                                            }
                                            block(thread)
        }
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
        var count: UInt = 0
        try enumerateVisibleThreads(isArchived: isArchived, transaction: transaction) { _ in
            count += 1
        }
        return count
    }

    func enumerateVisibleThreads(isArchived: Bool, transaction: GRDBReadTransaction, block: @escaping (TSThread) -> Void) throws {
        // TODO: Find a performant way to pull the isThreadArchived() check into this query.
        let sql = """
            SELECT *
            FROM \(ThreadRecord.databaseTableName)
            WHERE \(threadColumn: .shouldThreadBeVisible) = 1
        """
        let arguments: StatementArguments = []

        try ThreadRecord.fetchCursor(transaction.database, sql: sql, arguments: arguments).forEach { threadRecord in
            let thread = try TSThread.fromRecord(threadRecord)
            let isThreadArchived = try self.isThreadArchived(thread: thread, transaction: transaction)
            guard isArchived == isThreadArchived else {
                return
            }
            block(thread)
        }
    }

    func isThreadArchived(thread: TSThread, transaction: GRDBReadTransaction) throws -> Bool {
        guard let archivedAsOfMessageSortId = thread.archivedAsOfMessageSortId else {
            // Thread was never archived.
            return false
        }
        guard let lastVisibleInteractionRowId = try lastVisibleInteractionRowId(threadId: thread.uniqueId, transaction: transaction) else {
            // Thread archived, no visible interactions.
            return true
        }
        // Thread is still archived if the most recent visible interaction is
        // from before when the thread was archived.
        return lastVisibleInteractionRowId <= archivedAsOfMessageSortId.int64Value
    }

    func lastVisibleInteractionRowId(threadId: String, transaction: GRDBReadTransaction) throws -> Int64? {
        let sql = """
            SELECT
            MAX(\(interactionColumn: .id)) as maxInteractionId
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .storedShouldAppearInHomeView) == 1
            AND \(interactionColumn: .threadUniqueId) = ?
        """
        let arguments: StatementArguments = [TSErrorMessageType.nonBlockingIdentityChange.rawValue,
                                             TSInfoMessageType.verificationStateChange.rawValue,
                                             threadId]
        return try Int64.fetchOne(transaction.database, sql: sql, arguments: arguments) ?? nil
    }
}
