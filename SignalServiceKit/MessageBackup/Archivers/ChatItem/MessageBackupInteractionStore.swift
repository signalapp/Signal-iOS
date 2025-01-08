//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

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

    // MARK: Per type inserts

    func insert(
        _ interaction: TSIncomingMessage,
        in thread: MessageBackup.ChatThread,
        chatId: MessageBackup.ChatId,
        senderAci: Aci?,
        directionalDetails: BackupProto_ChatItem.IncomingMessageDetails,
        context: MessageBackup.ChatItemRestoringContext
    ) throws {
        let wasRead = BackupProto_ChatItem.OneOf_DirectionalDetails
            .incoming(directionalDetails).wasRead
        interaction.wasRead = wasRead
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
        in thread: MessageBackup.ChatThread,
        chatId: MessageBackup.ChatId,
        directionalDetails: BackupProto_ChatItem.OutgoingMessageDetails,
        context: MessageBackup.ChatItemRestoringContext
    ) throws {
        let wasRead = BackupProto_ChatItem.OneOf_DirectionalDetails
            .outgoing(directionalDetails).wasRead
        try insert(
            interaction: interaction,
            in: thread,
            chatId: chatId,
            // Outgoing messages are sent by local aci
            senderAci: context.recipientContext.localIdentifiers.aci,
            wasRead: wasRead,
            context: context
        )
    }

    func insert(
        _ interaction: TSInfoMessage,
        in thread: MessageBackup.ChatThread,
        chatId: MessageBackup.ChatId,
        directionalDetails: BackupProto_ChatItem.OneOf_DirectionalDetails,
        context: MessageBackup.ChatItemRestoringContext
    ) throws {
        let wasRead = directionalDetails.wasRead
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
        in thread: MessageBackup.ChatThread,
        chatId: MessageBackup.ChatId,
        directionalDetails: BackupProto_ChatItem.OneOf_DirectionalDetails,
        context: MessageBackup.ChatItemRestoringContext
    ) throws {
        let wasRead = directionalDetails.wasRead
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
        in thread: MessageBackup.ChatThread,
        chatId: MessageBackup.ChatId,
        callerAci: Aci?,
        wasRead: Bool,
        context: MessageBackup.ChatItemRestoringContext
    ) throws {
        interaction.wasRead = wasRead
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
        in thread: MessageBackup.ChatThread,
        chatId: MessageBackup.ChatId,
        startedCallAci: Aci?,
        wasRead: Bool,
        context: MessageBackup.ChatItemRestoringContext
    ) throws {
        interaction.wasRead = wasRead
        try insert(
            interaction: interaction,
            in: thread,
            chatId: chatId,
            senderAci: startedCallAci,
            wasRead: wasRead,
            context: context
        )
    }

    // MARK: Insert

    // Even generating the sql string itself is expensive when multiplied by 200k messages.
    // So we generate the string once and cache it (on top of caching the Statement)
    private var cachedSQL: String?
    private func insert(
        interaction: TSInteraction,
        in thread: MessageBackup.ChatThread,
        chatId: MessageBackup.ChatId,
        senderAci: Aci?,
        wasRead: Bool,
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
        statement.setUncheckedArguments((interaction.asRecord() as! InteractionRecord).asArguments())
        try statement.execute()
        interaction.updateRowId(context.tx.databaseConnection.lastInsertedRowID)

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
}

extension BackupProto_ChatItem.OneOf_DirectionalDetails {

    var wasRead: Bool {
        switch self {
        case .incoming(let incomingMessageDetails):
            return incomingMessageDetails.read
        case .outgoing:
            // Outgoing messages are always implicitly read
            return true
        case .directionless:
            // Since we don't track read state for directionless
            // messages, just treat them as read.
            return true
        }
    }
}
