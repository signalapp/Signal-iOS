//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

// View model for a draft which has already fetched any attachments
// from the original message.
public class DraftQuotedReplyModel {

    public let originalMessageTimestamp: UInt64?
    public let originalMessageAuthorAddress: SignalServiceAddress
    public let threadUniqueId: String
    public let isOriginalMessageAuthorLocalUser: Bool

    // MARK: Attachments

    public indirect enum Content {

        /// The original message had text with no attachment
        case text(MessageBody)

        // MARK: - "Special" types

        /// The original message was a gift badge
        case giftBadge
        /// The original message was a payment.
        /// String is the displayable text.
        case payment(String)
        /// The original message was view-once, so only
        /// placeholder information should be shown.
        case viewOnce
        /// The original message was a contact share
        case contactShare(OWSContact)
        /// The original message is a story reaction emoji
        case storyReactionEmoji(String)

        // MARK: - Attachment types

        /// The original message had an attachment, but it could not
        /// be thumbnail-ed
        case attachmentStub(
            MessageBody?,
            QuotedMessageAttachmentReference.Stub
        )
        /// The original message had an attachment that can be thumbnail-ed,
        /// though it may not actually be thumbnail-ed *yet*.
        ///
        /// - Note:
        /// This includes sticker messages, which are thumbnailable attachments.
        case attachment(
            MessageBody?,
            attachmentRef: AttachmentReference,
            attachment: Attachment,
            thumbnailImage: UIImage?
        )

        // MARK: - Edit

        /// A draft of an edit applied to an _existing_ quoted reply, with
        /// the existing quoted reply's information provided.
        case edit(
            TSMessage,
            TSQuotedMessage,
            content: Content
        )

        // MARK: - Convenience

        public var isGiftBadge: Bool {
            switch self {
            case .giftBadge:
                return true
            default:
                return false
            }
        }

        public var isViewOnce: Bool {
            switch self {
            case .viewOnce:
                return true
            default:
                return false
            }
        }

        public var isRemotelySourced: Bool {
            switch self {
            case .edit(_, let quotedMessage, _):
                // The only way we end up with a "remotely sourced"
                // draft is if we edit a quoted reply that was initially
                // created on a linked device.
                return quotedMessage.bodySource == .remote
            default:
                return false
            }
        }

        public var renderingFlag: AttachmentReference.RenderingFlag {
            switch self {
            case .attachment(_, let attachmentRef, _, _):
                return attachmentRef.renderingFlag
            case .edit(_, _, let content):
                return content.renderingFlag
            default:
                return .default
            }
        }
    }

    public let content: Content

    internal init(
        originalMessageTimestamp: UInt64?,
        originalMessageAuthorAddress: SignalServiceAddress,
        isOriginalMessageAuthorLocalUser: Bool,
        threadUniqueId: String,
        content: Content
    ) {
        self.originalMessageTimestamp = originalMessageTimestamp
        self.originalMessageAuthorAddress = originalMessageAuthorAddress
        self.isOriginalMessageAuthorLocalUser = isOriginalMessageAuthorLocalUser
        self.threadUniqueId = threadUniqueId
        self.content = content
    }

    public static func fromOriginalPaymentMessage(
        _ originalMessage: TSMessage,
        amountString: String,
        tx: SDSAnyReadTransaction
    ) -> DraftQuotedReplyModel? {
        let authorAddress: SignalServiceAddress? = {
            if originalMessage.isOutgoing {
                return DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aciAddress
            } else if let incomingMessage = originalMessage as? TSIncomingMessage {
                return incomingMessage.authorAddress
            } else {
                return nil
            }
        }()
        guard let authorAddress else {
            return nil
        }

        owsAssertDebug(originalMessage is OWSPaymentMessage)
        return DraftQuotedReplyModel(
            originalMessageTimestamp: originalMessage.timestamp,
            originalMessageAuthorAddress: authorAddress,
            isOriginalMessageAuthorLocalUser: originalMessage.isOutgoing,
            threadUniqueId: originalMessage.uniqueThreadId,
            content: .payment(amountString)
        )
    }

    public static func forEditingOriginalPaymentMessage(
        originalMessage: TSMessage,
        replyMessage: TSMessage,
        quotedReply: TSQuotedMessage,
        amountString: String,
        tx: SDSAnyReadTransaction
    ) -> DraftQuotedReplyModel? {
        let authorAddress: SignalServiceAddress? = {
            if originalMessage.isOutgoing {
                return DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aciAddress
            } else if let incomingMessage = originalMessage as? TSIncomingMessage {
                return incomingMessage.authorAddress
            } else {
                return nil
            }
        }()
        guard let authorAddress else {
            return nil
        }

        owsAssertDebug(originalMessage is OWSPaymentMessage)
        return DraftQuotedReplyModel(
            originalMessageTimestamp: originalMessage.timestamp,
            originalMessageAuthorAddress: authorAddress,
            isOriginalMessageAuthorLocalUser: originalMessage.isOutgoing,
            threadUniqueId: originalMessage.uniqueThreadId,
            content: .edit(replyMessage, quotedReply, content: .payment(amountString))
        )
    }

    public var bodyForSending: MessageBody? {
        return Self.bodyForSending(content, isOriginalMessageAuthorLocalUser: isOriginalMessageAuthorLocalUser)
    }

    private static func bodyForSending(_ content: DraftQuotedReplyModel.Content, isOriginalMessageAuthorLocalUser: Bool) -> MessageBody? {
        switch content {
        case .attachmentStub(let body, _):
            return body
        case .attachment(let body, _, _, _):
            return body
        case .edit(_, _, let innerContent):
            return bodyForSending(innerContent, isOriginalMessageAuthorLocalUser: isOriginalMessageAuthorLocalUser)
        case .contactShare(let contact):
            return MessageBody(
                text: "👤 " + contact.name.displayName,
                ranges: .empty
            )
        case .viewOnce:
            return MessageBody(
                text: OWSLocalizedString(
                    "PER_MESSAGE_EXPIRATION_NOT_VIEWABLE",
                    comment: "inbox cell and notification text for an already viewed view-once media message."
                ),
                ranges: .empty
            )
        case .payment(let text):
            return MessageBody(text: text, ranges: .empty)
        case .text(let body):
            return body
        case .giftBadge:
            return nil
        case .storyReactionEmoji(let emoji):
            let formatString: String
            if isOriginalMessageAuthorLocalUser {
                formatString = OWSLocalizedString(
                    "STORY_REACTION_QUOTE_FORMAT_SECOND_PERSON",
                    comment: "quote text for a reaction to a story by the user (the header on the bubble says \"You\"). Embeds {{reaction emoji}}"
                )
            } else {
                formatString = OWSLocalizedString(
                    "STORY_REACTION_QUOTE_FORMAT_THIRD_PERSON",
                    comment: "quote text for a reaction to a story by some other user (the header on the bubble says their name, e.g. \"Bob\"). Embeds {{reaction emoji}}"
                )
            }
            let text = String(
                format: formatString,
                emoji
            )
            return MessageBody(text: text, ranges: .empty)
        }
    }
}

// MARK: - Equatable

extension DraftQuotedReplyModel: Equatable {
    public static func == (lhs: DraftQuotedReplyModel, rhs: DraftQuotedReplyModel) -> Bool {
        return lhs.originalMessageTimestamp == rhs.originalMessageTimestamp
            && lhs.originalMessageAuthorAddress.isEqualToAddress(rhs.originalMessageAuthorAddress)
            && lhs.content == rhs.content
    }
}

extension DraftQuotedReplyModel.Content: Equatable {
    public static func == (lhs: DraftQuotedReplyModel.Content, rhs: DraftQuotedReplyModel.Content) -> Bool {
        switch (lhs, rhs) {
        case (.giftBadge, .giftBadge), (.viewOnce, .viewOnce):
            return true
        case let (.payment(lhsBody), .payment(rhsBody)):
            return lhsBody == rhsBody
        case let (.text(lhsBody), .text(rhsBody)):
            return lhsBody == rhsBody
        case let (.contactShare(lhsContact), .contactShare(rhsContact)):
            return lhsContact == rhsContact
        case let (.storyReactionEmoji(lhsEmoji), .storyReactionEmoji(rhsEmoji)):
            return lhsEmoji == rhsEmoji
        case let (.edit(lhsMessage, lhsQuotedReply, lhsContent), .edit(rhsMessage, rhsQuotedReply, rhsContent)):
            return lhsMessage == rhsMessage
                && lhsQuotedReply == rhsQuotedReply
                && lhsContent == rhsContent
        case let (.attachmentStub(lhsBody, lhsStub), .attachmentStub(rhsBody, rhsStub)):
            return lhsBody == rhsBody && lhsStub == rhsStub
        case let (
            .attachment(lhsBody, _, lhsAttachment, lhsThumbnailImage),
            .attachment(rhsBody, _, rhsAttachment, rhsThumbnailImage)
        ):
            return lhsBody == rhsBody
                && lhsAttachment.id == rhsAttachment.id
                && lhsThumbnailImage == rhsThumbnailImage
        case
            (.giftBadge, _),
            (.payment, _),
            (.text, _),
            (.viewOnce, _),
            (.contactShare, _),
            (.attachmentStub, _),
            (.attachment, _),
            (.edit, _),
            (.storyReactionEmoji, _),
            (_, .giftBadge),
            (_, .payment),
            (_, .text),
            (_, .viewOnce),
            (_, .contactShare),
            (_, .attachmentStub),
            (_, .attachment),
            (_, .edit),
            (_, .storyReactionEmoji):
            return false
        }
    }
}
