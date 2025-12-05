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

    /// Use this _only_ for already-inserted persisted messages that we are resending.
    /// No insertion or attachment prep is done; attachments should be inserted (but maybe not uploaded).
    public static func preprepared(
        forResending message: TSOutgoingMessage,
        messageRowId: Int64
    ) -> PreparedOutgoingMessage {
        let messageType = MessageType.persisted(MessageType.Persisted(
            rowId: messageRowId,
            message: message
        ))
        return PreparedOutgoingMessage(messageType: messageType)
    }

    /// Use this _only_ to "prepare" outgoing story messages that already created their attachments.
    /// Instantly prepares because...these messages don't need any preparing.
    public static func preprepared(
        outgoingStoryMessage: OutgoingStoryMessage
    ) -> PreparedOutgoingMessage {
        let messageType = MessageType.story(MessageType.Story(
            message: outgoingStoryMessage
        ))
        return PreparedOutgoingMessage(messageType: messageType)
    }

    /// Use this _only_ to "prepare" outgoing contact sync that, by definition, already uploaded their attachment.
    /// Instantly prepares because...these messages don't need any preparing.
    public static func preprepared(
        contactSyncMessage: OWSSyncContactsMessage
    ) -> PreparedOutgoingMessage {
        return _preprepared(transientMessage: contactSyncMessage)
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
        return _preprepared(transientMessage: transientMessageWithoutAttachments)
    }

    /// Use this _only_ to "prepare" messages that are:
    /// (1) not saved to the interactions table
    /// (2) don't have any attachments that need to be uploaded
    /// Instantly prepares because...these messages don't need any preparing.
    private static func _preprepared(
        transientMessage: TSOutgoingMessage
    ) -> PreparedOutgoingMessage {
        let messageType = MessageType.transient(transientMessage)
        return PreparedOutgoingMessage(messageType: messageType)
    }

    /// ``MessageSenderJobRecord`` gets created from a prepared message (see that class)
    /// and, after reading the record back into memory from disk, can be restored to a Prepared message.
    ///
    /// Returns nil if the message no longer exists; records keep a pointer to a message which may be since deleted.
    public static func restore(
        from jobRecord: MessageSenderJobRecord,
        tx: DBReadTransaction
    ) -> PreparedOutgoingMessage? {
        switch jobRecord.messageType {
        case .persisted(let messageId, _):
            guard
                let interaction = TSOutgoingMessage.anyFetch(uniqueId: messageId, transaction: tx),
                let message = interaction as? TSOutgoingMessage
            else {
                return nil
            }
            return .init(messageType: .persisted(.init(rowId: message.sqliteRowId!, message: message)))
        case .editMessage(let editedMessageId, let messageForSending, _):
            guard
                let interaction = TSOutgoingMessage.anyFetch(uniqueId: editedMessageId, transaction: tx),
                let editedMessage = interaction as? TSOutgoingMessage
            else {
                return nil
            }
            return .init(messageType: .editMessage(.init(
                editedMessageRowId: editedMessage.sqliteRowId!,
                editedMessage: editedMessage,
                messageForSending: messageForSending
            )))
        case .transient(let message):
            if let storyMessage = message as? OutgoingStoryMessage {
                guard storyMessage.storyMessageRowId != nil else {
                    /// This field was, in the past, inadvertently not exposed
                    /// to ObjC. If we deserialize one of these as `nil`, drop
                    /// it.
                    return nil
                }

                return .init(messageType: .story(.init(message: storyMessage)))
            }
            return .init(messageType: .transient(message))
        case .none:
            return nil
        }
    }

    // MARK: - Message Type

    public enum MessageType {

        /// The message is inserted into the Interactions table, ready for sending.
        case persisted(Persisted)

        /// An edit for an existing message; the original is (already was) persisted to the Interaction table, but is now edited.
        case editMessage(EditMessage)

        /// An OutgoingStoryMessage: a TSMessage subclass we use for sending a ``StoryMessage``
        /// The StoryMessage is persisted to the StoryMessages table and is the owner for any attachments;
        /// the OutgoingStoryMessage is _not_ persisted to the Interactions table.
        case story(Story)

        /// Catch-all for messages not persisted to the Interactions table. The
        /// MessageSender will not upload any attachments contained within these
        /// messages; callers are responsible for uploading them.
        case transient(TSOutgoingMessage)

        public struct Persisted {
            public let rowId: Int64
            public let message: TSOutgoingMessage
        }

        public struct EditMessage {
            public let editedMessageRowId: Int64
            public let editedMessage: TSOutgoingMessage
            public let messageForSending: OutgoingEditMessage
        }

        public struct Story {
            public let message: OutgoingStoryMessage

            public var storyMessageRowId: Int64 {
                message.storyMessageRowId
            }
        }
    }

    // MARK: - Public getters

    public var uniqueThreadId: String {
        // The message we send and the message we apply updates to always
        // have the same thread; just use this one for convenience.
        return messageForSendStateUpdates.uniqueThreadId
    }

    public func attachmentIdsForUpload(tx: DBReadTransaction) -> [Attachment.IDType] {
        switch messageType {
        case .persisted(let persisted):
            let attachmentIds = DependenciesBridge.shared.attachmentStore.allAttachments(
                forMessageWithRowId: persisted.rowId,
                tx: tx
            ).map(\.attachmentRowId)
            return attachmentIds
        case .editMessage(let editMessage):
            return DependenciesBridge.shared.attachmentStore.allAttachments(
                forMessageWithRowId: editMessage.editedMessageRowId,
                tx: tx
            ).map(\.attachmentRowId)
        case .story(let story):
            guard let storyMessage = StoryMessage.anyFetch(uniqueId: story.message.storyMessageId, transaction: tx) else {
                return []
            }
            switch storyMessage.attachment {
            case .media:
                return [
                    DependenciesBridge.shared.attachmentStore.fetchFirstReference(
                        owner: .storyMessageMedia(storyMessageRowId: story.storyMessageRowId),
                        tx: tx
                    )?.attachmentRowId
                ].compacted()
            case .text:
                return [
                    DependenciesBridge.shared.attachmentStore.fetchFirstReference(
                        owner: .storyMessageLinkPreview(storyMessageRowId: story.storyMessageRowId),
                        tx: tx
                    )?.attachmentRowId
                ].compacted()
            }
        case .transient:
            return []
        }
    }

    public func hasRenderableContent(tx: DBReadTransaction) -> Bool {
        switch messageType {
        case .persisted(let message):
            return message.message.insertedMessageHasRenderableContent(rowId: message.rowId, tx: tx)
        case .editMessage, .story:
            // Always have renderable content; send at normal priority.
            return true
        case .transient:
            return false
        }
    }

    /// The message, if any, we should use to donate the ``INSendMessageIntent`` to the OS for sharesheet shortcuts.
    public func messageForIntentDonation(tx: DBReadTransaction) -> TSOutgoingMessage? {
        switch messageType {
        case .persisted(let persisted):
            if persisted.message.isGroupStoryReply {
                return nil
            }
            guard persisted.message.insertedMessageHasRenderableContent(rowId: persisted.rowId, tx: tx) else {
                return nil
            }
            return persisted.message
        case .editMessage(let editMessage):
            // Edited messages were always renderable.
            return editMessage.editedMessage
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

    // MARK: - Sending

    public func send<T>(_ sender: (TSOutgoingMessage) async throws -> T) async throws -> T {
        return try await sender(messageForSending)
    }

    public func attachmentUploadOperations(tx: DBReadTransaction) -> [() async throws -> Void] {
        return attachmentIdsForUpload(tx: tx).map { attachmentId in
            return {
                try await DependenciesBridge.shared.attachmentUploadManager.uploadTransitTierAttachment(
                    attachmentId: attachmentId
                )
            }
        }
    }

    // MARK: - Message state updates

    public func updateAllUnsentRecipientsAsSending(tx: DBWriteTransaction) {
        messageForSendStateUpdates.updateAllUnsentRecipientsAsSending(transaction: tx)
    }

    public func updateWithAllSendingRecipientsMarkedAsFailed(
        error: (any Error)? = nil,
        tx: DBWriteTransaction
    ) {
        messageForSendStateUpdates.updateWithAllSendingRecipientsMarkedAsFailed(
            error: error,
            transaction: tx
        )
    }

    public func updateWithSendSuccess(tx: DBWriteTransaction) {
        messageForSendStateUpdates.updateWithSendSuccess(tx: tx)
    }

    // MARK: - Persistence

    public func asMessageSenderJobRecord(
        isHighPriority: Bool,
        tx: DBReadTransaction
    ) throws -> MessageSenderJobRecord {
        switch messageType {
        case .persisted(let persisted):
            return try .init(persistedMessage: persisted, isHighPriority: isHighPriority, transaction: tx)
        case .editMessage(let edit):
            return try .init(editMessage: edit, isHighPriority: isHighPriority, transaction: tx)
        case .story(let story):
            return .init(storyMessage: story, isHighPriority: isHighPriority)
        case .transient(let message):
            return .init(transientMessage: message, isHighPriority: isHighPriority)
        }
    }

    // MARK: - Private

    fileprivate let messageType: MessageType

    // Can effectively only be called by UnpreparedOutgoingMessage, as only
    // that class can instantiate a builder.
    internal convenience init(_ builder: UnpreparedOutgoingMessage.PreparedMessageBuilder) {
        self.init(messageType: builder.messageType)
    }

    private init(messageType: MessageType) {
        self.messageType = messageType

        let body = { () -> String? in
            switch messageType {
            case .persisted(let message):
                return message.message.body
            case .editMessage(let message):
                return message.editedMessage.body
            case .story:
                return nil
            case .transient(let message):
                return message.body
            }
        }()

        if let body {
            owsAssertDebug(body.lengthOfBytes(using: .utf8) <= OWSMediaUtils.kOversizeTextMessageSizeThresholdBytes)
        }
    }

    // Private on purpose; too easy to abuse for the variety of fields on
    // TSMessage if exposed.
    private var messageForSending: TSOutgoingMessage {
        switch messageType {
        case .persisted(let message):
            return message.message
        case .editMessage(let message):
            return message.messageForSending
        case .story(let storyMessage):
            return storyMessage.message
        case .transient(let message):
            return message
        }
    }

    // Private on purpose; too easy to abuse for the variety of fields on
    // TSMessage if exposed.
    private var messageForSendStateUpdates: TSOutgoingMessage {
        switch messageType {
        case .persisted(let message):
            return message.message
        case .editMessage(let message):
            // We update the send state on the _original_ edited message.
            return message.editedMessage
        case .story(let storyMessage):
            return storyMessage.message
        case .transient(let message):
            // Do send states even matter for transient messages?
            return message
        }
    }

    public var isPinChange: Bool {
        switch messageType {
        case .persisted, .editMessage, .story:
            return false
        case .transient(let message):
            return message is OutgoingPinMessage || message is OutgoingUnpinMessage
        }
    }
}

extension Array where Element == PreparedOutgoingMessage {

    public func attachmentIdsForUpload(tx: DBReadTransaction) -> [Attachment.IDType] {
        // Use a non-story message if we have one.
        // When we multisend N attachments to M message threads and S story threads,
        // we create M messages with N attachments each, and (N * S) story messages
        // with one attachment each. So, prefer a non story message which has
        // all the attachments on it.
        // Fall back to just a single story message; fetching attachments for each
        // one and collating is too expensive.
        var storyMessages = [PreparedOutgoingMessage]()
        for preparedMessage in self {
            switch preparedMessage.messageType {
            case .persisted, .editMessage, .transient:
                return preparedMessage.attachmentIdsForUpload(tx: tx)
            case .story:
                storyMessages.append(preparedMessage)
            }
        }
        var attachmentIds = Set<Attachment.IDType>()
        storyMessages.forEach { message in
            message.attachmentIdsForUpload(tx: tx).forEach { attachmentIds.insert($0) }
        }
        return [Attachment.IDType](attachmentIds)
    }
}

extension PreparedOutgoingMessage: CustomStringConvertible {

    public var description: String {
        return "\(type(of: messageForSending)), timestamp: \(messageForSending.timestamp)"
    }
}

extension PreparedOutgoingMessage: Equatable {
    public static func == (lhs: PreparedOutgoingMessage, rhs: PreparedOutgoingMessage) -> Bool {
        return lhs.messageForSending.uniqueId == rhs.messageForSending.uniqueId
    }
}
