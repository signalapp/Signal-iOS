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

        if let thread = thread {
            sql += " WHERE interaction.\(interactionColumn: .threadUniqueId) = ?"
            arguments.append(thread.uniqueId)
        }

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
}
