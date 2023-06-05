//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public protocol ThreadFinder {
    associatedtype ReadTransaction

    func visibleThreadCount(isArchived: Bool, transaction: ReadTransaction) throws -> UInt
    func enumerateVisibleThreads(isArchived: Bool, transaction: ReadTransaction, block: @escaping (TSThread) -> Void) throws
    func visibleThreadIds(isArchived: Bool, transaction: ReadTransaction) throws -> [String]
    func sortIndex(thread: TSThread, transaction: ReadTransaction) throws -> UInt?
    func threads(withThreadIds threadIds: Set<String>, transaction: ReadTransaction) throws -> Set<TSThread>
    func storyThreads(includeImplicitGroupThreads: Bool, transaction: ReadTransaction) -> [TSThread]
    func threadsWithRecentInteractions(limit: UInt, transaction: ReadTransaction) -> [TSThread]
}

@objc
public class AnyThreadFinder: NSObject, ThreadFinder {
    public typealias ReadTransaction = SDSAnyReadTransaction

    let grdbAdapter: GRDBThreadFinder = GRDBThreadFinder()

    /// Enumerates group threads in "last interaction" order.
    public func enumerateGroupThreads(transaction: SDSAnyReadTransaction, block: @escaping (TSGroupThread) -> Void) throws {
        switch transaction.readTransaction {
        case .grdbRead(let grdb):
            try grdbAdapter.enumerateGroupThreads(transaction: grdb, block: block)
        }
    }

    public func visibleThreadCount(isArchived: Bool, transaction: SDSAnyReadTransaction) throws -> UInt {
        switch transaction.readTransaction {
        case .grdbRead(let grdb):
            return try grdbAdapter.visibleThreadCount(isArchived: isArchived, transaction: grdb)
        }
    }

    @objc
    public func enumerateVisibleThreads(isArchived: Bool, transaction: SDSAnyReadTransaction, block: @escaping (TSThread) -> Void) throws {
        switch transaction.readTransaction {
        case .grdbRead(let grdb):
            try grdbAdapter.enumerateVisibleThreads(isArchived: isArchived, transaction: grdb, block: block)
        }
    }

    @objc
    public func visibleThreadIds(isArchived: Bool, transaction: SDSAnyReadTransaction) throws -> [String] {
        switch transaction.readTransaction {
        case .grdbRead(let grdb):
            return try grdbAdapter.visibleThreadIds(isArchived: isArchived, transaction: grdb)
        }
    }

    @objc
    public func sortIndexObjc(thread: TSThread, transaction: ReadTransaction) -> NSNumber? {
        do {
            guard let value = try sortIndex(thread: thread, transaction: transaction) else {
                return nil
            }
            return NSNumber(value: value)
        } catch {
            owsFailDebug("error: \(error)")
            return nil
        }
    }

    public func sortIndex(thread: TSThread, transaction: SDSAnyReadTransaction) throws -> UInt? {
        switch transaction.readTransaction {
        case .grdbRead(let grdb):
            return try grdbAdapter.sortIndex(thread: thread, transaction: grdb)
        }
    }

    public func threads(withThreadIds threadIds: Set<String>, transaction: SDSAnyReadTransaction) throws -> Set<TSThread> {
        switch transaction.readTransaction {
        case .grdbRead(let grdb):
            return try grdbAdapter.threads(withThreadIds: threadIds, transaction: grdb)
        }
    }

    public func storyThreads(includeImplicitGroupThreads: Bool, transaction: SDSAnyReadTransaction) -> [TSThread] {
        switch transaction.readTransaction {
        case .grdbRead(let grdb):
            return grdbAdapter.storyThreads(includeImplicitGroupThreads: includeImplicitGroupThreads, transaction: grdb)
        }
    }

    public func threadsWithRecentInteractions(limit: UInt, transaction: SDSAnyReadTransaction) -> [TSThread] {
        switch transaction.readTransaction {
        case .grdbRead(let grdb):
            return grdbAdapter.threadsWithRecentInteractions(limit: limit, transaction: grdb)
        }
    }
}

// MARK: -

@objc
public class GRDBThreadFinder: NSObject, ThreadFinder {

    public typealias ReadTransaction = GRDBReadTransaction

    static let cn = ThreadRecord.columnName

    /// Enumerates group threads in "last interaction" order.
    public func enumerateGroupThreads(transaction: GRDBReadTransaction, block: @escaping (TSGroupThread) -> Void) throws {
        let sql = """
            SELECT *
            FROM \(ThreadRecord.databaseTableName)
            WHERE \(threadColumn: .groupModel) IS NOT NULL
            ORDER BY \(threadColumn: .lastInteractionRowId) DESC
        """

        try ThreadRecord.fetchCursor(transaction.database, sql: sql).forEach { threadRecord in
            let thread = try TSThread.fromRecord(threadRecord)
            guard let groupThread = thread as? TSGroupThread else { return }
            block(groupThread)
        }
    }

    public func visibleThreadCount(isArchived: Bool, transaction: GRDBReadTransaction) throws -> UInt {
        let sql = """
            SELECT COUNT(*)
            FROM \(ThreadRecord.databaseTableName)
            \(archivedJoin(isArchived: isArchived))
            AND \(threadColumn: .shouldThreadBeVisible) = 1
        """

        guard let count = try UInt.fetchOne(transaction.database, sql: sql) else {
            owsFailDebug("count was unexpectedly nil")
            return 0
        }

        return count
    }

    @objc
    public func enumerateVisibleThreads(isArchived: Bool, transaction: GRDBReadTransaction, block: @escaping (TSThread) -> Void) throws {
        let sql = """
            SELECT *
            FROM \(ThreadRecord.databaseTableName)
            \(archivedJoin(isArchived: isArchived))
            AND \(threadColumn: .shouldThreadBeVisible) = 1
            ORDER BY \(threadColumn: .lastInteractionRowId) DESC
            """

        do {
            try ThreadRecord.fetchCursor(transaction.database, sql: sql).forEach { threadRecord in
                block(try TSThread.fromRecord(threadRecord))
            }
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            // rethrow the error after marking database
            throw error
        }
    }

    private func archivedJoin(isArchived: Bool) -> String {
        return """
            INNER JOIN \(ThreadAssociatedData.databaseTableName) AS ad
                ON ad.threadUniqueId = \(threadColumn: .uniqueId)
            WHERE ad.isArchived = \(isArchived ? "1" : "0")
        """
    }

    @objc
    public func visibleThreadIds(isArchived: Bool, transaction: GRDBReadTransaction) throws -> [String] {
        let sql = """
            SELECT \(threadColumn: .uniqueId)
            FROM \(ThreadRecord.databaseTableName)
            \(archivedJoin(isArchived: isArchived))
            AND \(threadColumn: .shouldThreadBeVisible) = 1
            ORDER BY \(threadColumn: .lastInteractionRowId) DESC
        """
        return try String.fetchAll(transaction.database, sql: sql)
    }

    public func sortIndex(thread: TSThread, transaction: GRDBReadTransaction) throws -> UInt? {
        let sql = """
        SELECT sortIndex
        FROM (
            SELECT
                (ROW_NUMBER() OVER (ORDER BY \(threadColumn: .lastInteractionRowId) DESC) - 1) as sortIndex,
                \(threadColumn: .id)
            FROM \(ThreadRecord.databaseTableName)
            WHERE \(threadColumn: .shouldThreadBeVisible) = 1
        )
        WHERE \(threadColumn: .id) = ?
        """
        guard let grdbId = thread.grdbId, grdbId.intValue > 0 else {
            throw OWSAssertionError("grdbId was unexpectedly nil")
        }

        let arguments: StatementArguments = [grdbId.intValue]
        return try UInt.fetchOne(transaction.database, sql: sql, arguments: arguments)
    }

    @objc
    public class func hasPendingMessageRequest(thread: TSThread, transaction: GRDBReadTransaction) -> Bool {

        // TODO: Should we consult isRequestingMember() here?
        if let groupThread = thread as? TSGroupThread,
            groupThread.isGroupV2Thread,
            groupThread.isLocalUserInvitedMember {
            return true
        }

        // If we're creating the thread, don't show the message request view
        guard thread.shouldThreadBeVisible else { return false }

        // If this thread is blocked AND we're still in the thread, show the message
        // request view regardless of if we have sent messages or not.
        if blockingManager.isThreadBlocked(thread, transaction: transaction.asAnyRead) { return true }

        let isGroupThread = thread is TSGroupThread
        let isLocalUserInGroup = (thread as? TSGroupThread)?.isLocalUserFullOrInvitedMember == true

        // If this is a group thread and we're not a member, never show the message request.
        if isGroupThread, !isLocalUserInGroup { return false }

        // If the thread is already whitelisted, do nothing. The user has already
        // accepted the request for this thread.
        guard !Self.profileManager.isThread(
            inProfileWhitelist: thread,
            transaction: transaction.asAnyRead
        ) else { return false }

        let interactionFinder = GRDBInteractionFinder(threadUniqueId: thread.uniqueId)

        if isGroupThread {
            // At this point, we know this is an un-whitelisted group thread.
            // If someone added us to the group, there will be a group update info message
            // in which case we want to show a pending message request. If the thread
            // is otherwise empty, we don't want to show the message request.
            if interactionFinder.hasGroupUpdateInfoMessage(transaction: transaction) { return true }
        }

        // This thread is likely only visible because of system messages like so-and-so
        // is on signal or sync status. Some of the "possibly" incoming messages might
        // actually have been triggered by us, but if we sent one of these then the thread
        // should be in our profile white list and not make it to this check.
        guard interactionFinder.possiblyHasIncomingMessages(transaction: transaction) else { return false }

        return true
    }

    @objc
    public class func shouldSetDefaultDisappearingMessageTimer(
        thread: TSThread,
        transaction tx: GRDBReadTransaction
    ) -> Bool {
        // We never set the default timer for group threads. Group thread timers
        // are set during group creation.
        guard !thread.isGroupThread else { return false }

        let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore

        // Make sure the universal timer is enabled.
        guard dmConfigurationStore.fetchOrBuildDefault(for: .universal, tx: tx.asAnyRead.asV2Read).isEnabled else {
            return false
        }

        // Make sure there the current timer is disabled.
        guard !dmConfigurationStore.fetchOrBuildDefault(for: .thread(thread), tx: tx.asAnyRead.asV2Read).isEnabled else {
            return false
        }

        // Make sure there has been no user initiated interactions.
        return !GRDBInteractionFinder(threadUniqueId: thread.uniqueId).hasUserInitiatedInteraction(transaction: tx)
    }

    @objc
    public func threads(withThreadIds threadIds: Set<String>, transaction: GRDBReadTransaction) throws -> Set<TSThread> {
        guard !threadIds.isEmpty else {
            return []
        }

        let sql = """
        SELECT * FROM \(ThreadRecord.databaseTableName)
        WHERE \(threadColumn: .uniqueId) IN (\(threadIds.map { "\'\($0)'" }.joined(separator: ",")))
        """
        let arguments: StatementArguments = []
        let cursor = TSThread.grdbFetchCursor(sql: sql, arguments: arguments, transaction: transaction)
        var threads = Set<TSThread>()
        while let thread = try cursor.next() {
            threads.insert(thread)
        }
        return threads
    }

    @objc
    public class func existsGroupThread(transaction: GRDBReadTransaction) -> Bool {
        let sql = """
        SELECT EXISTS(
            SELECT 1
            FROM \(ThreadRecord.databaseTableName)
            WHERE \(threadColumn: .recordType) = ?
            LIMIT 1
        )
        """
        let arguments: StatementArguments = [SDSRecordType.groupThread.rawValue]
        do {
            return try Bool.fetchOne(transaction.database, sql: sql, arguments: arguments) ?? false
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Failed to find group thread")
        }
    }

    public func storyThreads(includeImplicitGroupThreads: Bool, transaction: GRDBReadTransaction) -> [TSThread] {

        var allowedDefaultThreadIds = [String]()

        if includeImplicitGroupThreads {
            // Prefetch the group thread uniqueIds that currently have stories
            // TODO: We could potential join on the KVS for groupId -> threadId
            // to further reduce the number of queries required here, but it
            // may be overkill.

            let storyMessageGroupIdsSQL = """
                SELECT DISTINCT \(StoryMessage.columnName(.groupId))
                FROM \(StoryMessage.databaseTableName)
                WHERE \(StoryMessage.columnName(.groupId)) IS NOT NULL
            """

            do {
                let groupIdCursor = try Data.fetchCursor(transaction.database, sql: storyMessageGroupIdsSQL)

                while let groupId = try groupIdCursor.next() {
                    allowedDefaultThreadIds.append(TSGroupThread.threadId(
                        forGroupId: groupId,
                        transaction: transaction.asAnyRead
                    ))
                }
            } catch {
                owsFailDebug("Failed to query group thread ids \(error)")
            }
        }

        let sql = """
            SELECT *
            FROM \(ThreadRecord.databaseTableName)
            WHERE \(threadColumn: .storyViewMode) != \(TSThreadStoryViewMode.disabled.rawValue)
            AND \(threadColumn: .storyViewMode) != \(TSThreadStoryViewMode.default.rawValue)
            OR (
                \(threadColumn: .storyViewMode) = \(TSThreadStoryViewMode.default.rawValue)
                AND \(threadColumn: .recordType) = \(SDSRecordType.groupThread.rawValue)
                AND \(threadColumn: .uniqueId) IN (\(allowedDefaultThreadIds.map { "\"\($0)\"" }.joined(separator: ", ")))
            )
            ORDER BY \(threadColumn: .lastSentStoryTimestamp) DESC
        """

        let cursor = TSThread.grdbFetchCursor(sql: sql, transaction: transaction)
        var threads = [TSThread]()
        do {
            while let thread = try cursor.next() {
                if let groupThread = thread as? TSGroupThread {
                    guard groupThread.isStorySendEnabled(transaction: transaction.asAnyRead) else { continue }
                }

                threads.append(thread)
            }
        } catch {
            owsFailDebug("Failed to query story threads \(error)")
        }
        return threads
    }

    public func threadsWithRecentInteractions(limit: UInt, transaction: GRDBReadTransaction) -> [TSThread] {
        let sql = """
            SELECT *
            FROM \(ThreadRecord.databaseTableName)
            ORDER BY \(threadColumn: .lastInteractionRowId) DESC
            LIMIT \(limit)
            """

        let cursor = TSThread.grdbFetchCursor(sql: sql, transaction: transaction)
        var threads = [TSThread]()
        do {
            while let thread = try cursor.next() {
                threads.append(thread)
            }
        } catch {
            owsFailDebug("Failed to query recent threads \(error)")
        }
        return threads
    }
}
