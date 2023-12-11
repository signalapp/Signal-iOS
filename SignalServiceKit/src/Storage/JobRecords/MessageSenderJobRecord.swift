//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public final class MessageSenderJobRecord: JobRecord, FactoryInitializableFromRecordType {
    override class var jobRecordType: JobRecordType { .messageSender }

    public let messageId: String?
    public let threadId: String?
    public let isMediaMessage: Bool
    public let invisibleMessage: TSOutgoingMessage?
    public let removeMessageAfterSending: Bool
    public let isHighPriority: Bool

    init(
        messageId: String?,
        threadId: String?,
        invisibleMessage: TSOutgoingMessage?,
        isMediaMessage: Bool,
        removeMessageAfterSending: Bool,
        isHighPriority: Bool,
        exclusiveProcessIdentifier: String? = nil,
        failureCount: UInt = 0,
        status: Status = .ready
    ) {
        self.messageId = messageId
        self.threadId = threadId
        self.invisibleMessage = invisibleMessage
        self.isMediaMessage = isMediaMessage
        self.removeMessageAfterSending = removeMessageAfterSending
        self.isHighPriority = isHighPriority

        super.init(
            exclusiveProcessIdentifier: exclusiveProcessIdentifier,
            failureCount: failureCount,
            status: status
        )
    }

    convenience init(
        message: TSOutgoingMessage,
        removeMessageAfterSending: Bool,
        isHighPriority: Bool,
        transaction: SDSAnyReadTransaction
    ) throws {
        let messageId: String?
        let isMediaMessage: Bool
        let invisibleMessage: TSOutgoingMessage?

        if message.shouldBeSaved {
            let messageIdParam = message.uniqueId
            owsAssertDebug(!messageIdParam.isEmpty)

            guard TSInteraction.anyExists(uniqueId: messageIdParam, transaction: transaction) else {
                throw JobRecordError.assertionError(message: "Message wasn't saved!")
            }

            messageId = messageIdParam
            isMediaMessage = message.hasMediaAttachments(with: transaction.unwrapGrdbRead)
            invisibleMessage = nil
        } else {
            messageId = nil
            isMediaMessage = false
            invisibleMessage = message
        }

        self.init(
            messageId: messageId,
            threadId: message.uniqueThreadId,
            invisibleMessage: invisibleMessage,
            isMediaMessage: isMediaMessage,
            removeMessageAfterSending: removeMessageAfterSending,
            isHighPriority: isHighPriority
        )
    }

    required init(forRecordTypeFactoryInitializationFrom decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        messageId = try container.decodeIfPresent(String.self, forKey: .messageId)
        threadId = try container.decodeIfPresent(String.self, forKey: .threadId)
        isMediaMessage = try container.decode(Bool.self, forKey: .isMediaMessage)

        invisibleMessage = try container.decodeIfPresent(
            Data.self,
            forKey: .invisibleMessage
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

        try container.encodeIfPresent(messageId, forKey: .messageId)
        try container.encodeIfPresent(threadId, forKey: .threadId)
        try container.encode(isMediaMessage, forKey: .isMediaMessage)
        try container.encodeIfPresent(
            LegacySDSSerializer().serializeAsLegacySDSData(property: invisibleMessage),
            forKey: .invisibleMessage
        )
        try container.encode(removeMessageAfterSending, forKey: .removeMessageAfterSending)
        try container.encode(isHighPriority, forKey: .isHighPriority)
    }
}
