//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
public import LibSignalClient

// MARK: -

public class MentionFinder {

    public class func messagesMentioning(
        aci: Aci,
        in threadUniqueId: String? = nil,
        includeReadMessages: Bool = true,
        tx: DBReadTransaction
    ) -> [TSMessage] {
        var filters = [String]()
        var arguments = [aci.serviceIdUppercaseString]

        var isIndexedByUnreadIndex = false

        if let threadUniqueId {
            // The TSMention's uniqueThreadId should always match the TSInteraction's
            // threadUniqueId. However, we pick one column or the other depending on
            // whether or not we're filtering out read messages.
            //
            // If we're only considering unread messages, we'll use the "(read,
            // uniqueThreadId)" TSInteraction index and bound performance by the number
            // of unread messages in the thread.
            //
            // If we're considering all messages in the thread, we'll use the
            // "(uuidString, uniqueThreadId)" TSMention index and bound performance by
            // the number of mentions of `aci` in the chat. Because we check for
            // mentions of people who are no longer in the group (or were never in the
            // group), there's usually not any mentions, and the query is lightning
            // fast. (The alternative index is one which scans all the messages in the
            // conversation, and that's much slower.)
            if includeReadMessages {
                filters.append("mention.\(TSMention.columnName(.uniqueThreadId)) = ?")
                arguments.append(threadUniqueId)
            } else {
                filters.append("interaction.\(interactionColumn: .threadUniqueId) = ?")
                arguments.append(threadUniqueId)
                isIndexedByUnreadIndex = true
            }
        }

        if !includeReadMessages {
            filters.append("interaction.\(interactionColumn: .read) IS 0")
        }

        filters.append("interaction.\(interactionColumn: .isGroupStoryReply) IS 0")
        // The "WHERE" breaks if this is empty. The prior line ensures it passes.
        owsPrecondition(!filters.isEmpty)

        let sql = """
            SELECT interaction.*
            FROM \(InteractionRecord.databaseTableName) as interaction
            \(isIndexedByUnreadIndex ? DEBUG_INDEXED_BY("index_model_TSInteraction_UnreadMessages") : "")
            INNER JOIN \(TSMention.databaseTableName) as mention
                \(!isIndexedByUnreadIndex ? DEBUG_INDEXED_BY("index_model_TSMention_on_uuidString_and_uniqueThreadId") : "")
                ON mention.\(TSMention.columnName(.uniqueMessageId)) = interaction.\(interactionColumn: .uniqueId)
                AND mention.\(TSMention.columnName(.aciString)) = ?
            WHERE \(filters.joined(separator: " AND "))
            ORDER BY \(interactionColumn: .id)
            """

        let cursor = TSMessage.grdbFetchCursor(sql: sql, arguments: StatementArguments(arguments), transaction: tx)

        var messages = [TSMessage]()

        do {
            while let message = try cursor.next() as? TSMessage {
                messages.append(message)
            }
        } catch {
            owsFailDebug("unexpected error \(error)")
        }

        return messages
    }

    public class func deleteAllMentions(for message: TSMessage, transaction: DBWriteTransaction) {
        let sql = """
            DELETE FROM \(TSMention.databaseTableName)
            WHERE \(TSMention.columnName(.uniqueMessageId)) = ?
        """
        transaction.database.executeHandlingErrors(sql: sql, arguments: [message.uniqueId])
    }

    public class func mentionedAcis(for message: TSMessage, tx: DBReadTransaction) -> [Aci] {
        let sql = """
            SELECT \(TSMention.columnName(.aciString))
            FROM \(TSMention.databaseTableName)
            WHERE \(TSMention.columnName(.uniqueMessageId)) = ?
        """

        let aciStrings: [String]
        do {
            aciStrings = try String.fetchAll(tx.database, sql: sql, arguments: [message.uniqueId])
        } catch {
            owsFailDebug("unexpected error \(error.grdbErrorForLogging)")
            return []
        }

        return aciStrings.compactMap(Aci.parseFrom(aciString:))
    }

    public class func tryToCleanupOrphanedMention(
        uniqueId: String,
        thresholdDate: Date,
        shouldPerformRemove: Bool,
        transaction: DBWriteTransaction
    ) -> Bool {
        guard let mention = TSMention.anyFetch(uniqueId: uniqueId, transaction: transaction) else {
            // This could just be a race condition, but it should be very unlikely.
            Logger.warn("Could not load mention: \(uniqueId)")
            return false
        }

        guard mention.creationDate <= thresholdDate else {
            Logger.info("Skipping orphan mention due to age: \(-mention.creationDate.timeIntervalSinceNow)")
            return false
        }

        Logger.info("Removing orphan mention: \(mention.uniqueId)")

        // Sometimes we cleanup orphaned data as an audit and don't actually
        // perform the remove operation.
        if shouldPerformRemove { mention.anyRemove(transaction: transaction) }

        return true
    }
}
