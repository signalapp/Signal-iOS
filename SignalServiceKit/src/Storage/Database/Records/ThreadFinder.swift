//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import SignalCoreKit

public class ThreadFinder: Dependencies {
    public init() {}

    /// Fetch a thread with the given SQLite row ID, if one exists.
    public func fetch(rowId: Int64, tx: SDSAnyReadTransaction) -> TSThread? {
        guard let thread = TSThread.grdbFetchOne(
            sql: """
                SELECT *
                FROM \(ThreadRecord.databaseTableName)
                WHERE \(threadColumn: .id) = ?
            """,
            arguments: [ rowId ],
            transaction: tx.unwrapGrdbRead
        ) else {
            owsFailDebug("Missing thread with row ID - how did we get this row ID?")
            return nil
        }

        return thread
    }

    /// Enumerates group threads in "last interaction" order.
    public func enumerateGroupThreads(
        transaction: SDSAnyReadTransaction,
        block: (TSGroupThread, _ stop: inout Bool) -> Void
    ) throws {
        let sql = """
            SELECT *
            FROM \(ThreadRecord.databaseTableName)
            WHERE \(threadColumn: .groupModel) IS NOT NULL
            ORDER BY \(threadColumn: .lastInteractionRowId) DESC
        """

        var stop = false
        let cursor = try ThreadRecord.fetchCursor(
            transaction.unwrapGrdbRead.database,
            sql: sql
        )
        while let threadRecord = try cursor.next() {
            let thread = try TSThread.fromRecord(threadRecord)
            guard let groupThread = thread as? TSGroupThread else { continue }
            block(groupThread, &stop)
            if stop {
                return
            }
        }
    }

    /// Enumerates all non-story threads in arbitrary order.
    public func enumerateNonStoryThreads(
        transaction: SDSAnyReadTransaction,
        block: (TSThread, _ stop: inout Bool) -> Void
    ) throws {
        let sql = """
            SELECT *
            FROM \(ThreadRecord.databaseTableName)
            WHERE \(threadColumn: .recordType) IS NOT ?
        """

        var stop = false
        let cursor = try ThreadRecord.fetchCursor(
            transaction.unwrapGrdbRead.database,
            sql: sql,
            arguments: [SDSRecordType.privateStoryThread]
        )
        while let threadRecord = try cursor.next() {
            let thread = try TSThread.fromRecord(threadRecord)
            block(thread, &stop)
            if stop {
                return
            }
        }
    }

    public func visibleThreadCount(
        isArchived: Bool,
        transaction: SDSAnyReadTransaction
    ) throws -> UInt {
        let sql = """
            SELECT COUNT(*)
            FROM \(ThreadRecord.databaseTableName)
            \(archivedJoin(isArchived: isArchived))
            AND \(threadColumn: .shouldThreadBeVisible) = 1
        """

        guard let count = try UInt.fetchOne(
            transaction.unwrapGrdbRead.database,
            sql: sql
        ) else {
            owsFailDebug("count was unexpectedly nil")
            return 0
        }

        return count
    }

    public func enumerateVisibleThreads(
        isArchived: Bool,
        transaction: SDSAnyReadTransaction,
        block: (TSThread) -> Void
    ) throws {
        let sql = """
            SELECT *
            FROM \(ThreadRecord.databaseTableName)
            \(archivedJoin(isArchived: isArchived))
            AND \(threadColumn: .shouldThreadBeVisible) = 1
            ORDER BY \(threadColumn: .lastInteractionRowId) DESC
        """

        do {
            try ThreadRecord.fetchCursor(
                transaction.unwrapGrdbRead.database,
                sql: sql
            ).forEach { threadRecord in
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

    public func visibleThreadIds(
        isArchived: Bool,
        transaction: SDSAnyReadTransaction
    ) throws -> [String] {
        let sql = """
            SELECT \(threadColumn: .uniqueId)
            FROM \(ThreadRecord.databaseTableName)
            \(archivedJoin(isArchived: isArchived))
            AND \(threadColumn: .shouldThreadBeVisible) = 1
            ORDER BY \(threadColumn: .lastInteractionRowId) DESC
        """

        return try String.fetchAll(transaction.unwrapGrdbRead.database, sql: sql)
    }

    public func fetchContactSyncThreadRowIds(tx: SDSAnyReadTransaction) throws -> [Int64] {
        let sql = """
            SELECT \(threadColumn: .id)
            FROM \(ThreadRecord.databaseTableName)
            WHERE \(threadColumn: .shouldThreadBeVisible) = 1
            ORDER BY \(threadColumn: .lastInteractionRowId) DESC
        """
        do {
            return try Int64.fetchAll(tx.unwrapGrdbRead.database, sql: sql)
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    public func hasPendingMessageRequest(
        thread: TSThread,
        transaction: SDSAnyReadTransaction
    ) -> Bool {
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
        if blockingManager.isThreadBlocked(thread, transaction: transaction) { return true }

        let isGroupThread = thread is TSGroupThread
        let isLocalUserInGroup = (thread as? TSGroupThread)?.isLocalUserFullOrInvitedMember == true

        // If this is a group thread and we're not a member, never show the message request.
        if isGroupThread, !isLocalUserInGroup { return false }

        let interactionFinder = InteractionFinder(threadUniqueId: thread.uniqueId)

        if
            let thread = thread as? TSContactThread,
            DependenciesBridge.shared.recipientHidingManager.isHiddenAddress(
                thread.contactAddress,
                tx: transaction.asV2Read
            )
        {
            // If the user hides a contact and said contact subsequently sends an incoming
            // message or calls, we display the message request UI.
            let mostRecentInteraction = interactionFinder.mostRecentInteraction(
                transaction: transaction
            )
            let isLatestInteractionIncomingMessage = mostRecentInteraction?.interactionType == .incomingMessage
            var isLatestInteractionMissedCall = false
            if
                let call = mostRecentInteraction as? TSCall,
                call.callType == .incomingMissed
            {
                isLatestInteractionMissedCall = true
            }
            return isLatestInteractionIncomingMessage || isLatestInteractionMissedCall
        }

        // If the thread is already whitelisted, do nothing. The user has already
        // accepted the request for this thread.
        guard !Self.profileManager.isThread(
            inProfileWhitelist: thread,
            transaction: transaction
        ) else { return false }

        if isGroupThread {
            // At this point, we know this is an un-whitelisted group thread.
            // If someone added us to the group, there will be a group update info message
            // in which case we want to show a pending message request. If the thread
            // is otherwise empty, we don't want to show the message request.
            if interactionFinder.hasGroupUpdateInfoMessage(
                transaction: transaction
            ) { return true }
        }

        // This thread is likely only visible because of system messages like so-and-so
        // is on signal or sync status. Some of the "possibly" incoming messages might
        // actually have been triggered by us, but if we sent one of these then the thread
        // should be in our profile white list and not make it to this check.
        guard interactionFinder.possiblyHasIncomingMessages(
            transaction: transaction
        ) else { return false }

        return true
    }

    public func shouldSetDefaultDisappearingMessageTimer(
        thread: TSThread,
        transaction tx: SDSAnyReadTransaction
    ) -> Bool {
        // We never set the default timer for group threads. Group thread timers
        // are set during group creation.
        guard !thread.isGroupThread else { return false }

        let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore

        // Make sure the universal timer is enabled.
        guard dmConfigurationStore.fetchOrBuildDefault(
            for: .universal,
            tx: tx.asV2Read
        ).isEnabled else {
            return false
        }

        // Make sure there the current timer is disabled.
        guard !dmConfigurationStore.fetchOrBuildDefault(
            for: .thread(thread),
            tx: tx.asV2Read
        ).isEnabled else {
            return false
        }

        // Make sure there has been no user initiated interactions.
        return !InteractionFinder(threadUniqueId: thread.uniqueId)
            .hasUserInitiatedInteraction(transaction: tx)
    }

    public func threads(withThreadIds threadIds: Set<String>, transaction: SDSAnyReadTransaction) throws -> Set<TSThread> {
        guard !threadIds.isEmpty else {
            return []
        }

        let sql = """
            SELECT * FROM \(ThreadRecord.databaseTableName)
            WHERE \(threadColumn: .uniqueId) IN (\(threadIds.map { "\'\($0)'" }.joined(separator: ",")))
        """
        let cursor = TSThread.grdbFetchCursor(
            sql: sql,
            arguments: [],
            transaction: transaction.unwrapGrdbRead
        )

        var threads = Set<TSThread>()
        while let thread = try cursor.next() {
            threads.insert(thread)
        }

        return threads
    }

    public func existsGroupThread(transaction: SDSAnyReadTransaction) -> Bool {
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
            return try Bool.fetchOne(
                transaction.unwrapGrdbRead.database,
                sql: sql,
                arguments: arguments
            ) ?? false
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Failed to find group thread")
        }
    }

    public func storyThreads(
        includeImplicitGroupThreads: Bool,
        transaction: SDSAnyReadTransaction
    ) -> [TSThread] {
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
                let groupIdCursor = try Data.fetchCursor(
                    transaction.unwrapGrdbRead.database,
                    sql: storyMessageGroupIdsSQL
                )

                while let groupId = try groupIdCursor.next() {
                    allowedDefaultThreadIds.append(TSGroupThread.threadId(
                        forGroupId: groupId,
                        transaction: transaction
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

        let cursor = TSThread.grdbFetchCursor(
            sql: sql,
            transaction: transaction.unwrapGrdbRead
        )

        var threads = [TSThread]()
        do {
            while let thread = try cursor.next() {
                if let groupThread = thread as? TSGroupThread {
                    guard groupThread.isStorySendEnabled(transaction: transaction) else { continue }
                }

                threads.append(thread)
            }
        } catch {
            owsFailDebug("Failed to query story threads \(error)")
        }

        return threads
    }

    public func threadsWithRecentInteractions(
        limit: UInt,
        transaction: SDSAnyReadTransaction
    ) -> [TSThread] {
        let sql = """
            SELECT *
            FROM \(ThreadRecord.databaseTableName)
            ORDER BY \(threadColumn: .lastInteractionRowId) DESC
            LIMIT \(limit)
        """

        let cursor = TSThread.grdbFetchCursor(
            sql: sql,
            transaction: transaction.unwrapGrdbRead
        )

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

    private func archivedJoin(isArchived: Bool) -> String {
        return """
            INNER JOIN \(ThreadAssociatedData.databaseTableName) AS ad
                ON ad.threadUniqueId = \(threadColumn: .uniqueId)
            WHERE ad.isArchived = \(isArchived ? "1" : "0")
        """
    }
}
