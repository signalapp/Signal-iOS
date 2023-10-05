//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient

@objc
public class StoryFinder: NSObject {
    public static func unviewedSenderCount(transaction: SDSAnyReadTransaction) -> Int {
        let ownAciClause = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read).map {
            "AND \(StoryContextAssociatedData.columnName(.contactAci)) IS NOT '\($0.aci.serviceIdUppercaseString)'"
        } ?? ""
        let sql = """
            SELECT COUNT(*)
            FROM \(StoryContextAssociatedData.databaseTableName)
            WHERE
                \(StoryContextAssociatedData.columnName(.isHidden)) IS NOT 1
                AND \(StoryContextAssociatedData.columnName(.latestUnexpiredTimestamp)) IS NOT NULL
                AND (
                    \(StoryContextAssociatedData.columnName(.lastReadTimestamp)) IS NULL
                    OR \(StoryContextAssociatedData.columnName(.lastReadTimestamp))
                        < \(StoryContextAssociatedData.columnName(.latestUnexpiredTimestamp))
                )
                \(ownAciClause)
                ;
        """
        do {
            let unviewedStoryCount = try Int.fetchOne(transaction.unwrapGrdbRead.database, sql: sql) ?? 0

            // Check the system story separately, since its hidden state is kept separately.
            guard !Self.systemStoryManager.areSystemStoriesHidden(transaction: transaction) else {
                return unviewedStoryCount
            }

            let unviewedSystemStoryCount = Self.systemStoryManager.isOnboardingStoryRead(transaction: transaction) ? 0 : 1
            return unviewedStoryCount + unviewedSystemStoryCount

        } catch {
            owsFailDebug("Failed to query unviewed story sender count \(error)")
            return 0
        }
    }

    // The list view shows all incoming stories *and* outgoing group stories
    public static func storiesForListView(transaction: SDSAnyReadTransaction) -> [StoryMessage] {
        let sql = """
            SELECT *
            FROM \(StoryMessage.databaseTableName)
            WHERE (
                \(StoryMessage.columnName(.direction)) = \(StoryMessage.Direction.incoming.rawValue)
                OR \(StoryMessage.columnName(.groupId)) IS NOT NULL
            )
            ORDER BY \(StoryMessage.columnName(.timestamp)) ASC
        """

        do {
            return try StoryMessage.fetchAll(transaction.unwrapGrdbRead.database, sql: sql)
        } catch {
            owsFailDebug("Failed to fetch incoming stories \(error)")
            return []
        }
    }

    public static func outgoingStories(limit: Int? = nil, transaction: SDSAnyReadTransaction) -> [StoryMessage] {
        var sql = """
            SELECT *
            FROM \(StoryMessage.databaseTableName)
            WHERE \(StoryMessage.columnName(.direction)) = \(StoryMessage.Direction.outgoing.rawValue)
            ORDER BY \(StoryMessage.columnName(.timestamp)) DESC
        """

        if let limit = limit {
            sql += " LIMIT \(limit)"
        }

        do {
            return try StoryMessage.fetchAll(transaction.unwrapGrdbRead.database, sql: sql)
        } catch {
            owsFailDebug("Failed to fetch incoming stories \(error)")
            return []
        }
    }

    public static func enumerateOutgoingStories(transaction: SDSAnyReadTransaction, block: @escaping (StoryMessage, UnsafeMutablePointer<ObjCBool>) -> Void) {
        let sql = """
            SELECT *
            FROM \(StoryMessage.databaseTableName)
            WHERE \(StoryMessage.columnName(.direction)) = \(StoryMessage.Direction.outgoing.rawValue)
            ORDER BY \(StoryMessage.columnName(.timestamp)) DESC
        """

        do {
            let cursor = try StoryMessage.fetchCursor(transaction.unwrapGrdbRead.database, sql: sql)
            while let message = try cursor.next() {
                var stop: ObjCBool = false
                block(message, &stop)
                if stop.boolValue {
                    return
                }
            }
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    public static func enumerateUnreadIncomingStories(
        transaction: SDSAnyReadTransaction,
        block: @escaping (StoryMessage, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        let sql = """
            SELECT *
            FROM \(StoryMessage.databaseTableName)
            WHERE \(StoryMessage.columnName(.direction)) = \(StoryMessage.Direction.incoming.rawValue)
            AND json_extract(\(StoryMessage.columnName(.manifest)), '$.incoming.receivedState.readTimestamp') is NULL
        """

        do {
            let cursor = try StoryMessage.fetchCursor(transaction.unwrapGrdbRead.database, sql: sql)
            while let message = try cursor.next() {
                var stop: ObjCBool = false
                block(message, &stop)
                if stop.boolValue {
                    return
                }
            }
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    public static func listStoriesWithRowIds(_ rowIds: [Int64], transaction: SDSAnyReadTransaction) -> [StoryMessage] {
        let sql = """
            SELECT *
            FROM \(StoryMessage.databaseTableName)
            WHERE (
                \(StoryMessage.columnName(.direction)) = \(StoryMessage.Direction.incoming.rawValue)
                OR \(StoryMessage.columnName(.groupId)) IS NOT NULL
            )
            AND \(StoryMessage.columnName(.id)) IN (\(rowIds.lazy.map { "\($0)" }.joined(separator: ",")))
            ORDER BY \(StoryMessage.columnName(.timestamp)) ASC
        """

        do {
            return try StoryMessage.fetchAll(transaction.unwrapGrdbRead.database, sql: sql)
        } catch {
            owsFailDebug("Failed to fetch incoming stories \(error)")
            return []
        }
    }

    public static func listStoriesWithUniqueIds(_ uniqueIds: [String], transaction: SDSAnyReadTransaction) -> [StoryMessage] {
        let sql = """
            SELECT *
            FROM \(StoryMessage.databaseTableName)
            WHERE \(StoryMessage.columnName(.uniqueId)) IN (\(uniqueIds.lazy.map({ "'\($0)'" }).joined(separator: ",")))
            ORDER BY \(StoryMessage.columnName(.timestamp)) ASC
        """

        do {
            return try StoryMessage.fetchAll(transaction.unwrapGrdbRead.database, sql: sql)
        } catch {
            owsFailDebug("Failed to fetch incoming stories \(error)")
            return []
        }
    }

    public static func latestStoryForThread(_ thread: TSThread, transaction: SDSAnyReadTransaction) -> StoryMessage? {
        latestStoryForContext(thread.storyContext, transaction: transaction)
    }

    public static func latestStoryForContext(_ context: StoryContext, transaction: SDSAnyReadTransaction) -> StoryMessage? {

        guard let contextQuery = context.query else { return nil }

        let sql = """
            SELECT *
            FROM \(StoryMessage.databaseTableName)
            WHERE \(contextQuery)
            ORDER BY \(StoryMessage.columnName(.timestamp)) DESC
            LIMIT 1
        """

        do {
            return try StoryMessage.fetchOne(transaction.unwrapGrdbRead.database, sql: sql)
        } catch {
            owsFailDebug("Failed to fetch incoming stories \(error)")
            return nil
        }
    }

    public static func enumerateStoriesForContext(_ context: StoryContext, transaction: SDSAnyReadTransaction, block: (StoryMessage, UnsafeMutablePointer<ObjCBool>) -> Void) {

        guard let contextQuery = context.query else { return }

        let sql = """
            SELECT *
            FROM \(StoryMessage.databaseTableName)
            WHERE \(contextQuery)
            ORDER BY \(StoryMessage.columnName(.timestamp)) ASC
        """

        do {
            let cursor = try StoryMessage.fetchCursor(transaction.unwrapGrdbRead.database, sql: sql)
            while let message = try cursor.next() {
                var stop: ObjCBool = false
                block(message, &stop)
                if stop.boolValue {
                    return
                }
            }
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    public static func enumerateStories(
        fromSender senderAci: Aci,
        tx: SDSAnyReadTransaction,
        block: (StoryMessage, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        let sql = """
            SELECT *
            FROM \(StoryMessage.databaseTableName)
            WHERE \(StoryMessage.columnName(.authorAci)) = ?
        """

        do {
            let cursor = try StoryMessage.fetchCursor(tx.unwrapGrdbRead.database, sql: sql, arguments: [senderAci.rawUUID.uuidString])
            while let message = try cursor.next() {
                var stop: ObjCBool = false
                block(message, &stop)
                if stop.boolValue {
                    return
                }
            }
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    public static func enumerateUnviewedIncomingStoriesForContext(_ context: StoryContext, transaction: SDSAnyReadTransaction, block: @escaping (StoryMessage, UnsafeMutablePointer<ObjCBool>) -> Void) {

        guard let contextQuery = context.query else { return }

        let sql = """
            SELECT *
            FROM \(StoryMessage.databaseTableName)
            WHERE \(contextQuery)
            AND json_extract(\(StoryMessage.columnName(.manifest)), '$.incoming.receivedState.viewedTimestamp') is NULL
            AND \(StoryMessage.columnName(.direction)) = \(StoryMessage.Direction.incoming.rawValue)
            ORDER BY \(StoryMessage.columnName(.timestamp)) ASC
        """

        do {
            let cursor = try StoryMessage.fetchCursor(transaction.unwrapGrdbRead.database, sql: sql)
            while let message = try cursor.next() {
                var stop: ObjCBool = false
                block(message, &stop)
                if stop.boolValue {
                    return
                }
            }
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    // The stories should be enumerated in order from "next to expire" to "last to expire".
    public static func enumerateExpiredStories(transaction: SDSAnyReadTransaction, block: @escaping (StoryMessage, UnsafeMutablePointer<ObjCBool>) -> Void) {

        let sql = """
            SELECT *
            FROM \(StoryMessage.databaseTableName)
            WHERE \(StoryMessage.columnName(.timestamp)) <= \(Date().ows_millisecondsSince1970 - StoryManager.storyLifetimeMillis)
            ORDER BY \(StoryMessage.columnName(.timestamp)) ASC
        """

        do {
            let cursor = try StoryMessage.fetchCursor(transaction.unwrapGrdbRead.database, sql: sql)
            while let message = try cursor.next() {
                var stop: ObjCBool = false
                block(message, &stop)
                if stop.boolValue {
                    return
                }
            }
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    public static func oldestExpirableTimestamp(transaction: SDSAnyReadTransaction) -> UInt64? {
        let sql = """
            SELECT \(StoryMessage.columnName(.timestamp))
            FROM \(StoryMessage.databaseTableName)
            WHERE \(StoryMessage.columnName(.authorAci)) != '\(StoryMessage.systemStoryAuthor.serviceIdUppercaseString)'
            ORDER BY \(StoryMessage.columnName(.timestamp)) ASC
            LIMIT 1
        """

        do {
            return try UInt64.fetchOne(transaction.unwrapGrdbRead.database, sql: sql)
        } catch {
            owsFailDebug("failed to lookup next story expiration \(error)")
            return nil
        }
    }

    public static func story(timestamp: UInt64, author: Aci, transaction: SDSAnyReadTransaction) -> StoryMessage? {
        let sql = """
            SELECT *
            FROM \(StoryMessage.databaseTableName)
            WHERE \(StoryMessage.columnName(.authorAci)) = '\(author.serviceIdUppercaseString)'
            AND \(StoryMessage.columnName(.timestamp)) = \(timestamp)
            ORDER BY \(StoryMessage.columnName(.timestamp)) DESC
            LIMIT 1
        """

        do {
            return try StoryMessage.fetchOne(transaction.unwrapGrdbRead.database, sql: sql)
        } catch {
            owsFailDebug("Failed to fetch story \(error)")
            return nil
        }
    }

    public static func enumerateSendingStories(transaction: SDSAnyReadTransaction, block: @escaping (StoryMessage, UnsafeMutablePointer<ObjCBool>) -> Void) {

        let sql = """
            SELECT *
            FROM \(StoryMessage.databaseTableName)
            WHERE \(StoryMessage.columnName(.direction)) = \(StoryMessage.Direction.outgoing.rawValue)
            AND (
                    SELECT 1 FROM json_tree(\(StoryMessage.columnName(.manifest)), '$.outgoing.recipientStates')
                    WHERE json_tree.type IS 'object'
                    AND json_extract(json_tree.value, '$.sendingState') = \(OWSOutgoingMessageRecipientState.sending.rawValue)
                )
            ORDER BY \(StoryMessage.columnName(.timestamp)) ASC
        """

        do {
            let cursor = try StoryMessage.fetchCursor(transaction.unwrapGrdbRead.database, sql: sql)
            while let message = try cursor.next() {
                var stop: ObjCBool = false
                block(message, &stop)
                if stop.boolValue {
                    return
                }
            }
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    public static func hasFailedStories(transaction: SDSAnyReadTransaction) -> Bool {
        let sql = """
            SELECT EXISTS (
                SELECT 1 FROM \(StoryMessage.databaseTableName)
                WHERE \(StoryMessage.columnName(.direction)) = \(StoryMessage.Direction.outgoing.rawValue)
                AND (
                    SELECT 1 FROM json_tree(\(StoryMessage.columnName(.manifest)), '$.outgoing.recipientStates')
                    WHERE json_tree.type IS 'object'
                    AND json_extract(json_tree.value, '$.sendingState') = \(OWSOutgoingMessageRecipientState.failed.rawValue)
                )
            )
        """
        do {
            return try Bool.fetchOne(transaction.unwrapGrdbRead.database, sql: sql) ?? false
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Fetch failed")
        }
    }
}

private extension StoryContext {
    var query: String? {
        switch self {
        case .groupId(let data):
            return "\(StoryMessage.columnName(.groupId)) = x'\(data.hexadecimalString)'"
        case .authorAci(let authorAci):
            return "\(StoryMessage.columnName(.authorAci)) = '\(authorAci.serviceIdUppercaseString)' AND \(StoryMessage.columnName(.groupId)) is NULL"
        case .privateStory(let uniqueId):
            return """
                \(StoryMessage.columnName(.direction)) = \(StoryMessage.Direction.outgoing.rawValue)
                AND \(StoryMessage.columnName(.groupId)) is NULL
                AND (
                    SELECT 1 FROM json_tree(\(StoryMessage.columnName(.manifest)), '$.outgoing.recipientStates')
                    WHERE json_tree.type IS 'object'
                    AND json_extract(json_tree.value, '$.contexts') LIKE '%"\(uniqueId)"%'
                )
            """
        case .none:
            return nil
        }
    }
}

// MARK: - StoryContextAssociatedData

extension StoryFinder {

    public static func getAssociatedData(
        forContext source: StoryContextAssociatedData.SourceContext,
        transaction: SDSAnyReadTransaction
    ) -> StoryContextAssociatedData? {
        switch source {
        case .contact(let contactAci):
            return try? StoryContextAssociatedData
                .filter(Column(StoryContextAssociatedData.columnName(.contactAci)) == contactAci.serviceIdUppercaseString)
                .fetchOne(transaction.unwrapGrdbRead.database)

        case .group(let groupId):
            return try? StoryContextAssociatedData
                .filter(Column(StoryContextAssociatedData.columnName(.groupId)) == groupId)
                .fetchOne(transaction.unwrapGrdbRead.database)
        }
    }

    public static func getAssociatedData(
        forAci contactAci: Aci,
        tx: SDSAnyReadTransaction
    ) -> StoryContextAssociatedData? {
        return getAssociatedData(forContext: .contact(contactAci: contactAci), transaction: tx)
    }

    public static func associatedData(for thread: TSThread, transaction: SDSAnyReadTransaction) -> StoryContextAssociatedData? {
        if let contactThread = thread as? TSContactThread, let contactAci = contactThread.contactAddress.serviceId as? Aci {
            return getAssociatedData(forContext: .contact(contactAci: contactAci), transaction: transaction)
        } else if let groupThread = thread as? TSGroupThread {
            return getAssociatedData(forContext: .group(groupId: groupThread.groupId), transaction: transaction)
        } else {
            return nil
        }
    }

    public static func associatedDatasWithRecentlyViewedStories(limit: Int, transaction: SDSAnyReadTransaction) -> [StoryContextAssociatedData] {
        do {
            return try StoryContextAssociatedData
            .order(Column(StoryContextAssociatedData.columnName(.lastViewedTimestamp)).desc)
            .limit(limit)
            .fetchAll(transaction.unwrapGrdbRead.database)
        } catch {
            owsFailDebug("Failed to query recent threads \(error)")
            return []
        }
    }
}
