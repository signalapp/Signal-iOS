//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Wraps a TSOutgoingMessage that is unprepared for sending;
/// it hasn't been inserted, its attachments haven't been inserted, nothing.
///
/// Just a wrapper for the message object and metadata needed
/// to prepare for sending.
public class UnpreparedOutgoingMessage {

    // MARK: - Constructors

    public static func forMessage(
        _ message: TSOutgoingMessage,
        unsavedBodyMediaAttachments: [AttachmentDataSource] = [],
        oversizeTextDataSource: AttachmentDataSource? = nil,
        linkPreviewDraft: LinkPreviewDataSource? = nil,
        quotedReplyDraft: DraftQuotedReplyModel.ForSending? = nil,
        messageStickerDraft: MessageStickerDataSource? = nil,
        contactShareDraft: ContactShareDraft.ForSending? = nil
    ) -> UnpreparedOutgoingMessage {
        if !message.shouldBeSaved {
            owsAssertDebug(
                unsavedBodyMediaAttachments.isEmpty
                && oversizeTextDataSource == nil
                && linkPreviewDraft != nil
                && quotedReplyDraft != nil
                && messageStickerDraft != nil,
                "Unknown unsaved message sent through saved path with attachments!"
            )
            Self.assertIsAllowedTransientMessage(message)
            return .init(messageType: .transient(message))
        } else {
            return .init(messageType: .persistable(.init(
                message: message,
                unsavedBodyMediaAttachments: unsavedBodyMediaAttachments,
                oversizeTextDataSource: oversizeTextDataSource,
                linkPreviewDraft: linkPreviewDraft,
                quotedReplyDraft: quotedReplyDraft,
                messageStickerDraft: messageStickerDraft,
                contactShareDraft: contactShareDraft
            )))
        }
    }

    public static func forEditMessage(
        targetMessage: TSOutgoingMessage,
        edits: MessageEdits,
        oversizeTextDataSource: AttachmentDataSource?,
        linkPreviewDraft: LinkPreviewDataSource?,
        quotedReplyEdit: MessageEdits.Edit<Void>
    ) -> UnpreparedOutgoingMessage {
        return .init(messageType: .editMessage(.init(
            targetMessage: targetMessage,
            edits: edits,
            oversizeTextDataSource: oversizeTextDataSource,
            linkPreviewDraft: linkPreviewDraft,
            quotedReplyEdit: quotedReplyEdit
        )))
    }

    public static func forContactSync(
        _ contactSyncMessage: OWSSyncContactsMessage
    ) -> UnpreparedOutgoingMessage {
        return .init(messageType: .contactSync(contactSyncMessage))
    }

    public static func forOutgoingStoryMessage(
        _ message: OutgoingStoryMessage,
        storyMessageRowId: Int64
    ) -> UnpreparedOutgoingMessage {
        return .init(messageType: .story(.init(
            message: message,
            storyMessageRowId: storyMessageRowId
        )))
    }

    // MARK: - Preparation

    /// "Prepares" the outgoing message, inserting it into the database if needed and
    /// returning a ``PreparedOutgoingMessage`` ready to be sent.
    public func prepare(
        tx: SDSAnyWriteTransaction
    ) throws -> PreparedOutgoingMessage {
        return try self._prepare(tx: tx)
    }

    public var messageTimestampForLogging: UInt64 {
        switch messageType {
        case .persistable(let message):
            return message.message.timestamp
        case .editMessage(let message):
            return message.edits.timestamp.unwrapChange(
                orKeepValue: message.targetMessage.timestamp
            )
        case .contactSync(let message):
            return message.timestamp
        case .story(let story):
            return story.message.timestamp
        case .transient(let message):
            return message.timestamp
        }
    }

    // MARK: - Private

    private enum MessageType {

        /// The message that will be inserted into the Interaction table before sending.
        case persistable(Persistable)

        /// An edit for an existing message; persisted to the Interaction table, but as an edit.
        case editMessage(EditMessage)

        /// A contact sync message that is not inserted into the Interactions table.
        /// It has an attachment, but that attachment is never persisted as an Attachment
        /// in the database; it is simply in memory and already uploaded.
        case contactSync(OWSSyncContactsMessage)

        /// An OutgoingStoryMessage: a TSMessage subclass we use for sending a ``StoryMessage``
        /// The StoryMessage is persisted to the StoryMessages table and is the owner for any attachments;
        /// the OutgoingStoryMessage is _not_ persisted to the Interactions table.
        case story(Story)

        /// Catch-all for messages not persisted to the Interactions table. NOT allowed to have attachments.
        case transient(TSOutgoingMessage)

        struct Persistable {
            let message: TSOutgoingMessage
            let unsavedBodyMediaAttachments: [AttachmentDataSource]
            let oversizeTextDataSource: AttachmentDataSource?
            let linkPreviewDraft: LinkPreviewDataSource?
            let quotedReplyDraft: DraftQuotedReplyModel.ForSending?
            let messageStickerDraft: MessageStickerDataSource?
            let contactShareDraft: ContactShareDraft.ForSending?
        }

        struct EditMessage {
            let targetMessage: TSOutgoingMessage
            let edits: MessageEdits
            let oversizeTextDataSource: AttachmentDataSource?
            let linkPreviewDraft: LinkPreviewDataSource?
            let quotedReplyEdit: MessageEdits.Edit<Void>
        }

        struct Story {
            let message: OutgoingStoryMessage
            let storyMessageRowId: Int64
        }
    }

    private let messageType: MessageType

    private init(messageType: MessageType) {
        self.messageType = messageType
    }

    public func _prepare(
        tx: SDSAnyWriteTransaction
    ) throws -> PreparedOutgoingMessage {
        let preparedMessageType: PreparedOutgoingMessage.MessageType
        switch messageType {
        case .persistable(let message):
            if message.message.shouldBeSaved {
                preparedMessageType = try preparePersistableMessage(message, tx: tx)
            } else {
                owsFailDebug("Unknown unsaved message type!")
                // As a last resort, still send the message. But don't bother with
                // attachments, those are dropped if we don't know how to handle them.
                preparedMessageType = prepareTransientMessage(message.message)
            }
        case .editMessage(let message):
            preparedMessageType = try prepareEditMessage(message, tx: tx)
        case .contactSync(let message):
            preparedMessageType = prepareContactSyncMessage(message)
        case .story(let story):
            preparedMessageType = prepareStoryMessage(story)
        case .transient(let message):
            preparedMessageType = prepareTransientMessage(message)
        }

        let builder = PreparedMessageBuilder(messageType: preparedMessageType)
        return PreparedOutgoingMessage(builder)
    }

    internal struct PreparedMessageBuilder {
        internal let messageType: PreparedOutgoingMessage.MessageType

        // Only this class can have access to this initializer, which in
        // turns means only this class can create a PreparedOutgoingMessage
        fileprivate init(messageType: PreparedOutgoingMessage.MessageType) {
            self.messageType = messageType
        }
    }

    private func preparePersistableMessage(
        _ message: MessageType.Persistable,
        tx: SDSAnyWriteTransaction
    ) throws -> PreparedOutgoingMessage.MessageType {
        guard
            let thread = message.message.thread(tx: tx),
            let threadRowId = thread.sqliteRowId
        else {
            throw OWSAssertionError("Outgoing message missing thread.")
        }

        let linkPreviewBuilder = try message.linkPreviewDraft.map {
            try DependenciesBridge.shared.linkPreviewManager.buildLinkPreview(
                from: $0,
                tx: tx.asV2Write
            )
        }.map {
            message.message.update(with: $0.info, transaction: tx)
            return $0
        }

        let quotedReplyBuilder = message.quotedReplyDraft.map {
            DependenciesBridge.shared.quotedReplyManager.buildQuotedReplyForSending(
                draft: $0,
                tx: tx.asV2Write
            )
        }.map {
            message.message.update(with: $0.info, transaction: tx)
            return $0
        }

        let messageStickerBuilder = try message.messageStickerDraft.map {
            try DependenciesBridge.shared.messageStickerManager.buildValidatedMessageSticker(from: $0, tx: tx.asV2Write)
        }.map {
            message.message.update(with: $0.info, transaction: tx)
            return $0
        }

        let contactShareBuilder = try message.contactShareDraft.map {
            try DependenciesBridge.shared.contactShareManager.build(
                draft: $0,
                tx: tx.asV2Write
            )
        }.map {
            message.message.update(withContactShare: $0.info, transaction: tx)
            return $0
        }

        message.message.anyInsert(transaction: tx)
        guard let messageRowId = message.message.sqliteRowId else {
            // We failed to insert!
            throw OWSAssertionError("Failed to insert message!")
        }

        if let oversizeTextDataSource = message.oversizeTextDataSource {
            try DependenciesBridge.shared.attachmentManager.createAttachmentStream(
                consuming: .init(
                    dataSource: oversizeTextDataSource,
                    owner: .messageOversizeText(.init(
                        messageRowId: messageRowId,
                        receivedAtTimestamp: message.message.receivedAtTimestamp,
                        threadRowId: threadRowId,
                        isPastEditRevision: message.message.isPastEditRevision()
                    ))
                ),
                tx: tx.asV2Write
            )
        }
        if message.unsavedBodyMediaAttachments.count > 0 {
            // Borderless is disallowed on any message with a quoted reply.
            let unsavedBodyMediaAttachments: [AttachmentDataSource]
            if quotedReplyBuilder != nil {
                unsavedBodyMediaAttachments = message.unsavedBodyMediaAttachments.map {
                    return $0.removeBorderlessRenderingFlagIfPresent()
                }
            } else {
                unsavedBodyMediaAttachments = message.unsavedBodyMediaAttachments
            }
            try DependenciesBridge.shared.attachmentManager.createAttachmentStreams(
                consuming: unsavedBodyMediaAttachments.map { dataSource in
                    return .init(
                        dataSource: dataSource,
                        owner: .messageBodyAttachment(.init(
                            messageRowId: messageRowId,
                            receivedAtTimestamp: message.message.receivedAtTimestamp,
                            threadRowId: threadRowId,
                            isViewOnce: message.message.isViewOnceMessage,
                            isPastEditRevision: message.message.isPastEditRevision()
                        ))
                    )
                },
                tx: tx.asV2Write
            )
        }

        try linkPreviewBuilder?.finalize(
            owner: .messageLinkPreview(.init(
                messageRowId: messageRowId,
                receivedAtTimestamp: message.message.receivedAtTimestamp,
                threadRowId: threadRowId,
                isPastEditRevision: message.message.isPastEditRevision()
            )),
            tx: tx.asV2Write
        )
        try quotedReplyBuilder?.finalize(
            owner: .quotedReplyAttachment(.init(
                messageRowId: messageRowId,
                receivedAtTimestamp: message.message.receivedAtTimestamp,
                threadRowId: threadRowId,
                isPastEditRevision: message.message.isPastEditRevision()
            )),
            tx: tx.asV2Write
        )

        try messageStickerBuilder.map {
            try $0.finalize(
                owner: .messageSticker(.init(
                    messageRowId: messageRowId,
                    receivedAtTimestamp: message.message.receivedAtTimestamp,
                    threadRowId: threadRowId,
                    isPastEditRevision: message.message.isPastEditRevision(),
                    stickerPackId: $0.info.packId,
                    stickerId: $0.info.stickerId
                )),
                tx: tx.asV2Write
            )
            StickerManager.stickerWasSent($0.info.info, transaction: tx)
        }

        try? contactShareBuilder?.finalize(
            owner: .messageContactAvatar(.init(
                messageRowId: messageRowId,
                receivedAtTimestamp: message.message.receivedAtTimestamp,
                threadRowId: threadRowId,
                isPastEditRevision: message.message.isPastEditRevision()
            )),
            tx: tx.asV2Write
        )

        return .persisted(PreparedOutgoingMessage.MessageType.Persisted(
            rowId: messageRowId,
            message: message.message
        ))
    }

    private func prepareEditMessage(
        _ message: MessageType.EditMessage,
        tx: SDSAnyWriteTransaction
    ) throws -> PreparedOutgoingMessage.MessageType {
        guard let thread = message.targetMessage.thread(tx: tx) else {
            throw OWSAssertionError("Outgoing message missing thread.")
        }

        let outgoingEditMessage = try DependenciesBridge.shared.editManager.createOutgoingEditMessage(
            targetMessage: message.targetMessage,
            thread: thread,
            edits: message.edits,
            oversizeText: message.oversizeTextDataSource,
            quotedReplyEdit: message.quotedReplyEdit,
            linkPreview: message.linkPreviewDraft,
            tx: tx.asV2Write
        )

        // All editable messages, by definition, should have been inserted.
        // Fail if we have no row id.
        guard let editedMessageRowId = outgoingEditMessage.editedMessage.sqliteRowId else {
            // We failed to insert!
            throw OWSAssertionError("Failed to insert message!")
        }

        return .editMessage(.init(
            editedMessageRowId: editedMessageRowId,
            editedMessage: outgoingEditMessage.editedMessage,
            messageForSending: outgoingEditMessage
        ))
    }

    private func prepareContactSyncMessage(
        _ message: OWSSyncContactsMessage
    ) -> PreparedOutgoingMessage.MessageType {
        return .contactSync(message)
    }

    private func prepareStoryMessage(
        _ story: MessageType.Story
    ) -> PreparedOutgoingMessage.MessageType {
        return .story(PreparedOutgoingMessage.MessageType.Story(
            message: story.message
        ))
    }

    private func prepareTransientMessage(
        _ message: TSOutgoingMessage
    ) -> PreparedOutgoingMessage.MessageType {
        return .transient(message)
    }

    // MARK: - Helpers

    internal static func assertIsAllowedTransientMessage(_ message: TSOutgoingMessage) {
        owsAssertDebug(
            message.shouldBeSaved.negated
            && !(message is OWSSyncContactsMessage)
            && !(message is OutgoingStoryMessage)
            && !(message is OutgoingEditMessage),
            "Disallowed transient message; use type-specific initializers instead"
        )
    }
}
