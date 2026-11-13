//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient

class BackupArchiveReactionStore {

    init() {}

    // MARK: - Archiving

    /// Returns a list of all reactions to this message
    func allReactions(
        message: TSMessage,
        context: BackupArchive.RecipientArchivingContext,
    ) -> [ReactionRecord] {
        let messageId = message.sqliteRowId.owsFailUnwrap("must exist")
        let sql = """
        SELECT * FROM \(ReactionRecord.databaseTableName)
        WHERE \(ReactionRecord.Columns.messageId.name) = ?
        ORDER BY \(ReactionRecord.Columns.id.name) DESC
        """
        return failIfThrows {
            let statement = try context.tx.database.cachedStatement(sql: sql)
            return try ReactionRecord.fetchAll(statement, arguments: [messageId])
        }
    }

    // MARK: - Restoring

    func createReaction(
        message: TSMessage,
        reactorId: SignalRecipient.RowId,
        threadId: TSThread.RowId,
        emoji: String,
        sentAtTimestamp: UInt64,
        context: BackupArchive.RecipientRestoringContext,
    ) {
        let messageId = message.sqliteRowId.owsFailUnwrap("must exist")
        _ = ReactionRecord.insertRecord(
            messageId: messageId,
            reactorId: reactorId,
            threadId: threadId,
            emoji: emoji,
            timestamp: sentAtTimestamp,
            isRead: ReactionRecord.isReadableMessage(message) ? false : nil,
            tx: context.tx,
        )
    }
}
