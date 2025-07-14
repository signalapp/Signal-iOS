//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
public import LibSignalClient

public enum EditMessageQueryMode {
    case includeAllEdits
    case excludeReadEdits
    case excludeAllEdits
}

// MARK: -

@objc
public class InteractionFinder: NSObject {
    let threadUniqueId: String

    @objc
    public init(threadUniqueId: String) {
        self.threadUniqueId = threadUniqueId
    }

    // MARK: - static methods

    public class func fetch(
        rowId: Int64,
        transaction: DBReadTransaction
    ) -> TSInteraction? {
        guard let interaction = TSInteraction.grdbFetchOne(
            sql: """
                SELECT *
                FROM \(InteractionRecord.databaseTableName)
                WHERE \(interactionColumn: .id) = ?
                """,
            arguments: [ rowId ],
            transaction: transaction
        ) else {
            owsFailDebug("Missing interaction with row ID - how did we get this row ID?")
            return nil
        }

        return interaction
    }

    public class func existsIncomingMessage(
        timestamp: UInt64,
        sourceAci: Aci,
        transaction: DBReadTransaction
    ) -> Bool {
        let sql = """
            SELECT 1
            FROM \(InteractionRecord.databaseTableName)
            \(DEBUG_INDEXED_BY("Interaction_timestamp", or: "index_interactions_on_timestamp_sourceDeviceId_and_authorPhoneNumber"))
            WHERE \(interactionColumn: .timestamp) = ?
            AND (
                \(interactionColumn: .authorUUID) = ?
                OR (
                    \(interactionColumn: .authorUUID) IS NULL
                    AND \(interactionColumn: .authorPhoneNumber) = ?
                )
            )
            LIMIT 1
            """
        let arguments: StatementArguments = [
            timestamp,
            sourceAci.serviceIdUppercaseString,
            SignalServiceAddress(sourceAci).phoneNumber
        ]
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
            owsFail("Failed to find incoming message")
        }
    }

    @objc
    public class func fetchInteractions(
        timestamp: UInt64,
        transaction: DBReadTransaction
    ) throws -> [TSInteraction] {
        let sql = """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            \(DEBUG_INDEXED_BY("Interaction_timestamp", or: "index_interactions_on_timestamp_sourceDeviceId_and_authorPhoneNumber"))
            WHERE \(interactionColumn: .timestamp) = ?
        """

        return try TSInteraction.grdbFetchCursor(
            sql: sql,
            arguments: [timestamp],
            transaction: transaction
        ).all()
    }

    public class func incompleteCallIds(transaction: DBReadTransaction) -> [String] {
        let sql: String = """
            SELECT \(interactionColumn: .uniqueId)
            FROM \(InteractionRecord.databaseTableName)
            \(DEBUG_INDEXED_BY("index_interaction_on_recordType_and_callType"))
            WHERE \(interactionColumn: .recordType) = ?
            AND (
                \(interactionColumn: .callType) = ?
                OR \(interactionColumn: .callType) = ?
            )
            """
        let statementArguments: StatementArguments = [
            SDSRecordType.call.rawValue,
            RPRecentCallType.outgoingIncomplete.rawValue,
            RPRecentCallType.incomingIncomplete.rawValue
        ]
        var result = [String]()
        do {
            result = try String.fetchAll(
                transaction.database,
                sql: sql,
                arguments: statementArguments
            )
        } catch {
            owsFailDebug("error: \(error)")
        }
        return result
    }

    public class func attemptingOutInteractionIds(
        transaction: DBReadTransaction
    ) -> [String] {
        let sql: String = """
            SELECT \(interactionColumn: .uniqueId)
            FROM \(InteractionRecord.databaseTableName)
            \(DEBUG_INDEXED_BY("index_interaction_on_storedMessageState"))
            WHERE \(interactionColumn: .storedMessageState) = ?
            """
        var result = [String]()
        do {
            result = try String.fetchAll(
                transaction.database,
                sql: sql,
                arguments: [TSOutgoingMessageState.sending.rawValue]
            )
        } catch {
            owsFailDebug("error: \(error)")
        }
        return result
    }

    public class func pendingInteractionIds(
        transaction: DBReadTransaction
    ) -> [String] {
        let sql: String = """
            SELECT \(interactionColumn: .uniqueId)
            FROM \(InteractionRecord.databaseTableName)
            \(DEBUG_INDEXED_BY("index_interaction_on_storedMessageState"))
            WHERE \(interactionColumn: .storedMessageState) = ?
            """
        var result = [String]()
        do {
            result = try String.fetchAll(
                transaction.database,
                sql: sql,
                arguments: [TSOutgoingMessageState.pending.rawValue]
            )
        } catch {
            owsFailDebug("error: \(error)")
        }
        return result
    }

    public class func unreadCountInAllThreads(transaction: DBReadTransaction) -> UInt {
        do {
            let includeMutedThreads = SSKPreferences.includeMutedThreadsInBadgeCount(transaction: transaction)

            var unreadInteractionQuery = """
                SELECT COUNT(interaction.\(interactionColumn: .id))
                FROM \(InteractionRecord.databaseTableName) AS interaction
                \(DEBUG_INDEXED_BY("index_model_TSInteraction_UnreadMessages"))
                INNER JOIN \(ThreadAssociatedData.databaseTableName) AS associatedData
                \(DEBUG_INDEXED_BY("index_thread_associated_data_on_threadUniqueId_and_isArchived"))
                    ON associatedData.threadUniqueId = \(interactionColumn: .threadUniqueId)
                WHERE associatedData.isArchived = "0"
                """

            if !includeMutedThreads {
                unreadInteractionQuery += " \(sqlClauseForIgnoringInteractionsWithMutedThread(threadAssociatedDataAlias: "associatedData")) "
            }

            unreadInteractionQuery += " AND \(sqlClauseForUnreadInteractionCounts(interactionsAlias: "interaction")) "

            let unreadInteractionCount = try UInt.fetchOne(transaction.database, sql: unreadInteractionQuery)
            owsAssertDebug(unreadInteractionCount != nil, "unreadInteractionCount was unexpectedly nil")

            var markedUnreadThreadQuery = """
                SELECT COUNT(*)
                FROM \(ThreadRecord.databaseTableName)
                INNER JOIN \(ThreadAssociatedData.databaseTableName) AS associatedData
                    ON associatedData.threadUniqueId = \(threadColumn: .uniqueId)
                WHERE associatedData.isMarkedUnread = 1
                AND associatedData.isArchived = "0"
                AND \(threadColumn: .shouldThreadBeVisible) = 1
                """

            if !includeMutedThreads {
                markedUnreadThreadQuery += " \(sqlClauseForIgnoringInteractionsWithMutedThread(threadAssociatedDataAlias: "associatedData")) "
            }

            let markedUnreadCount = try UInt.fetchOne(transaction.database, sql: markedUnreadThreadQuery)
            owsAssertDebug(markedUnreadCount != nil, "markedUnreadCount was unexpectedly nil")

            return (unreadInteractionCount ?? 0) + (markedUnreadCount ?? 0)
        } catch {
            owsFailDebug("error: \(error.grdbErrorForLogging)")
            return 0
        }
    }

    // The interactions should be enumerated in order from "next to expire" to "last to expire".
    public class func nextMessageWithStartedPerConversationExpirationToExpire(
        transaction: DBReadTransaction
    ) -> TSMessage? {
        // NOTE: We DO NOT consult storedShouldStartExpireTimer here;
        //       once expiration has begun we want to see it through.
        let sql = """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            \(DEBUG_INDEXED_BY("Interaction_disappearingMessages_partial", or: "index_interactions_on_expiresInSeconds_and_expiresAt"))
            WHERE \(interactionColumn: .expiresAt) > 0
            ORDER BY \(interactionColumn: .expiresAt)
            """
        let cursor = TSInteraction.grdbFetchCursor(
            sql: sql,
            transaction: transaction
        )
        do {
            while let interaction = try cursor.next() {
                if let message = interaction as? TSMessage {
                    return message
                } else {
                    owsFailDebug("Unexpected object: \(type(of: interaction))")
                }
            }
        } catch {
            owsFail("error: \(error)")
        }
        return nil
    }

    public class func fetchSomeExpiredMessageRowIds(now: UInt64, limit: Int, tx: DBReadTransaction) throws -> [Int64] {
        // NOTE: We DO NOT consult storedShouldStartExpireTimer here;
        //       once expiration has begun we want to see it through.
        let sql = """
            SELECT \(interactionColumn: .id)
            FROM \(InteractionRecord.databaseTableName)
            \(DEBUG_INDEXED_BY("Interaction_disappearingMessages_partial", or: "index_interactions_on_expiresInSeconds_and_expiresAt"))
            WHERE \(interactionColumn: .expiresAt) > 0
            AND \(interactionColumn: .expiresAt) <= ?
            LIMIT \(limit)
            """
        do {
            return try Int64.fetchAll(tx.database, sql: sql, arguments: [now])
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    public class func fetchAllMessageUniqueIdsWhichFailedToStartExpiring(
        transaction: DBReadTransaction
    ) -> [String] {
        // NOTE: We DO consult storedShouldStartExpireTimer here.
        //       We don't want to start expiration until it is true.
        let sql = """
            SELECT \(interactionColumn: .uniqueId)
            FROM \(InteractionRecord.databaseTableName)
            \(DEBUG_INDEXED_BY("index_interactions_on_threadUniqueId_storedShouldStartExpireTimer_and_expiresAt"))
            WHERE \(interactionColumn: .storedShouldStartExpireTimer) IS TRUE
            AND (
                \(interactionColumn: .expiresAt) IS 0 OR
                \(interactionColumn: .expireStartedAt) IS 0
            )
            """
        do {
            return try String.fetchAll(
                transaction.database,
                sql: sql
            )
        } catch {
            owsFailDebug("error: \(error)")
            return []
        }
    }

    public class func interactions(
        withInteractionIds interactionIds: Set<String>,
        transaction: DBReadTransaction
    ) -> Set<TSInteraction> {
        guard !interactionIds.isEmpty else {
            return []
        }

        let sql = """
            SELECT * FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .uniqueId) IN (\(interactionIds.map { "\'\($0)'" }.joined(separator: ",")))
            """
        let arguments: StatementArguments = []
        let cursor = TSInteraction.grdbFetchCursor(
            sql: sql,
            arguments: arguments,
            transaction: transaction
        )
        var interactions = Set<TSInteraction>()
        do {
            while let interaction = try cursor.next() {
                interactions.insert(interaction)
            }
        } catch {
            owsFailDebug("unexpected error \(error)")
        }
        return interactions
    }

    public static func enumerateGroupReplies(
        for storyMessage: StoryMessage,
        transaction: DBReadTransaction,
        block: @escaping (TSMessage, inout Bool) -> Void
    ) {
        let sql = """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            \(DEBUG_INDEXED_BY("Interaction_storyReply_partial", or: "index_model_TSInteraction_on_StoryContext"))
            WHERE \(interactionColumn: .storyTimestamp) = ?
            AND \(interactionColumn: .storyAuthorUuidString) = ?
            AND \(interactionColumn: .isGroupStoryReply) = 1
            """
        let cursor = TSInteraction.grdbFetchCursor(
            sql: sql,
            arguments: [storyMessage.timestamp, storyMessage.authorAci.serviceIdUppercaseString],
            transaction: transaction
        )
        do {
            while let interaction = try cursor.next() {
                guard let message = interaction as? TSMessage else {
                    owsFailDebug("Unexpected object: \(type(of: interaction))")
                    return
                }
                var stop: Bool = false
                block(message, &stop)
                if stop {
                    return
                }
            }
        } catch {
            owsFail("error: \(error)")
        }
    }

    public static func hasLocalUserReplied(
        storyTimestamp: UInt64,
        storyAuthorAci: Aci,
        transaction: DBReadTransaction
    ) -> Bool {
        let sql = """
            SELECT 1
            FROM \(InteractionRecord.databaseTableName)
            \(DEBUG_INDEXED_BY("Interaction_storyReply_partial", or: "index_model_TSInteraction_on_StoryContext"))
            WHERE \(interactionColumn: .storyTimestamp) = ?
            AND \(interactionColumn: .storyAuthorUuidString) = ?
            AND \(interactionColumn: .recordType) = \(SDSRecordType.outgoingMessage.rawValue)
            AND \(interactionColumn: .isGroupStoryReply) = 1
            LIMIT 1
            """
        do {
            return try Bool.fetchOne(
                transaction.database,
                sql: sql,
                arguments: [
                    storyTimestamp,
                    storyAuthorAci.serviceIdUppercaseString
                ]
            ) ?? false
        } catch {
            owsFail("error: \(error)")
        }
    }

    public static func groupReplyUniqueIdsAndRowIds(
        storyAuthor: Aci,
        storyTimestamp: UInt64,
        transaction: DBReadTransaction
    ) -> [(String, Int64)] {
        guard storyAuthor != StoryMessage.systemStoryAuthor else {
            // No replies on system stories.
            return []
        }
        do {
            let sql: String = """
                SELECT \(interactionColumn: .uniqueId), \(interactionColumn: .id)
                FROM \(InteractionRecord.databaseTableName)
                \(DEBUG_INDEXED_BY("Interaction_storyReply_partial", or: "index_model_TSInteraction_on_StoryContext"))
                WHERE \(interactionColumn: .storyTimestamp) = ?
                AND \(interactionColumn: .storyAuthorUuidString) = ?
                AND \(interactionColumn: .isGroupStoryReply) = 1
                ORDER BY \(interactionColumn: .id) ASC
                """
            return try Row.fetchAll(
                transaction.database,
                sql: sql,
                arguments: [storyTimestamp, storyAuthor.serviceIdUppercaseString]
            ).map { ($0[0], $0[1]) }
        } catch {
            owsFail("error: \(error)")
        }
    }

    static func enumeratePlaceholders(
        transaction: DBReadTransaction,
        block: (OWSRecoverableDecryptionPlaceholder) -> Void
    ) {
        let sql = """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            \(DEBUG_INDEXED_BY("index_interaction_on_recordType_and_callType"))
            WHERE \(interactionColumn: .recordType) IS \(SDSRecordType.recoverableDecryptionPlaceholder.rawValue)
            """
        do {
            let cursor = TSInteraction.grdbFetchCursor(
                sql: sql,
                transaction: transaction
            )
            while let result = try cursor.next() {
                if let placeholder = result as? OWSRecoverableDecryptionPlaceholder {
                    block(placeholder)
                } else {
                    owsFailDebug("Unexpected type: \(type(of: result))")
                }
            }
        } catch {
            owsFailDebug("unexpected error \(error)")
        }
    }

    @objc
    public class func findMessage(
        withTimestamp timestamp: UInt64,
        threadId: String,
        author: SignalServiceAddress,
        transaction: DBReadTransaction
    ) -> TSMessage? {
        guard timestamp > 0 else {
            owsFailDebug("invalid timestamp: \(timestamp)")
            return nil
        }

        guard !threadId.isEmpty else {
            owsFailDebug("invalid thread")
            return nil
        }

        guard author.isValid else {
            owsFailDebug("Invalid author \(author)")
            return nil
        }

        let messages: [TSMessage]

        do {
            messages = try InteractionFinder.fetchInteractions(
                timestamp: timestamp,
                transaction: transaction
            ).compactMap { $0 as? TSMessage }
        } catch {
            owsFailDebug("Error loading interactions \(error)")
            return nil
        }

        for message in messages {
            guard message.uniqueThreadId == threadId else { continue }

            if let incomingMessage = message as? TSIncomingMessage,
                incomingMessage.authorAddress.isEqualToAddress(author) {
                return incomingMessage
            }

            if let outgoingMessage = message as? TSOutgoingMessage,
                author.isLocalAddress {
                return outgoingMessage
            }
        }

        return nil
    }

    /// Gets the most recently inserted Interaction of type `incomingMessage`.
    public static func lastInsertedIncomingMessage(
        transaction: DBReadTransaction
    ) -> TSIncomingMessage? {
        let sql: String = """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            \(DEBUG_INDEXED_BY("index_interaction_on_recordType_and_callType"))
            WHERE \(interactionColumn: .recordType) = ?
            AND \(interactionColumn: .callType) IS NULL
            ORDER BY \(interactionColumn: .id) DESC
            LIMIT 1
            """
        let arguments: StatementArguments = [
            SDSRecordType.incomingMessage.rawValue
        ]
        let result = TSInteraction.grdbFetchOne(
            sql: sql,
            arguments: arguments,
            transaction: transaction
        )
        if let result = result as? TSIncomingMessage {
            return result
        } else if let result {
            owsFailDebug("Unexpected type: \(type(of: result))")
            return nil
        } else {
            return nil
        }
    }

    // MARK: - instance methods

    public func profileUpdateInteractions(
        afterSortId sortId: UInt64,
        transaction: DBReadTransaction
    ) -> [TSInfoMessage] {
        let cursor = TSInteraction.grdbFetchCursor(
            sql: """
                SELECT *
                FROM \(InteractionRecord.databaseTableName)
                \(DEBUG_INDEXED_BY("index_interactions_on_threadUniqueId_and_id"))
                WHERE \(interactionColumn: .threadUniqueId) = ?
                AND \(interactionColumn: .messageType) = ?
                AND \(interactionColumn: .id) > ?
                """,
            arguments: [threadUniqueId, TSInfoMessageType.profileUpdate.rawValue, sortId],
            transaction: transaction
        )

        let allResults: [TSInteraction]
        do {
            // Every result should be an info message with associated profile changes
            allResults = try cursor.all()
            owsAssertDebug(allResults.allSatisfy({ ($0 as? TSInfoMessage)?.profileChangeAddress != nil }))
        } catch {
            owsFailDebug("Unexpected error \(error)")
            allResults = []
        }

        return allResults.compactMap { $0 as? TSInfoMessage }
    }

    func latestInteraction(
        from address: SignalServiceAddress,
        transaction: DBReadTransaction
    ) -> TSInteraction? {
        let sql = """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            \(DEBUG_INDEXED_BY("index_interactions_on_threadUniqueId_and_id"))
            WHERE \(interactionColumn: .threadUniqueId) = ?
            AND (
                \(interactionColumn: .authorUUID) = ?
                OR (\(interactionColumn: .authorUUID) IS NULL AND \(interactionColumn: .authorPhoneNumber) = ?)
            )
            ORDER BY \(interactionColumn: .id) DESC
            LIMIT 1
            """
        let arguments: StatementArguments = [threadUniqueId, address.serviceIdUppercaseString, address.phoneNumber]
        return TSInteraction.grdbFetchOne(
            sql: sql,
            arguments: arguments,
            transaction: transaction
        )
    }

    private var mostRecentInteractionSqlAndArgs: (String, StatementArguments) {
        return (
            """
                SELECT *
                FROM \(InteractionRecord.databaseTableName)
                \(DEBUG_INDEXED_BY("index_interactions_on_threadUniqueId_and_id"))
                WHERE \(interactionColumn: .threadUniqueId) = ?
                \(Self.filterGroupStoryRepliesClause())
                \(Self.filterEditHistoryClause())
                AND \(interactionColumn: .errorType) IS NOT ?
                AND \(interactionColumn: .messageType) IS NOT ?
                AND \(interactionColumn: .messageType) IS NOT ?
                ORDER BY \(interactionColumn: .id) DESC
                """,
            [
                threadUniqueId,
                TSErrorMessageType.nonBlockingIdentityChange.rawValue,
                TSInfoMessageType.verificationStateChange.rawValue,
                TSInfoMessageType.profileUpdate.rawValue
            ]
        )
    }

    func mostRecentInteraction(
        transaction: DBReadTransaction
    ) -> TSInteraction? {
        let (sql, args) = mostRecentInteractionSqlAndArgs
        let firstInteractionSql = sql + " LIMIT 1"
        return TSInteraction.grdbFetchOne(
            sql: firstInteractionSql,
            arguments: args,
            transaction: transaction
        )
    }

    @objc
    public func mostRecentInteractionForInbox(
        transaction: DBReadTransaction
    ) -> TSInteraction? {
        guard let firstInteraction = mostRecentInteraction(transaction: transaction) else {
            return nil
        }

        // We can't exclude specific group updates in the query.
        // In the (mildly) rare case that the most recent message
        // is a group update that shouldn't be shown,
        // we iterate backward until we find a good interaction.
        if firstInteraction.shouldAppearInInbox(transaction: transaction) {
            return firstInteraction
        }
        do {
            let (sql, args) = mostRecentInteractionSqlAndArgs
            let cursor = TSInteraction.grdbFetchCursor(
                sql: sql,
                arguments: args,
                transaction: transaction
            )
            while let interaction = try cursor.next() {
                if interaction.shouldAppearInInbox(transaction: transaction) {
                    return interaction
                }
            }
            return nil
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    public func unreadCount(transaction: DBReadTransaction) -> UInt {
        do {
            let sql = """
                SELECT COUNT(*)
                FROM \(InteractionRecord.databaseTableName)
                \(DEBUG_INDEXED_BY("index_model_TSInteraction_UnreadMessages"))
                WHERE \(interactionColumn: .threadUniqueId) = ?
                AND \(InteractionFinder.sqlClauseForUnreadInteractionCounts())
                """
            let arguments: StatementArguments = [threadUniqueId]

            guard let count = try UInt.fetchOne(
                transaction.database,
                sql: sql,
                arguments: arguments
            ) else {
                owsFailDebug("count was unexpectedly nil")
                return 0
            }
            return count
        } catch {
            owsFailDebug("error: \(error)")
            return 0
        }
    }

    /// Enumerates all the unread interactions in this thread, sorted by sort id.
    public func fetchAllUnreadMessages(
        transaction: DBReadTransaction
    ) -> SDSMappedCursor<TSInteractionCursor, OWSReadTracking> {
        let sql = """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            \(DEBUG_INDEXED_BY("index_model_TSInteraction_UnreadMessages"))
            WHERE \(interactionColumn: .threadUniqueId) = ?
            AND \(Self.sqlClauseForAllUnreadInteractions(excludeReadEdits: true))
            ORDER BY \(interactionColumn: .id)
            """

        let cursor = TSInteraction.grdbFetchCursor(
            sql: sql,
            arguments: [threadUniqueId],
            transaction: transaction
        )
        return cursor.compactMap { interaction -> OWSReadTracking? in
            guard let readTracking = interaction as? OWSReadTracking else {
                owsFailDebug("Interaction has unexpected type: \(type(of: interaction))")
                return nil
            }
            guard !readTracking.wasRead else {
                owsFailDebug("Unexpectedly found read interaction: \(interaction.timestamp)")
                return nil
            }
            return readTracking
        }
    }

    /// Do we have any messages to mark read in this thread before a given sort ID?
    ///
    /// See also: ``fetchUnreadMessages`` and ``fetchMessagesWithUnreadReactions``.
    public func hasMessagesToMarkRead(
        beforeSortId: UInt64,
        transaction: DBReadTransaction
    ) -> Bool {
        let hasUnreadMessages = (try? Bool.fetchOne(
            transaction.database,
            sql: """
                SELECT 1
                FROM \(InteractionRecord.databaseTableName)
                \(DEBUG_INDEXED_BY("index_model_TSInteraction_UnreadMessages"))
                WHERE \(interactionColumn: .threadUniqueId) = ?
                AND \(interactionColumn: .id) <= ?
                AND \(Self.sqlClauseForAllUnreadInteractions())
                LIMIT 1
                """,
            arguments: [threadUniqueId, beforeSortId]
        )) ?? false

        if hasUnreadMessages {
            return true
        }

        let hasOutgoingMessagesWithUnreadReactions = (try? Bool.fetchOne(
            transaction.database,
            sql: """
                SELECT 1
                FROM \(InteractionRecord.databaseTableName) AS interaction
                \(DEBUG_INDEXED_BY("index_interactions_on_threadUniqueId_and_id"))
                INNER JOIN \(OWSReaction.databaseTableName) AS reaction
                    ON interaction.\(interactionColumn: .uniqueId) = reaction.\(OWSReaction.columnName(.uniqueMessageId))
                    AND reaction.\(OWSReaction.columnName(.read)) IS 0
                WHERE interaction.\(interactionColumn: .recordType) IS \(SDSRecordType.outgoingMessage.rawValue)
                AND interaction.\(interactionColumn: .threadUniqueId) = ?
                AND interaction.\(interactionColumn: .id) <= ?
                LIMIT 1
                """,
            arguments: [threadUniqueId, beforeSortId]
        )) ?? false

        return hasOutgoingMessagesWithUnreadReactions
    }

    /// Enumerates all the unread interactions in this thread before a given sort id,
    /// sorted by sort id.
    ///
    /// See also: ``hasMessagesToMarkRead``.
    public func fetchUnreadMessages(
        beforeSortId: UInt64,
        transaction: DBReadTransaction
    ) -> SDSMappedCursor<TSInteractionCursor, OWSReadTracking> {
        let sql = """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            \(DEBUG_INDEXED_BY("index_model_TSInteraction_UnreadMessages"))
            WHERE \(interactionColumn: .threadUniqueId) = ?
            AND \(interactionColumn: .id) <= ?
            AND \(Self.sqlClauseForAllUnreadInteractions())
            ORDER BY \(interactionColumn: .id)
            """

        let cursor = TSInteraction.grdbFetchCursor(
            sql: sql,
            arguments: [threadUniqueId, beforeSortId],
            transaction: transaction
        )
        return cursor.compactMap { interaction -> OWSReadTracking? in
            guard let readTracking = interaction as? OWSReadTracking else {
                owsFailDebug("Interaction has unexpected type: \(type(of: interaction))")
                return nil
            }
            guard !readTracking.wasRead else {
                owsFailDebug("Unexpectedly found read interaction: \(interaction.timestamp)")
                return nil
            }
            return readTracking
        }
    }

    /// Returns all the messages with unread reactions in this thread before a given sort id,
    /// sorted by sort id.
    ///
    /// See also: ``hasMessagesToMarkRead``.
    public func fetchMessagesWithUnreadReactions(
        beforeSortId: UInt64,
        transaction: DBReadTransaction
    ) -> SDSMappedCursor<TSInteractionCursor, TSOutgoingMessage> {
        let sql = """
            SELECT interaction.*
            FROM \(InteractionRecord.databaseTableName) AS interaction
            \(DEBUG_INDEXED_BY("index_interactions_on_threadUniqueId_and_id"))
            INNER JOIN \(OWSReaction.databaseTableName) AS reaction
                ON interaction.\(interactionColumn: .uniqueId) = reaction.\(OWSReaction.columnName(.uniqueMessageId))
                AND reaction.\(OWSReaction.columnName(.read)) IS 0
            WHERE interaction.\(interactionColumn: .recordType) IS \(SDSRecordType.outgoingMessage.rawValue)
            AND interaction.\(interactionColumn: .threadUniqueId) = ?
            AND interaction.\(interactionColumn: .id) <= ?
            GROUP BY interaction.\(interactionColumn: .id)
            ORDER BY interaction.\(interactionColumn: .id)
            """

        let cursor = TSOutgoingMessage.grdbFetchCursor(
            sql: sql,
            arguments: [threadUniqueId, beforeSortId],
            transaction: transaction
        )
        return cursor.compactMap { $0 as? TSOutgoingMessage }
    }

    public func oldestUnreadInteraction(transaction: DBReadTransaction) throws -> TSInteraction? {
        let sql = """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            \(DEBUG_INDEXED_BY("index_model_TSInteraction_UnreadMessages"))
            WHERE \(interactionColumn: .threadUniqueId) = ?
            AND \(Self.sqlClauseForAllUnreadInteractions(excludeReadEdits: true))
            ORDER BY \(interactionColumn: .id)
            """
        let cursor = TSInteraction.grdbFetchCursor(
            sql: sql,
            arguments: [threadUniqueId],
            transaction: transaction
        )
        return try cursor.next()
    }

    @objc
    public func firstInteraction(
        atOrAroundSortId sortId: UInt64,
        transaction: DBReadTransaction
    ) -> TSInteraction? {
        guard sortId > 0 else { return nil }

        // First, see if there's an interaction at or before this sortId.

        let atOrBeforeQuery = """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            \(DEBUG_INDEXED_BY("index_interactions_on_threadUniqueId_and_id"))
            WHERE \(interactionColumn: .threadUniqueId) = ?
            AND \(interactionColumn: .id) <= ?
            \(Self.filterEditHistoryClause())
            ORDER BY \(interactionColumn: .id) DESC
            LIMIT 1
            """
        let arguments: StatementArguments = [threadUniqueId, sortId]

        if let interactionAtOrBeforeSortId = TSInteraction.grdbFetchOne(
            sql: atOrBeforeQuery,
            arguments: arguments,
            transaction: transaction
        ) {
            return interactionAtOrBeforeSortId
        }

        // If there wasn't an interaction at or before this sortId,
        // look for the first interaction *after* this sort id.

        let afterQuery = """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            \(DEBUG_INDEXED_BY("index_interactions_on_threadUniqueId_and_id"))
            WHERE \(interactionColumn: .threadUniqueId) = ?
            AND \(interactionColumn: .id) > ?
            \(Self.filterEditHistoryClause())
            ORDER BY \(interactionColumn: .id) ASC
            LIMIT 1
            """

        return TSInteraction.grdbFetchOne(
            sql: afterQuery,
            arguments: arguments,
            transaction: transaction
        )
    }

    public func existsOutgoingMessage(transaction: DBReadTransaction) -> Bool {
        let sql = """
            SELECT 1
            FROM \(InteractionRecord.databaseTableName)
            \(DEBUG_INDEXED_BY("index_model_TSInteraction_on_uniqueThreadId_recordType_messageType"))
            WHERE \(interactionColumn: .threadUniqueId) = ?
            AND \(interactionColumn: .recordType) = ?
            LIMIT 1
            """
        let arguments: StatementArguments = [
            threadUniqueId,
            SDSRecordType.outgoingMessage.rawValue
        ]
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
            owsFail("Failed to find outgoing message")
        }
    }

    func hasGroupUpdateInfoMessage(transaction: DBReadTransaction) -> Bool {
        let sql = """
            SELECT 1
            FROM \(InteractionRecord.databaseTableName)
            \(DEBUG_INDEXED_BY("index_model_TSInteraction_on_uniqueThreadId_recordType_messageType"))
            WHERE \(interactionColumn: .threadUniqueId) = ?
            AND \(interactionColumn: .recordType) = \(SDSRecordType.infoMessage.rawValue)
            AND \(interactionColumn: .messageType) = \(TSInfoMessageType.typeGroupUpdate.rawValue)
            LIMIT 1
            """

        let arguments: StatementArguments = [threadUniqueId]
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
            owsFail("Failed to find info message")
        }
    }

    public func enumerateRecentGroupUpdateMessages(
        transaction: DBReadTransaction,
        block: (TSInfoMessage, UnsafeMutablePointer<ObjCBool>) -> Void
    ) throws {
        let sql = """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            \(DEBUG_INDEXED_BY("index_model_TSInteraction_on_uniqueThreadId_recordType_messageType"))
            WHERE \(interactionColumn: .threadUniqueId) = ?
            AND \(interactionColumn: .recordType) = \(SDSRecordType.infoMessage.rawValue)
            AND \(interactionColumn: .messageType) = \(TSInfoMessageType.typeGroupUpdate.rawValue)
            ORDER BY \(interactionColumn: .id) DESC
            """

        let cursor = TSInfoMessage.grdbFetchCursor(
            sql: sql,
            arguments: [threadUniqueId],
            transaction: transaction
        )

        while let interaction = try cursor.next() {
            guard let infoMessage = interaction as? TSInfoMessage else { return }
            var stop: ObjCBool = false
            block(infoMessage, &stop)
            if stop.boolValue {
                return
            }
        }
    }

    public func hasUserReportedSpam(transaction: DBReadTransaction) -> Bool {
        let sql = """
            SELECT 1
            FROM \(InteractionRecord.databaseTableName)
            \(DEBUG_INDEXED_BY("index_model_TSInteraction_on_uniqueThreadId_recordType_messageType"))
            WHERE \(interactionColumn: .threadUniqueId) = ?
            AND \(interactionColumn: .recordType) = \(SDSRecordType.infoMessage.rawValue)
            AND \(interactionColumn: .messageType) = \(TSInfoMessageType.reportedSpam.rawValue)
            LIMIT 1
            """

        let arguments: StatementArguments = [threadUniqueId]
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
            owsFail("Failed to find info message")
        }
    }

    func hasUserInitiatedInteraction(transaction: DBReadTransaction) -> Bool {
        let infoMessageTypes: [TSInfoMessageType] = [
            .typeGroupQuit,
            .typeGroupUpdate,
            .typeLocalUserEndedSession,
            .typeRemoteUserEndedSession,
            .typeDisappearingMessagesUpdate,
            .unknownProtocolVersion
        ]

        let errorMessageInteractions: [SDSRecordType] = [
            .errorMessage,
            .recoverableDecryptionPlaceholder
        ]
        let errorMessageTypes: [TSErrorMessageType] = [
            .noSession,
            .wrongTrustedIdentityKey,
            .invalidKeyException,
            .missingKeyId,
            .invalidMessage,
            .duplicateMessage,
            .groupCreationFailed,
            .sessionRefresh,
            .decryptionFailure
        ]

        let interactionTypes: [SDSRecordType] = [
            .incomingMessage,
            .outgoingMessage,
            .disappearingConfigurationUpdateInfoMessage,
            .unknownProtocolVersionMessage,
            .call,
            .groupCallMessage,
            .verificationStateChangeMessage
        ]

        let sql = """
            SELECT 1
            FROM \(InteractionRecord.databaseTableName)
            \(DEBUG_INDEXED_BY("index_model_TSInteraction_on_uniqueThreadId_recordType_messageType", or: "index_model_TSInteraction_on_uniqueThreadId_and_eraId_and_recordType"))
            WHERE \(interactionColumn: .threadUniqueId) = ?
            AND (
                (
                    \(interactionColumn: .recordType) = \(SDSRecordType.infoMessage.rawValue)
                    AND \(interactionColumn: .messageType) IN (\(infoMessageTypes.map { "\($0.rawValue)" }.joined(separator: ",")))
                ) OR (
                    \(interactionColumn: .recordType) IN (\(errorMessageInteractions.map { "\($0.rawValue)" }.joined(separator: ",")))
                    AND \(interactionColumn: .errorType) IN (\(errorMessageTypes.map { "\($0.rawValue)" }.joined(separator: ",")))
                ) OR \(interactionColumn: .recordType) IN (\(interactionTypes.map { "\($0.rawValue)" }.joined(separator: ",")))
            )
            \(Self.filterGroupStoryRepliesClause())
            \(Self.filterEditHistoryClause())
            LIMIT 1
            """
        let arguments: StatementArguments = [threadUniqueId]

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
            owsFail("Failed to determine interaction")
        }
    }

    func possiblyHasIncomingMessages(transaction: DBReadTransaction) -> Bool {
        // All of these message types could have been triggered by anyone in
        // the conversation. So, if one of them exists we have to assume the conversation
        // *might* have received messages. At some point it'd be nice to refactor this to
        // be more explicit, but not all our interaction types allow for that level of
        // granularity presently.

        let interactionTypes: [SDSRecordType] = [
            .incomingMessage,
            .disappearingConfigurationUpdateInfoMessage,
            .unknownProtocolVersionMessage,
            .verificationStateChangeMessage,
            .call,
            .errorMessage,
            .recoverableDecryptionPlaceholder,
            .invalidIdentityKeyErrorMessage,
            .invalidIdentityKeyReceivingErrorMessage,
            .invalidIdentityKeySendingErrorMessage
        ]

        let sqlInteractionTypes = interactionTypes.map { "\($0.rawValue)" }.joined(separator: ",")

        let sql = """
            SELECT 1
            FROM \(InteractionRecord.databaseTableName)
            \(DEBUG_INDEXED_BY("index_model_TSInteraction_on_uniqueThreadId_recordType_messageType"))
            WHERE \(interactionColumn: .threadUniqueId) = ?
            AND \(interactionColumn: .recordType) IN (\(sqlInteractionTypes))
            LIMIT 1
            """
        let arguments: StatementArguments = [threadUniqueId]

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
            owsFail("Failed to find Incoming message")
        }
    }

    public func outgoingMessageCount(transaction: DBReadTransaction) -> UInt {
        let sql = """
            SELECT COUNT(*)
            FROM \(InteractionRecord.databaseTableName)
            \(DEBUG_INDEXED_BY("index_model_TSInteraction_on_uniqueThreadId_recordType_messageType"))
            WHERE \(interactionColumn: .threadUniqueId) = ?
            AND \(interactionColumn: .recordType) = ?
            """
        let arguments: StatementArguments = [
            threadUniqueId,
            SDSRecordType.outgoingMessage.rawValue
        ]

        do {
            return try UInt.fetchOne(
                transaction.database,
                sql: sql,
                arguments: arguments
            ) ?? 0
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Failed to determine message count")
        }
    }

    public class func outgoingAndIncomingMessageCount(transaction: DBReadTransaction, limit: Int) -> UInt {
        let sql = """
            SELECT COUNT(*)
            FROM (
             SELECT * FROM \(InteractionRecord.databaseTableName)
            \(DEBUG_INDEXED_BY("index_interaction_on_recordType_and_callType"))
            WHERE \(interactionColumn: .recordType) IN (?, ?)
            LIMIT ?)
            """
        let arguments: StatementArguments = [
            SDSRecordType.outgoingMessage.rawValue,
            SDSRecordType.incomingMessage.rawValue,
            limit
        ]

        do {
            return try UInt.fetchOne(
                transaction.database,
                sql: sql,
                arguments: arguments
            ) ?? 0
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Failed to determine message count")
        }
    }

    // MARK: - Fetch by Row ID

    public enum RowIdFilter {
        case newest
        case atOrBefore(Int64)
        case before(Int64)
        case after(Int64)
        case range(ClosedRange<Int64>)
    }

    /// Fetch interaction unique IDs covered by this finder, filtered and
    /// ordered as they should appear in the conversation view.
    public func fetchUniqueIdsForConversationView(
        rowIdFilter: RowIdFilter,
        limit: Int,
        tx: DBReadTransaction
    ) throws -> [String] {
        let (rowIdClause, arguments, isAscending) = sqlClauseForInteractionsByRowId(
            rowIdFilter: rowIdFilter,
            additionalFiltering: .filterForConversationView,
            limit: limit
        )

        let indexedBy: String
        if FeatureFlags.useNewConversationLoadIndex {
            indexedBy = "INDEXED BY index_interactions_on_threadUniqueId_and_id"
        } else {
            indexedBy = DEBUG_INDEXED_BY("index_interactions_on_threadUniqueId_and_id", or: "index_model_TSInteraction_ConversationLoadInteractionDistance")
        }

        let uniqueIds = try String.fetchAll(
            tx.database,
            sql: """
                SELECT "uniqueId" FROM \(InteractionRecord.databaseTableName)
                \(indexedBy)
                \(rowIdClause)
                """,
            arguments: arguments
        )

        return isAscending ? uniqueIds : Array(uniqueIds.reversed())
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func enumerateRecentInteractionsForConversationView(
        transaction tx: DBReadTransaction,
        block: (TSInteraction) -> Bool
    ) throws {
        try enumerateInteractionsForConversationView(
            rowIdFilter: .newest,
            tx: tx,
            block: block
        )
    }

    /// Enumerate interactions covered by this finder, filtered and ordered as
    /// they should appear in the conversation view.
    ///
    /// - Parameter block
    /// A block executed for each enumerated interaction. Returns `true` if
    /// enumeration should continue, and `false` otherwise.
    public func enumerateInteractionsForConversationView(
        rowIdFilter: RowIdFilter,
        tx: DBReadTransaction,
        block: (TSInteraction) -> Bool
    ) throws {
        try buildInteractionCursor(
            rowIdFilter: rowIdFilter,
            additionalFiltering: .filterForConversationView,
            limit: nil,
            tx: tx
        ).enumerate(block: block)
    }

    /// Fetch all interactions covered by this finder.
    func fetchAllInteractions(
        rowIdFilter: RowIdFilter,
        limit: Int,
        tx: DBReadTransaction
    ) throws -> [TSInteraction] {
        var interactions: [TSInteraction] = []

        try buildInteractionCursor(
            rowIdFilter: rowIdFilter,
            additionalFiltering: .noFiltering,
            limit: limit,
            tx: tx
        ).enumerate { interaction -> Bool in
            interactions.append(interaction)
            return true
        }

        return interactions
    }

    /// Returns a cursor over all ``TSIncomingMessage``s covered by this finder
    /// that returns its next element in O(1) time.
    ///
    /// - Important
    /// This cursor may not outlive the given transaction!
    func buildIncomingMessagesCursor(
        rowIdFilter: RowIdFilter,
        tx: DBReadTransaction
    ) -> TSInteractionCursor {
        return buildInteractionCursor(
            rowIdFilter: rowIdFilter,
            additionalFiltering: .filterForIncomingMessages,
            limit: nil,
            tx: tx
        )
    }

    /// Returns a cursor over all ``TSOutgoingMessage``s covered by this finder
    /// that returns its next element in O(1) time.
    ///
    /// - Important
    /// This cursor may not outlive the given transaction!
    func buildOutgoingMessagesCursor(
        rowIdFilter: RowIdFilter,
        tx: DBReadTransaction
    ) -> TSInteractionCursor {
        return buildInteractionCursor(
            rowIdFilter: rowIdFilter,
            additionalFiltering: .filterForOutgoingMessages,
            limit: nil,
            tx: tx
        )
    }

    /// Options for configuring the SQL clause to fetch interactions by row ID.
    ///
    /// - Important
    /// At the time of writing, all cases included here result in a SQL clause
    /// that is supported by a database index and is therefore fast. Take care
    /// when updating these options that the resulting SQL clause does not
    /// result in queries that will *not* be supported by an index.
    private enum InteractionsByRowIdAdditionalFiltering {
        /// Filter the fetched interactions as appropriate for the conversation
        /// view. This includes filtering out decryption placeholders, group
        /// story replies, and edit history.
        ///
        /// Relies on `index_model_TSInteraction_UnreadMessages`.
        case filterForConversationView

        /// Filter the fetched interactions to ``TSIncomingMessage``s.
        ///
        /// Relies on `index_interactions_on_recordType_and_threadUniqueId_and_errorType`,
        /// by passing a `NULL` error type since no incoming message will
        /// have that column populated.
        case filterForIncomingMessages

        /// Filter the fetched interactions to ``TSOutgoingMessage``s.
        ///
        /// Relies on `index_interactions_on_recordType_and_threadUniqueId_and_errorType`,
        /// by passing a `NULL` error type since no outgoing message will
        /// have that column populated.
        case filterForOutgoingMessages

        /// Do no additional filtering. This will return all interactions.
        ///
        /// Relies on `index_interactions_on_threadUniqueId_and_id`.
        case noFiltering
    }

    private func buildInteractionCursor(
        rowIdFilter: RowIdFilter,
        additionalFiltering: InteractionsByRowIdAdditionalFiltering,
        limit: Int?,
        tx: DBReadTransaction
    ) -> TSInteractionCursor {
        let (rowIdClause, arguments, _) = sqlClauseForInteractionsByRowId(
            rowIdFilter: rowIdFilter,
            additionalFiltering: additionalFiltering,
            limit: limit
        )

        let indexedBy: String
        switch additionalFiltering {
        case .filterForConversationView where FeatureFlags.useNewConversationLoadIndex:
            indexedBy = "INDEXED BY index_interactions_on_threadUniqueId_and_id"
        case .filterForConversationView:
            indexedBy = DEBUG_INDEXED_BY("index_interactions_on_threadUniqueId_and_id", or: "index_model_TSInteraction_ConversationLoadInteractionDistance")
        case .filterForIncomingMessages:
            indexedBy = DEBUG_INDEXED_BY("index_interactions_on_recordType_and_threadUniqueId_and_errorType")
        case .filterForOutgoingMessages:
            indexedBy = DEBUG_INDEXED_BY("index_interactions_on_recordType_and_threadUniqueId_and_errorType")
        case .noFiltering:
            indexedBy = DEBUG_INDEXED_BY("index_interactions_on_threadUniqueId_and_id")
        }

        return TSInteraction.grdbFetchCursor(
            sql: """
                SELECT * FROM \(InteractionRecord.databaseTableName)
                \(indexedBy)
                \(rowIdClause)
                """,
            arguments: arguments,
            transaction: tx
        )
    }

    private func sqlClauseForInteractionsByRowId(
        rowIdFilter: RowIdFilter,
        additionalFiltering: InteractionsByRowIdAdditionalFiltering,
        limit: Int?
    ) -> (String, StatementArguments, isAscending: Bool) {
        let rowIdFilterClause: String
        let rowIdArguments: StatementArguments
        let isAscending: Bool
        switch rowIdFilter {
        case .newest:
            rowIdFilterClause = ""
            rowIdArguments = []
            isAscending = false
        case .atOrBefore(let rowId):
            rowIdFilterClause = "AND \(interactionColumn: .id) <= ?"
            rowIdArguments = [rowId]
            isAscending = false
        case .before(let rowId):
            rowIdFilterClause = "AND \(interactionColumn: .id) < ?"
            rowIdArguments = [rowId]
            isAscending = false
        case .after(let rowId):
            rowIdFilterClause = "AND \(interactionColumn: .id) > ?"
            rowIdArguments = [rowId]
            isAscending = true
        case .range(let rowIds):
            rowIdFilterClause = "AND \(interactionColumn: .id) >= ? AND \(interactionColumn: .id) <= ?"
            rowIdArguments = [rowIds.lowerBound, rowIds.upperBound]
            isAscending = true
        }

        let additionalFilterClause: String = switch additionalFiltering {
        case .filterForConversationView:
            """
            \(Self.filterGroupStoryRepliesClause())
            \(Self.filterEditHistoryClause())
            \(Self.filterPlaceholdersClause)
            """
        case .filterForIncomingMessages:
            "AND recordType = \(SDSRecordType.incomingMessage.rawValue) AND errorType is NULL"
        case .filterForOutgoingMessages:
            "AND recordType = \(SDSRecordType.outgoingMessage.rawValue) AND errorType is NULL"
        case .noFiltering:
            ""
        }

        var sql = """
            WHERE
                \(interactionColumn: .threadUniqueId) = ?
                \(rowIdFilterClause)
                \(additionalFilterClause)
            ORDER BY \(interactionColumn: .id) \(isAscending ? "ASC" : "DESC")
            """
        if let limit {
            sql += " LIMIT \(limit)"
        }

        let arguments: StatementArguments = [threadUniqueId] + rowIdArguments

        return (sql, arguments, isAscending)
    }

    // MARK: -

    /// The SQLite row ID of the most-recently inserted interaction covered by
    /// this finder.
    func mostRecentRowId(tx: DBReadTransaction) -> Int64 {
        var mostRecentRowId: Int64 = 0

        try? buildInteractionCursor(
            rowIdFilter: .newest,
            additionalFiltering: .noFiltering,
            limit: 1,
            tx: tx
        ).enumerate { mostRecentInteraction -> Bool in
            mostRecentRowId = mostRecentInteraction.sqliteRowId!
            return false
        }

        return mostRecentRowId
    }
}

private extension TSInteractionCursor {
    func enumerate(block: (TSInteraction) -> Bool) throws {
        while
            let interaction = try next(),
            block(interaction)
        {}
    }
}

// MARK: - Clauses

extension InteractionFinder {
    private static func sqlClauseForAllUnreadInteractions(
        excludeReadEdits: Bool = false
    ) -> String {
        let recordTypes: [SDSRecordType] = [
            .disappearingConfigurationUpdateInfoMessage,
            .unknownProtocolVersionMessage,
            .verificationStateChangeMessage,
            .call,
            .groupCallMessage,
            .errorMessage,
            .recoverableDecryptionPlaceholder,
            .incomingMessage,
            .incomingPaymentMessage,
            .infoMessage,
            .invalidIdentityKeyErrorMessage,
            .invalidIdentityKeyReceivingErrorMessage,
            .invalidIdentityKeySendingErrorMessage
        ]

        let recordTypesSql = recordTypes.map { "\($0.rawValue)" }.joined(separator: ",")
        let editQueryMode: EditMessageQueryMode = excludeReadEdits ? .excludeReadEdits : .includeAllEdits

        return """
        (
            \(interactionColumn: .read) IS 0
            \(Self.filterGroupStoryRepliesClause())
            \(self.filterEditHistoryClause(mode: editQueryMode))
            AND \(interactionColumn: .recordType) IN (\(recordTypesSql))
        )
        """
    }

    static func sqlClauseForUnreadInteractionCounts(
        interactionsAlias: String? = nil
    ) -> String {
        let columnPrefix: String
        if let interactionsAlias = interactionsAlias {
            columnPrefix = interactionsAlias + "."
        } else {
            columnPrefix = ""
        }

        return """
        \(columnPrefix)\(interactionColumn: .read) IS 0
        \(Self.filterGroupStoryRepliesClause(interactionsAlias: interactionsAlias))
        \(Self.filterEditHistoryClause(mode: .excludeReadEdits, interactionsAlias: interactionsAlias))
        AND (
            \(columnPrefix)\(interactionColumn: .recordType) IS \(SDSRecordType.incomingMessage.rawValue)
            OR (
                \(columnPrefix)\(interactionColumn: .recordType) IS \(SDSRecordType.infoMessage.rawValue)
                AND \(columnPrefix)\(interactionColumn: .messageType) IS \(TSInfoMessageType.userJoinedSignal.rawValue)
            )
        )
        """
    }

    private static func sqlClauseForIgnoringInteractionsWithMutedThread(threadAssociatedDataAlias: String) -> String {
        """
            AND (
                \(threadAssociatedDataAlias).mutedUntilTimestamp <= strftime('%s','now') * 1000
                OR \(threadAssociatedDataAlias).mutedUntilTimestamp = 0
            )
            """
    }

    // From: https://www.sqlite.org/optoverview.html
    // This clause has been tuned hand-in-hand with the index_model_TSInteraction_on_nonPlaceholders_uniqueThreadId_id index
    // If you need to adjust this clause, you should probably update the index as well. This is a perf sensitive code path.
    static let filterPlaceholdersClause = "AND \(interactionColumn: .recordType) IS NOT \(SDSRecordType.recoverableDecryptionPlaceholder.rawValue)"

    static func filterGroupStoryRepliesClause(interactionsAlias: String? = nil) -> String {
        let columnPrefix: String
        if let interactionsAlias = interactionsAlias {
            columnPrefix = interactionsAlias + "."
        } else {
            columnPrefix = ""
        }

        // Treat NULL and 0 as equivalent.
        return "AND \(columnPrefix)\(interactionColumn: .isGroupStoryReply) IS NOT 1"
    }

    static func filterEditHistoryClause(
        mode: EditMessageQueryMode = .includeAllEdits,
        interactionsAlias: String? = nil
    ) -> String {
        let columnPrefix: String
        if let interactionsAlias = interactionsAlias {
            columnPrefix = interactionsAlias + "."
        } else {
            columnPrefix = ""
        }

        /// We need to ensure that whatever clauses we return here appropriately
        /// handle `NULL` values for `editState.
        ///
        /// Specifically, only ``TSMessage`` descendants will have a non-`NULL`
        /// `editState`, since it refers to the ``TSMessage/editState`` column.
        /// However, we don't want this clause to necessarily exclude those
        /// (non-``TSMessage``) interactions with `editState = NULL`.
        switch mode {
        case .includeAllEdits:
            /// Using `IS NOT` includes `NULL`.
            return "AND \(columnPrefix)\(interactionColumn: .editState) IS NOT \(TSEditState.pastRevision.rawValue)"
        case .excludeReadEdits:
            return """
            AND (
                \(columnPrefix)\(interactionColumn: .editState) IN (\(TSEditState.none.rawValue), \(TSEditState.latestRevisionUnread.rawValue))
                OR \(columnPrefix)\(interactionColumn: .editState) IS NULL
            )
            """
        case .excludeAllEdits:
            return "AND \(columnPrefix)\(interactionColumn: .editState) IS \(TSEditState.none.rawValue)"
        }
    }

    public class func maxInteractionRowId(transaction: DBReadTransaction) -> UInt64 {
        let sql = """
            SELECT MAX(\(interactionColumn: .id))
            FROM \(InteractionRecord.databaseTableName)
            """
        do {
            return try UInt64.fetchOne(
                transaction.database,
                sql: sql
            ) ?? 0
        } catch {
            owsFailDebug("Failed to find max transaction ID: \(error)")
            return 0
        }
    }
}
