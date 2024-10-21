//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB
import LibSignalClient

public protocol InteractionStore {

    // MARK: - 

    /// Whether an interaction exists with the given unique ID.
    func exists(uniqueId: String, tx: DBReadTransaction) -> Bool

    /// Fetch the unique IDs of all interactions.
    func fetchAllUniqueIds(tx: DBReadTransaction) -> [String]

    /// Fetch the interaction with the given SQLite row ID, if one exists.
    func fetchInteraction(
        rowId interactionRowId: Int64,
        tx: DBReadTransaction
    ) -> TSInteraction?

    func fetchInteraction(
        uniqueId: String,
        tx: DBReadTransaction
    ) -> TSInteraction?

    func findMessage(
        withTimestamp timestamp: UInt64,
        threadId: String,
        author: SignalServiceAddress,
        tx: DBReadTransaction
    ) -> TSMessage?

    func interactions(
        withTimestamp timestamp: UInt64,
        tx: DBReadTransaction
    ) throws -> [TSInteraction]

    /// Enumerate all interactions.
    ///
    /// - Parameter block
    /// A block executed for each enumerated interaction. Returns `true` if
    /// enumeration should continue, and `false` otherwise.
    func enumerateAllInteractions(
        tx: DBReadTransaction,
        block: (TSInteraction) throws -> Bool
    ) throws

    func fetchCursor(
        minRowIdExclusive: Int64?,
        maxRowIdInclusive: Int64?,
        tx: DBReadTransaction
    ) throws -> AnyCursor<TSInteraction>

    func insertedMessageHasRenderableContent(
        message: TSMessage,
        rowId: Int64,
        tx: DBReadTransaction
    ) -> Bool

    // MARK: -

    /// Insert the given interaction to the databse.
    func insertInteraction(_ interaction: TSInteraction, tx: DBWriteTransaction)

    /// Applies the given block to the given already-inserted interaction, and
    /// saves the updated interaction to the database.
    func updateInteraction<InteractionType: TSInteraction>(
        _ interaction: InteractionType,
        tx: DBWriteTransaction,
        block: (InteractionType) -> Void
    )

    // MARK: -

    func buildOutgoingMessage(
        builder: TSOutgoingMessageBuilder,
        tx: DBReadTransaction
    ) -> TSOutgoingMessage

    func buildOutgoingArchivedPaymentMessage(
        builder: TSOutgoingMessageBuilder,
        amount: String?,
        fee: String?,
        note: String?,
        tx: DBReadTransaction
    ) -> OWSOutgoingArchivedPaymentMessage

    func insertOrReplacePlaceholder(
        for interaction: TSInteraction,
        from sender: SignalServiceAddress,
        tx: DBWriteTransaction
    )

    // MARK: - TSOutgoingMessage state updates

    func updateRecipientsFromNonLocalDevice(
        _ message: TSOutgoingMessage,
        recipientStates: [SignalServiceAddress: TSOutgoingMessageRecipientState],
        isSentUpdate: Bool,
        tx: DBWriteTransaction
    )
}

// MARK: -

public class InteractionStoreImpl: InteractionStore {

    public init() {}

    // MARK: -

    public func exists(uniqueId: String, tx: any DBReadTransaction) -> Bool {
        return TSInteraction.anyExists(uniqueId: uniqueId, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func fetchAllUniqueIds(tx: any DBReadTransaction) -> [String] {
        return TSInteraction.anyAllUniqueIds(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func fetchInteraction(
        rowId interactionRowId: Int64,
        tx: DBReadTransaction
    ) -> TSInteraction? {
        return InteractionFinder.fetch(
            rowId: interactionRowId, transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func fetchInteraction(
        uniqueId: String,
        tx: DBReadTransaction
    ) -> TSInteraction? {
        return TSInteraction.anyFetch(uniqueId: uniqueId, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func findMessage(
        withTimestamp timestamp: UInt64,
        threadId: String,
        author: SignalServiceAddress,
        tx: DBReadTransaction
    ) -> TSMessage? {
        return InteractionFinder.findMessage(
            withTimestamp: timestamp,
            threadId: threadId,
            author: author,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func interactions(
        withTimestamp timestamp: UInt64,
        tx: DBReadTransaction
    ) throws -> [TSInteraction] {
        return try InteractionFinder.interactions(
            withTimestamp: timestamp,
            filter: { _ in true },
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func enumerateAllInteractions(
        tx: DBReadTransaction,
        block: (TSInteraction) throws -> Bool
    ) throws {
        let cursor = TSInteraction.grdbFetchCursor(
            transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
        )

        while
            let interaction = try cursor.next(),
            try block(interaction)
        {}
    }

    public func fetchCursor(
        minRowIdExclusive: Int64?,
        maxRowIdInclusive: Int64?,
        tx: DBReadTransaction
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
        let cursor = try query.fetchCursor(tx.databaseConnection)
            .map(TSInteraction.fromRecord(_:))
        return AnyCursor(cursor)
    }

    public func insertedMessageHasRenderableContent(
        message: TSMessage,
        rowId: Int64,
        tx: DBReadTransaction
    ) -> Bool {
        return message.insertedMessageHasRenderableContent(rowId: rowId, tx: SDSDB.shimOnlyBridge(tx))
    }

    // MARK: -

    public func insertInteraction(_ interaction: TSInteraction, tx: DBWriteTransaction) {
        interaction.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func updateInteraction<InteractionType: TSInteraction>(
        _ interaction: InteractionType,
        tx: DBWriteTransaction,
        block: (InteractionType) -> Void
    ) {
        interaction.anyUpdate(transaction: SDSDB.shimOnlyBridge(tx)) { interaction in
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
        tx: DBReadTransaction
    ) -> TSOutgoingMessage {
        return TSOutgoingMessage(
            outgoingMessageWith: builder,
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func buildOutgoingArchivedPaymentMessage(
        builder: TSOutgoingMessageBuilder,
        amount: String?,
        fee: String?,
        note: String?,
        tx: DBReadTransaction
    ) -> OWSOutgoingArchivedPaymentMessage {
        return OWSOutgoingArchivedPaymentMessage(
            outgoingArchivedPaymentMessageWith: builder,
            amount: amount,
            fee: fee,
            note: note,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func insertOrReplacePlaceholder(
        for interaction: TSInteraction,
        from sender: SignalServiceAddress,
        tx: DBWriteTransaction
    ) {
        interaction.insertOrReplacePlaceholder(from: sender, transaction: SDSDB.shimOnlyBridge(tx))
    }

    // MARK: - TSOutgoingMessage state updates

    public func updateRecipientsFromNonLocalDevice(
        _ message: TSOutgoingMessage,
        recipientStates: [SignalServiceAddress: TSOutgoingMessageRecipientState],
        isSentUpdate: Bool,
        tx: DBWriteTransaction
    ) {
        message.updateRecipientsFromNonLocalDevice(
            recipientStates,
            isSentUpdate: isSentUpdate,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }
}

// MARK: -

#if TESTABLE_BUILD

open class MockInteractionStore: InteractionStore {

    var insertedInteractions = [TSInteraction]()

    // MARK: -

    public func exists(uniqueId: String, tx: any DBReadTransaction) -> Bool {
        return insertedInteractions.contains { $0.uniqueId == uniqueId }
    }

    public func fetchAllUniqueIds(tx: any DBReadTransaction) -> [String] {
        return insertedInteractions.map { $0.uniqueId }
    }

    open func fetchInteraction(
        rowId interactionRowId: Int64,
        tx: DBReadTransaction
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
        tx: DBReadTransaction
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

    public func interactions(
        withTimestamp timestamp: UInt64,
        tx: DBReadTransaction
    ) throws -> [TSInteraction] {
        return insertedInteractions.filter { $0.timestamp == timestamp }
    }

    open func enumerateAllInteractions(
        tx: DBReadTransaction,
        block: (TSInteraction) throws -> Bool
    ) throws {
        for interaction in insertedInteractions {
            if !(try block(interaction)) {
                return
            }
        }
    }

    open func fetchCursor(
        minRowIdExclusive: Int64?,
        maxRowIdInclusive: Int64?,
        tx: DBReadTransaction
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
        tx: DBReadTransaction
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
        tx: DBWriteTransaction
    ) {}

    public func update(
        _ message: TSMessage,
        with linkPreview: OWSLinkPreview,
        tx: DBWriteTransaction
    ) {}

    public func update(
        _ message: TSMessage,
        with contact: OWSContact,
        tx: DBWriteTransaction
    ) {}

    public func update(
        _ message: TSMessage,
        with sticker: MessageSticker,
        tx: DBWriteTransaction
    ) {}

    open func updateInteraction<InteractionType: TSInteraction>(
        _ interaction: InteractionType,
        tx: DBWriteTransaction,
        block: (InteractionType) -> Void
    ) {
        block(interaction)
    }

    // MARK: -

    open func buildOutgoingMessage(
        builder: TSOutgoingMessageBuilder,
        tx: DBReadTransaction
    ) -> TSOutgoingMessage {
        // Override in a subclass if you want recipient states populated.
        return TSOutgoingMessage(
            outgoingMessageWith: builder,
            recipientAddressStates: [:]
        )
    }

    public func buildOutgoingArchivedPaymentMessage(
        builder: TSOutgoingMessageBuilder,
        amount: String?,
        fee: String?,
        note: String?,
        tx: DBReadTransaction
    ) -> OWSOutgoingArchivedPaymentMessage {
        owsFail("Not implemented, because this message type really needs an SDSAnyReadTransaction to be initialized, and at the time of writing no caller cares.")
    }

    open func insertOrReplacePlaceholder(
        for interaction: TSInteraction,
        from sender: SignalServiceAddress,
        tx: DBWriteTransaction
    ) {
        // Do nothing
    }

    // MARK: - TSOutgoingMessage state updates

    open func updateRecipientsFromNonLocalDevice(
        _ message: TSOutgoingMessage,
        recipientStates: [SignalServiceAddress: TSOutgoingMessageRecipientState],
        isSentUpdate: Bool,
        tx: DBWriteTransaction
    ) {
        // Unimplemented
    }
}

#endif
