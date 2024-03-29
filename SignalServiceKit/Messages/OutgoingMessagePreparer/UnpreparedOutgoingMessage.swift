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
        unsavedBodyAttachments: [AttachmentDataSource] = [],
        linkPreviewDraft: OWSLinkPreviewDraft? = nil,
        quotedReplyDraft: DraftQuotedReplyModel? = nil,
        messageStickerDraft: MessageStickerDraft? = nil,
        contactShareDraft: ContactShareDraft? = nil
    ) -> UnpreparedOutgoingMessage {
        if let editMessage = message as? OutgoingEditMessage {
            owsAssertDebug(messageStickerDraft == nil, "Can't edit sticker messages")
            return .init(messageType: .editMessage(.init(
                editedMessage: editMessage.editedMessage,
                messageForSending: editMessage,
                unsavedBodyAttachments: unsavedBodyAttachments,
                linkPreviewDraft: linkPreviewDraft,
                quotedReplyDraft: quotedReplyDraft
            )))
        } else if !message.shouldBeSaved {
            owsAssertDebug(
                unsavedBodyAttachments.isEmpty
                || linkPreviewDraft != nil
                || quotedReplyDraft != nil
                || messageStickerDraft != nil,
                "Unknown unsaved message sent through saved path with attachments!"
            )
            Self.assertIsAllowedTransientMessage(message)
            return .init(messageType: .transient(message))
        } else {
            return .init(messageType: .persistable(.init(
                message: message,
                unsavedBodyAttachments: unsavedBodyAttachments,
                linkPreviewDraft: linkPreviewDraft,
                quotedReplyDraft: quotedReplyDraft,
                messageStickerDraft: messageStickerDraft,
                contactShareDraft: contactShareDraft
            )))
        }
    }

    public static func forContactSync(
        _ contactSyncMessage: OWSSyncContactsMessage,
        dataSource: DataSource
    ) -> UnpreparedOutgoingMessage {
        return .init(messageType: .contactSync(.init(
            message: contactSyncMessage,
            attachmentDataSource: dataSource
        )))
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

    public var message: TSOutgoingMessage {
        switch messageType {
        case .persistable(let message):
            return message.message
        case .editMessage(let message):
            return message.messageForSending
        case .contactSync(let contactSync):
            return contactSync.message
        case .story(let story):
            return story.message
        case .transient(let message):
            return message
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
        /// in the database; it is simply in memory (or a temporary file location on disk).
        case contactSync(ContactSync)

        /// An OutgoingStoryMessage: a TSMessage subclass we use for sending a ``StoryMessage``
        /// The StoryMessage is persisted to the StoryMessages table and is the owner for any attachments;
        /// the OutgoingStoryMessage is _not_ persisted to the Interactions table.
        case story(Story)

        /// Catch-all for messages not persisted to the Interactions table. NOT allowed to have attachments.
        case transient(TSOutgoingMessage)

        struct Persistable {
            let message: TSOutgoingMessage
            let unsavedBodyAttachments: [AttachmentDataSource]
            let linkPreviewDraft: OWSLinkPreviewDraft?
            let quotedReplyDraft: DraftQuotedReplyModel?
            let messageStickerDraft: MessageStickerDraft?
            let contactShareDraft: ContactShareDraft?
        }

        struct EditMessage {
            let editedMessage: TSOutgoingMessage
            let messageForSending: OutgoingEditMessage
            let unsavedBodyAttachments: [AttachmentDataSource]
            let linkPreviewDraft: OWSLinkPreviewDraft?
            let quotedReplyDraft: DraftQuotedReplyModel?
        }

        struct ContactSync {
            let message: OWSSyncContactsMessage
            let attachmentDataSource: DataSource
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
        case .contactSync(let contactSync):
            preparedMessageType = prepareContactSyncMessage(contactSync)
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
        return try Self.prepareMessageAttachments(.persistable(message), tx: tx)
    }

    private func prepareEditMessage(
        _ message: MessageType.EditMessage,
        tx: SDSAnyWriteTransaction
    ) throws -> PreparedOutgoingMessage.MessageType {
        return try Self.prepareMessageAttachments(.editMessage(message), tx: tx)
    }

    private enum AttachmentPrepMessage {
        case persistable(MessageType.Persistable)
        case editMessage(MessageType.EditMessage)
    }

    private static func prepareMessageAttachments(
        _ type: AttachmentPrepMessage,
        tx: SDSAnyWriteTransaction
    ) throws -> PreparedOutgoingMessage.MessageType {

        let thread: TSThread?
        let attachmentOwnerMessage: TSOutgoingMessage
        let unsavedBodyAttachments: [AttachmentDataSource]
        let linkPreviewDraft: OWSLinkPreviewDraft?
        let quotedReplyDraft: DraftQuotedReplyModel?
        let messageStickerDraft: MessageStickerDraft?
        let contactShareDraft: ContactShareDraft?

        switch type {
        case .persistable(let persistable):
            thread = persistable.message.thread(tx: tx)
            attachmentOwnerMessage = persistable.message
            unsavedBodyAttachments = persistable.unsavedBodyAttachments
            linkPreviewDraft = persistable.linkPreviewDraft
            quotedReplyDraft = persistable.quotedReplyDraft
            messageStickerDraft = persistable.messageStickerDraft
            contactShareDraft = persistable.contactShareDraft
        case .editMessage(let editMessage):
            thread = editMessage.editedMessage.thread(tx: tx)
            attachmentOwnerMessage = editMessage.editedMessage
            unsavedBodyAttachments = editMessage.unsavedBodyAttachments
            linkPreviewDraft = editMessage.linkPreviewDraft
            quotedReplyDraft = editMessage.quotedReplyDraft
            // Note: no sticker because you can't edit sticker messages
            messageStickerDraft = nil
            // Note: no contact share because you can't edit contact share messages
            contactShareDraft = nil
        }

        guard let thread else {
            throw OWSAssertionError("Outgoing message missing thread.")
        }

        let linkPreviewBuilder = linkPreviewDraft.flatMap {
            try? DependenciesBridge.shared.linkPreviewManager.validateAndBuildLinkPreview(
                from: $0,
                tx: tx.asV2Write
            )
        }.map {
            attachmentOwnerMessage.update(with: $0.info, transaction: tx)
            return $0
        }

        let quotedReplyBuilder = quotedReplyDraft.flatMap {
            DependenciesBridge.shared.quotedReplyManager.buildQuotedReplyForSending(
                draft: $0,
                threadUniqueId: thread.uniqueId,
                tx: tx.asV2Write
            )
        }.map {
            attachmentOwnerMessage.update(with: $0.info, transaction: tx)
            return $0
        }

        let messageStickerBuilder = messageStickerDraft.flatMap {
            // TODO: message stickers, specifically and unlike the other ones, would fail
            // the message send if they failed to finalize (create the attachment).
            // should just unify all the error handling.
            let builder = try? MessageSticker.buildValidatedMessageSticker(fromDraft: $0, transaction: tx)
            if let builder {
                attachmentOwnerMessage.update(with: builder.info, transaction: tx)
            }
            return builder
        }

        let contactShareBuilder = contactShareDraft.flatMap {
            return try? $0.builderForSending(tx: tx)
        }.map {
            attachmentOwnerMessage.update(withContactShare: $0.info, transaction: tx)
            return $0
        }

        let attachmentOwnerMessageRowId = try {
            switch type {
            case .editMessage(let editMessage):
                // Write changes and insert new edit revisions/records
                DependenciesBridge.shared.editManager.insertOutgoingEditRevisions(
                    for: editMessage.messageForSending,
                    thread: thread,
                    tx: tx.asV2Write
                )
                // All editable messages, by definition, should have been inserted.
                // Fail if we have no row id.
                guard let messageRowId = editMessage.editedMessage.sqliteRowId else {
                    // We failed to insert!
                    throw OWSAssertionError("Failed to insert message!")
                }
                return messageRowId
            case .persistable(let persistable):
                persistable.message.anyInsert(transaction: tx)
                guard let messageRowId = persistable.message.sqliteRowId else {
                    // We failed to insert!
                    throw OWSAssertionError("Failed to insert message!")
                }
                return messageRowId
            }
        }()

        if unsavedBodyAttachments.count > 0 {
            try DependenciesBridge.shared.tsResourceManager.createBodyAttachmentStreams(
                consuming: unsavedBodyAttachments,
                message: attachmentOwnerMessage,
                tx: tx.asV2Write
            )
        }

        try? linkPreviewBuilder?.finalize(
            owner: .messageLinkPreview(messageRowId: attachmentOwnerMessageRowId),
            tx: tx.asV2Write
        )
        try? quotedReplyBuilder?.finalize(
            owner: .quotedReplyAttachment(messageRowId: attachmentOwnerMessageRowId),
            tx: tx.asV2Write
        )

        // TODO: message stickers, specifically and unlike the other ones, would fail
        // the message send if they failed to finalize (create the attachment).
        // should just unify all the error handling.
        try? messageStickerBuilder?.finalize(
            owner: .messageSticker(messageRowId: attachmentOwnerMessageRowId),
            tx: tx.asV2Write
        )
        if let stickerInfo = messageStickerBuilder?.info {
            StickerManager.stickerWasSent(stickerInfo.info, transaction: tx)
        }

        try? contactShareBuilder?.finalize(
            owner: .messageContactAvatar(messageRowId: attachmentOwnerMessageRowId),
            tx: tx.asV2Write
        )

        let legacyAttachmentIdsForUpload: [String] = Self.fetchLegacyAttachmentIdsForUpload(
            persistedMessage: attachmentOwnerMessage
        )

        switch type {
        case .editMessage(let editMessage):
            return .editMessage(PreparedOutgoingMessage.MessageType.EditMessage(
                editedMessageRowId: attachmentOwnerMessageRowId,
                editedMessage: editMessage.editedMessage,
                messageForSending: editMessage.messageForSending,
                legacyAttachmentIdsForUpload: legacyAttachmentIdsForUpload
            ))
        case .persistable(let persistable):
            return .persisted(PreparedOutgoingMessage.MessageType.Persisted(
                rowId: attachmentOwnerMessageRowId,
                message: persistable.message,
                legacyAttachmentIdsForUpload: legacyAttachmentIdsForUpload
            ))
        }
    }

    private func prepareContactSyncMessage(
        _ contactSync: MessageType.ContactSync
    ) -> PreparedOutgoingMessage.MessageType {
        return .contactSync(PreparedOutgoingMessage.MessageType.ContactSync(
            message: contactSync.message,
            attachmentDataSource: contactSync.attachmentDataSource
        ))
    }

    private func prepareStoryMessage(
        _ story: MessageType.Story
    ) -> PreparedOutgoingMessage.MessageType {
        let legacyAttachmentIdsForUpload: [String] = Self.fetchLegacyAttachmentIdsForUpload(
            storyMessage: story.message
        )

        return .story(PreparedOutgoingMessage.MessageType.Story(
            message: story.message,
            legacyAttachmentIdsForUpload: legacyAttachmentIdsForUpload
        ))
    }

    private func prepareTransientMessage(
        _ message: TSOutgoingMessage
    ) -> PreparedOutgoingMessage.MessageType {
        return .transient(message)
    }

    // MARK: - Helpers

    internal static func fetchLegacyAttachmentIdsForUpload(
        persistedMessage message: TSMessage
    ) -> [String] {
        return message.attachmentIds
    }

    internal static func fetchLegacyAttachmentIdsForUpload(
        storyMessage: OutgoingStoryMessage
    ) -> [String] {
        // In the legacy world, we make _copies_ of the original attachments on
        // the StoryMessage and use those for upload; the IDs for those copies
        // are put into the OutgoingStoryMessage.
        return storyMessage.attachmentIds
    }

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
