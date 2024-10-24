//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public final class MessageBackupInteractionStore {

    private let interactionStore: InteractionStore

    init(interactionStore: InteractionStore) {
        self.interactionStore = interactionStore
    }

    /// Enumerate all interactions.
    ///
    /// - Parameter block
    /// A block executed for each enumerated interaction. Returns `true` if
    /// enumeration should continue, and `false` otherwise.
    func enumerateAllInteractions(
        tx: DBReadTransaction,
        block: (TSInteraction) throws -> Bool
    ) throws {
        let cursor = try InteractionRecord
            .fetchCursor(tx.databaseConnection)
            .map { try TSInteraction.fromRecord($0) }

        while
            let interaction = try cursor.next(),
            try block(interaction)
        {}
    }

    // Even generating the sql string itself is expensive when multiplied by 200k messages.
    // So we generate the string once and cache it (on top of caching the Statement)
    private var cachedSQL: String?
    func insert(
        _ interaction: TSInteraction,
        in thread: MessageBackup.ChatThread,
        chatId: MessageBackup.ChatId,
        context: MessageBackup.ChatItemRestoringContext
    ) throws {
        guard interaction.shouldBeSaved else {
            owsFailDebug("Unsaveable interaction in a backup?")
            return
        }
        if let message = interaction as? TSOutgoingMessage {
            message.updateStoredMessageState()
        }
        if let message = interaction as? TSMessage {
            message.updateStoredShouldStartExpireTimer()
        }

        let shouldAppearInInbox = interaction.shouldAppearInInbox(
            groupUpdateItemsBuilder: { infoMessage in
                // In a backups context, _all_ info message group updates are precomputed.
                // We can assume this in this builder override.
                switch infoMessage.groupUpdateMetadata(
                    localIdentifiers: context.recipientContext.localIdentifiers
                ) {
                case .precomputed(let wrapper):
                    return wrapper.updateItems
                default:
                    return nil
                }
            }
        )

        // Note: We do not insert restored messages into the MessageSendLog.
        // This means if we get a retry request for a message we sent pre-backup
        // and restore, we'll only send back a Null message. (Until such a day
        // when resends use the interactions table and not MSL at all).

        let sql: String
        if let cachedSQL {
            sql = cachedSQL
        } else {
            let columnsSQL = InteractionRecord.CodingKeys.allCases.filter({ $0 != .id }).map(\.name).joined(separator: ", ")
            let valuesSQL = InteractionRecord.CodingKeys.allCases.filter({ $0 != .id }).map({ _ in "?" }).joined(separator: ", ")
            sql = """
                INSERT INTO \(InteractionRecord.databaseTableName) (\(columnsSQL)) \
                VALUES (\(valuesSQL))
                """
            cachedSQL = sql
        }

        let statement = try context.tx.databaseConnection.cachedStatement(sql: sql)
        try statement.setUncheckedArguments((interaction.asRecord() as! InteractionRecord).asArguments())
        try statement.execute()
        interaction.updateRowId(context.tx.databaseConnection.lastInsertedRowID)

        guard let interactionRowId = interaction.sqliteRowId else {
            throw OWSAssertionError("Missing row id after insertion!")
        }

        if shouldAppearInInbox {
            context.chatContext.updateLastVisibleInteractionRowId(
                interactionRowId: interactionRowId,
                chatId: chatId
            )
        }
    }
}
