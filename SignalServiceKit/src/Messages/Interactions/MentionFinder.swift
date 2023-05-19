//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import SignalCoreKit

// MARK: -

@objc
public class MentionFinder: NSObject {

    @objc
    public class func messagesMentioning(
        address: SignalServiceAddress,
        in thread: TSThread? = nil,
        includeReadMessages: Bool = true,
        transaction: GRDBReadTransaction
    ) -> [TSMessage] {
        guard let uuidString = address.uuidString else { return [] }
        var sql = """
            SELECT interaction.*
            FROM \(InteractionRecord.databaseTableName) as interaction
            INNER JOIN \(TSMention.databaseTableName) as mention
                ON mention.\(TSMention.columnName(.uniqueMessageId)) = interaction.\(interactionColumn: .uniqueId)
                AND mention.\(TSMention.columnName(.uuidString)) = ?
        """

        var arguments = [uuidString]

        var next = "WHERE"

        if let thread = thread {
            sql += " \(next) interaction.\(interactionColumn: .threadUniqueId) = ?"
            arguments.append(thread.uniqueId)
            next = "AND"
        }

        if !includeReadMessages {
            sql += " \(next) interaction.\(interactionColumn: .read) IS 0"
            next = "AND"
        }

        sql += " \(next) interaction.\(interactionColumn: .isGroupStoryReply) IS 0"
        next = "AND"

        sql += " ORDER BY \(interactionColumn: .id)"

        let cursor = TSMessage.grdbFetchCursor(sql: sql, arguments: StatementArguments(arguments), transaction: transaction)

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

    @objc
    public class func deleteAllMentions(for message: TSMessage, transaction: GRDBWriteTransaction) {
        let sql = """
            DELETE FROM \(TSMention.databaseTableName)
            WHERE \(TSMention.columnName(.uniqueMessageId)) = ?
        """
        transaction.execute(sql: sql, arguments: [message.uniqueId])
    }

    @objc
    public class func mentionedAddresses(for message: TSMessage, transaction: GRDBReadTransaction) -> [SignalServiceAddress] {
        let sql = """
            SELECT *
            FROM \(TSMention.databaseTableName)
            WHERE \(TSMention.columnName(.uniqueMessageId)) = ?
        """

        var addresses = [SignalServiceAddress]()

        do {
            let cursor = try TSMention.fetchCursor(transaction.database, sql: sql, arguments: [message.uniqueId])
            while let mention = try cursor.next() {
                addresses.append(mention.address)
            }
        } catch {
            owsFailDebug("unexpected error \(error)")
        }

        return addresses
    }

    @objc
    public class func tryToCleanupOrphanedMention(
        uniqueId: String,
        thresholdDate: Date,
        shouldPerformRemove: Bool,
        transaction: SDSAnyWriteTransaction
    ) -> Bool {
        guard let mention = TSMention.anyFetch(uniqueId: uniqueId, transaction: transaction) else {
            // This could just be a race condition, but it should be very unlikely.
            Logger.warn("Could not load mention: \(uniqueId)")
            return false
        }

        guard !mention.creationDate.isAfter(thresholdDate) else {
            Logger.info("Skipping orphan mention due to age: \(mention.creationDate.timeIntervalSinceNow)")
            return false
        }

        Logger.info("Removing orphan mention: \(mention.uniqueId)")

        // Sometimes we cleanup orphaned data as an audit and don't actually
        // perform the remove operation.
        if shouldPerformRemove { mention.anyRemove(transaction: transaction) }

        return true
    }
}
