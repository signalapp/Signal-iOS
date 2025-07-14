//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

public class ThreadFinder {
    public init() {}

    private func requiredVisibleThreadsClause(forThreadIds threadIds: Set<String>) -> String {
        if threadIds.isEmpty {
            return ""
        } else {
            let threadIdsExpression = threadIds.lazy.map { "'\($0)'" }.joined(separator: ", ")
            return "OR \(threadColumnFullyQualified: .uniqueId) IN (\(threadIdsExpression))"
        }
    }

    /// Fetch a thread with the given SQLite row ID, if one exists.
    public func fetch(rowId: Int64, tx: DBReadTransaction) -> TSThread? {
        guard let thread = TSThread.grdbFetchOne(
            sql: """
                SELECT *
                FROM \(ThreadRecord.databaseTableName)
                WHERE \(threadColumn: .id) = ?
            """,
            arguments: [ rowId ],
            transaction: tx
        ) else {
            owsFailDebug("Missing thread with row ID - how did we get this row ID?")
            return nil
        }

        return thread
    }

    /// Enumerates through all story thread (distribution lists)
    /// - Parameter block
    /// A block executed for each enumerated thread. Returns `true` if
    /// enumeration should continue, and `false` otherwise.
    public func enumerateStoryThreads(
        transaction: DBReadTransaction,
        block: (TSPrivateStoryThread) throws -> Bool
    ) throws {
        let sql = """
            SELECT *
            FROM \(ThreadRecord.databaseTableName)
            WHERE \(threadColumn: .recordType) = \(SDSRecordType.privateStoryThread.rawValue)
        """
        let cursor = try ThreadRecord.fetchCursor(
            transaction.database,
            sql: sql
        )
        while let threadRecord = try cursor.next() {
            guard let storyThread = (try TSThread.fromRecord(threadRecord)) as? TSPrivateStoryThread else {
                owsFailDebug("Skipping thread that's not a story.")
                continue
            }
            guard try block(storyThread) else {
                break
            }
        }
    }

    /// Enumerates group threads in "last interaction" order.
    /// - Parameter block
    /// A block executed for each enumerated thread. Returns `true` if
    /// enumeration should continue, and `false` otherwise.
    public func enumerateGroupThreads(
        transaction: DBReadTransaction,
        block: (TSGroupThread) throws -> Bool
    ) throws {
        let sql = """
            SELECT *
            FROM \(ThreadRecord.databaseTableName)
            WHERE \(threadColumn: .groupModel) IS NOT NULL
            ORDER BY \(threadColumn: .lastInteractionRowId) DESC
        """

        let cursor = try ThreadRecord.fetchCursor(
            transaction.database,
            sql: sql
        )
        while let threadRecord = try cursor.next() {
            guard let groupThread = (try TSThread.fromRecord(threadRecord)) as? TSGroupThread else {
                owsFailDebug("Skipping thread that's not a group.")
                continue
            }
            guard try block(groupThread) else {
                break
            }
        }
    }

    /// Enumerates all non-story threads in arbitrary order.
    /// - Parameter block
    /// A block executed for each enumerated thread. Returns `true` if
    /// enumeration should continue, and `false` otherwise.
    public func enumerateNonStoryThreads(
        transaction: DBReadTransaction,
        block: (TSThread) throws -> Bool
    ) throws {
        let sql = """
            SELECT *
            FROM \(ThreadRecord.databaseTableName)
            WHERE \(threadColumn: .recordType) IS NOT ?
        """

        let cursor = try ThreadRecord.fetchCursor(
            transaction.database,
            sql: sql,
            arguments: [SDSRecordType.privateStoryThread]
        )
        while
            let thread = try cursor.next().map({ try TSThread.fromRecord($0) }),
            try block(thread)
        {}
    }

    public func visibleThreadCount(
        isArchived: Bool,
        transaction: DBReadTransaction
    ) throws -> UInt {
        let sql = """
            SELECT COUNT(*)
            FROM \(ThreadRecord.databaseTableName)
            \(threadAssociatedDataJoinClause(isArchived: isArchived))
            WHERE \(threadColumn: .shouldThreadBeVisible) = 1
            """

        guard let count = try UInt.fetchOne(
            transaction.database,
            sql: sql
        ) else {
            owsFailDebug("count was unexpectedly nil")
            return 0
        }

        return count
    }

    public func enumerateVisibleThreads(
        isArchived: Bool,
        transaction: DBReadTransaction,
        block: (TSThread) -> Void
    ) throws {
        let sql = """
            SELECT *
            FROM \(ThreadRecord.databaseTableName)
            \(threadAssociatedDataJoinClause(isArchived: isArchived))
            WHERE \(threadColumn: .shouldThreadBeVisible) = 1
            ORDER BY \(threadColumn: .lastInteractionRowId) DESC
            """

        do {
            try ThreadRecord.fetchCursor(
                transaction.database,
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

    public func visibleInboxThreadIds(
        filteredBy inboxFilter: InboxFilter? = nil,
        requiredVisibleThreadIds: Set<String> = [],
        transaction: DBReadTransaction
    ) throws -> [String] {
        if inboxFilter == .unread {
            let sql = """
                SELECT
                    \(threadColumnFullyQualified: .uniqueId) AS thread_uniqueId,
                    \(ThreadAssociatedData.databaseTableName).isMarkedUnread AS thread_isMarkedUnread,
                    COUNT(i.\(interactionColumn: .uniqueId)) AS interactions_unreadCount
                FROM \(ThreadRecord.databaseTableName)
                INNER JOIN \(ThreadAssociatedData.databaseTableName)
                    ON \(ThreadAssociatedData.databaseTableName).threadUniqueId = \(threadColumnFullyQualified: .uniqueId)
                    AND \(ThreadAssociatedData.databaseTableName).isArchived = 0
                LEFT OUTER JOIN \(InteractionRecord.databaseTableName) AS i
                    \(DEBUG_INDEXED_BY("index_model_TSInteraction_UnreadMessages"))
                    ON i.\(interactionColumn: .threadUniqueId) = thread_uniqueId
                    AND \(InteractionFinder.sqlClauseForUnreadInteractionCounts(interactionsAlias: "i"))
                WHERE \(threadColumnFullyQualified: .shouldThreadBeVisible) = 1
                GROUP BY thread_uniqueId
                HAVING (
                    thread_isMarkedUnread = 1
                    OR interactions_unreadCount > 0
                    \(requiredVisibleThreadsClause(forThreadIds: requiredVisibleThreadIds))
                )
                ORDER BY \(threadColumnFullyQualified: .lastInteractionRowId) DESC
                """
            return try String.fetchAll(transaction.database, sql: sql, adapter: RangeRowAdapter(0..<1))
        } else {
            let sql = """
                SELECT \(threadColumn: .uniqueId)
                FROM \(ThreadRecord.databaseTableName)
                INNER JOIN \(ThreadAssociatedData.databaseTableName)
                    ON \(ThreadAssociatedData.databaseTableName).threadUniqueId = \(threadColumnFullyQualified: .uniqueId)
                    AND \(ThreadAssociatedData.databaseTableName).isArchived = 0
                WHERE \(threadColumn: .shouldThreadBeVisible) = 1
                ORDER BY \(threadColumn: .lastInteractionRowId) DESC
                """
            return try String.fetchAll(transaction.database, sql: sql)
        }
    }

    public func visibleArchivedThreadIds(
        transaction: DBReadTransaction
    ) throws -> [String] {
        let sql = """
            SELECT \(threadColumn: .uniqueId)
            FROM \(ThreadRecord.databaseTableName)
            \(threadAssociatedDataJoinClause(isArchived: true))
            WHERE \(threadColumn: .shouldThreadBeVisible) = 1
            ORDER BY \(threadColumn: .lastInteractionRowId) DESC
            """

        return try String.fetchAll(transaction.database, sql: sql)
    }

    public func fetchContactSyncThreadRowIds(tx: DBReadTransaction) throws -> [Int64] {
        let sql = """
            SELECT \(threadColumn: .id)
            FROM \(ThreadRecord.databaseTableName)
            WHERE \(threadColumn: .shouldThreadBeVisible) = 1
            ORDER BY \(threadColumn: .lastInteractionRowId) DESC
            """
        do {
            return try Int64.fetchAll(tx.database, sql: sql)
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    public func hasPendingMessageRequest(
        thread: TSThread,
        transaction: DBReadTransaction
    ) -> Bool {
        // TODO: Should we consult isRequestingMember() here?
        if let groupThread = thread as? TSGroupThread, groupThread.isGroupV2Thread, groupThread.isLocalUserInvitedMember {
            return true
        }

        // If we're creating the thread, don't show the message request view
        if !thread.shouldThreadBeVisible {
            return false
        }

        // If this thread is blocked AND we're still in the thread, show the message
        // request view regardless of if we have sent messages or not.
        if SSKEnvironment.shared.blockingManagerRef.isThreadBlocked(thread, transaction: transaction) {
            return true
        }

        let isGroupThread = thread is TSGroupThread
        let isLocalUserInGroup = (thread as? TSGroupThread)?.isLocalUserFullOrInvitedMember == true

        // If this is a group thread and we're not a member, never show the message request.
        if isGroupThread, !isLocalUserInGroup {
            return false
        }

        let interactionFinder = InteractionFinder(threadUniqueId: thread.uniqueId)

        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
        let recipientHidingManager = DependenciesBridge.shared.recipientHidingManager
        if
            let contactThread = thread as? TSContactThread,
            let signalRecipient = recipientDatabaseTable.fetchRecipient(
                contactThread: contactThread,
                tx: transaction
            ),
            let hiddenRecipient = recipientHidingManager.fetchHiddenRecipient(
                signalRecipient: signalRecipient,
                tx: transaction
            )
        {
            return recipientHidingManager.isHiddenRecipientThreadInMessageRequest(
                hiddenRecipient: hiddenRecipient,
                contactThread: contactThread,
                tx: transaction
            )
        }

        // If the thread is already whitelisted, do nothing. The user has already
        // accepted the request for this thread.
        if SSKEnvironment.shared.profileManagerRef.isThread(inProfileWhitelist: thread, transaction: transaction) {
            return false
        }

        // At this point, we know this is an un-whitelisted group thread.
        // If someone added us to the group, there will be a group update info message
        // in which case we want to show a pending message request. If the thread
        // is otherwise empty, we don't want to show the message request.
        if isGroupThread, interactionFinder.hasGroupUpdateInfoMessage(transaction: transaction) {
            return true
        }

        // This thread is likely only visible because of system messages like so-and-so
        // is on signal or sync status. Some of the "possibly" incoming messages might
        // actually have been triggered by us, but if we sent one of these then the thread
        // should be in our profile white list and not make it to this check.
        return interactionFinder.possiblyHasIncomingMessages(transaction: transaction)
    }

    /// Whether we should set the default timer for the given contact thread.
    ///
    /// - Note
    /// We never set the default timer for group threads, which are instead set
    /// during group creation.
    public func shouldSetDefaultDisappearingMessageTimer(
        contactThread: TSContactThread,
        transaction tx: DBReadTransaction
    ) -> Bool {
        let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore

        // Make sure the universal timer is enabled.
        guard dmConfigurationStore.fetchOrBuildDefault(
            for: .universal,
            tx: tx
        ).isEnabled else {
            return false
        }

        // Make sure the current timer is disabled.
        guard !dmConfigurationStore.fetchOrBuildDefault(
            for: .thread(contactThread),
            tx: tx
        ).isEnabled else {
            return false
        }

        // Make sure there has been no user initiated interactions.
        return !InteractionFinder(threadUniqueId: contactThread.uniqueId)
            .hasUserInitiatedInteraction(transaction: tx)
    }

    public func threads(withThreadIds threadIds: Set<String>, transaction: DBReadTransaction) throws -> Set<TSThread> {
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
            transaction: transaction
        )

        var threads = Set<TSThread>()
        while let thread = try cursor.next() {
            threads.insert(thread)
        }

        return threads
    }

    public func existsGroupThread(transaction: DBReadTransaction) -> Bool {
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
                transaction.database,
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
        transaction: DBReadTransaction
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
                    transaction.database,
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
            transaction: transaction
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
        transaction: DBReadTransaction
    ) -> [TSThread] {
        let sql = """
            SELECT *
            FROM \(ThreadRecord.databaseTableName)
            ORDER BY \(threadColumn: .lastInteractionRowId) DESC
            LIMIT \(limit)
        """

        let cursor = TSThread.grdbFetchCursor(
            sql: sql,
            transaction: transaction
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

    private func threadAssociatedDataJoinClause(isArchived: Bool) -> String {
        """
        INNER JOIN \(ThreadAssociatedData.databaseTableName)
            ON \(ThreadAssociatedData.databaseTableName).threadUniqueId = \(threadColumnFullyQualified: .uniqueId)
            AND \(ThreadAssociatedData.databaseTableName).isArchived = \(isArchived ? "1" : "0")
        """
    }

    public func internal_visibleInboxThreadIds(
        filteredBy inboxFilter: InboxFilter? = nil,
        requiredVisibleThreadIds: Set<String> = [],
        transaction: DBReadTransaction
    ) throws -> [String] {
        if inboxFilter == .unread {
            let sql = """
                SELECT
                    \(threadColumnFullyQualified: .uniqueId) AS thread_uniqueId,
                    \(ThreadAssociatedData.databaseTableName).isMarkedUnread AS thread_isMarkedUnread,
                    COUNT(i.\(interactionColumn: .uniqueId)) AS interactions_unreadCount
                FROM \(ThreadRecord.databaseTableName)
                INNER JOIN \(ThreadAssociatedData.databaseTableName)
                    ON \(ThreadAssociatedData.databaseTableName).threadUniqueId = \(threadColumnFullyQualified: .uniqueId)
                    AND \(ThreadAssociatedData.databaseTableName).isArchived = 0
                LEFT OUTER JOIN \(InteractionRecord.databaseTableName) AS i
                    \(DEBUG_INDEXED_BY("index_model_TSInteraction_UnreadMessages"))
                    ON i.\(interactionColumn: .threadUniqueId) = thread_uniqueId
                    AND \(InteractionFinder.sqlClauseForUnreadInteractionCounts(interactionsAlias: "i"))
                WHERE \(threadColumnFullyQualified: .shouldThreadBeVisible) = 1
                GROUP BY thread_uniqueId
                HAVING (
                    thread_isMarkedUnread = 1
                    OR interactions_unreadCount > 0
                    \(requiredVisibleThreadsClause(forThreadIds: requiredVisibleThreadIds))
                )
                ORDER BY
                    CASE WHEN \(threadColumn: .lastDraftInteractionRowId) > \(threadColumn: .lastInteractionRowId)
                        THEN \(threadColumn: .lastDraftInteractionRowId) ELSE \(threadColumn: .lastInteractionRowId)
                    END DESC,
                    \(threadColumn: .lastDraftUpdateTimestamp) DESC
                """

            return try String.fetchAll(transaction.database, sql: sql, adapter: RangeRowAdapter(0..<1))
        } else {
            let sql = """
                SELECT \(threadColumn: .uniqueId)
                FROM \(ThreadRecord.databaseTableName)
                INNER JOIN \(ThreadAssociatedData.databaseTableName)
                    ON \(ThreadAssociatedData.databaseTableName).threadUniqueId = \(threadColumnFullyQualified: .uniqueId)
                    AND \(ThreadAssociatedData.databaseTableName).isArchived = 0
                WHERE \(threadColumn: .shouldThreadBeVisible) = 1
                ORDER BY
                    CASE WHEN \(threadColumn: .lastDraftInteractionRowId) > \(threadColumn: .lastInteractionRowId)
                        THEN \(threadColumn: .lastDraftInteractionRowId) ELSE \(threadColumn: .lastInteractionRowId)
                    END DESC,
                    \(threadColumn: .lastDraftUpdateTimestamp) DESC
                """
            return try String.fetchAll(transaction.database, sql: sql)
        }
    }

    public func internal_visibleArchivedThreadIds(
        transaction: DBReadTransaction
    ) throws -> [String] {
        let sql = """
            SELECT \(threadColumn: .uniqueId)
            FROM \(ThreadRecord.databaseTableName)
            \(threadAssociatedDataJoinClause(isArchived: true))
            WHERE \(threadColumn: .shouldThreadBeVisible) = 1
            ORDER BY
                CASE WHEN \(threadColumn: .lastDraftInteractionRowId) > \(threadColumn: .lastInteractionRowId)
                    THEN \(threadColumn: .lastDraftInteractionRowId) ELSE \(threadColumn: .lastInteractionRowId)
                END DESC,
                \(threadColumn: .lastDraftUpdateTimestamp) DESC
            """

        return try String.fetchAll(transaction.database, sql: sql)
    }
}
