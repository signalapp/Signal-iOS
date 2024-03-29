//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Wraps a TSOutgoingMessage that:
/// * Is already inserted to the database, if the message type needs inserting
/// * Has had any attachments created and inserted to the database
/// and is therefore prepared for sending.
///
/// Just a wrapper for the message object and metadata needed for sending.
public class PreparedOutgoingMessage {

    // MARK: - Pre-prepared constructors

    /// Use this _only_ for already-inserted persisted messages that already uploaded their attachments.
    /// No insertion or attachment prep is done; its assumed any attachments are already prepared.
    public static func preprepared(
        insertedAndUploadedMessage message: TSOutgoingMessage,
        messageRowId: Int64
    ) -> PreparedOutgoingMessage {
        let messageType = MessageType.persisted(MessageType.Persisted(
            rowId: messageRowId,
            message: message,
            legacyAttachmentIdsForUpload: []
        ))
        return PreparedOutgoingMessage(messageType: messageType)
    }

    /// Use this _only_ for already-inserted persisted messages that we are resending, but which may have
    /// unuploaded attachments.
    /// No insertion or attachment prep is done; its assumed any attachments are already prepared.
    public static func preprepared(
        forResending message: TSOutgoingMessage,
        messageRowId: Int64
    ) -> PreparedOutgoingMessage {
        let legacyAttachmentIdsForUpload = UnpreparedOutgoingMessage.fetchLegacyAttachmentIdsForUpload(
            persistedMessage: message
        )
        let messageType = MessageType.persisted(MessageType.Persisted(
            rowId: messageRowId,
            message: message,
            legacyAttachmentIdsForUpload: legacyAttachmentIdsForUpload
        ))
        return PreparedOutgoingMessage(messageType: messageType)
    }

    /// Use this _only_ to "prepare" outgoing story messages that already created their attachments.
    /// Instantly prepares because...these messages don't need any preparing.
    public static func preprepared(
        outgoingStoryMessage: OutgoingStoryMessage
    ) -> PreparedOutgoingMessage {
        let legacyAttachmentIdsForUpload = UnpreparedOutgoingMessage.fetchLegacyAttachmentIdsForUpload(
            storyMessage: outgoingStoryMessage
        )
        let messageType = MessageType.story(MessageType.Story(
            message: outgoingStoryMessage,
            legacyAttachmentIdsForUpload: legacyAttachmentIdsForUpload
        ))
        return PreparedOutgoingMessage(messageType: messageType)
    }

    /// Use this _only_ to "prepare" messages that are:
    /// (1) not saved to the interactions table
    /// AND
    /// (2) don't have any attachments associated with them
    /// Instantly prepares because...these messages don't need any preparing.
    public static func preprepared(
        transientMessageWithoutAttachments: TSOutgoingMessage
    ) -> PreparedOutgoingMessage {
        UnpreparedOutgoingMessage.assertIsAllowedTransientMessage(transientMessageWithoutAttachments)
        let messageType = MessageType.transient(transientMessageWithoutAttachments)
        return PreparedOutgoingMessage(messageType: messageType)
    }

    // MARK: - Message Type

    public enum MessageType {

        /// The message is inserted into the Interactions table, ready for sending.
        case persisted(Persisted)

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

        public struct Persisted {
            public let rowId: Int64
            public let message: TSOutgoingMessage
            public let legacyAttachmentIdsForUpload: [String]
        }

        public struct ContactSync {
            public let message: OWSSyncContactsMessage
            public let attachmentDataSource: DataSource
        }

        public struct Story {
            public let message: OutgoingStoryMessage
            public let legacyAttachmentIdsForUpload: [String]

            public var storyMessageRowId: Int64 {
                message.storyMessageRowId
            }
        }
    }

    // MARK: - Public mutations

    public func dequeueForSending(tx: SDSAnyWriteTransaction) -> MessageType {
        // When we start a message send, all "failed" recipients should be marked as "sending".
        let messageToUpdateRecipientsSending: TSOutgoingMessage? = {
            switch messageType {
            case .persisted(let message):
                return message.message
            case .contactSync(let contactSync):
                return contactSync.message
            case .story(let storyMessage):
                return storyMessage.message
            case .transient(let message):
                // Is this even necessary for transient messages?
                return message
            }
        }()
        messageToUpdateRecipientsSending?.updateAllUnsentRecipientsAsSending(transaction: tx)
        return messageType
    }

    public func messageForIntentDonation(tx: SDSAnyReadTransaction) -> TSOutgoingMessage? {
        switch messageType {
        case .persisted(let persisted):
            if persisted.message.isGroupStoryReply {
                return nil
            }
            // At this point, the message is prepared, meaning its attachments
            // have been created and its been inserted. Any renderable content
            // should be ready.
            guard persisted.message.hasRenderableContent(tx: tx) else {
                return nil
            }
            return persisted.message
        case .contactSync:
            return nil
        case .story:
            // We don't donate story message intents.
            return nil
        case .transient(let message):
            if message is OWSOutgoingReactionMessage {
                return message
            } else {
                return nil
            }
        }
    }

    /// Used when waiting on media attachment uploads.
    public func mediaAttachments(tx: SDSAnyReadTransaction) -> [TSResourceReference] {
        switch messageType {
        case .persisted(let persisted):
            return DependenciesBridge.shared.tsResourceStore.bodyMediaAttachments(
                for: persisted.message,
                tx: tx.asV2Read
            )
        case .contactSync:
            return []
        case .story(let story):
            guard let storyMessage = StoryMessage.anyFetch(uniqueId: story.message.storyMessageId, transaction: tx) else {
                return []
            }
            return [DependenciesBridge.shared.tsResourceStore.mediaAttachment(
                for: storyMessage,
                tx: tx.asV2Read
            )].compacted()
        case .transient:
            return []
        }
    }

    // MARK: - Private

    private let messageType: MessageType

    // Can effectively only be called by UnpreparedOutgoingMessage, as only
    // that class can instantiate a builder.
    internal convenience init(_ builder: UnpreparedOutgoingMessage.PreparedMessageBuilder) {
        self.init(messageType: builder.messageType)
    }

    private init(messageType: MessageType) {
        self.messageType = messageType
    }
}

// TODO: remove these methods when we remove multisend; they need to exposed only
// for that use case.
extension PreparedOutgoingMessage {
    public var storyMessage: OutgoingStoryMessage? {
        switch messageType {
        case .persisted, .contactSync, .transient:
            return nil
        case .story(let storyMessage):
            return storyMessage.message
        }
    }

    public func legacyAttachmentIdsForMultisend(tx: SDSAnyReadTransaction) -> [String] {
        switch messageType {
        case .persisted(let persisted):
            return persisted.message.bodyAttachmentIds(transaction: tx)
        case .contactSync:
            return []
        case .story(let story):
            return story.message.bodyAttachmentIds(transaction: tx)
        case .transient:
            return []
        }
    }
}
