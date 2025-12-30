//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB
public import LibSignalClient

public protocol InteractionStore {

    // MARK: -

    /// Fetch the interaction with the given SQLite row ID, if one exists.
    func fetchInteraction(
        rowId interactionRowId: Int64,
        tx: DBReadTransaction,
    ) -> TSInteraction?

    func fetchInteraction(
        uniqueId: String,
        tx: DBReadTransaction,
    ) -> TSInteraction?

    func findMessage(
        withTimestamp timestamp: UInt64,
        threadId: String,
        author: SignalServiceAddress,
        tx: DBReadTransaction,
    ) -> TSMessage?

    func fetchInteractions(
        timestamp: UInt64,
        tx: DBReadTransaction,
    ) throws -> [TSInteraction]

    func fetchCursor(
        minRowIdExclusive: Int64?,
        maxRowIdInclusive: Int64?,
        tx: DBReadTransaction,
    ) throws -> AnyCursor<TSInteraction>

    func insertedMessageHasRenderableContent(
        message: TSMessage,
        rowId: Int64,
        tx: DBReadTransaction,
    ) -> Bool

    /// Fetch the message with the given timestamp and incomingMessageAuthor. If
    /// incomingMessageAuthor is nil, returns any outgoing message with the timestamp.
    func fetchMessage(
        timestamp: UInt64,
        incomingMessageAuthor: Aci?,
        transaction: DBReadTransaction,
    ) throws -> TSMessage?

    // MARK: -

    /// Insert the given interaction to the databse.
    func insertInteraction(_ interaction: TSInteraction, tx: DBWriteTransaction)

    /// Applies the given block to the given already-inserted interaction, and
    /// saves the updated interaction to the database.
    func updateInteraction<InteractionType: TSInteraction>(
        _ interaction: InteractionType,
        tx: DBWriteTransaction,
        block: (InteractionType) -> Void,
    )

    // MARK: -

    func buildOutgoingMessage(
        builder: TSOutgoingMessageBuilder,
        tx: DBReadTransaction,
    ) -> TSOutgoingMessage

    func buildOutgoingArchivedPaymentMessage(
        builder: TSOutgoingMessageBuilder,
        amount: String?,
        fee: String?,
        note: String?,
        tx: DBReadTransaction,
    ) -> OWSOutgoingArchivedPaymentMessage

    func insertOrReplacePlaceholder(
        for interaction: TSInteraction,
        from sender: SignalServiceAddress,
        tx: DBWriteTransaction,
    )

    // MARK: - TSOutgoingMessage state updates

    func updateRecipientsFromNonLocalDevice(
        _ message: TSOutgoingMessage,
        recipientStates: [SignalServiceAddress: TSOutgoingMessageRecipientState],
        isSentUpdate: Bool,
        tx: DBWriteTransaction,
    )
}

// MARK: -

public class InteractionStoreImpl: InteractionStore {

    public init() {}

    // MARK: -

    public func fetchInteraction(
        rowId interactionRowId: Int64,
        tx: DBReadTransaction,
    ) -> TSInteraction? {
        return InteractionFinder.fetch(
            rowId: interactionRowId,
            transaction: tx,
        )
    }

    public func fetchInteraction(
        uniqueId: String,
        tx: DBReadTransaction,
    ) -> TSInteraction? {
        return TSInteraction.anyFetch(uniqueId: uniqueId, transaction: tx)
    }

    public func findMessage(
        withTimestamp timestamp: UInt64,
        threadId: String,
        author: SignalServiceAddress,
        tx: DBReadTransaction,
    ) -> TSMessage? {
        return InteractionFinder.findMessage(
            withTimestamp: timestamp,
            threadId: threadId,
            author: author,
            transaction: tx,
        )
    }

    public func fetchInteractions(
        timestamp: UInt64,
        tx: DBReadTransaction,
    ) throws -> [TSInteraction] {
        return try InteractionFinder.fetchInteractions(
            timestamp: timestamp,
            transaction: tx,
        )
    }

    public func fetchCursor(
        minRowIdExclusive: Int64?,
        maxRowIdInclusive: Int64?,
        tx: DBReadTransaction,
    ) throws -> AnyCursor<TSInteraction> {
        let idColumn = Column(InteractionRecord.CodingKeys.id)
        var query = InteractionRecord
            .order(idColumn.asc)
        if let minRowIdExclusive {
            query = query.filter(idColumn > minRowIdExclusive)
        }
        if let maxRowIdInclusive {
            query = query.filter(idColumn <= maxRowIdInclusive)
        }
        let cursor = try query.fetchCursor(tx.database)
            .map(TSInteraction.fromRecord(_:))
        return AnyCursor(cursor)
    }

    public func insertedMessageHasRenderableContent(
        message: TSMessage,
        rowId: Int64,
        tx: DBReadTransaction,
    ) -> Bool {
        return message.insertedMessageHasRenderableContent(rowId: rowId, tx: tx)
    }

    // MARK: -

    public func insertInteraction(_ interaction: TSInteraction, tx: DBWriteTransaction) {
        interaction.anyInsert(transaction: tx)
    }

    public func updateInteraction<InteractionType: TSInteraction>(
        _ interaction: InteractionType,
        tx: DBWriteTransaction,
        block: (InteractionType) -> Void,
    ) {
        interaction.anyUpdate(transaction: tx) { interaction in
            guard let interaction = interaction as? InteractionType else {
                owsFailBeta("Interaction of unexpected type! \(type(of: interaction))")
                return
            }

            block(interaction)
        }
    }

    // MARK: -

    public func buildOutgoingMessage(
        builder: TSOutgoingMessageBuilder,
        tx: DBReadTransaction,
    ) -> TSOutgoingMessage {
        return TSOutgoingMessage(
            outgoingMessageWith: builder,
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: tx,
        )
    }

    public func buildOutgoingArchivedPaymentMessage(
        builder: TSOutgoingMessageBuilder,
        amount: String?,
        fee: String?,
        note: String?,
        tx: DBReadTransaction,
    ) -> OWSOutgoingArchivedPaymentMessage {
        return OWSOutgoingArchivedPaymentMessage(
            outgoingArchivedPaymentMessageWith: builder,
            amount: amount,
            fee: fee,
            note: note,
            transaction: tx,
        )
    }

    public func insertOrReplacePlaceholder(
        for interaction: TSInteraction,
        from sender: SignalServiceAddress,
        tx: DBWriteTransaction,
    ) {
        interaction.insertOrReplacePlaceholder(from: sender, transaction: tx)
    }

    // MARK: - TSOutgoingMessage state updates

    public func updateRecipientsFromNonLocalDevice(
        _ message: TSOutgoingMessage,
        recipientStates: [SignalServiceAddress: TSOutgoingMessageRecipientState],
        isSentUpdate: Bool,
        tx: DBWriteTransaction,
    ) {
        message.updateRecipientsFromNonLocalDevice(
            recipientStates,
            isSentUpdate: isSentUpdate,
            transaction: tx,
        )
    }

    public func fetchMessage(
        timestamp: UInt64,
        incomingMessageAuthor: Aci?,
        transaction: DBReadTransaction,
    ) throws -> TSMessage? {
        let records = try InteractionRecord.fetchAll(
            transaction.database,
            sql: """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .timestamp) = ?
            """,
            arguments: [timestamp],
        )

        for record in records {
            if incomingMessageAuthor == nil, let outgoingMessage = try TSInteraction.fromRecord(record) as? TSOutgoingMessage {
                return outgoingMessage
            }

            if
                let incomingMessage = try TSInteraction.fromRecord(record) as? TSIncomingMessage,
                let authorUUID = incomingMessage.authorUUID,
                try ServiceId.parseFrom(serviceIdString: authorUUID) == incomingMessageAuthor
            {
                return incomingMessage
            }
        }
        return nil
    }
}

// MARK: -

#if TESTABLE_BUILD

open class MockInteractionStore: InteractionStore {

    var insertedInteractions = [TSInteraction]()

    // MARK: -

    public func exists(uniqueId: String, tx: DBReadTransaction) -> Bool {
        return insertedInteractions.contains { $0.uniqueId == uniqueId }
    }

    open func fetchInteraction(
        rowId interactionRowId: Int64,
        tx: DBReadTransaction,
    ) -> TSInteraction? {
        return insertedInteractions.first(where: { $0.sqliteRowId == interactionRowId })
    }

    public func fetchInteraction(uniqueId: String, tx: DBReadTransaction) -> TSInteraction? {
        return insertedInteractions.first(where: { $0.uniqueId == uniqueId })
    }

    public func findMessage(
        withTimestamp timestamp: UInt64,
        threadId: String,
        author: SignalServiceAddress,
        tx: DBReadTransaction,
    ) -> TSMessage? {
        return insertedInteractions
            .lazy
            .filter { $0.uniqueThreadId == threadId }
            .compactMap { $0 as? TSMessage }
            .filter { message in
                if
                    let incomingMessage = message as? TSIncomingMessage,
                    incomingMessage.authorAddress.isEqualToAddress(author)
                {
                    return true
                }

                if
                    message is TSOutgoingMessage,
                    author.isLocalAddress
                {
                    return true
                }
                return false
            }
            .first
    }

    public func fetchInteractions(
        timestamp: UInt64,
        tx: DBReadTransaction,
    ) throws -> [TSInteraction] {
        return insertedInteractions.filter { $0.timestamp == timestamp }
    }

    open func fetchCursor(
        minRowIdExclusive: Int64?,
        maxRowIdInclusive: Int64?,
        tx: DBReadTransaction,
    ) throws -> AnyCursor<TSInteraction> {
        let filtered = insertedInteractions.lazy
            .filter { interaction in
                guard let rowId = interaction.sqliteRowId else { return false }
                if let minRowIdExclusive, rowId <= minRowIdExclusive {
                    return false
                }
                if let maxRowIdInclusive, rowId > maxRowIdInclusive {
                    return false
                }
                return true
            }
            .sorted(by: { lhs, rhs in
                return lhs.sqliteRowId! < rhs.sqliteRowId!
            })

        class Iterator: IteratorProtocol {
            var index = 0
            var array: [TSInteraction]

            init(index: Int = 0, array: [TSInteraction]) {
                self.index = index
                self.array = array
            }

            func next() -> TSInteraction? {
                guard index < array.count else {
                    return nil
                }
                defer { index += 1 }
                return array[index]
            }

            typealias Element = TSInteraction
        }

        return AnyCursor(iterator: Iterator(array: filtered))
    }

    open func insertedMessageHasRenderableContent(
        message: TSMessage,
        rowId: Int64,
        tx: DBReadTransaction,
    ) -> Bool {
        return true
    }

    // MARK: -

    open func insertInteraction(_ interaction: TSInteraction, tx: DBWriteTransaction) {
        interaction.updateRowId(.random(in: 0...Int64.max))
        insertedInteractions.append(interaction)
    }

    open func deleteInteraction(_ interaction: TSInteraction, tx: DBWriteTransaction) {
        _ = insertedInteractions.removeFirst { $0.sqliteRowId! == interaction.sqliteRowId! }
    }

    open func update(
        _ message: TSMessage,
        with quotedMessage: TSQuotedMessage,
        tx: DBWriteTransaction,
    ) {}

    public func update(
        _ message: TSMessage,
        with linkPreview: OWSLinkPreview,
        tx: DBWriteTransaction,
    ) {}

    public func update(
        _ message: TSMessage,
        with contact: OWSContact,
        tx: DBWriteTransaction,
    ) {}

    public func update(
        _ message: TSMessage,
        with sticker: MessageSticker,
        tx: DBWriteTransaction,
    ) {}

    open func updateInteraction<InteractionType: TSInteraction>(
        _ interaction: InteractionType,
        tx: DBWriteTransaction,
        block: (InteractionType) -> Void,
    ) {
        block(interaction)
    }

    // MARK: -

    open func buildOutgoingMessage(
        builder: TSOutgoingMessageBuilder,
        tx: DBReadTransaction,
    ) -> TSOutgoingMessage {
        // Override in a subclass if you want recipient states populated.
        return TSOutgoingMessage(
            outgoingMessageWith: builder,
            recipientAddressStates: [:],
        )
    }

    public func buildOutgoingArchivedPaymentMessage(
        builder: TSOutgoingMessageBuilder,
        amount: String?,
        fee: String?,
        note: String?,
        tx: DBReadTransaction,
    ) -> OWSOutgoingArchivedPaymentMessage {
        owsFail("Not implemented, because this message type really needs an DBReadTransaction to be initialized, and at the time of writing no caller cares.")
    }

    open func insertOrReplacePlaceholder(
        for interaction: TSInteraction,
        from sender: SignalServiceAddress,
        tx: DBWriteTransaction,
    ) {
        // Do nothing
    }

    // MARK: - TSOutgoingMessage state updates

    open func updateRecipientsFromNonLocalDevice(
        _ message: TSOutgoingMessage,
        recipientStates: [SignalServiceAddress: TSOutgoingMessageRecipientState],
        isSentUpdate: Bool,
        tx: DBWriteTransaction,
    ) {
        // Unimplemented
    }

    public func fetchMessage(
        timestamp: UInt64,
        incomingMessageAuthor: Aci?,
        transaction: DBReadTransaction,
    ) throws -> TSMessage? {
        // Unimplemented
        return nil
    }
}

#endif
