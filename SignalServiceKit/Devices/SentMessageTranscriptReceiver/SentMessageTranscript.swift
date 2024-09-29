//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public enum SentMessageTranscriptTarget {
    case group(TSGroupThread)
    case contact(TSContactThread, VersionedDisappearingMessageToken)

    var thread: TSThread {
        switch self {
        case .group(let thread):
            return thread
        case .contact(let thread, _):
            return thread
        }
    }

    var threadUniqueId: String { thread.uniqueId }
}

public enum SentMessageTranscriptType {

    public struct Message {
        public let target: SentMessageTranscriptTarget

        public let body: String?
        public let bodyRanges: MessageBodyRanges?

        public let attachmentPointerProtos: [SSKProtoAttachmentPointer]

        /// Construction of the builder itself deferred since the builder's constructor does database inserts.
        /// Edit messages construct a transcript but don't use the attachment builders and instead make their own.
        public let makeQuotedMessageBuilder: (DBWriteTransaction) throws -> OwnedAttachmentBuilder<TSQuotedMessage>?

        /// Construction of the builder itself deferred since the builder's constructor does database inserts.
        /// Edit messages construct a transcript but don't use the attachment builders and instead make their own.
        public let makeContactBuilder: (DBWriteTransaction) throws -> OwnedAttachmentBuilder<OWSContact>?

        /// Construction of the builder itself deferred since the builder's constructor does database inserts.
        /// Edit messages construct a transcript but don't use the attachment builders and instead make their own.
        public let makeLinkPreviewBuilder: (DBWriteTransaction) throws -> OwnedAttachmentBuilder<OWSLinkPreview>?

        public let giftBadge: OWSGiftBadge?

        /// Construction of the builder itself deferred since the builder's constructor does database inserts.
        /// Edit messages construct a transcript but don't use the attachment builders and instead make their own.
        public let makeMessageStickerBuilder: (DBWriteTransaction) throws -> OwnedAttachmentBuilder<MessageSticker>?

        public let isViewOnceMessage: Bool

        public let expirationStartedAt: UInt64?
        public let expirationDurationSeconds: UInt32?
        public let expireTimerVersion: UInt32?

        public let storyTimestamp: UInt64?
        public let storyAuthorAci: Aci?
    }

    public struct PaymentNotification {
        public let target: SentMessageTranscriptTarget
        public let serverTimestamp: UInt64
        public let notification: TSPaymentNotification
    }

    public struct ArchivedPayment {
        public let target: SentMessageTranscriptTarget
        public let amount: String?
        public let fee: String?
        public let note: String?
        public let expirationStartedAt: UInt64?
        public let expirationDurationSeconds: UInt32?
    }

    case message(Message)
    case recipientUpdate(TSGroupThread)
    case expirationTimerUpdate(SentMessageTranscriptTarget)
    case endSessionUpdate(TSContactThread)
    case paymentNotification(PaymentNotification)
    case archivedPayment(ArchivedPayment)
}

/// A transcript for a message that has already been sent, and which came in
/// as a sync message from a linked device.
public protocol SentMessageTranscript {

    var type: SentMessageTranscriptType { get }

    var timestamp: UInt64 { get }

    var requiredProtocolVersion: UInt32? { get }

    var recipientStates: [SignalServiceAddress: TSOutgoingMessageRecipientState] { get }
}

extension SentMessageTranscript {

    public var threadForDataMessage: TSThread? {
        switch type {
        case .endSessionUpdate, .expirationTimerUpdate:
            return nil
        case .message(let messageParams):
            return messageParams.target.thread
        case .paymentNotification(let notification):
            return notification.target.thread
        case .archivedPayment(let payment):
            return payment.target.thread
        case .recipientUpdate(let thread):
            return thread
        }
    }
}
