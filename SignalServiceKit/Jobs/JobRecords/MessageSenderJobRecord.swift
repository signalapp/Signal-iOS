//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public final class MessageSenderJobRecord: JobRecord {
    override public class var jobRecordType: JobRecordType { .messageSender }

    public let threadId: String?
    public let isHighPriority: Bool

    /// Unique id of the ougoing message persisted in the Interactions table;
    /// mutually exclusive with `transientMessage`.
    private let persistedMessageId: String?
    /// Ignored for in memory messages. Determined if the media queue should
    /// be used for sending.
    let useMediaQueue: Bool

    /// A message we send but which is never inserted into the Interactions table;
    /// its only used for sending.
    private let transientMessage: TransientOutgoingMessage?

    // exposed for tests
    let removeMessageAfterSending: Bool

    public enum MessageType {
        case persisted(messageId: String, useMediaQueue: Bool)
        case editMessage(
            editedMessageId: String,
            messageForSending: OutgoingEditMessage,
            useMediaQueue: Bool,
        )
        case transient(TransientOutgoingMessage)
    }

    public var messageType: MessageType? {
        if let editMessage = transientMessage as? OutgoingEditMessage {
            return .editMessage(
                editedMessageId: persistedMessageId ?? editMessage.editedMessage.uniqueId,
                messageForSending: editMessage,
                useMediaQueue: useMediaQueue,
            )
        }
        if let transientMessage {
            return .transient(transientMessage)
        }
        if let persistedMessageId {
            return .persisted(messageId: persistedMessageId, useMediaQueue: useMediaQueue)
        }
        return nil
    }

    // exposed for tests
    init(
        threadId: String?,
        messageType: MessageType?,
        removeMessageAfterSending: Bool,
        isHighPriority: Bool,
        failureCount: UInt = 0,
        status: Status = .ready,
    ) {
        self.threadId = threadId
        self.removeMessageAfterSending = removeMessageAfterSending
        self.isHighPriority = isHighPriority

        switch messageType {
        case .persisted(let messageId, let useMediaQueue):
            self.persistedMessageId = messageId
            self.transientMessage = nil
            self.useMediaQueue = useMediaQueue
        case let .editMessage(editedMessageId, messageForSending, useMediaQueue):
            self.persistedMessageId = editedMessageId
            self.transientMessage = messageForSending
            self.useMediaQueue = useMediaQueue
        case .transient(let outgoingMessage):
            self.persistedMessageId = nil
            self.transientMessage = outgoingMessage
            self.useMediaQueue = false
        case nil:
            self.persistedMessageId = nil
            self.transientMessage = nil
            self.useMediaQueue = false
        }

        super.init(
            failureCount: failureCount,
            status: status,
        )
    }

    convenience init(
        persistedMessage: PreparedOutgoingMessage.MessageType.Persisted,
        isHighPriority: Bool,
        transaction: DBReadTransaction,
    ) throws {
        let messageType = MessageType.persisted(
            messageId: persistedMessage.message.uniqueId,
            useMediaQueue: persistedMessage.message.hasMediaAttachments(transaction: transaction),
        )

        self.init(
            threadId: persistedMessage.message.uniqueThreadId,
            messageType: messageType,
            removeMessageAfterSending: false,
            isHighPriority: isHighPriority,
        )
    }

    convenience init(
        editMessage: PreparedOutgoingMessage.MessageType.EditMessage,
        isHighPriority: Bool,
        transaction: DBReadTransaction,
    ) throws {
        let messageType = MessageType.editMessage(
            editedMessageId: editMessage.editedMessage.uniqueId,
            messageForSending: editMessage.messageForSending,
            // This would ideally only check for un-uploaded attachments.
            useMediaQueue: editMessage.editedMessage.hasMediaAttachments(transaction: transaction),
        )

        self.init(
            threadId: editMessage.editedMessage.uniqueThreadId,
            messageType: messageType,
            removeMessageAfterSending: false,
            isHighPriority: isHighPriority,
        )
    }

    convenience init(
        storyMessage: PreparedOutgoingMessage.MessageType.Story,
        isHighPriority: Bool,
    ) {
        let messageType = MessageType.transient(storyMessage.message)

        self.init(
            threadId: storyMessage.message.uniqueThreadId,
            messageType: messageType,
            removeMessageAfterSending: false,
            isHighPriority: isHighPriority,
        )
    }

    convenience init(
        transientMessage: TransientOutgoingMessage,
        isHighPriority: Bool,
    ) {
        owsPrecondition(
            !transientMessage.shouldBeSaved
                && !(transientMessage is OutgoingStoryMessage),
            "Invalid transient message type!",
        )
        let messageType = MessageType.transient(transientMessage)

        self.init(
            threadId: transientMessage.uniqueThreadId,
            messageType: messageType,
            removeMessageAfterSending: false,
            isHighPriority: isHighPriority,
        )
    }

    public enum CodingKeys: String, CodingKey {
        case threadId = "threadId"
        case isHighPriority = "isHighPriority"
        case removeMessageAfterSending = "removeMessageAfterSending"

        case persistedMessageId = "messageId"
        case useMediaQueue = "isMediaMessage"
        case transientMessage = "invisibleMessage"
    }

    required init(inheritableDecoder decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        persistedMessageId = try container.decodeIfPresent(String.self, forKey: .persistedMessageId)
        threadId = try container.decodeIfPresent(String.self, forKey: .threadId)
        useMediaQueue = try container.decode(Bool.self, forKey: .useMediaQueue)

        transientMessage = try container.decodeIfPresent(
            Data.self,
            forKey: .transientMessage,
        ).flatMap { invisibleMessageData -> TransientOutgoingMessage? in
            do {
                return try LegacySDSSerializer().deserializeLegacySDSData(invisibleMessageData, ofClass: TransientOutgoingMessage.self)
            } catch {
                owsFailDebug("couldn't decode transient message: \(error)")
                return nil
            }
        }

        removeMessageAfterSending = try container.decode(Bool.self, forKey: .removeMessageAfterSending)
        isHighPriority = try container.decode(Bool.self, forKey: .isHighPriority)

        try super.init(inheritableDecoder: decoder)
    }

    override public func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(persistedMessageId, forKey: .persistedMessageId)
        try container.encodeIfPresent(threadId, forKey: .threadId)
        try container.encode(useMediaQueue, forKey: .useMediaQueue)
        try container.encodeIfPresent(
            transientMessage.map { LegacySDSSerializer().serializeAsLegacySDSData($0) },
            forKey: .transientMessage,
        )
        try container.encode(removeMessageAfterSending, forKey: .removeMessageAfterSending)
        try container.encode(isHighPriority, forKey: .isHighPriority)
    }
}
