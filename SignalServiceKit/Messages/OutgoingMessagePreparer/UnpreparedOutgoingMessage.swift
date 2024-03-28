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
        messageStickerDraft: MessageStickerDraft? = nil
    ) -> UnpreparedOutgoingMessage {
        if !message.shouldBeSaved {
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
                messageStickerDraft: messageStickerDraft
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
        guard let thread = message.message.thread(tx: tx) else {
            throw OWSAssertionError("Outgoing message missing thread.")
        }

        let linkPreviewBuilder = message.linkPreviewDraft.flatMap {
            try? DependenciesBridge.shared.linkPreviewManager.validateAndBuildLinkPreview(
                from: $0,
                tx: tx.asV2Write
            )
        }.map {
            message.message.update(with: $0.info, transaction: tx)
            return $0
        }

        let quotedReplyBuilder = message.quotedReplyDraft.flatMap {
            DependenciesBridge.shared.quotedReplyManager.buildQuotedReplyForSending(
                draft: $0,
                threadUniqueId: thread.uniqueId,
                tx: tx.asV2Write
            )
        }.map {
            message.message.update(with: $0.info, transaction: tx)
            return $0
        }

        let messageStickerBuilder = message.messageStickerDraft.flatMap {
            // TODO: message stickers, specifically and unlike the other ones, would fail
            // the message send if they failed to finalize (create the attachment).
            // should just unify all the error handling.
            let builder = try? MessageSticker.buildValidatedMessageSticker(fromDraft: $0, transaction: tx)
            if let builder {
                message.message.update(with: builder.info, transaction: tx)
            }
            return builder
        }

        let messageRowId: Int64
        if let message = message.message as? OutgoingEditMessage {
            // Write changes and insert new edit revisions/records
            DependenciesBridge.shared.editManager.insertOutgoingEditRevisions(
                for: message,
                thread: thread,
                tx: tx.asV2Write
            )
            // All editable messages, by definition, should have been inserted.
            // Fail if we have no row id.
            guard let id = message.sqliteRowId else {
                // We failed to insert!
                throw OWSAssertionError("Failed to insert message!")
            }
            messageRowId = id
        } else {
            message.message.anyInsert(transaction: tx)
            guard let id = message.message.sqliteRowId else {
                // We failed to insert!
                throw OWSAssertionError("Failed to insert message!")
            }
            messageRowId = id
        }

        if message.unsavedBodyAttachments.count > 0 {
            try DependenciesBridge.shared.tsResourceManager.createBodyAttachmentStreams(
                consuming: message.unsavedBodyAttachments,
                message: message.message,
                tx: tx.asV2Write
            )
        }

        try? linkPreviewBuilder?.finalize(
            owner: .messageLinkPreview(messageRowId: messageRowId),
            tx: tx.asV2Write
        )
        try? quotedReplyBuilder?.finalize(
            owner: .quotedReplyAttachment(messageRowId: messageRowId),
            tx: tx.asV2Write
        )

        // TODO: message stickers, specifically and unlike the other ones, would fail
        // the message send if they failed to finalize (create the attachment).
        // should just unify all the error handling.
        try? messageStickerBuilder?.finalize(
            owner: .messageSticker(messageRowId: messageRowId),
            tx: tx.asV2Write
        )
        if let stickerInfo = messageStickerBuilder?.info {
            StickerManager.stickerWasSent(stickerInfo.info, transaction: tx)
        }

        let legacyAttachmentIdsForUpload: [String] = Self.fetchLegacyAttachmentIdsForUpload(
            persistedMessage: message.message
        )

        return .persisted(PreparedOutgoingMessage.MessageType.Persisted(
            rowId: messageRowId,
            message: message.message,
            legacyAttachmentIdsForUpload: legacyAttachmentIdsForUpload
        ))
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
            && !(message is OutgoingStoryMessage),
            "Disallowed transient message; use type-specific initializers instead"
        )
    }
}
