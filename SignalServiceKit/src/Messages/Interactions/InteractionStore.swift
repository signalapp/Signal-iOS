//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public protocol InteractionStore {

    // MARK: - 

    /// Fetch the interaction with the given SQLite row ID, if one exists.
    func fetchInteraction(
        rowId interactionRowId: Int64,
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

    func enumerateAllInteractions(
        tx: DBReadTransaction,
        block: @escaping (TSInteraction, _ stop: inout Bool) -> Void
    ) throws

    // MARK: -

    /// Insert the given interaction to the databse.
    func insertInteraction(_ interaction: TSInteraction, tx: DBWriteTransaction)

    /// Deletes the given interaction from the database.
    func deleteInteraction(_ interaction: TSInteraction, tx: DBWriteTransaction)

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

    func insertOrReplacePlaceholder(
        for interaction: TSInteraction,
        from sender: SignalServiceAddress,
        tx: DBWriteTransaction
    )

    func updateAttachmentIds(
        _ attachmentIds: [String],
        for outgoingMessage: TSOutgoingMessage,
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

    public func fetchInteraction(
        rowId interactionRowId: Int64,
        tx: DBReadTransaction
    ) -> TSInteraction? {
        return InteractionFinder.fetch(
            rowId: interactionRowId, transaction: SDSDB.shimOnlyBridge(tx)
        )
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
        block: @escaping (TSInteraction, _ stop: inout Bool) -> Void
    ) throws {
        let cursor = TSInteraction.grdbFetchCursor(
            transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
        )

        var stop = false
        while let interaction = try cursor.next() {
            block(interaction, &stop)
            if stop {
                break
            }
        }
    }

    // MARK: -

    public func insertInteraction(_ interaction: TSInteraction, tx: DBWriteTransaction) {
        interaction.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func deleteInteraction(_ interaction: TSInteraction, tx: DBWriteTransaction) {
        interaction.anyRemove(transaction: SDSDB.shimOnlyBridge(tx))
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

    // MARK: 

    public func buildOutgoingMessage(
        builder: TSOutgoingMessageBuilder,
        tx: DBReadTransaction
    ) -> TSOutgoingMessage {
        return TSOutgoingMessage(
            outgoingMessageWithBuilder: builder,
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

    public func updateAttachmentIds(
        _ attachmentIds: [String],
        for outgoingMessage: TSOutgoingMessage,
        tx: DBWriteTransaction
    ) {
        outgoingMessage.anyUpdateOutgoingMessage(transaction: SDSDB.shimOnlyBridge(tx)) {
            $0.attachmentIds = attachmentIds
        }
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

    open func fetchInteraction(
        rowId interactionRowId: Int64,
        tx: DBReadTransaction
    ) -> TSInteraction? {
        return insertedInteractions.first(where: { $0.sqliteRowId == interactionRowId })
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
        block: @escaping (TSInteraction, _ stop: inout Bool) -> Void
    ) throws {
        var stop = false
        for interaction in insertedInteractions {
            block(interaction, &stop)
            if stop {
                break
            }
        }
    }

    // MARK: -

    open func insertInteraction(_ interaction: TSInteraction, tx: DBWriteTransaction) {
        interaction.updateRowId(.random(in: 0...Int64.max))
        insertedInteractions.append(interaction)
    }

    open func deleteInteraction(_ interaction: TSInteraction, tx: DBWriteTransaction) {
        _ = insertedInteractions.removeFirst { $0.sqliteRowId! == interaction.sqliteRowId! }
    }

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
        // Override in a subclass if you want more detailed instantiation.
        return TSOutgoingMessage(
            in: builder.thread,
            messageBody: builder.messageBody,
            attachmentId: builder.attachmentIds.first
        )
    }

    open func insertOrReplacePlaceholder(
        for interaction: TSInteraction,
        from sender: SignalServiceAddress,
        tx: DBWriteTransaction
    ) {
        // Do nothing
    }

    public func updateAttachmentIds(
        _ attachmentIds: [String],
        for outgoingMessage: TSOutgoingMessage,
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
