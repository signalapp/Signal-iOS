//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol InteractionStore {
    /// Fetch the interaction with the given SQLite row ID, if one exists.
    func fetchInteraction(
        rowId interactionRowId: Int64,
        tx: DBReadTransaction
    ) -> TSInteraction?

    /// Insert the given interaction to the databse.
    func insertInteraction(_ interaction: TSInteraction, tx: DBWriteTransaction)

    func buildOutgoingMessage(builder: TSOutgoingMessageBuilder, tx: DBReadTransaction) -> TSOutgoingMessage

    /// Applies the given block to the given already-inserted interaction, and
    /// saves the updated interaction to the database.
    func updateInteraction<InteractionType: TSInteraction>(
        _ interaction: InteractionType,
        tx: DBWriteTransaction,
        block: (InteractionType) -> Void
    )

    func enumerateAllInteractions(
        tx: DBReadTransaction,
        block: @escaping (TSInteraction, _ stop: inout Bool) -> Void
    ) throws

    // MARK: - TSOutgoingMessage state updates

    func update(
        _ message: TSOutgoingMessage,
        withFailedRecipient: SignalServiceAddress,
        error: Error,
        tx: DBWriteTransaction
    )

    func update(
        _ message: TSOutgoingMessage,
        withSentRecipientAddress: SignalServiceAddress,
        wasSentByUD: Bool,
        tx: DBWriteTransaction
    )

    func update(
        _ message: TSOutgoingMessage,
        withDeliveredRecipient: SignalServiceAddress,
        deviceId: UInt32,
        deliveryTimestamp: UInt64,
        context: DeliveryReceiptContext,
        tx: DBWriteTransaction
    )

    func update(
        _ message: TSOutgoingMessage,
        withReadRecipient: SignalServiceAddress,
        deviceId: UInt32,
        readTimestamp: UInt64,
        tx: DBWriteTransaction
    )

    func update(
        _ message: TSOutgoingMessage,
        withViewedRecipient: SignalServiceAddress,
        deviceId: UInt32,
        viewedTimestamp: UInt64,
        tx: DBWriteTransaction
    )

    func update(
        _ message: TSOutgoingMessage,
        withSkippedRecipient: SignalServiceAddress,
        tx: DBWriteTransaction
    )
}

public class InteractionStoreImpl: InteractionStore {

    public init() {}

    public func fetchInteraction(
        rowId interactionRowId: Int64,
        tx: DBReadTransaction
    ) -> TSInteraction? {
        return InteractionFinder.fetch(
            rowId: interactionRowId, transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func insertInteraction(_ interaction: TSInteraction, tx: DBWriteTransaction) {
        interaction.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func buildOutgoingMessage(builder: TSOutgoingMessageBuilder, tx: DBReadTransaction) -> TSOutgoingMessage {
        return TSOutgoingMessage.init(outgoingMessageWithBuilder: builder, transaction: SDSDB.shimOnlyBridge(tx))
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

    // MARK: - TSOutgoingMessage state updates

    public func update(
        _ message: TSOutgoingMessage,
        withFailedRecipient: SignalServiceAddress,
        error: Error,
        tx: DBWriteTransaction
    ) {
        message.update(withFailedRecipient: withFailedRecipient, error: error, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func update(
        _ message: TSOutgoingMessage,
        withSentRecipientAddress: SignalServiceAddress,
        wasSentByUD: Bool,
        tx: DBWriteTransaction
    ) {
        message.update(withSentRecipientAddress: withSentRecipientAddress, wasSentByUD: wasSentByUD, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func update(
        _ message: TSOutgoingMessage,
        withDeliveredRecipient: SignalServiceAddress,
        deviceId: UInt32,
        deliveryTimestamp: UInt64,
        context: DeliveryReceiptContext,
        tx: DBWriteTransaction
    ) {
        message.update(
            withDeliveredRecipient: withDeliveredRecipient,
            deviceId: deviceId,
            deliveryTimestamp: deliveryTimestamp,
            context: context,
            tx: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func update(
        _ message: TSOutgoingMessage,
        withReadRecipient: SignalServiceAddress,
        deviceId: UInt32,
        readTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        message.update(withReadRecipient: withReadRecipient, deviceId: deviceId, readTimestamp: readTimestamp, tx: SDSDB.shimOnlyBridge(tx))
    }

    public func update(
        _ message: TSOutgoingMessage,
        withViewedRecipient: SignalServiceAddress,
        deviceId: UInt32,
        viewedTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        message.update(
            withViewedRecipient: withViewedRecipient,
            deviceId: deviceId,
            viewedTimestamp: viewedTimestamp,
            tx: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func update(
        _ message: TSOutgoingMessage,
        withSkippedRecipient: SignalServiceAddress,
        tx: DBWriteTransaction
    ) {
        message.update(withSkippedRecipient: withSkippedRecipient, transaction: SDSDB.shimOnlyBridge(tx))
    }
}

#if TESTABLE_BUILD

open class MockInteractionStore: InteractionStore {
    var insertedInteractions = [TSInteraction]()

    open func fetchInteraction(
        rowId interactionRowId: Int64,
        tx: DBReadTransaction
    ) -> TSInteraction? {
        return insertedInteractions.first(where: { $0.sqliteRowId == interactionRowId })
    }

    open func insertInteraction(_ interaction: TSInteraction, tx: DBWriteTransaction) {
        interaction.updateRowId(.random(in: 0...Int64.max))
        insertedInteractions.append(interaction)
    }

    open func buildOutgoingMessage(builder: TSOutgoingMessageBuilder, tx: DBReadTransaction) -> TSOutgoingMessage {
        // Override in a subclass if you want more detailed instantiation.
        return TSOutgoingMessage(in: builder.thread, messageBody: builder.messageBody, attachmentId: builder.attachmentIds.first)
    }

    open func updateInteraction<InteractionType: TSInteraction>(
        _ interaction: InteractionType,
        tx: DBWriteTransaction,
        block: (InteractionType) -> Void
    ) {
        block(interaction)
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

    // MARK: - TSOutgoingMessage state updates

    open func update(
        _ message: TSOutgoingMessage,
        withFailedRecipient: SignalServiceAddress,
        error: Error,
        tx: DBWriteTransaction
    ) {
        // Unimplemented
    }

    open func update(
        _ message: TSOutgoingMessage,
        withSentRecipientAddress: SignalServiceAddress,
        wasSentByUD: Bool,
        tx: DBWriteTransaction
    ) {
        // Unimplemented
    }

    open func update(
        _ message: TSOutgoingMessage,
        withDeliveredRecipient: SignalServiceAddress,
        deviceId: UInt32,
        deliveryTimestamp: UInt64,
        context: DeliveryReceiptContext,
        tx: DBWriteTransaction
    ) {
        // Unimplemented
    }

    open func update(
        _ message: TSOutgoingMessage,
        withReadRecipient: SignalServiceAddress,
        deviceId: UInt32,
        readTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        // Unimplemented
    }

    open func update(
        _ message: TSOutgoingMessage,
        withViewedRecipient: SignalServiceAddress,
        deviceId: UInt32,
        viewedTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        // Unimplemented
    }

    open func update(
        _ message: TSOutgoingMessage,
        withSkippedRecipient: SignalServiceAddress,
        tx: DBWriteTransaction
    ) {
        // Unimplemented
    }
}

#endif
