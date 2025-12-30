//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// This needs to reflect the edit as represented (and sourced) from the db.
@objc
public final class OutgoingEditMessage: TSOutgoingMessage {
    public required init?(coder: NSCoder) {
        self.editedMessage = coder.decodeObject(of: TSOutgoingMessage.self, forKey: "editedMessage")
        self.targetMessageTimestamp = coder.decodeObject(of: NSNumber.self, forKey: "targetMessageTimestamp")?.uint64Value ?? 0
        super.init(coder: coder)
    }

    override public func encode(with coder: NSCoder) {
        super.encode(with: coder)
        if let editedMessage {
            coder.encode(editedMessage, forKey: "editedMessage")
        }
        coder.encode(NSNumber(value: self.targetMessageTimestamp), forKey: "targetMessageTimestamp")
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(editedMessage)
        hasher.combine(targetMessageTimestamp)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.editedMessage == object.editedMessage else { return false }
        guard self.targetMessageTimestamp == object.targetMessageTimestamp else { return false }
        return true
    }

    override public func copy(with zone: NSZone? = nil) -> Any {
        let result = super.copy(with: zone) as! Self
        result.editedMessage = self.editedMessage
        result.targetMessageTimestamp = self.targetMessageTimestamp
        return result
    }

    // MARK: - Edit target data

    @objc
    private(set) var editedMessage: TSOutgoingMessage?

    @objc
    private(set) var targetMessageTimestamp: UInt64 = 0

    // MARK: - Overrides

    @objc
    override public var shouldBeSaved: Bool { false }

    @objc
    override public var debugDescription: String { "editMessage" }

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
        transaction: DBReadTransaction,
    ) {
        self.targetMessageTimestamp = targetMessageTimestamp
        self.editedMessage = editMessage

        let builder: TSOutgoingMessageBuilder = .withDefaultValues(
            thread: thread,
            timestamp: editMessage.timestamp,
        )
        super.init(
            outgoingMessageWith: builder,
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: transaction,
        )
    }

    // MARK: - Builders

    override public func contentBuilder(
        thread: TSThread,
        transaction tx: DBReadTransaction,
    ) -> SSKProtoContentBuilder? {

        let editBuilder = SSKProtoEditMessage.builder()
        let contentBuilder = SSKProtoContent.builder()

        guard
            let editedMessage,
            let targetDataMessageBuilder = editedMessage.dataMessageBuilder(with: thread, transaction: tx)
        else {
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

    override public func dataMessageBuilder(
        with thread: TSThread,
        transaction: DBReadTransaction,
    ) -> SSKProtoDataMessageBuilder? {
        return editedMessage?.dataMessageBuilder(
            with: thread,
            transaction: transaction,
        )
    }

    override public func buildTranscriptSyncMessage(
        localThread: TSContactThread,
        transaction: DBWriteTransaction,
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
            transaction: transaction,
        )
        return transcript
    }

    /// This override is required to properly update the correct interaction row
    /// when delivery receipts are processed. Without this, the delivery is
    /// registered against the OutgoingEditMessage, which doesn't have a backing
    /// entry in the interactions table. Instead, when updating this message,
    /// ensure that the `recipientAddressStates` are in sync between the
    /// OutgoingEditMessage and its wrapped TSOutgoingMessage.
    override public func anyUpdateOutgoingMessage(
        transaction tx: DBWriteTransaction,
        block: (TSOutgoingMessage) -> Void,
    ) {
        super.anyUpdateOutgoingMessage(transaction: tx, block: block)

        if
            let editedMessage,
            let editedMessage = TSOutgoingMessage.anyFetchOutgoingMessage(uniqueId: editedMessage.uniqueId, transaction: tx)
        {
            editedMessage.anyUpdateOutgoingMessage(transaction: tx, block: block)
        }
    }
}
