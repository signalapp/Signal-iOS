//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// This needs to reflect the edit as represented (and sourced) from the db.
@objc
public class OutgoingEditMessage: TSOutgoingMessage {

    // MARK: - Edit target data

    @objc
    private(set) var editedMessage: TSOutgoingMessage

    @objc
    private(set) var targetMessageTimestamp: UInt64 = 0

    // MARK: - Overrides

    @objc
    public override var isUrgent: Bool { false }

    @objc
    public override var shouldBeSaved: Bool { false }

    @objc
    public override var debugDescription: String { "editMessage" }

    @objc
    override var shouldRecordSendLog: Bool { true }

    @objc
    override var contentHint: SealedSenderContentHint { .implicit }

    // MARK: - Initialization

    @objc
    public init(
        thread: TSThread,
        targetMessageTimestamp: UInt64,
        editMessage: TSOutgoingMessage,
        transaction: SDSAnyReadTransaction) {
        self.targetMessageTimestamp = targetMessageTimestamp
        self.editedMessage = editMessage

        let builder = TSOutgoingMessageBuilder(thread: thread)
        super.init(outgoingMessageWithBuilder: builder, transaction: transaction)
    }

    /// Note on `init?(coder:)` and `init(dictionary:)`: Both are implemented as seeming
    /// no-ops here and initialize `editMessage` to an empty value. However, these methods
    /// are subtly important.
    ///
    /// 1. `OutgoingEditMessage` is a subclass of `TSOutgoingMessage`, which is in turn,
    ///   an ancestor of `MTLModel`.  `MTLModel` uses  both of these methods to provide
    ///   reflection based encoding/decoding of it's subclasses, which is used when serializing
    ///   messages into the MessageSendingQueue
    ///
    /// 2. Since this is Swift, once a custom initializer is added, Swift requires implementing any
    ///   required initializers.
    ///
    /// So, long story short, these empty methods keep the compiler happy, while allowing the
    /// `MTLModel` base class to properly serialize `OutgoingEditMessage` and all it's
    /// inherited properties
    @objc
    required init?(coder: NSCoder) {
        // Placeholder message to appease the compiler.  The message
        do {
            self.editedMessage = try TSOutgoingMessage(dictionary: [:])
        } catch {
            owsFailDebug("Failed to create placeholder message")
            return nil
        }

        super.init(coder: coder)
    }

    @objc
    required init(dictionary dictionaryValue: [String: Any]!) throws {

        do {
            self.editedMessage = try TSOutgoingMessage(dictionary: [:])
        } catch {
            owsFailDebug("Failed to create placeholder message")
            throw error
        }

        try super.init(dictionary: dictionaryValue)
    }

    // MARK: - Builders

    public override func contentBuilder(
        thread: TSThread,
        transaction: SDSAnyReadTransaction
    ) -> SSKProtoContentBuilder? {

        let editBuilder = SSKProtoEditMessage.builder()
        let contentBuilder = SSKProtoContent.builder()

        guard let targetDataMessageBuilder = editedMessage.dataMessageBuilder(
            with: thread,
            transaction: transaction
        ) else {
            owsFailDebug("failed to build outgoing edit data message")
            return nil
        }

        do {
            editBuilder.setDataMessage(try targetDataMessageBuilder.build())
            editBuilder.setTargetSentTimestamp(self.targetMessageTimestamp)

            contentBuilder.setEditMessage(try editBuilder.build())

            return contentBuilder
        } catch {
            owsFailDebug("failed to build protobuf: \(error)")
            return nil
        }
    }

    public override func dataMessageBuilder(
        with thread: TSThread,
        transaction: SDSAnyReadTransaction
    ) -> SSKProtoDataMessageBuilder? {
        editedMessage.dataMessageBuilder(
            with: thread,
            transaction: transaction
        )
    }

    public override func buildTranscriptSyncMessage(
        localThread: TSThread,
        transaction: SDSAnyWriteTransaction
    ) -> OWSOutgoingSyncMessage? {
        guard let thread = thread(tx: transaction) else {
            owsFailDebug("Missing thread for interaction.")
            return nil
        }

        let transcript = OutgoingEditMessageSyncTranscript(
            localThread: localThread,
            messageThread: thread,
            outgoingMessage: self,
            isRecipientUpdate: false,
            transaction: transaction
        )
        return transcript
    }

    /// This override is required to properly update the correct interaction row when delivery
    /// receipts are processed.   Without this, the deliviery is registered against the
    /// OutgoingEditMessage, which doesn't have a backing entry in the interactions table.
    /// Instead, when updating this message, ensure that the `recipientAddressStates` are
    /// in sync between the OutgoingEditMesasge and it's wrapped TSOutgoingMessage
    public override func anyUpdateOutgoingMessage(
        transaction: SDSAnyWriteTransaction,
        block: (TSOutgoingMessage) -> Void
    ) {
        super.anyUpdateOutgoingMessage(transaction: transaction, block: block)

        if let editedMessage = TSOutgoingMessage.anyFetchOutgoingMessage(
            uniqueId: editedMessage.uniqueId,
            transaction: transaction
        ) {
            editedMessage .updateWith(
                recipientAddressStates: self.recipientAddressStates,
                transaction: transaction
            )
        }
    }
}
