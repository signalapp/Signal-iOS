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
        body: ValidatedMessageBody?,
        unsavedBodyMediaAttachments: [AttachmentDataSource] = [],
        linkPreviewDraft: LinkPreviewDataSource? = nil,
        quotedReplyDraft: DraftQuotedReplyModel.ForSending? = nil,
        messageStickerDraft: MessageStickerDataSource? = nil,
        contactShareDraft: ContactShareDraft.ForSending? = nil,
        poll: CreatePollMessage? = nil,
    ) -> UnpreparedOutgoingMessage {
        let oversizeTextDataSource = (body?.oversizeText).map {
            AttachmentDataSource.pendingAttachment($0)
        }
        if !message.shouldBeSaved {
            owsAssertDebug(
                unsavedBodyMediaAttachments.isEmpty
                    && oversizeTextDataSource == nil
                    && linkPreviewDraft != nil
                    && quotedReplyDraft != nil
                    && messageStickerDraft != nil,
                "Unknown unsaved message sent through saved path with attachments!",
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
                contactShareDraft: contactShareDraft,
                poll: poll,
            )))
        }
    }

    public static func forEditMessage(
        targetMessage: TSOutgoingMessage,
        edits: MessageEdits,
        oversizeTextDataSource: AttachmentDataSource?,
        linkPreviewDraft: LinkPreviewDataSource?,
        quotedReplyEdit: MessageEdits.Edit<Void>,
    ) -> UnpreparedOutgoingMessage {
        return .init(messageType: .editMessage(.init(
            targetMessage: targetMessage,
            edits: edits,
            oversizeTextDataSource: oversizeTextDataSource,
            linkPreviewDraft: linkPreviewDraft,
            quotedReplyEdit: quotedReplyEdit,
        )))
    }

    public static func forOutgoingStoryMessage(
        _ message: OutgoingStoryMessage,
        storyMessageRowId: Int64,
    ) -> UnpreparedOutgoingMessage {
        return .init(messageType: .story(.init(
            message: message,
            storyMessageRowId: storyMessageRowId,
        )))
    }

    // MARK: - Preparation

    /// "Prepares" the outgoing message, inserting it into the database if needed and
    /// returning a ``PreparedOutgoingMessage`` ready to be sent.
    public func prepare(
        tx: DBWriteTransaction,
    ) throws -> PreparedOutgoingMessage {
        return try self._prepare(tx: tx)
    }

    public var messageTimestampForLogging: UInt64 {
        switch messageType {
        case .persistable(let message):
            return message.message.timestamp
        case .editMessage(let message):
            return message.edits.timestamp.unwrapChange(
                orKeepValue: message.targetMessage.timestamp,
            )
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

        /// An OutgoingStoryMessage: a TSMessage subclass we use for sending a ``StoryMessage``
        /// The StoryMessage is persisted to the StoryMessages table and is the owner for any attachments;
        /// the OutgoingStoryMessage is _not_ persisted to the Interactions table.
        case story(Story)

        /// Catch-all for messages not persisted to the Interactions table. The
        /// MessageSender will not upload any attachments contained within these
        /// messages; callers are responsible for uploading them.
        case transient(TSOutgoingMessage)

        struct Persistable {
            let message: TSOutgoingMessage
            let unsavedBodyMediaAttachments: [AttachmentDataSource]
            let oversizeTextDataSource: AttachmentDataSource?
            let linkPreviewDraft: LinkPreviewDataSource?
            let quotedReplyDraft: DraftQuotedReplyModel.ForSending?
            let messageStickerDraft: MessageStickerDataSource?
            let contactShareDraft: ContactShareDraft.ForSending?
            let poll: CreatePollMessage?
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
        tx: DBWriteTransaction,
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
        case .story(let story):
            preparedMessageType = prepareStoryMessage(story)
        case .transient(let message):
            preparedMessageType = prepareTransientMessage(message)
        }

        let builder = PreparedMessageBuilder(messageType: preparedMessageType)
        return PreparedOutgoingMessage(builder)
    }

    struct PreparedMessageBuilder {
        let messageType: PreparedOutgoingMessage.MessageType

        // Only this class can have access to this initializer, which in
        // turns means only this class can create a PreparedOutgoingMessage
        fileprivate init(messageType: PreparedOutgoingMessage.MessageType) {
            self.messageType = messageType
        }
    }

    private func preparePersistableMessage(
        _ message: MessageType.Persistable,
        tx: DBWriteTransaction,
    ) throws -> PreparedOutgoingMessage.MessageType {
        let attachmentManager = DependenciesBridge.shared.attachmentManager
        let contactShareManager = DependenciesBridge.shared.contactShareManager
        let linkPreviewManager = DependenciesBridge.shared.linkPreviewManager
        let messageStickerManager = DependenciesBridge.shared.messageStickerManager
        let quotedReplyManager = DependenciesBridge.shared.quotedReplyManager

        guard
            let thread = message.message.thread(tx: tx),
            let threadRowId = thread.sqliteRowId
        else {
            throw OWSAssertionError("Outgoing message missing thread.")
        }

        let validatedLinkPreview = try message.linkPreviewDraft.map {
            return try linkPreviewManager.validateDataSource(dataSource: $0, tx: tx)
        }
        if let validatedLinkPreview {
            message.message.update(with: validatedLinkPreview.preview, transaction: tx)
        }

        let validatedQuotedReply = message.quotedReplyDraft.map {
            return quotedReplyManager.prepareQuotedReplyForSending(draft: $0, tx: tx)
        }
        if let validatedQuotedReply {
            message.message.update(with: validatedQuotedReply.quotedReply, transaction: tx)
        }

        let validatedMessageSticker = try message.messageStickerDraft.map {
            return try messageStickerManager.validateMessageSticker(dataSource: $0)
        }
        if let validatedMessageSticker {
            message.message.update(with: validatedMessageSticker.sticker, transaction: tx)
        }

        let validatedContactShare = message.contactShareDraft.map {
            contactShareManager.validateAndBuild(preparedDraft: $0)
        }
        if let validatedContactShare {
            message.message.update(withContactShare: validatedContactShare.contact, transaction: tx)
        }

        if message.poll != nil {
            message.message.update(withIsPoll: true, transaction: tx)
        }

        message.message.anyInsert(transaction: tx)
        guard let messageRowId = message.message.sqliteRowId else {
            // We failed to insert!
            throw OWSAssertionError("Failed to insert message!")
        }

        if let poll = message.poll {
            try DependenciesBridge.shared.pollMessageManager.processOutgoingPollCreate(
                interactionId: messageRowId,
                pollOptions: poll.options,
                allowsMultiSelect: poll.allowMultiple,
                transaction: tx,
            )
        }

        if let oversizeTextDataSource = message.oversizeTextDataSource {
            try DependenciesBridge.shared.attachmentManager.createAttachmentStream(
                from: OwnedAttachmentDataSource(
                    dataSource: oversizeTextDataSource,
                    owner: .messageOversizeText(.init(
                        messageRowId: messageRowId,
                        receivedAtTimestamp: message.message.receivedAtTimestamp,
                        threadRowId: threadRowId,
                        isPastEditRevision: message.message.isPastEditRevision(),
                    )),
                ),
                tx: tx,
            )
        }

        for (idx, var unsavedBodyMediaAttachment) in message.unsavedBodyMediaAttachments.enumerated() {
            // Borderless is disallowed on any message with a quoted reply.
            if validatedQuotedReply != nil {
                unsavedBodyMediaAttachment = unsavedBodyMediaAttachment.removeBorderlessRenderingFlagIfPresent()
            }

            let attachmentManager = DependenciesBridge.shared.attachmentManager
            try attachmentManager.createAttachmentStream(
                from: OwnedAttachmentDataSource(
                    dataSource: unsavedBodyMediaAttachment,
                    owner: .messageBodyAttachment(.init(
                        messageRowId: messageRowId,
                        receivedAtTimestamp: message.message.receivedAtTimestamp,
                        threadRowId: threadRowId,
                        isViewOnce: message.message.isViewOnceMessage,
                        isPastEditRevision: message.message.isPastEditRevision(),
                        orderInMessage: UInt32(idx),
                    )),
                ),
                tx: tx,
            )
        }

        if let linkPreviewImageDataSource = validatedLinkPreview?.imageDataSource {
            try attachmentManager.createAttachmentStream(
                from: OwnedAttachmentDataSource(
                    dataSource: linkPreviewImageDataSource,
                    owner: .messageLinkPreview(.init(
                        messageRowId: messageRowId,
                        receivedAtTimestamp: message.message.receivedAtTimestamp,
                        threadRowId: threadRowId,
                        isPastEditRevision: message.message.isPastEditRevision(),
                    )),
                ),
                tx: tx,
            )
        }

        if let thumbnailDataSource = validatedQuotedReply?.thumbnailDataSource {
            try attachmentManager.createQuotedReplyMessageThumbnail(
                from: thumbnailDataSource,
                owningMessageAttachmentBuilder: .init(
                    messageRowId: messageRowId,
                    receivedAtTimestamp: message.message.receivedAtTimestamp,
                    threadRowId: threadRowId,
                    isPastEditRevision: message.message.isPastEditRevision(),
                ),
                tx: tx,
            )
        }

        if let validatedMessageSticker {
            try attachmentManager.createAttachmentStream(
                from: OwnedAttachmentDataSource(
                    dataSource: validatedMessageSticker.attachmentDataSource,
                    owner: .messageSticker(.init(
                        messageRowId: messageRowId,
                        receivedAtTimestamp: message.message.receivedAtTimestamp,
                        threadRowId: threadRowId,
                        isPastEditRevision: message.message.isPastEditRevision(),
                        stickerPackId: validatedMessageSticker.sticker.packId,
                        stickerId: validatedMessageSticker.sticker.stickerId,
                    )),
                ),
                tx: tx,
            )

            StickerManager.stickerWasSent(
                validatedMessageSticker.sticker.info,
                transaction: tx,
            )
        }

        if let avatarDataSource = validatedContactShare?.avatarDataSource {
            try attachmentManager.createAttachmentStream(
                from: OwnedAttachmentDataSource(
                    dataSource: avatarDataSource,
                    owner: .messageContactAvatar(.init(
                        messageRowId: messageRowId,
                        receivedAtTimestamp: message.message.receivedAtTimestamp,
                        threadRowId: threadRowId,
                        isPastEditRevision: message.message.isPastEditRevision(),
                    )),
                ),
                tx: tx,
            )
        }

        return .persisted(PreparedOutgoingMessage.MessageType.Persisted(
            rowId: messageRowId,
            message: message.message,
        ))
    }

    private func prepareEditMessage(
        _ message: MessageType.EditMessage,
        tx: DBWriteTransaction,
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
            tx: tx,
        )

        // All editable messages, by definition, should have been inserted.
        // Fail if we have no row id.
        guard
            let editedMessage = outgoingEditMessage.editedMessage,
            let editedMessageRowId = editedMessage.sqliteRowId
        else {
            // We failed to insert!
            throw OWSAssertionError("Failed to insert message!")
        }

        return .editMessage(.init(
            editedMessageRowId: editedMessageRowId,
            editedMessage: editedMessage,
            messageForSending: outgoingEditMessage,
        ))
    }

    private func prepareStoryMessage(
        _ story: MessageType.Story,
    ) -> PreparedOutgoingMessage.MessageType {
        return .story(PreparedOutgoingMessage.MessageType.Story(
            message: story.message,
        ))
    }

    private func prepareTransientMessage(
        _ message: TSOutgoingMessage,
    ) -> PreparedOutgoingMessage.MessageType {
        return .transient(message)
    }

    // MARK: - Helpers

    static func assertIsAllowedTransientMessage(_ message: TSOutgoingMessage) {
        owsAssertDebug(
            !message.shouldBeSaved
                && !(message is OWSSyncContactsMessage)
                && !(message is OutgoingStoryMessage)
                && !(message is OutgoingEditMessage),
            "Disallowed transient message; use type-specific initializers instead",
        )
    }
}
