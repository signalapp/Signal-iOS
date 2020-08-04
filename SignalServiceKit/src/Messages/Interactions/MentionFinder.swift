//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

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
            INNER JOIN \(MentionRecord.databaseTableName) as mention
                ON mention.\(mentionColumn: .uniqueMessageId) = interaction.\(interactionColumn: .uniqueId)
                AND mention.\(mentionColumn: .uuidString) = ?
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
        }

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
            DELETE FROM \(MentionRecord.databaseTableName)
            WHERE \(reactionColumn: .uniqueMessageId) = ?
        """
        transaction.executeUpdate(sql: sql, arguments: [message.uniqueId])
    }

    @objc
    public class func mentionedAddresses(for message: TSMessage, transaction: GRDBReadTransaction) -> [SignalServiceAddress] {
        let sql = """
            SELECT *
            FROM \(MentionRecord.databaseTableName)
            WHERE \(mentionColumn: .uniqueMessageId) = ?
        """

        let cursor = TSMention.grdbFetchCursor(sql: sql, arguments: [message.uniqueId], transaction: transaction)

        var addresses = [SignalServiceAddress]()

        do {
            while let mention = try cursor.next() {
                addresses.append(mention.address)
            }
        } catch {
            owsFailDebug("unexpected error \(error)")
        }

        return addresses
    }
}
