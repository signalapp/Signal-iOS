//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient

public class MessageBackupReactionStore {

    public init() {}

    // MARK: - Archiving

    /// Returns a list of all reactions to this message
    func allReactions(
        message: TSMessage,
        context: MessageBackup.RecipientArchivingContext
    ) throws -> [OWSReaction] {
        let sql = """
            SELECT * FROM \(OWSReaction.databaseTableName)
            WHERE \(OWSReaction.columnName(.uniqueMessageId)) = ?
            ORDER BY \(OWSReaction.columnName(.id)) DESC
        """
        let statement = try context.tx.databaseConnection.cachedStatement(sql: sql)
        return try OWSReaction.fetchAll(statement, arguments: [message.uniqueId])
    }

    // MARK: - Restoring

    func createReaction(
        uniqueMessageId: String,
        emoji: String,
        reactorAci: Aci,
        sentAtTimestamp: UInt64,
        sortOrder: UInt64,
        context: MessageBackup.RecipientRestoringContext
    ) throws {
        let reaction = OWSReaction.fromRestoredBackup(
            uniqueMessageId: uniqueMessageId,
            emoji: emoji,
            reactorAci: reactorAci,
            sentAtTimestamp: sentAtTimestamp,
            sortOrder: sortOrder
        )
        try reaction.insert(context.tx.databaseConnection)
    }

    /// In the olden days before the introduction of Acis, reactions were sent by e164s.
    func createLegacyReaction(
        uniqueMessageId: String,
        emoji: String,
        reactorE164: E164,
        sentAtTimestamp: UInt64,
        sortOrder: UInt64,
        context: MessageBackup.RecipientRestoringContext
    ) throws {
        let reaction = OWSReaction.fromRestoredBackup(
            uniqueMessageId: uniqueMessageId,
            emoji: emoji,
            reactorE164: reactorE164,
            sentAtTimestamp: sentAtTimestamp,
            sortOrder: sortOrder
        )
        try reaction.insert(context.tx.databaseConnection)
    }
}
