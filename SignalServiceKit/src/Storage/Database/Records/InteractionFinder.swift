//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import SignalCoreKit

public enum EditMessageQueryMode {
    case includeLatestVersion
    case excludeAllEdits
}

protocol InteractionFinderAdapter {
    associatedtype ReadTransaction

    // MARK: - static methods

    static func fetch(uniqueId: String, transaction: ReadTransaction) throws -> TSInteraction?

    static func fetch(rowId: Int64, transaction: ReadTransaction) throws -> TSInteraction?

    static func existsIncomingMessage(timestamp: UInt64, sourceServiceId: ServiceId, sourceDeviceId: UInt32, transaction: ReadTransaction) -> Bool

    static func interactions(withTimestamp timestamp: UInt64, filter: @escaping (TSInteraction) -> Bool, transaction: ReadTransaction) throws -> [TSInteraction]

    static func incompleteCallIds(transaction: ReadTransaction) -> [String]

    static func attemptingOutInteractionIds(transaction: ReadTransaction) -> [String]

    static func pendingInteractionIds(transaction: ReadTransaction) -> [String]

    // The interactions should be enumerated in order from "first to expire" to "last to expire".
    static func nextMessageWithStartedPerConversationExpirationToExpire(transaction: ReadTransaction) -> TSMessage?

    static func interactionIdsWithExpiredPerConversationExpiration(transaction: ReadTransaction) -> [String]

    static func fetchAllMessageUniqueIdsWhichFailedToStartExpiring(transaction: ReadTransaction) -> [String]

    static func interactions(withInteractionIds interactionIds: Set<String>, transaction: ReadTransaction) -> Set<TSInteraction>

    static func enumerateGroupReplies(for storyMessage: StoryMessage, transaction: ReadTransaction, block: @escaping (TSMessage, UnsafeMutablePointer<ObjCBool>) -> Void)
    static func hasLocalUserReplied(storyTimestamp: UInt64, storyAuthorUuidString: String, transaction: ReadTransaction) -> Bool
    static func groupReplyUniqueIdsAndRowIds(storyAuthor: ServiceId, storyTimestamp: UInt64, transaction: ReadTransaction) -> [(String, Int64)]

    // MARK: - instance methods

    func latestInteraction(from address: SignalServiceAddress, transaction: ReadTransaction) -> TSInteraction?

    func mostRecentInteractionForInbox(transaction: ReadTransaction) -> TSInteraction?

    func earliestKnownInteractionRowId(transaction: ReadTransaction) -> Int?

    func enumerateInteractionIds(transaction: ReadTransaction, block: @escaping (String, UnsafeMutablePointer<ObjCBool>) throws -> Void) throws
    func enumerateRecentInteractions(excludingPlaceholders excludePlaceholders: Bool, transaction: ReadTransaction, block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void) throws
    func existsOutgoingMessage(transaction: ReadTransaction) -> Bool
    func outgoingMessageCount(transaction: ReadTransaction) -> UInt

    func firstInteraction(atOrAroundSortId sortId: UInt64, transaction: ReadTransaction) -> TSInteraction?

    func fetchUniqueIds(
        filter: RowIdFilter,
        excludingPlaceholders excludePlaceholders: Bool,
        limit: Int,
        tx: ReadTransaction
    ) throws -> [String]

    #if DEBUG
    func enumerateUnstartedExpiringMessages(transaction: ReadTransaction, block: @escaping (TSMessage, UnsafeMutablePointer<ObjCBool>) -> Void)
    #endif
}

public enum RowIdFilter {
    case newest
    case before(Int64)
    case after(Int64)
    case range(ClosedRange<Int64>)
}

// MARK: -

@objc
public class InteractionFinder: NSObject, InteractionFinderAdapter {

    let grdbAdapter: GRDBInteractionFinder
    let threadUniqueId: String

    @objc
    public init(threadUniqueId: String) {
        self.threadUniqueId = threadUniqueId
        self.grdbAdapter = GRDBInteractionFinder(threadUniqueId: threadUniqueId)
    }

    // MARK: - static methods

    @objc
    public class func fetchSwallowingErrors(uniqueId: String, transaction: SDSAnyReadTransaction) -> TSInteraction? {
        do {
            return try fetch(uniqueId: uniqueId, transaction: transaction)
        } catch {
            owsFailDebug("error: \(error)")
            return nil
        }
    }

    public class func fetch(uniqueId: String, transaction: SDSAnyReadTransaction) throws -> TSInteraction? {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return try GRDBInteractionFinder.fetch(uniqueId: uniqueId, transaction: grdbRead)
        }
    }

    public class func fetch(rowId: Int64, transaction: SDSAnyReadTransaction) throws -> TSInteraction? {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return try GRDBInteractionFinder.fetch(rowId: rowId, transaction: grdbRead)
        }
    }

    public class func existsIncomingMessage(timestamp: UInt64, sourceServiceId: ServiceId, sourceDeviceId: UInt32, transaction: SDSAnyReadTransaction) -> Bool {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return GRDBInteractionFinder.existsIncomingMessage(timestamp: timestamp, sourceServiceId: sourceServiceId, sourceDeviceId: sourceDeviceId, transaction: grdbRead)
        }
    }

    @objc
    public class func interactions(withTimestamp timestamp: UInt64, filter: (TSInteraction) -> Bool, transaction: SDSAnyReadTransaction) throws -> [TSInteraction] {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return try GRDBInteractionFinder.interactions(withTimestamp: timestamp, filter: filter, transaction: grdbRead)
        }
    }

    @objc
    public class func incompleteCallIds(transaction: SDSAnyReadTransaction) -> [String] {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return GRDBInteractionFinder.incompleteCallIds(transaction: grdbRead)
        }
    }

    @objc
    public class func attemptingOutInteractionIds(transaction: SDSAnyReadTransaction) -> [String] {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return GRDBInteractionFinder.attemptingOutInteractionIds(transaction: grdbRead)
        }
    }

    @objc
    public class func pendingInteractionIds(transaction: SDSAnyReadTransaction) -> [String] {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return GRDBInteractionFinder.pendingInteractionIds(transaction: grdbRead)
        }
    }

    @objc
    public class func unreadCountInAllThreads(transaction: GRDBReadTransaction) -> UInt {
        do {
            var unreadInteractionQuery = """
                SELECT COUNT(interaction.\(interactionColumn: .id))
                FROM \(InteractionRecord.databaseTableName) AS interaction
                INNER JOIN \(ThreadAssociatedData.databaseTableName) AS associatedData
                    ON associatedData.threadUniqueId = \(interactionColumn: .threadUniqueId)
                WHERE associatedData.isArchived = "0"
            """

            if !SSKPreferences.includeMutedThreadsInBadgeCount(transaction: transaction.asAnyRead) {
                unreadInteractionQuery += " \(sqlClauseForIgnoringInteractionsWithMutedThread(threadAssociatedDataAlias: "associatedData")) "
            }

            unreadInteractionQuery += " AND \(sqlClauseForUnreadInteractionCounts(interactionsAlias: "interaction")) "

            guard let unreadInteractionCount = try UInt.fetchOne(transaction.database, sql: unreadInteractionQuery) else {
                owsFailDebug("unreadInteractionCount was unexpectedly nil")
                return 0
            }

            let markedUnreadThreadQuery = """
                SELECT COUNT(*)
                FROM \(ThreadRecord.databaseTableName)
                INNER JOIN \(ThreadAssociatedData.databaseTableName) AS associatedData
                    ON associatedData.threadUniqueId = \(threadColumn: .uniqueId)
                WHERE associatedData.isMarkedUnread = 1
                AND associatedData.isArchived = "0"
                AND \(threadColumn: .shouldThreadBeVisible) = 1
            """

            guard let markedUnreadCount = try UInt.fetchOne(transaction.database, sql: markedUnreadThreadQuery) else {
                owsFailDebug("markedUnreadCount was unexpectedly nil")
                return unreadInteractionCount
            }

            return unreadInteractionCount + markedUnreadCount
        } catch {
            owsFailDebug("error: \(error)")
            return 0
        }
    }

    @objc
    public class func nextMessageWithStartedPerConversationExpirationToExpire(transaction: SDSAnyReadTransaction) -> TSMessage? {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return GRDBInteractionFinder.nextMessageWithStartedPerConversationExpirationToExpire(transaction: grdbRead)
        }
    }

    @objc
    public class func interactionIdsWithExpiredPerConversationExpiration(transaction: SDSAnyReadTransaction) -> [String] {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return GRDBInteractionFinder.interactionIdsWithExpiredPerConversationExpiration(transaction: grdbRead)
        }
    }

    @objc
    public class func fetchAllMessageUniqueIdsWhichFailedToStartExpiring(transaction: SDSAnyReadTransaction) -> [String] {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return GRDBInteractionFinder.fetchAllMessageUniqueIdsWhichFailedToStartExpiring(transaction: grdbRead)
        }
    }

    @objc
    public class func interactions(withInteractionIds interactionIds: Set<String>, transaction: SDSAnyReadTransaction) -> Set<TSInteraction> {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return GRDBInteractionFinder.interactions(withInteractionIds: interactionIds, transaction: grdbRead)
        }
    }

    public static func enumerateGroupReplies(for storyMessage: StoryMessage, transaction: SDSAnyReadTransaction, block: @escaping (TSMessage, UnsafeMutablePointer<ObjCBool>) -> Void) {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            GRDBInteractionFinder.enumerateGroupReplies(for: storyMessage, transaction: grdbRead, block: block)
        }
    }

    public static func hasLocalUserReplied(storyTimestamp: UInt64, storyAuthorUuidString: String, transaction: SDSAnyReadTransaction) -> Bool {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return GRDBInteractionFinder.hasLocalUserReplied(storyTimestamp: storyTimestamp, storyAuthorUuidString: storyAuthorUuidString, transaction: grdbRead)
        }
    }

    public static func groupReplyUniqueIdsAndRowIds(
        storyAuthor: ServiceId,
        storyTimestamp: UInt64,
        transaction: SDSAnyReadTransaction
    ) -> [(String, Int64)] {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return GRDBInteractionFinder.groupReplyUniqueIdsAndRowIds(
                storyAuthor: storyAuthor,
                storyTimestamp: storyTimestamp,
                transaction: grdbRead
            )
        }
    }

    @objc
    public class func findMessage(
        withTimestamp timestamp: UInt64,
        threadId: String,
        author: SignalServiceAddress,
        transaction: SDSAnyReadTransaction
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

        let interactions: [TSInteraction]

        do {
            interactions = try InteractionFinder.interactions(
                withTimestamp: timestamp,
                filter: { $0 is TSMessage },
                transaction: transaction
            )
        } catch {
            owsFailDebug("Error loading interactions \(error.userErrorDescription)")
            return nil
        }

        for interaction in interactions {
            guard let message = interaction as? TSMessage else {
                owsFailDebug("received unexpected non-message interaction")
                continue
            }

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
    public static func lastInsertedIncomingMessage(transaction: SDSAnyReadTransaction) -> TSIncomingMessage? {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return GRDBInteractionFinder.lastInsertedIncomingMessage(transaction: grdbRead)
        }
    }

    // MARK: - instance methods

    @objc
    func latestInteraction(from address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> TSInteraction? {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return grdbAdapter.latestInteraction(from: address, transaction: grdbRead)
        }
    }

    @objc
    public func mostRecentInteractionForInbox(transaction: SDSAnyReadTransaction) -> TSInteraction? {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return grdbAdapter.mostRecentInteractionForInbox(transaction: grdbRead)
        }
    }

    func earliestKnownInteractionRowId(transaction: SDSAnyReadTransaction) -> Int? {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return grdbAdapter.earliestKnownInteractionRowId(transaction: grdbRead)
        }
    }

    @objc
    public func unreadCount(transaction: GRDBReadTransaction) -> UInt {
        do {
            let sql = """
                SELECT COUNT(*)
                FROM \(InteractionRecord.databaseTableName)
                WHERE \(interactionColumn: .threadUniqueId) = ?
                AND \(InteractionFinder.sqlClauseForUnreadInteractionCounts())
            """
            let arguments: StatementArguments = [threadUniqueId]

            guard let count = try UInt.fetchOne(transaction.database,
                                                sql: sql,
                                                arguments: arguments) else {
                    owsFailDebug("count was unexpectedly nil")
                    return 0
            }
            return count
        } catch {
            owsFailDebug("error: \(error)")
            return 0
        }
    }

    public func enumerateInteractionIds(transaction: SDSAnyReadTransaction, block: @escaping (String, UnsafeMutablePointer<ObjCBool>) throws -> Void) throws {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return try grdbAdapter.enumerateInteractionIds(transaction: grdbRead, block: block)
        }
    }

    @objc
    public func enumerateInteractionIds(transaction: SDSAnyReadTransaction, block: @escaping (String, UnsafeMutablePointer<ObjCBool>) -> Void) throws {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return try grdbAdapter.enumerateInteractionIds(transaction: grdbRead, block: block)
        }
    }

    @objc
    public func enumerateRecentInteractions(transaction: SDSAnyReadTransaction, block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void) throws {
        try enumerateRecentInteractions(excludingPlaceholders: true, transaction: transaction, block: block)
    }

    public func enumerateRecentInteractions(excludingPlaceholders excludePlaceholders: Bool, transaction: SDSAnyReadTransaction, block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void) throws {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return try grdbAdapter.enumerateRecentInteractions(excludingPlaceholders: excludePlaceholders, transaction: grdbRead, block: block)
        }
    }

    /// Enumerates all the unread interactions in this thread, sorted by sort id.
    public func fetchAllUnreadMessages(
        transaction: GRDBReadTransaction
    ) -> SDSMappedCursor<TSInteractionCursor, OWSReadTracking> {
        let sql = """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .threadUniqueId) = ?
            AND \(sqlClauseForAllUnreadInteractions())
            ORDER BY \(interactionColumn: .id)
        """

        let cursor = TSInteraction.grdbFetchCursor(sql: sql, arguments: [threadUniqueId], transaction: transaction)
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
        transaction: GRDBReadTransaction
    ) -> Bool {
        let hasUnreadMessages = (try? Bool.fetchOne(
            transaction.database,
            sql: """
            SELECT EXISTS (
                SELECT 1
                FROM \(InteractionRecord.databaseTableName)
                WHERE \(interactionColumn: .threadUniqueId) = ?
                AND \(interactionColumn: .id) <= ?
                AND \(sqlClauseForAllUnreadInteractions())
                LIMIT 1
            )
            """,
            arguments: [threadUniqueId, beforeSortId]
        )) ?? false

        lazy var hasOutgoingMessagesWithUnreadReactions = (try? Bool.fetchOne(
            transaction.database,
            sql: """
            SELECT EXISTS (
                SELECT 1
                FROM \(InteractionRecord.databaseTableName) AS interaction
                INNER JOIN \(OWSReaction.databaseTableName) AS reaction
                    ON interaction.\(interactionColumn: .uniqueId) = reaction.\(OWSReaction.columnName(.uniqueMessageId))
                    AND reaction.\(OWSReaction.columnName(.read)) IS 0
                WHERE interaction.\(interactionColumn: .recordType) IS \(SDSRecordType.outgoingMessage.rawValue)
                AND interaction.\(interactionColumn: .threadUniqueId) = ?
                AND interaction.\(interactionColumn: .id) <= ?
                LIMIT 1
            )
            """,
            arguments: [threadUniqueId, beforeSortId]
        )) ?? false

        return hasUnreadMessages || hasOutgoingMessagesWithUnreadReactions
    }

    /// Enumerates all the unread interactions in this thread before a given sort id,
    /// sorted by sort id.
    ///
    /// See also: ``hasMessagesToMarkRead``.
    public func fetchUnreadMessages(
        beforeSortId: UInt64,
        transaction: GRDBReadTransaction
    ) -> SDSMappedCursor<TSInteractionCursor, OWSReadTracking> {
        let sql = """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .threadUniqueId) = ?
            AND \(interactionColumn: .id) <= ?
            AND \(sqlClauseForAllUnreadInteractions())
            ORDER BY \(interactionColumn: .id)
        """

        let cursor = TSInteraction.grdbFetchCursor(sql: sql, arguments: [threadUniqueId, beforeSortId], transaction: transaction)
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
        transaction: GRDBReadTransaction
    ) -> SDSMappedCursor<TSInteractionCursor, TSOutgoingMessage> {
        let sql = """
            SELECT interaction.*
            FROM \(InteractionRecord.databaseTableName) AS interaction
            INNER JOIN \(OWSReaction.databaseTableName) AS reaction
                ON interaction.\(interactionColumn: .uniqueId) = reaction.\(OWSReaction.columnName(.uniqueMessageId))
                AND reaction.\(OWSReaction.columnName(.read)) IS 0
            WHERE interaction.\(interactionColumn: .recordType) IS \(SDSRecordType.outgoingMessage.rawValue)
            AND interaction.\(interactionColumn: .threadUniqueId) = ?
            AND interaction.\(interactionColumn: .id) <= ?
            GROUP BY interaction.\(interactionColumn: .id)
            ORDER BY interaction.\(interactionColumn: .id)
        """

        let cursor = TSOutgoingMessage.grdbFetchCursor(sql: sql, arguments: [threadUniqueId, beforeSortId], transaction: transaction)
        return cursor.compactMap { $0 as? TSOutgoingMessage }
    }

    public func oldestUnreadInteraction(transaction: GRDBReadTransaction) throws -> TSInteraction? {
        let sql = """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .threadUniqueId) = ?
            AND \(sqlClauseForAllUnreadInteractions(excludeAllEdits: true))
            ORDER BY \(interactionColumn: .id)
        """
        let cursor = TSInteraction.grdbFetchCursor(sql: sql, arguments: [threadUniqueId], transaction: transaction)
        return try cursor.next()
    }

    @objc
    public func firstInteraction(atOrAroundSortId sortId: UInt64, transaction: SDSAnyReadTransaction) -> TSInteraction? {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return grdbAdapter.firstInteraction(atOrAroundSortId: sortId, transaction: grdbRead)
        }
    }

    @objc
    public func existsOutgoingMessage(transaction: SDSAnyReadTransaction) -> Bool {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return grdbAdapter.existsOutgoingMessage(transaction: grdbRead)
        }
    }

    #if DEBUG
    @objc
    public func enumerateUnstartedExpiringMessages(transaction: SDSAnyReadTransaction, block: @escaping (TSMessage, UnsafeMutablePointer<ObjCBool>) -> Void) {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return grdbAdapter.enumerateUnstartedExpiringMessages(transaction: grdbRead, block: block)
        }
    }
    #endif

    @objc
    public func outgoingMessageCount(transaction: SDSAnyReadTransaction) -> UInt {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return grdbAdapter.outgoingMessageCount(transaction: grdbRead)
        }
    }

    public func fetchUniqueIds(
        filter: RowIdFilter,
        excludingPlaceholders excludePlaceholders: Bool,
        limit: Int,
        tx: SDSAnyReadTransaction
    ) throws -> [String] {
        switch tx.readTransaction {
        case .grdbRead(let grdbRead):
            return try grdbAdapter.fetchUniqueIds(
                filter: filter,
                excludingPlaceholders: excludePlaceholders,
                limit: limit,
                tx: grdbRead
            )
        }
    }

    // MARK: - Unread

    private func sqlClauseForAllUnreadInteractions(
        excludeAllEdits: Bool = false
    ) -> String {
        let recordTypes: [SDSRecordType] = [
            .disappearingConfigurationUpdateInfoMessage,
            .unknownProtocolVersionMessage,
            .verificationStateChangeMessage,
            .call,
            .errorMessage,
            .recoverableDecryptionPlaceholder,
            .incomingMessage,
            .infoMessage,
            .invalidIdentityKeyErrorMessage,
            .invalidIdentityKeyReceivingErrorMessage,
            .invalidIdentityKeySendingErrorMessage
        ]

        let recordTypesSql = recordTypes.map { "\($0.rawValue)" }.joined(separator: ",")

        return """
        (
            \(interactionColumn: .read) IS 0
            \(GRDBInteractionFinder.filterStoryRepliesClause())
            \(GRDBInteractionFinder.filterEditHistoryClause(excludeAll: excludeAllEdits))
            AND \(interactionColumn: .recordType) IN (\(recordTypesSql))
        )
        """
    }

    private static func sqlClauseForUnreadInteractionCounts(interactionsAlias: String? = nil) -> String {
        let columnPrefix: String
        if let interactionsAlias = interactionsAlias {
            columnPrefix = interactionsAlias + "."
        } else {
            columnPrefix = ""
        }

        return """
        \(columnPrefix)\(interactionColumn: .read) IS 0
        \(GRDBInteractionFinder.filterStoryRepliesClause(interactionsAlias: interactionsAlias))
        \(GRDBInteractionFinder.filterEditHistoryClause(excludeAll: true, interactionsAlias: interactionsAlias))
        AND (
            \(columnPrefix)\(interactionColumn: .recordType) IN (\(SDSRecordType.incomingMessage.rawValue), \(SDSRecordType.call.rawValue))
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
}

// MARK: -

@objc
public class GRDBInteractionFinder: NSObject, InteractionFinderAdapter {

    typealias ReadTransaction = GRDBReadTransaction

    let threadUniqueId: String

    @objc
    public init(threadUniqueId: String) {
        self.threadUniqueId = threadUniqueId
    }

    // MARK: - static methods

    static func fetch(uniqueId: String, transaction: GRDBReadTransaction) throws -> TSInteraction? {
        return TSInteraction.anyFetch(uniqueId: uniqueId, transaction: transaction.asAnyRead)
    }

    static func fetch(rowId: Int64, transaction: GRDBReadTransaction) throws -> TSInteraction? {
        let arguments: StatementArguments = [ rowId ]
        return TSInteraction.grdbFetchOne(
            sql: """
                SELECT *
                FROM \(InteractionRecord.databaseTableName)
                WHERE \(interactionColumn: .id) = ?
            """,
            arguments: arguments,
            transaction: transaction
        )
    }

    static func existsIncomingMessage(timestamp: UInt64, sourceServiceId: ServiceId, sourceDeviceId: UInt32, transaction: GRDBReadTransaction) -> Bool {
        let sql = """
            SELECT EXISTS(
                SELECT 1
                FROM \(InteractionRecord.databaseTableName)
                WHERE \(interactionColumn: .timestamp) = ?
                AND (
                    \(interactionColumn: .authorUUID) = ?
                    OR (\(interactionColumn: .authorUUID) IS NULL AND \(interactionColumn: .authorPhoneNumber) = ?)
                )
                AND \(interactionColumn: .sourceDeviceId) = ?
            )
        """
        let arguments: StatementArguments = [
            timestamp,
            sourceServiceId.uuidValue.uuidString,
            SignalServiceAddress(sourceServiceId).phoneNumber,
            sourceDeviceId
        ]
        do {
            return try Bool.fetchOne(transaction.database, sql: sql, arguments: arguments) ?? false
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Failed to find incoming message")
        }
    }

    static func interactions(withTimestamp timestamp: UInt64, filter: (TSInteraction) -> Bool, transaction: ReadTransaction) throws -> [TSInteraction] {
        let sql = """
        SELECT *
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .timestamp) = ?
        """
        let arguments: StatementArguments = [timestamp]

        let unfiltered = try TSInteraction.grdbFetchCursor(sql: sql, arguments: arguments, transaction: transaction).all()
        return unfiltered.filter(filter)
    }

    static func incompleteCallIds(transaction: ReadTransaction) -> [String] {
        let sql: String = """
        SELECT \(interactionColumn: .uniqueId)
        FROM \(InteractionRecord.databaseTableName)
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
            result = try String.fetchAll(transaction.database,
                                         sql: sql,
                                         arguments: statementArguments)
        } catch {
            owsFailDebug("error: \(error)")
        }
        return result
    }

    public static func existsGroupCallMessageForEraId(_ eraId: String, thread: TSThread, transaction: SDSAnyReadTransaction) -> Bool {
        let sql = """
        SELECT EXISTS(
            SELECT 1
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .recordType) IS \(SDSRecordType.groupCallMessage.rawValue)
            AND \(interactionColumn: .threadUniqueId) = ?
            AND \(interactionColumn: .eraId) = ?
            LIMIT 1
        )
        """
        let arguments: StatementArguments = [thread.uniqueId, eraId]
        do {
            return try Bool.fetchOne(transaction.unwrapGrdbRead.database, sql: sql, arguments: arguments) ?? false
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Failed to find group call")
        }
    }

    public static func unendedCallsForGroupThread(_ thread: TSThread, transaction: SDSAnyReadTransaction) -> [OWSGroupCallMessage] {
        let sql: String = """
        SELECT *
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .recordType) IS \(SDSRecordType.groupCallMessage.rawValue)
        AND \(interactionColumn: .hasEnded) IS FALSE
        AND \(interactionColumn: .threadUniqueId) = ?
        """

        var groupCalls: [OWSGroupCallMessage] = []
        let cursor = OWSGroupCallMessage.grdbFetchCursor(
            sql: sql,
            arguments: [thread.uniqueId],
            transaction: transaction.unwrapGrdbRead)

        do {
            while let interaction = try cursor.next() {
                guard let groupCall = interaction as? OWSGroupCallMessage, !groupCall.hasEnded else {
                    owsFailDebug("Unexpectedly result: \(interaction.timestamp)")
                    continue
                }
                groupCalls.append(groupCall)
            }
        } catch {
            owsFailDebug("unexpected error \(error)")
        }
        return groupCalls
    }

    static func attemptingOutInteractionIds(transaction: ReadTransaction) -> [String] {
        let sql: String = """
        SELECT \(interactionColumn: .uniqueId)
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .storedMessageState) = ?
        """
        var result = [String]()
        do {
            result = try String.fetchAll(transaction.database,
                                         sql: sql,
                                         arguments: [TSOutgoingMessageState.sending.rawValue])
        } catch {
            owsFailDebug("error: \(error)")
        }
        return result
    }

    static func pendingInteractionIds(transaction: ReadTransaction) -> [String] {
        let sql: String = """
        SELECT \(interactionColumn: .uniqueId)
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .storedMessageState) = ?
        """
        var result = [String]()
        do {
            result = try String.fetchAll(transaction.database,
                                         sql: sql,
                                         arguments: [TSOutgoingMessageState.pending.rawValue])
        } catch {
            owsFailDebug("error: \(error)")
        }
        return result
    }

    // The interactions should be enumerated in order from "next to expire" to "last to expire".
    static func nextMessageWithStartedPerConversationExpirationToExpire(transaction: ReadTransaction) -> TSMessage? {
        // NOTE: We DO NOT consult storedShouldStartExpireTimer here;
        //       once expiration has begun we want to see it through.
        let sql = """
        SELECT *
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .expiresInSeconds) > 0
        AND \(interactionColumn: .expiresAt) > 0
        ORDER BY \(interactionColumn: .expiresAt)
        """
        let cursor = TSInteraction.grdbFetchCursor(sql: sql, transaction: transaction)
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

    static func interactionIdsWithExpiredPerConversationExpiration(transaction: ReadTransaction) -> [String] {
        // NOTE: We DO NOT consult storedShouldStartExpireTimer here;
        //       once expiration has begun we want to see it through.
        let now: UInt64 = NSDate.ows_millisecondTimeStamp()
        let sql = """
        SELECT \(interactionColumn: .uniqueId)
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .expiresAt) > 0
        AND \(interactionColumn: .expiresAt) <= ?
        """
        let statementArguments: StatementArguments = [
            now
        ]
        var result = [String]()
        do {
            result = try String.fetchAll(transaction.database,
                                         sql: sql,
                                         arguments: statementArguments)
        } catch {
            owsFailDebug("error: \(error)")
        }
        return result
    }

    static func fetchAllMessageUniqueIdsWhichFailedToStartExpiring(transaction: ReadTransaction) -> [String] {
        // NOTE: We DO consult storedShouldStartExpireTimer here.
        //       We don't want to start expiration until it is true.
        let sql = """
        SELECT \(interactionColumn: .uniqueId)
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .storedShouldStartExpireTimer) IS TRUE
        AND (
            \(interactionColumn: .expiresAt) IS 0 OR
            \(interactionColumn: .expireStartedAt) IS 0
        )
        """
        do {
            return try String.fetchAll(transaction.database, sql: sql)
        } catch {
            owsFailDebug("error: \(error)")
            return []
        }
    }

    static func interactions(withInteractionIds interactionIds: Set<String>, transaction: GRDBReadTransaction) -> Set<TSInteraction> {
        guard !interactionIds.isEmpty else {
            return []
        }

        let sql = """
            SELECT * FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .uniqueId) IN (\(interactionIds.map { "\'\($0)'" }.joined(separator: ",")))
        """
        let arguments: StatementArguments = []
        let cursor = TSInteraction.grdbFetchCursor(sql: sql, arguments: arguments, transaction: transaction)
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

    static func enumerateGroupReplies(
        for storyMessage: StoryMessage,
        transaction: ReadTransaction,
        block: @escaping (TSMessage, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        let sql = """
        SELECT *
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .storyTimestamp) = ?
        AND \(interactionColumn: .storyAuthorUuidString) = ?
        AND \(interactionColumn: .isGroupStoryReply) = 1
        """
        let cursor = TSInteraction.grdbFetchCursor(
            sql: sql,
            arguments: [storyMessage.timestamp, storyMessage.authorUuid.uuidString],
            transaction: transaction
        )
        do {
            while let interaction = try cursor.next() {
                guard let message = interaction as? TSMessage else {
                    owsFailDebug("Unexpected object: \(type(of: interaction))")
                    return
                }
                var stop: ObjCBool = false
                block(message, &stop)
                if stop.boolValue {
                    return
                }
            }
        } catch {
            owsFail("error: \(error)")
        }
    }

    static func hasLocalUserReplied(
        storyTimestamp: UInt64,
        storyAuthorUuidString: String,
        transaction: ReadTransaction
    ) -> Bool {
        let sql = """
            SELECT EXISTS(
                SELECT 1
                FROM \(InteractionRecord.databaseTableName)
                WHERE \(interactionColumn: .storyTimestamp) = ?
                AND \(interactionColumn: .storyAuthorUuidString) = ?
                AND \(interactionColumn: .recordType) = \(SDSRecordType.outgoingMessage.rawValue)
                AND \(interactionColumn: .isGroupStoryReply) = 1
                LIMIT 1
            )
        """
        do {
            return try Bool.fetchOne(
                transaction.database,
                sql: sql,
                arguments: [
                    storyTimestamp,
                    storyAuthorUuidString
                ]
            ) ?? false
        } catch {
            owsFail("error: \(error)")
        }
    }

    static func groupReplyUniqueIdsAndRowIds(
        storyAuthor: ServiceId,
        storyTimestamp: UInt64,
        transaction: GRDBReadTransaction
    ) -> [(String, Int64)] {
        guard storyAuthor.uuidValue != StoryMessage.systemStoryAuthorUUID else {
            // No replies on system stories.
            return []
        }
        do {
            let sql: String = """
                SELECT \(interactionColumn: .uniqueId), \(interactionColumn: .id)
                FROM \(InteractionRecord.databaseTableName)
                WHERE \(interactionColumn: .storyTimestamp) = ?
                AND \(interactionColumn: .storyAuthorUuidString) = ?
                AND \(interactionColumn: .isGroupStoryReply) = 1
                ORDER BY \(interactionColumn: .id) ASC
            """
            return try Row.fetchAll(
                transaction.database,
                sql: sql,
                arguments: [storyTimestamp, storyAuthor.uuidValue.uuidString]
            ).map { ($0[0], $0[1]) }
        } catch {
            owsFail("error: \(error)")
        }
    }

    static func oldestPlaceholderInteraction(transaction: GRDBReadTransaction) -> OWSRecoverableDecryptionPlaceholder? {
        let sql = """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .recordType) IS \(SDSRecordType.recoverableDecryptionPlaceholder.rawValue)
            ORDER BY \(interactionColumn: .id) ASC
            LIMIT 1
        """
        let result = TSInteraction.grdbFetchOne(sql: sql, transaction: transaction)
        if let result = result as? OWSRecoverableDecryptionPlaceholder {
            return result
        } else if let result = result {
            owsFailDebug("Unexpected type: \(type(of: result))")
            return nil
        } else {
            return nil
        }
    }

    static func enumeratePlaceholders(transaction: GRDBReadTransaction, block: (OWSRecoverableDecryptionPlaceholder, UnsafeMutablePointer<ObjCBool>) -> Void) {
        let sql = """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .recordType) IS \(SDSRecordType.recoverableDecryptionPlaceholder.rawValue)
            ORDER BY \(interactionColumn: .id) ASC
        """
        do {
            let cursor = TSInteraction.grdbFetchCursor(sql: sql, transaction: transaction)
            while let result = try cursor.next() {
                if let placeholder = result as? OWSRecoverableDecryptionPlaceholder {
                    var stop: ObjCBool = false
                    block(placeholder, &stop)
                    if stop.boolValue {
                        return
                    }
                } else {
                    owsFailDebug("Unexpected type: \(type(of: result))")
                }
            }
        } catch {
            owsFailDebug("unexpected error \(error)")
        }
    }

    /// Gets the most recently inserted Interaction of type `incomingMessage`.
    static func lastInsertedIncomingMessage(transaction: GRDBReadTransaction) -> TSIncomingMessage? {
        let sql: String = """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .recordType) = ?
            AND \(interactionColumn: .callType) IS NULL
            ORDER BY \(interactionColumn: .id) DESC
            LIMIT 1
        """
        let arguments: StatementArguments = [
            SDSRecordType.incomingMessage.rawValue
        ]
        let result = TSInteraction.grdbFetchOne(sql: sql, arguments: arguments, transaction: transaction)
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

    public func profileUpdateInteractions(afterSortId sortId: UInt64, transaction: GRDBReadTransaction) -> [TSInfoMessage] {
        let cursor = TSInteraction.grdbFetchCursor(
            sql: """
                SELECT *
                FROM \(InteractionRecord.databaseTableName)
                WHERE \(interactionColumn: .threadUniqueId) = ?
                AND \(interactionColumn: .messageType) = ?
                AND \(interactionColumn: .id) > ?
            """,
            arguments: [threadUniqueId, TSInfoMessageType.profileUpdate.rawValue, sortId],
            transaction: transaction)

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

    func latestInteraction(from address: SignalServiceAddress, transaction: GRDBReadTransaction) -> TSInteraction? {
        var latestInteraction: TSInteraction?

        if let uuidString = address.uuidString {
            let sql = """
                SELECT *
                FROM \(InteractionRecord.databaseTableName)
                WHERE \(interactionColumn: .threadUniqueId) = ?
                AND \(interactionColumn: .authorUUID) = ?
                ORDER BY \(interactionColumn: .id) DESC
                LIMIT 1
            """
            let arguments: StatementArguments = [threadUniqueId, uuidString]
            latestInteraction = TSInteraction.grdbFetchOne(sql: sql, arguments: arguments, transaction: transaction)
        }

        if latestInteraction == nil, let phoneNumber = address.phoneNumber {
            let sql = """
                SELECT *
                FROM \(InteractionRecord.databaseTableName)
                WHERE \(interactionColumn: .threadUniqueId) = ?
                AND \(interactionColumn: .authorPhoneNumber) = ?
                ORDER BY \(interactionColumn: .id) DESC
                LIMIT 1
            """
            let arguments: StatementArguments = [threadUniqueId, phoneNumber]
            latestInteraction = TSInteraction.grdbFetchOne(sql: sql, arguments: arguments, transaction: transaction)
        }

        return latestInteraction
    }

    func mostRecentInteractionForInbox(transaction: GRDBReadTransaction) -> TSInteraction? {
        let interactionsSql = """
                SELECT *
                FROM \(InteractionRecord.databaseTableName)
                WHERE \(interactionColumn: .threadUniqueId) = ?
                \(Self.filterStoryRepliesClause())
                \(Self.filterEditHistoryClause())
                AND \(interactionColumn: .errorType) IS NOT ?
                AND \(interactionColumn: .messageType) IS NOT ?
                AND \(interactionColumn: .messageType) IS NOT ?
                ORDER BY \(interactionColumn: .id) DESC
                """
        let firstInteractionSql = interactionsSql + " LIMIT 1"
        let arguments: StatementArguments = [threadUniqueId,
                                             TSErrorMessageType.nonBlockingIdentityChange.rawValue,
                                             TSInfoMessageType.verificationStateChange.rawValue,
                                             TSInfoMessageType.profileUpdate.rawValue]
        guard let firstInteraction = TSInteraction.grdbFetchOne(sql: firstInteractionSql,
                                                                arguments: arguments,
                                                                transaction: transaction) else {
            return nil
        }

        // We can't exclude specific group updates in the query.
        // In the (mildly) rare case that the most recent message
        // is a group update that shouldn't be shown,
        // we iterate backward until we find a good interaction.
        let anyTransaction = transaction.asAnyRead
        if firstInteraction.shouldAppearInInbox(transaction: anyTransaction) {
            return firstInteraction
        }
        do {
            let cursor = TSInteraction.grdbFetchCursor(sql: interactionsSql,
                                                       arguments: arguments,
                                                       transaction: transaction)
            while let interaction = try cursor.next() {
                if interaction.shouldAppearInInbox(transaction: anyTransaction) {
                    return interaction
                }
            }
            return nil
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    func earliestKnownInteractionRowId(transaction: GRDBReadTransaction) -> Int? {
        let sql = """
                SELECT \(interactionColumn: .id)
                FROM \(InteractionRecord.databaseTableName)
                WHERE \(interactionColumn: .threadUniqueId) = ?
                ORDER BY \(interactionColumn: .id) ASC
                LIMIT 1
                """
        let arguments: StatementArguments = [threadUniqueId]
        return try? Int.fetchOne(transaction.database, sql: sql, arguments: arguments)
    }

    // From: https://www.sqlite.org/optoverview.html
    // This clause has been tuned hand-in-hand with the index_model_TSInteraction_on_nonPlaceholders_uniqueThreadId_id index
    // If you need to adjust this clause, you should probably update the index as well. This is a perf sensitive code path.
    private let filterPlaceholdersClause = "AND \(interactionColumn: .recordType) IS NOT \(SDSRecordType.recoverableDecryptionPlaceholder.rawValue)"

    fileprivate static func filterStoryRepliesClause(interactionsAlias: String? = nil) -> String {
        // Until stories are supported, and all the requisite indices have been built,
        // keep using the old story-free query which works with both the old and new indices.
        guard RemoteConfig.stories else { return "" }

        let columnPrefix: String
        if let interactionsAlias = interactionsAlias {
            columnPrefix = interactionsAlias + "."
        } else {
            columnPrefix = ""
        }

        // Treat NULL and 0 as equivalent.
        return "AND \(columnPrefix)\(interactionColumn: .isGroupStoryReply) IS NOT 1"
    }

    fileprivate static func filterEditHistoryClause(
        excludeAll: Bool = false,
        interactionsAlias: String? = nil
    ) -> String {
        guard FeatureFlags.editMessageReceive else { return "" }

        let columnPrefix: String
        if let interactionsAlias = interactionsAlias {
            columnPrefix = interactionsAlias + "."
        } else {
            columnPrefix = ""
        }

        if excludeAll {
            return "AND \(columnPrefix)\(interactionColumn: .editState) IS \(TSEditState.none.rawValue)"
        } else {
            return "AND \(columnPrefix)\(interactionColumn: .editState) IS NOT \(TSEditState.pastRevision.rawValue)"
        }

    }

    func enumerateInteractionIds(transaction: GRDBReadTransaction, block: @escaping (String, UnsafeMutablePointer<ObjCBool>) throws -> Void) throws {

        let cursor = try String.fetchCursor(transaction.database,
                                            sql: """
            SELECT \(interactionColumn: .uniqueId)
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .threadUniqueId) = ?
            ORDER BY \(interactionColumn: .id) DESC
            """,
            arguments: [threadUniqueId])
        while let uniqueId = try cursor.next() {
            var stop: ObjCBool = false
            try block(uniqueId, &stop)
            if stop.boolValue {
                return
            }
        }
    }

    func enumerateRecentInteractions(
        excludingPlaceholders excludePlaceholders: Bool,
        transaction: GRDBReadTransaction,
        block: @escaping (TSInteraction, UnsafeMutablePointer<ObjCBool>) -> Void
    ) throws {
        let sql = """
        SELECT *
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .threadUniqueId) = ?
        \(Self.filterStoryRepliesClause())
        \(Self.filterEditHistoryClause())
        \(excludePlaceholders ? filterPlaceholdersClause : "")
        ORDER BY \(interactionColumn: .id) DESC
        """
        let arguments: StatementArguments = [threadUniqueId]
        let cursor = TSInteraction.grdbFetchCursor(sql: sql,
                                                   arguments: arguments,
                                                   transaction: transaction)

        while let interaction = try cursor.next() {
            var stop: ObjCBool = false
            block(interaction, &stop)
            if stop.boolValue {
                return
            }
        }
    }

    @objc
    public func enumerateMessagesWithAttachments(transaction: GRDBReadTransaction, block: @escaping (TSMessage, UnsafeMutablePointer<ObjCBool>) -> Void) throws {

        let emptyArraySerializedData = try! NSKeyedArchiver.archivedData(withRootObject: [String](), requiringSecureCoding: true)

        let sql = """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .threadUniqueId) = ?
            AND \(interactionColumn: .attachmentIds) IS NOT NULL
            AND \(interactionColumn: .attachmentIds) != ?
        """
        let arguments: StatementArguments = [threadUniqueId, emptyArraySerializedData]
        let cursor = TSInteraction.grdbFetchCursor(sql: sql, arguments: arguments, transaction: transaction)
        while let interaction = try cursor.next() {
            var stop: ObjCBool = false

            guard let message = interaction as? TSMessage else {
                owsFailDebug("Interaction has unexpected type: \(type(of: interaction))")
                continue
            }

            guard !message.attachmentIds.isEmpty else {
                owsFailDebug("message unexpectedly has no attachments")
                continue
            }

            block(message, &stop)

            if stop.boolValue {
                return
            }
        }
    }

    func firstInteraction(atOrAroundSortId sortId: UInt64, transaction: GRDBReadTransaction) -> TSInteraction? {
        guard sortId > 0 else { return nil }

        // First, see if there's an interaction at or before this sortId.

        let atOrBeforeQuery = """
        SELECT *
        FROM \(InteractionRecord.databaseTableName)
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

    func existsOutgoingMessage(transaction: GRDBReadTransaction) -> Bool {
        let sql = """
        SELECT EXISTS(
            SELECT 1
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .threadUniqueId) = ?
            AND \(interactionColumn: .recordType) = ?
            LIMIT 1
        )
        """
        let arguments: StatementArguments = [threadUniqueId, SDSRecordType.outgoingMessage.rawValue]
        do {
            return try Bool.fetchOne(transaction.database, sql: sql, arguments: arguments) ?? false
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Failed to find outgoing message")
        }
    }

    func hasGroupUpdateInfoMessage(transaction: GRDBReadTransaction) -> Bool {
        let sql = """
        SELECT EXISTS(
            SELECT 1
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .threadUniqueId) = ?
            AND \(interactionColumn: .recordType) = \(SDSRecordType.infoMessage.rawValue)
            AND \(interactionColumn: .messageType) = \(TSInfoMessageType.typeGroupUpdate.rawValue)
            LIMIT 1
        )
        """
        let arguments: StatementArguments = [threadUniqueId]
        do {
            return try Bool.fetchOne(transaction.database, sql: sql, arguments: arguments)!
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Failed to find info message")
        }
    }

    func hasUserInitiatedInteraction(transaction: GRDBReadTransaction) -> Bool {
        let infoMessageTypes: [TSInfoMessageType] = [
            .typeGroupQuit,
            .typeGroupUpdate,
            .typeSessionDidEnd,
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
        SELECT EXISTS(
            SELECT 1
            FROM \(InteractionRecord.databaseTableName)
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
            \(Self.filterStoryRepliesClause())
            \(Self.filterEditHistoryClause())
            LIMIT 1
        )
        """
        let arguments: StatementArguments = [threadUniqueId]
        do {
            return try Bool.fetchOne(transaction.database, sql: sql, arguments: arguments)!
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Failed to determine interaction")
        }
    }

    func possiblyHasIncomingMessages(transaction: GRDBReadTransaction) -> Bool {
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
        SELECT EXISTS(
            SELECT 1
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .threadUniqueId) = ?
            AND \(interactionColumn: .recordType) IN (\(sqlInteractionTypes))
            LIMIT 1
        )
        """
        let arguments: StatementArguments = [threadUniqueId]
        do {
            return try Bool.fetchOne(transaction.database, sql: sql, arguments: arguments)!
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Failed to find Incoming message")
        }
    }

    #if DEBUG
    func enumerateUnstartedExpiringMessages(transaction: GRDBReadTransaction, block: @escaping (TSMessage, UnsafeMutablePointer<ObjCBool>) -> Void) {
        // NOTE: We DO consult storedShouldStartExpireTimer here.
        //       We don't want to start expiration until it is true.
        let sql = """
        SELECT *
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .threadUniqueId) = ?
        AND \(interactionColumn: .storedShouldStartExpireTimer) IS TRUE
        AND (
            \(interactionColumn: .expiresAt) IS 0 OR
            \(interactionColumn: .expireStartedAt) IS 0
        )
        """
        let cursor = TSInteraction.grdbFetchCursor(sql: sql, arguments: [threadUniqueId], transaction: transaction)
        do {
            while let interaction = try cursor.next() {
                guard let message = interaction as? TSMessage else {
                    owsFailDebug("Unexpected object: \(type(of: interaction))")
                    return
                }
                var stop: ObjCBool = false
                block(message, &stop)
                if stop.boolValue {
                    return
                }
            }
        } catch {
            owsFail("error: \(error)")
        }
    }
    #endif

    func outgoingMessageCount(transaction: GRDBReadTransaction) -> UInt {
        let sql = """
        SELECT COUNT(*)
        FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .threadUniqueId) = ?
        AND \(interactionColumn: .recordType) = ?
        """
        let arguments: StatementArguments = [threadUniqueId, SDSRecordType.outgoingMessage.rawValue]
        do {
            return try UInt.fetchOne(transaction.database, sql: sql, arguments: arguments) ?? 0
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Failed to determine message count")
        }
    }

    func fetchUniqueIds(
        filter: RowIdFilter,
        excludingPlaceholders excludePlaceholders: Bool,
        limit: Int,
        tx: GRDBReadTransaction
    ) throws -> [String] {
        let rowIdFilter: String
        let rowIdArguments: StatementArguments
        let isAscending: Bool
        switch filter {
        case .newest:
            rowIdFilter = ""
            rowIdArguments = []
            isAscending = false
        case .before(let rowId):
            rowIdFilter = "AND \(interactionColumn: .id) < ?"
            rowIdArguments = [rowId]
            isAscending = false
        case .after(let rowId):
            rowIdFilter = "AND \(interactionColumn: .id) > ?"
            rowIdArguments = [rowId]
            isAscending = true
        case .range(let rowIds):
            rowIdFilter = "AND \(interactionColumn: .id) >= ? AND \(interactionColumn: .id) <= ?"
            rowIdArguments = [rowIds.lowerBound, rowIds.upperBound]
            isAscending = true
        }

        let sql = """
            SELECT "uniqueId" FROM \(InteractionRecord.databaseTableName)
            WHERE
                \(interactionColumn: .threadUniqueId) = ?
                \(rowIdFilter)
                \(Self.filterStoryRepliesClause())
                \(Self.filterEditHistoryClause())
                \(excludePlaceholders ? filterPlaceholdersClause : "")
            ORDER BY \(interactionColumn: .id) \(isAscending ? "ASC" : "DESC")
            LIMIT \(limit)
        """
        let arguments: StatementArguments = [threadUniqueId] + rowIdArguments
        let uniqueIds = try String.fetchAll(tx.database, sql: sql, arguments: arguments)
        return isAscending ? uniqueIds : Array(uniqueIds.reversed())
    }

    public static func maxRowId(transaction: GRDBReadTransaction) -> Int {
        do {
            return try Int.fetchOne(transaction.database, sql: "SELECT MAX(id) FROM model_TSInteraction") ?? 0
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Failed to find max row id")
        }
    }
}
