//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public enum SentMessageTranscriptTarget {
    case group(TSGroupThread)
    case contact(TSContactThread, DisappearingMessageToken)

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

        // TODO: generalize to cover attachments from backups
        public let attachmentPointerProtos: [SSKProtoAttachmentPointer]

        public let quotedMessage: TSQuotedMessage?

        public let contact: OWSContact?

        public let linkPreview: OWSLinkPreview?

        public let giftBadge: OWSGiftBadge?

        public let messageSticker: MessageSticker?

        public let isViewOnceMessage: Bool

        public let expirationStartedAt: UInt64
        public let expirationDuration: UInt32

        public let storyTimestamp: UInt64?
        public let storyAuthorAci: Aci?
    }

    case message(Message)
    case recipientUpdate(TSGroupThread)
    case expirationTimerUpdate(SentMessageTranscriptTarget)
    case endSessionUpdate(TSContactThread)
    case paymentNotification(SentMessageTranscriptTarget, TSPaymentNotification)
}

/// A transcript for a message that has already been sent, and which came in either
/// as a sync message from a linked device, or from a backup.
public protocol SentMessageTranscript {

    var type: SentMessageTranscriptType { get }

    var timestamp: UInt64 { get }
    var dataMessageTimestamp: UInt64 { get }
    var serverTimestamp: UInt64 { get }

    var requiredProtocolVersion: UInt32? { get }

    // TODO: generalize to include recipient states (not just "sent")
    var udRecipients: [ServiceId] { get }
    var nonUdRecipients: [ServiceId] { get }
}

extension SentMessageTranscript {

    public var threadForDataMessage: TSThread? {
        switch type {
        case .endSessionUpdate, .expirationTimerUpdate:
            return nil
        case .message(let messageParams):
            return messageParams.target.thread
        case .paymentNotification(let target, _):
            return target.thread
        case .recipientUpdate(let thread):
            return thread
        }
    }
}
