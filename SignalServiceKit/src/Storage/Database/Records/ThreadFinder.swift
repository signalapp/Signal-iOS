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
            return try grdbAdapter.visibleThreadCount(isArchived: isArchived, transaction: grdb.database)
        case .yapRead(let yap):
            return yapAdapter.visibleThreadCount(isArchived: isArchived, transaction: yap)
        }
    }

    public func enumerateVisibleThreads(isArchived: Bool, transaction: SDSAnyReadTransaction, block: @escaping (TSThread) -> Void) throws {
        switch transaction.readTransaction {
        case .grdbRead(let grdb):
            try grdbAdapter.enumerateVisibleThreads(isArchived: isArchived, transaction: grdb.database, block: block)
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
    typealias ReadTransaction = Database

    static let cn = ThreadRecord.columnName

    func visibleThreadCount(isArchived: Bool, transaction: Database) throws -> UInt {
        guard let count = try UInt.fetchOne(transaction, sql: """
            SELECT COUNT(*)
            FROM (
                SELECT
                    \( threadColumn: .shouldThreadBeVisible),
                    CASE maxInteractionId <= \(threadColumn: .archivedAsOfMessageSortId)
                        WHEN 1 THEN 1
                        ELSE 0
                    END isArchived
                FROM \(ThreadRecord.databaseTableName)
                LEFT JOIN (
                    SELECT
                        MAX(\(interactionColumn: .id)) as maxInteractionId,
                        \(interactionColumn: .threadUniqueId)
                    FROM \(InteractionRecord.databaseTableName)
                    GROUP BY \(interactionColumn: .threadUniqueId)
                ) latestInteractions
                ON latestInteractions.\(interactionColumn: .threadUniqueId) = \(threadColumn: .uniqueId)
            )
            WHERE isArchived = ?
            AND \(threadColumn: .shouldThreadBeVisible) = 1
            """,
            arguments: [isArchived]) else {
                owsFailDebug("count was unexpectedly nil")
                return 0
        }

        return count
    }

    func enumerateVisibleThreads(isArchived: Bool, transaction: Database, block: @escaping (TSThread) -> Void) throws {
        try ThreadRecord.fetchCursor(transaction, sql: """
            SELECT *
            FROM (
                SELECT
                    \(ThreadRecord.databaseTableName).*,
                    CASE maxInteractionId <= \(threadColumn: .archivedAsOfMessageSortId)
                        WHEN 1 THEN 1
                        ELSE 0
                    END isArchived
                FROM \(ThreadRecord.databaseTableName)
                LEFT JOIN (
                    SELECT
                        MAX(\(interactionColumn: .id)) as maxInteractionId,
                        \(interactionColumn: .threadUniqueId)
                    FROM \(InteractionRecord.databaseTableName)
                    GROUP BY \(interactionColumn: .threadUniqueId)
                ) latestInteractions
                ON latestInteractions.\(interactionColumn: .threadUniqueId) = \(threadColumn: .uniqueId)
                ORDER BY maxInteractionId DESC
            )
            WHERE isArchived = ?
            AND \( threadColumn: .shouldThreadBeVisible) = 1
            """,
            arguments: [isArchived]).forEach { threadRecord in
                block(try TSThread.fromRecord(threadRecord))
        }
    }
}
