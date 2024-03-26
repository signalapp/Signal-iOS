//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public final class MessageSenderJobRecord: JobRecord, FactoryInitializableFromRecordType {
    override class var jobRecordType: JobRecordType { .messageSender }

    public let threadId: String?
    public let isHighPriority: Bool

    /// Unique id of the ougoing message persisted in the Interactions table;
    /// mutually exclusive with `transientMessage`.
    private let persistedMessageId: String?
    /// Ignored for in memory messages. Determined if the media queue should
    /// be used for sending.
    private let useMediaQueue: Bool

    /// A message we send but which is never inserted into the Interactions table;
    /// its only used for sending.
    private let transientMessage: TSOutgoingMessage?

    // exposed for tests
    internal let removeMessageAfterSending: Bool

    public enum MessageType {
        case persisted(messageId: String, useMediaQueue: Bool)
        case transient(TSOutgoingMessage)
        /// Generally considered invalid, but failed at processing time not deserialization time.
        case none
    }

    public var messageType: MessageType {
        if let transientMessage {
            return .transient(transientMessage)
        } else if let persistedMessageId {
            return .persisted(messageId: persistedMessageId, useMediaQueue: useMediaQueue)
        } else {
            return .none
        }
    }

    // exposed for tests
    internal init(
        threadId: String?,
        messageType: MessageType,
        removeMessageAfterSending: Bool,
        isHighPriority: Bool,
        exclusiveProcessIdentifier: String? = nil,
        failureCount: UInt = 0,
        status: Status = .ready
    ) {
        self.threadId = threadId
        self.removeMessageAfterSending = removeMessageAfterSending
        self.isHighPriority = isHighPriority

        switch messageType {
        case .persisted(let messageId, let useMediaQueue):
            self.persistedMessageId = messageId
            self.transientMessage = nil
            self.useMediaQueue = useMediaQueue
        case .transient(let outgoingMessage):
            self.persistedMessageId = nil
            self.transientMessage = outgoingMessage
            self.useMediaQueue = false
        case .none:
            self.persistedMessageId = nil
            self.transientMessage = nil
            self.useMediaQueue = false
        }

        super.init(
            exclusiveProcessIdentifier: exclusiveProcessIdentifier,
            failureCount: failureCount,
            status: status
        )
    }

    convenience init(
        message: TSOutgoingMessage,
        isHighPriority: Bool,
        transaction: SDSAnyReadTransaction
    ) throws {
        let messageType: MessageType
        if message.shouldBeSaved {
            let messageIdParam = message.uniqueId
            owsAssertDebug(!messageIdParam.isEmpty)

            guard TSInteraction.anyExists(uniqueId: messageIdParam, transaction: transaction) else {
                throw JobRecordError.assertionError(message: "Message wasn't saved!")
            }

            messageType = .persisted(
                messageId: messageIdParam,
                useMediaQueue: message.hasMediaAttachments(transaction: transaction)
            )
        } else {
            messageType = .transient(message)
        }

        self.init(
            threadId: message.uniqueThreadId,
            messageType: messageType,
            removeMessageAfterSending: false,
            isHighPriority: isHighPriority
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

    required init(forRecordTypeFactoryInitializationFrom decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        persistedMessageId = try container.decodeIfPresent(String.self, forKey: .persistedMessageId)
        threadId = try container.decodeIfPresent(String.self, forKey: .threadId)
        useMediaQueue = try container.decode(Bool.self, forKey: .useMediaQueue)

        transientMessage = try container.decodeIfPresent(
            Data.self,
            forKey: .transientMessage
        ).flatMap { invisibleMessageData -> TSOutgoingMessage? in
            do {
                return try LegacySDSSerializer().deserializeLegacySDSData(
                    invisibleMessageData,
                    propertyName: "invisibleMessage"
                )
            } catch let error {
                owsFailDebug("Failed to deserialize invisible message data! Has this message type been removed? \(error)")
                return nil
            }
        }

        removeMessageAfterSending = try container.decode(Bool.self, forKey: .removeMessageAfterSending)
        isHighPriority = try container.decode(Bool.self, forKey: .isHighPriority)

        try super.init(baseClassDuringFactoryInitializationFrom: container.superDecoder())
    }

    override public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try super.encode(to: container.superEncoder())

        try container.encodeIfPresent(persistedMessageId, forKey: .persistedMessageId)
        try container.encodeIfPresent(threadId, forKey: .threadId)
        try container.encode(useMediaQueue, forKey: .useMediaQueue)
        try container.encodeIfPresent(
            LegacySDSSerializer().serializeAsLegacySDSData(property: transientMessage),
            forKey: .transientMessage
        )
        try container.encode(removeMessageAfterSending, forKey: .removeMessageAfterSending)
        try container.encode(isHighPriority, forKey: .isHighPriority)
    }

    override var canBeRunByCurrentProcess: Bool {
        return super.canBeRunByCurrentProcess && !removeMessageAfterSending
    }
}
