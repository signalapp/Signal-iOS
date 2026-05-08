//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient
public import SignalServiceKit

/// View model for an existing quoted reply which has already fetched any attachments.
/// NOT used for draft quoted replies; this is for TSMessages with quoted replies (or story replies)
/// that have already been created, for use rendering in a conversation.
public class QuotedReplyModel {

    /// Timestamp of the original message, be it StoryMessage or TSMessage.
    public let originalMessageTimestamp: UInt64?

    /// Address of the original message's author, be it StoryMessage or TSMessage.
    public let originalMessageAuthorAddress: SignalServiceAddress

    public let originalMessageMemberLabel: String?

    public let isOriginalMessageAuthorLocalUser: Bool

    /// IFF the original's content was a story message, the emoji used
    /// _on the reply body_ to that story message.
    /// Ignored for other original content types.
    public let storyReactionEmoji: String?

    /// The content on the _original_ message being replied to.
    public enum OriginalContent {

        /// The original message had text with no attachment
        case text(MessageBody?)

        // MARK: - "Special" types

        /// The original message was a gift badge
        case giftBadge
        /// The original message is itself a reply to a story
        /// with an emoji.
        case storyReactionEmoji(String)

        // MARK: - Attachment types

        /// The original message had an attachment, but it could not
        /// be thumbnail-ed
        case attachmentStub(
            MessageBody?,
            QuotedMessageAttachmentReference.Stub,
        )
        /// The original message had an attachment that can be thumbnail-ed,
        /// though it may not actually be thumbnail-ed *yet*.
        case attachment(
            MessageBody?,
            attachment: ReferencedAttachment,
            thumbnailImage: UIImage?,
        )

        // MARK: - Story types

        case mediaStory(
            body: StyleOnlyMessageBody?,
            attachment: ReferencedAttachment,
            thumbnailImage: UIImage?,
        )

        public typealias TextStoryThumbnailRenderer = (SpoilerRenderState) -> UIView
        case textStory(TextStoryThumbnailRenderer)

        /// Used if the story has expired; we do not retain a copy.
        case expiredStory

        case poll(String)

        // MARK: - Convenience

        public var isGiftBadge: Bool {
            switch self {
            case .giftBadge:
                return true
            default:
                return false
            }
        }

        public var isStory: Bool {
            switch self {
            case .mediaStory, .textStory, .expiredStory:
                return true
            default:
                return false
            }
        }

        public var isPoll: Bool {
            switch self {
            case .poll:
                return true
            default:
                return false
            }
        }

        public var attachmentMimeType: String? {
            switch self {
            case .text:
                return nil
            case .giftBadge:
                return nil
            case .storyReactionEmoji:
                return nil
            case .attachmentStub(_, let stub):
                return stub.mimeType
            case .attachment(_, let attachment, _):
                return attachment.attachment.mimeType
            case .mediaStory(_, let attachment, _):
                return attachment.attachment.mimeType
            case .textStory:
                return nil
            case .expiredStory:
                return nil
            case .poll:
                return nil
            }
        }

        public var attachmentContentType: Attachment.ContentType? {
            switch self {
            case .text:
                return nil
            case .giftBadge:
                return nil
            case .storyReactionEmoji:
                return nil
            case .attachmentStub:
                return nil
            case .attachment(_, let attachment, _):
                return attachment.attachment.asStream()?.contentType
            case .mediaStory(_, let attachment, _):
                return attachment.attachment.asStream()?.contentType
            case .textStory:
                return nil
            case .expiredStory:
                return nil
            case .poll:
                return nil
            }
        }
    }

    public let originalContent: OriginalContent

    /// Where we got the origina's content from.
    /// In plain english: did we have the original message (NOT its attachment,
    /// the TSMessage itself) locally when we created the TSQuotedMessage?
    public let sourceOfOriginal: TSQuotedMessageContentSource

    // MARK: Convenience

    public var originalMessageBody: MessageBody? {
        switch originalContent {
        case .text(let messageBody):
            return messageBody
        case .giftBadge:
            return nil
        case .storyReactionEmoji(let string):
            return MessageBody(text: string, ranges: .empty)
        case .attachmentStub(let messageBody, _):
            return messageBody
        case .attachment(let messageBody, _, _):
            return messageBody
        case .mediaStory(let body, _, _):
            return body?.asMessageBody()
        case .textStory:
            return nil
        case .expiredStory:
            return MessageBody(
                text: OWSLocalizedString(
                    "STORY_NO_LONGER_AVAILABLE",
                    comment: "Text indicating a story that was replied to is no longer available.",
                ),
                ranges: .empty,
            )
        case .poll(let pollQuestion):
            return MessageBody(text: pollQuestion, ranges: .empty)
        }
    }

    public var originalAttachmentSourceFilename: String? {
        switch originalContent {
        case .text:
            return nil
        case .giftBadge:
            return nil
        case .storyReactionEmoji:
            return nil
        case .attachmentStub(_, let stub):
            return stub.sourceFilename
        case .attachment(_, let attachment, _):
            return attachment.reference.sourceFilename
        case .mediaStory:
            return nil
        case .textStory:
            return nil
        case .expiredStory:
            return nil
        case .poll:
            return nil
        }
    }

    public var originalMessageAccessibilityLabel: String? {
        let mediaString = OWSLocalizedString(
            "ACCESSIBILITY_LABEL_MEDIA",
            comment: "Accessibility label for media.",
        )

        switch originalContent {
        case .text(let messageBody):
            return messageBody?.text
        case .giftBadge:
            return nil
        case .storyReactionEmoji(let string):
            return string
        case .attachmentStub(let messageBody, _):
            var captionString = ""
            let caption = messageBody?.text.nilIfEmpty
            if let caption {
                captionString.append(caption + ",")
            }
            return captionString + mediaString
        case .attachment(let messageBody, _, _):
            var captionString = ""
            let caption = messageBody?.text.nilIfEmpty
            if let caption {
                captionString.append(caption + ",")
            }
            return captionString + mediaString
        case .mediaStory(let body, _, _):
            return body?.text
        case .textStory:
            return nil
        case .expiredStory:
            return OWSLocalizedString(
                "STORY_NO_LONGER_AVAILABLE",
                comment: "Text indicating a story that was replied to is no longer available.",
            )
        case .poll(let pollQuestion):
            let formatQuestion = OWSLocalizedString(
                "POLL_ACCESSIBILITY_LABEL",
                comment: "Accessibility label for poll message. Embeds {{ poll question }}.",
            )
            return String.nonPluralLocalizedStringWithFormat(formatQuestion, pollQuestion)
        }
    }

    public var hasQuotedThumbnail: Bool {
        switch originalContent {
        case .text:
            return false
        case .giftBadge:
            // This pretends to be a thumbnail
            return true
        case .storyReactionEmoji:
            return false
        case .attachmentStub:
            return false
        case .attachment(_, _, let thumbnailImage):
            return thumbnailImage != nil
        case .mediaStory:
            return true
        case .textStory:
            return true
        case .expiredStory:
            return false
        case .poll:
            return false
        }
    }

    public static func build(
        replyingTo storyMessage: StoryMessage,
        reactionEmoji: String? = nil,
        transaction: DBReadTransaction,
    ) -> QuotedReplyModel {
        let isOriginalAuthorLocalUser = DependenciesBridge.shared.tsAccountManager
            .localIdentifiers(tx: transaction)?
            .aciAddress
            .isEqualToAddress(storyMessage.authorAddress)
            ?? false

        func buildQuotedReplyModel(
            originalContent: OriginalContent,
        ) -> QuotedReplyModel {
            return QuotedReplyModel(
                originalMessageTimestamp: storyMessage.timestamp,
                originalMessageAuthorAddress: storyMessage.authorAddress,
                originalMessageMemberLabel: nil,
                isOriginalMessageAuthorLocalUser: isOriginalAuthorLocalUser,
                storyReactionEmoji: reactionEmoji,
                originalContent: originalContent,
                sourceOfOriginal: .story,
            )
        }

        switch storyMessage.attachment {
        case .media:
            let referencedAttachment = storyMessage.id.map {
                return DependenciesBridge.shared.attachmentStore
                    .fetchAnyReferencedAttachment(
                        for: .storyMessageMedia(storyMessageRowId: $0),
                        tx: transaction,
                    )
            } ?? nil

            let thumbnailImage: UIImage?
            if let referencedAttachment {
                if let stream = referencedAttachment.attachment.asStream() {
                    thumbnailImage = stream.thumbnailImageSync(quality: .small)
                } else if let blurHash = referencedAttachment.attachment.blurHash {
                    thumbnailImage = BlurHash.image(for: blurHash)
                } else {
                    thumbnailImage = nil
                }
                return buildQuotedReplyModel(originalContent: .mediaStory(
                    body: referencedAttachment.reference.storyMediaCaption,
                    attachment: referencedAttachment,
                    thumbnailImage: thumbnailImage,
                ))
            } else {
                return buildQuotedReplyModel(originalContent: .expiredStory)
            }

        case .text(let textAttachment):
            let preloadedTextAttachment = PreloadedTextAttachment.from(
                textAttachment,
                storyMessage: storyMessage,
                tx: transaction,
            )
            return buildQuotedReplyModel(originalContent: .textStory({ spoilerState in
                return TextAttachmentView(
                    attachment: preloadedTextAttachment,
                    interactionIdentifier: .fromStoryMessage(storyMessage),
                    spoilerState: spoilerState,
                ).asThumbnailView()
            }))
        }
    }

    public static func build(
        storyReplyMessage message: TSMessage,
        storyTimestamp: UInt64?,
        storyAuthorAci: Aci,
        transaction: DBReadTransaction,
    ) -> QuotedReplyModel {
        guard
            let storyTimestamp,
            let storyMessage = StoryFinder.story(
                timestamp: storyTimestamp,
                author: storyAuthorAci,
                transaction: transaction,
            )
        else {
            let isOriginalMessageAuthorLocalUser = DependenciesBridge.shared.tsAccountManager
                .localIdentifiers(tx: transaction)?
                .aci == storyAuthorAci
            return QuotedReplyModel(
                originalMessageTimestamp: storyTimestamp,
                originalMessageAuthorAddress: SignalServiceAddress(storyAuthorAci),
                originalMessageMemberLabel: nil,
                isOriginalMessageAuthorLocalUser: isOriginalMessageAuthorLocalUser,
                storyReactionEmoji: message.storyReactionEmoji,
                originalContent: .expiredStory,
                sourceOfOriginal: .story,
            )
        }
        return QuotedReplyModel.build(
            replyingTo: storyMessage,
            reactionEmoji: message.storyReactionEmoji,
            transaction: transaction,
        )
    }

    // Used for persisted quoted replies, both incoming and outgoing.
    public static func build(
        replyMessage message: TSMessage,
        quotedMessage: TSQuotedMessage,
        memberLabel: String?,
        transaction: DBReadTransaction,
    ) -> QuotedReplyModel {
        func buildQuotedReplyModel(
            originalContent: OriginalContent,
        ) -> QuotedReplyModel {
            let isOriginalAuthorLocalUser = DependenciesBridge.shared.tsAccountManager
                .localIdentifiers(tx: transaction)?
                .aciAddress
                .isEqualToAddress(quotedMessage.authorAddress)
                ?? false

            return QuotedReplyModel(
                originalMessageTimestamp: quotedMessage.timestampValue?.uint64Value,
                originalMessageAuthorAddress: quotedMessage.authorAddress,
                originalMessageMemberLabel: memberLabel,
                isOriginalMessageAuthorLocalUser: isOriginalAuthorLocalUser,
                storyReactionEmoji: nil,
                originalContent: originalContent,
                sourceOfOriginal: quotedMessage.bodySource,
            )
        }

        let originalMessageBody: MessageBody? = quotedMessage.body.map {
            MessageBody(text: $0, ranges: quotedMessage.bodyRanges ?? .empty)
        }

        if quotedMessage.isGiftBadge {
            return buildQuotedReplyModel(originalContent: .giftBadge)
        }

        if quotedMessage.isPoll {
            guard let pollQuestion = originalMessageBody?.text else {
                owsFailDebug("Quoted message is poll but no question found")
                return buildQuotedReplyModel(originalContent: .text(originalMessageBody))
            }
            return buildQuotedReplyModel(originalContent: .poll(pollQuestion))
        }

        if quotedMessage.isTargetMessageViewOnce {
            return buildQuotedReplyModel(originalContent: .text(.init(
                text: OWSLocalizedString(
                    "PER_MESSAGE_EXPIRATION_NOT_VIEWABLE",
                    comment: "inbox cell and notification text for an already viewed view-once media message.",
                ),
                ranges: .empty,
            )))
        }

        let quotedMessageAttachmentReference = DependenciesBridge.shared.attachmentStore.quotedAttachmentReference(
            owningMessage: message,
            tx: transaction,
        )

        switch quotedMessageAttachmentReference {
        case nil:
            return buildQuotedReplyModel(originalContent: .text(originalMessageBody))
        case .stub(let stub):
            return buildQuotedReplyModel(originalContent: .attachmentStub(originalMessageBody, stub))
        case .thumbnail(let thumbnailReferencedAttachment):
            let image: UIImage? = {
                if
                    let image = thumbnailReferencedAttachment.attachment
                        .asStream()?
                        .thumbnailImageSync(quality: .small)
                {
                    return image
                } else if
                    let blurHash = thumbnailReferencedAttachment.attachment.blurHash,
                    let image = BlurHash.image(for: blurHash)
                {
                    return image
                } else {
                    return nil
                }
            }()

            if
                let originalMessageTimestamp = quotedMessage.timestampValue?.uint64Value,
                let originalMessage = InteractionFinder.findMessage(
                    withTimestamp: originalMessageTimestamp,
                    threadId: message.uniqueThreadId,
                    author: quotedMessage.authorAddress,
                    transaction: transaction,
                ),
                let originalAttachmentReference = DependenciesBridge.shared.attachmentStore
                    .attachmentToUseInQuote(
                        originalMessageRowId: originalMessage.sqliteRowId!,
                        tx: transaction,
                    ),
                let originalAttachment = DependenciesBridge.shared.attachmentStore.fetch(
                    id: originalAttachmentReference.attachmentRowId,
                    tx: transaction,
                )
            {
                return buildQuotedReplyModel(originalContent: .attachment(
                    originalMessageBody,
                    attachment: .init(
                        reference: originalAttachmentReference,
                        attachment: originalAttachment,
                    ),
                    thumbnailImage: image,
                ))
            } else {
                return buildQuotedReplyModel(originalContent: .attachment(
                    originalMessageBody,
                    attachment: thumbnailReferencedAttachment,
                    thumbnailImage: image,
                ))
            }
        }
    }

    private init(
        originalMessageTimestamp: UInt64?,
        originalMessageAuthorAddress: SignalServiceAddress,
        originalMessageMemberLabel: String?,
        isOriginalMessageAuthorLocalUser: Bool,
        storyReactionEmoji: String?,
        originalContent: OriginalContent,
        sourceOfOriginal: TSQuotedMessageContentSource,
    ) {
        self.originalMessageTimestamp = originalMessageTimestamp
        self.originalMessageAuthorAddress = originalMessageAuthorAddress
        self.originalMessageMemberLabel = originalMessageMemberLabel
        self.isOriginalMessageAuthorLocalUser = isOriginalMessageAuthorLocalUser
        self.storyReactionEmoji = storyReactionEmoji
        self.originalContent = originalContent
        self.sourceOfOriginal = sourceOfOriginal
    }
}

// MARK: - Equatable

extension QuotedReplyModel: Equatable {
    public static func ==(lhs: QuotedReplyModel, rhs: QuotedReplyModel) -> Bool {
        return lhs.originalMessageTimestamp == rhs.originalMessageTimestamp
            && lhs.originalMessageAuthorAddress == rhs.originalMessageAuthorAddress
            && lhs.isOriginalMessageAuthorLocalUser == rhs.isOriginalMessageAuthorLocalUser
            && lhs.storyReactionEmoji == rhs.storyReactionEmoji
            && lhs.originalContent == rhs.originalContent
            && lhs.sourceOfOriginal == rhs.sourceOfOriginal
    }
}

extension QuotedReplyModel.OriginalContent: Equatable {
    public static func ==(lhs: QuotedReplyModel.OriginalContent, rhs: QuotedReplyModel.OriginalContent) -> Bool {
        switch (lhs, rhs) {
        case let (.text(lhsBody), .text(rhsBody)):
            return lhsBody == rhsBody
        case (.giftBadge, .giftBadge):
            return true
        case let (.storyReactionEmoji(lhsString), .storyReactionEmoji(rhsString)):
            return lhsString == rhsString
        case let (.attachmentStub(lhsBody, lhsStub), .attachmentStub(rhsBody, rhsStub)):
            return lhsBody == rhsBody && lhsStub == rhsStub
        case let (.attachment(lhsBody, lhsAttachment, lhsImage), .attachment(rhsBody, rhsAttachment, rhsImage)):
            return lhsBody == rhsBody
                && lhsAttachment.attachment.id == rhsAttachment.attachment.id
                && lhsImage == rhsImage
        case let (.mediaStory(lhsBody, lhsAttachment, lhsImage), .mediaStory(rhsBody, rhsAttachment, rhsImage)):
            return lhsBody == rhsBody
                && lhsAttachment.attachment.id == rhsAttachment.attachment.id
                && lhsImage == rhsImage
        case (.textStory(_), .textStory(_)):
            /// Defensively re-render every time.
            return false
        case (.expiredStory, .expiredStory):
            return true
        case (.poll, .poll):
            return true
        case
            (.text, _),
            (.giftBadge, _),
            (.storyReactionEmoji, _),
            (.attachmentStub, _),
            (.attachment, _),
            (.mediaStory, _),
            (.textStory, _),
            (.expiredStory, _),
            (.poll, _):
            return false
        }
    }

}
