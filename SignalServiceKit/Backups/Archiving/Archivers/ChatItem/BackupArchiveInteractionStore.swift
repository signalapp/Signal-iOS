//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import GRDB

public final class BackupArchiveInteractionStore {

    private let interactionStore: InteractionStore

    init(interactionStore: InteractionStore) {
        self.interactionStore = interactionStore
    }

    // MARK: Per type inserts

    func insert(
        _ interaction: TSIncomingMessage,
        in thread: BackupArchive.ChatThread,
        chatId: BackupArchive.ChatId,
        senderAci: Aci?,
        wasRead: Bool,
        context: BackupArchive.ChatItemRestoringContext
    ) throws {
        try insert(
            interaction: interaction,
            in: thread,
            chatId: chatId,
            senderAci: senderAci,
            wasRead: wasRead,
            context: context
        )
    }

    func insert(
        _ interaction: TSOutgoingMessage,
        in thread: BackupArchive.ChatThread,
        chatId: BackupArchive.ChatId,
        context: BackupArchive.ChatItemRestoringContext
    ) throws {
        try insert(
            interaction: interaction,
            in: thread,
            chatId: chatId,
            // Outgoing messages are sent by local aci
            senderAci: context.recipientContext.localIdentifiers.aci,
            // Outgoing messages are implicitly read.
            wasRead: true,
            context: context
        )
    }

    func insert(
        _ interaction: TSInfoMessage,
        in thread: BackupArchive.ChatThread,
        chatId: BackupArchive.ChatId,
        context: BackupArchive.ChatItemRestoringContext
    ) throws {
        // Info messages are always "directionless", and consequently their
        // "read" is not backed up. Treat them as read.
        let wasRead = true
        interaction.wasRead = wasRead

        try insert(
            interaction: interaction,
            in: thread,
            chatId: chatId,
            // No sender for info messages
            senderAci: nil,
            wasRead: wasRead,
            context: context
        )
    }

    func insert(
        _ interaction: TSErrorMessage,
        in thread: BackupArchive.ChatThread,
        chatId: BackupArchive.ChatId,
        context: BackupArchive.ChatItemRestoringContext
    ) throws {
        // Error messages are always "directionless", and consequently their
        // "read" state is not backed up. Treat them as read.
        let wasRead = true
        interaction.wasRead = wasRead

        try insert(
            interaction: interaction,
            in: thread,
            chatId: chatId,
            // No sender for error messages
            senderAci: nil,
            wasRead: wasRead,
            context: context
        )
    }

    /// Caller aci can be nil for legacy calls made by e164 accounts before
    /// the introduction of acis.
    func insert(
        _ interaction: TSCall,
        in thread: BackupArchive.ChatThread,
        chatId: BackupArchive.ChatId,
        callerAci: Aci?,
        wasRead: Bool,
        context: BackupArchive.ChatItemRestoringContext
    ) throws {
        try insert(
            interaction: interaction,
            in: thread,
            chatId: chatId,
            senderAci: callerAci,
            wasRead: wasRead,
            context: context
        )
    }

    /// StartedCallAci can be nil if who started the call is unknown.
    func insert(
        _ interaction: OWSGroupCallMessage,
        in thread: BackupArchive.ChatThread,
        chatId: BackupArchive.ChatId,
        startedCallAci: Aci?,
        wasRead: Bool,
        context: BackupArchive.ChatItemRestoringContext
    ) throws {
        try insert(
            interaction: interaction,
            in: thread,
            chatId: chatId,
            senderAci: startedCallAci,
            wasRead: wasRead,
            context: context
        )
    }

    // MARK: - Insert

    private func insert(
        interaction: TSInteraction,
        in thread: BackupArchive.ChatThread,
        chatId: BackupArchive.ChatId,
        senderAci: Aci?,
        wasRead: Bool,
        context: BackupArchive.ChatItemRestoringContext
    ) throws {
        guard interaction.shouldBeSaved else {
            owsFailDebug("Unsaveable interaction in a backup?")
            return
        }
        if let message = interaction as? TSOutgoingMessage {
            message.updateStoredMessageState()
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

        try insertInteractionWithDirectSQLiteCalls(interaction, database: context.tx.database)
        interaction.updateRowId(context.tx.database.lastInsertedRowID)

        guard let interactionRowId = interaction.sqliteRowId else {
            throw OWSAssertionError("Missing row id after insertion!")
        }

        if shouldAppearInInbox {
            context.chatContext.updateLastVisibleInteractionRowId(
                interactionRowId: interactionRowId,
                wasRead: wasRead,
                chatId: chatId
            )
        }

        // If we are in a group and the sender has an aci,
        // track the sent timestamp. Note we may not have
        // a sender for e.g. group update messages, along with
        // other cases of lost/missing/legacy information.
        // This is best-effort rather than guaranteed.
        if let senderAci {
            switch thread.threadType {
            case .contact:
                break
            case .groupV2(let groupThread):
                context.chatContext.updateGroupMemberLastInteractionTimestamp(
                    groupThread: groupThread,
                    chatId: chatId,
                    senderAci: senderAci,
                    timestamp: interaction.timestamp
                )
            }
        }
    }

    /// Reuse the same SQL string, since generating the same string for each
    /// message gets expensive.
    private lazy var insertInteractionSQL: String = {
        let columnsSQL = InteractionRecord.CodingKeys.allCases.filter({ $0 != .id }).map(\.name).joined(separator: ", ")
        let valuesSQL = InteractionRecord.CodingKeys.allCases.filter({ $0 != .id }).map({ _ in "?" }).joined(separator: ", ")
        return """
        INSERT INTO \(InteractionRecord.databaseTableName) (\(columnsSQL)) \
        VALUES (\(valuesSQL))
        """
    }()

    /// Inserts the given interaction using direct `sqlite3_*` function calls,
    /// sidestepping GRDB abstractions.
    ///
    /// Profiling showed that the GRDB methods for creating `Statement` and
    /// `StatementArgument` structs for insertion were taking a shocking amount
    /// of time, primarily due to their use of Swift methods like `zip` that
    /// instantiate opaque iterator structs. To avoid that cost, this method
    /// sidesteps the GRDB abstractions and makes direct `sqlite3_*` method
    /// calls instead.
    ///
    /// In normal app functioning, the cost of those abstractions probably isn't
    /// worth managing these `sqlite3_*` methods ourselves. However, the savings
    /// over hundreds of thousands of interaction inserts during a restore are.
    private func insertInteractionWithDirectSQLiteCalls(
        _ interaction: TSInteraction,
        database: GRDB.Database
    ) throws {
        guard let sqliteConnection = database.sqliteConnection else {
            throw OWSAssertionError("Missing SQLite connection!")
        }

        /// SQLite compiles SQL strings into its internal bytecode. The bytecode
        /// statements can be cached by SQLite, to avoid re-compiling an
        /// identical SQL string repeatedly.
        ///
        /// This line uses GRDB to make the necessary SQLite calls to compile
        /// and cache our "insert interaction" statement, which is returned as a
        /// pointer we can pass back into SQLite,, since those calls involve
        /// tricky pointer math. GRDB then holds a reference to that compiled
        /// statement pointer in a package-level cache, from which we can
        /// retrieve it.
        let cachedSqliteStatement: GRDB.SQLiteStatement = try database.cachedStatement(
            sql: insertInteractionSQL
        ).sqliteStatement

        /// The compiled "insert interaction" SQLite statement contains `?`
        /// placeholders, which must have real values "bound" to them before the
        /// statement can be used to actually insert a database row. Those bound
        /// values are specific to each interaction being inserted; so, before
        /// we can use the cached statement we must reset any values from
        /// previous interaction inserts and bind new values.
        var sqliteReturnCode: Int32

        // Reset the cached statement.
        sqliteReturnCode = sqlite3_reset(cachedSqliteStatement)
        guard sqliteReturnCode == SQLITE_OK else {
            let errmsg = String(cString: sqlite3_errmsg(sqliteConnection)!)
            throw OWSAssertionError("Failed to reset interaction insert statement! \(errmsg)")
        }

        // Clear any previously bound arguments.
        sqliteReturnCode = sqlite3_clear_bindings(cachedSqliteStatement)
        guard sqliteReturnCode == SQLITE_OK else {
            let errmsg = String(cString: sqlite3_errmsg(sqliteConnection)!)
            throw OWSAssertionError("Failed to clear argument bindings from interaction insert statement! \(errmsg)")
        }

        // Bind new values from the current interaction.
        let args = (interaction.asRecord() as! InteractionRecord).asValues()
        var count: Int32 = 1
        for arg in args {
            defer { count += 1 }

            guard let arg else {
                continue
            }

            let code = arg.databaseValue.bind(to: cachedSqliteStatement, at: count)
            guard code == SQLITE_OK else {
                let errmsg = String(cString: sqlite3_errmsg(sqliteConnection)!)
                throw OWSAssertionError("Failed to bind argument to interaction insert statement! \(errmsg)")
            }
        }

        /// Now that we've bound values for the current interaction, we can
        /// execute the statement.
        insertLoop: while true {
            switch sqlite3_step(cachedSqliteStatement) {
            case SQLITE_DONE:
                break insertLoop
            case SQLITE_ROW, SQLITE_OK:
                break
            case let code:
                let errmsg = String(cString: sqlite3_errmsg(sqliteConnection)!)
                throw OWSAssertionError("Unexpected SQLite return code \(code) while executing interaction insert statement! \(errmsg)")
            }
        }
    }
}
