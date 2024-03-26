//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import LibSignalClient

/// View model for an existing quoted reply which has already fetched any attachments.
/// NOT used for draft quoted replies; this is for TSMessages with quoted replies (or story replies)
/// that have already been created, for use rendering in a conversation.
public class QuotedReplyModel: NSObject {

    public let timestamp: UInt64?
    public let authorAddress: SignalServiceAddress
    /// The attachment stream on the reply message. May still point at the original
    /// message's attachment if the thumbnail copy has not yet occured.
    public let attachmentStream: TSAttachmentStream?
    public let attachmentType: TSAttachmentType?
    public let canTapToDownload: Bool

    // This property should be set IFF we are quoting a text message
    // or attachment with caption.
    public let body: String?
    public let bodyRanges: MessageBodyRanges?
    private let bodySource: TSQuotedMessageContentSource
    public let reactionEmoji: String?

    public var isRemotelySourced: Bool { bodySource == .remote }

    public var isStory: Bool { bodySource == .story }

    public let isGiftBadge: Bool

    public let isPayment: Bool

    // MARK: Attachments

    // This mime type comes from the sender and is not validated.
    //
    // This property should be set IFF we are quoting an attachment message.
    public let mimeType: String?

    // This content type comes from our local device and is validated.
    // Should be preferred to the mimeType if available.
    //
    // This property should be set IFF we are quoting an attachment message.
    public let contentType: TSResourceContentType?

    public let sourceFilename: String?

    public let thumbnailImage: UIImage?
    public let thumbnailViewFactory: ((SpoilerRenderState) -> UIView?)?

    public static func build(
        replyingTo storyMessage: StoryMessage,
        reactionEmoji: String? = nil,
        transaction: SDSAnyReadTransaction
    ) -> QuotedReplyModel {
        let thumbnailImage = storyMessage.thumbnailImage(transaction: transaction)

        let preloadedTextAttachment: PreloadedTextAttachment?
        switch storyMessage.attachment {
        case .file, .foreignReferenceAttachment:
            preloadedTextAttachment = nil
        case .text(let textAttachment):
            preloadedTextAttachment = PreloadedTextAttachment.from(
                textAttachment,
                storyMessage: storyMessage,
                tx: transaction
            )
        }

        let thumbnailViewFactory: ((SpoilerRenderState) -> UIView?)?
        if thumbnailImage == nil, let preloadedTextAttachment  {
            thumbnailViewFactory = { spoilerState in
                return TextAttachmentView(
                    attachment: preloadedTextAttachment,
                    interactionIdentifier: .fromStoryMessage(storyMessage),
                    spoilerState: spoilerState
                ).asThumbnailView()
            }
        } else {
            thumbnailViewFactory = nil
        }

        let attachmentStream: TSAttachmentStream?
        let canTapToDownload: Bool
        let quotedAttachment = storyMessage.fileAttachment(tx: transaction)
        if let quotedAttachmentStream = quotedAttachment as? TSAttachmentStream {
            attachmentStream = quotedAttachmentStream
            canTapToDownload = false
        } else if let attachmentPointer = quotedAttachment as? TSAttachmentPointer {
            attachmentStream = nil
            canTapToDownload = true
        } else {
            attachmentStream = nil
            canTapToDownload = false
        }

        let attachmentType: TSAttachmentType? = quotedAttachment?
            .isLoopingVideo(inContainingStoryMessage: storyMessage, transaction: transaction) ?? false
            ? .GIF : .default

        let body = storyMessage.quotedBody(transaction: transaction)

        return QuotedReplyModel(
            timestamp: storyMessage.timestamp,
            authorAddress: storyMessage.authorAddress,
            bodySource: .story,
            body: body?.text,
            bodyRanges: body?.ranges,
            thumbnailImage: thumbnailImage,
            thumbnailViewFactory: thumbnailViewFactory,
            mimeType: attachmentStream?.mimeType,
            contentType: attachmentStream?.cachedContentType,
            attachmentStream: attachmentStream,
            attachmentType: attachmentType,
            canTapToDownload: canTapToDownload,
            reactionEmoji: reactionEmoji
        )
     }

    public static func build(
        storyReplyMessage message: TSMessage,
        storyTimestamp: UInt64,
        storyAuthorAci: Aci,
        transaction: SDSAnyReadTransaction
    ) -> QuotedReplyModel {
        guard let storyMessage = StoryFinder.story(
            timestamp: storyTimestamp,
            author: storyAuthorAci,
            transaction: transaction
        ) else {
            // Story message does not exist, return generic reply.
            return QuotedReplyModel(
                timestamp: storyTimestamp,
                authorAddress: SignalServiceAddress(storyAuthorAci),
                bodySource: .story,
                body: OWSLocalizedString(
                    "STORY_NO_LONGER_AVAILABLE",
                    comment: "Text indicating a story that was replied to is no longer available."
                ),
                bodyRanges: .empty,
                reactionEmoji: message.storyReactionEmoji
            )
        }

        return QuotedReplyModel.build(
            replyingTo: storyMessage,
            reactionEmoji: message.storyReactionEmoji,
            transaction: transaction
        )
    }

    // Used for persisted quoted replies, both incoming and outgoing.
    public static func build(
        replyMessage message: TSMessage,
        quotedMessage: TSQuotedMessage,
        transaction: SDSAnyReadTransaction
    ) -> QuotedReplyModel {
        let attachmentReference = DependenciesBridge.shared.tsResourceStore.quotedAttachmentReference(
            for: message,
            tx: transaction.asV2Read
        )
        let mimeType: String?
        let contentType: TSResourceContentType?
        let sourceFilename: String?
        let renderingFlag: AttachmentReference.RenderingFlag?
        let canTapToDownload: Bool
        let thumbnailImage: UIImage?
        switch attachmentReference {
        case nil:
            mimeType = nil
            contentType = nil
            sourceFilename = nil
            renderingFlag = nil
            canTapToDownload = false
            thumbnailImage = nil
        case .stub(let stub):
            mimeType = stub.mimeType
            contentType = nil
            sourceFilename = stub.sourceFilename
            renderingFlag = nil
            canTapToDownload = false
            thumbnailImage = nil
        case .thumbnail(let attachmentRef):
            sourceFilename = attachmentRef.sourceFilename
            renderingFlag = attachmentRef.renderingFlag

            // Fetch the full attachment.
            let thumbnailAttachment = DependenciesBridge.shared.tsResourceStore.fetch(
                attachmentRef.resourceId,
                tx: transaction.asV2Read
            )
            mimeType = thumbnailAttachment?.mimeType
            if
                let thumbnailAttachment,
                let image = DependenciesBridge.shared.tsResourceManager.thumbnailImage(
                    attachment: thumbnailAttachment,
                    parentMessage: message,
                    tx: transaction.asV2Read
                )
            {
                contentType = thumbnailAttachment.asResourceStream()?.cachedContentType
                thumbnailImage = image
                canTapToDownload = false
            } else if thumbnailAttachment?.asTransitTierPointer() != nil {
                if let blurHash = thumbnailAttachment?.resourceBlurHash {
                    thumbnailImage = BlurHash.image(for: blurHash)
                } else {
                    thumbnailImage = nil
                }
                contentType = thumbnailAttachment?.asResourceStream()?.cachedContentType
                canTapToDownload = true
            } else {
                contentType = nil
                thumbnailImage = nil
                canTapToDownload = false
            }
        }

        var body: String? = quotedMessage.body
        var bodyRanges: MessageBodyRanges? = quotedMessage.bodyRanges

        let isPayment: Bool
        if let paymentMessage = message as? OWSPaymentMessage {
            isPayment = true
            body = PaymentsFormat.paymentPreviewText(
                paymentMessage: paymentMessage,
                type: message.interactionType,
                transaction: transaction
            )
            bodyRanges = nil
        } else {
            isPayment = false
        }

        return QuotedReplyModel(
            timestamp: quotedMessage.timestampValue?.uint64Value,
            authorAddress: quotedMessage.authorAddress,
            bodySource: quotedMessage.bodySource,
            body: body,
            bodyRanges: bodyRanges,
            thumbnailImage: thumbnailImage,
            mimeType: mimeType,
            contentType: contentType,
            sourceFilename: sourceFilename,
            attachmentType: renderingFlag?.tsAttachmentType,
            canTapToDownload: canTapToDownload,
            isGiftBadge: quotedMessage.isGiftBadge,
            isPayment: isPayment
        )
    }

    private init(
        timestamp: UInt64?,
        authorAddress: SignalServiceAddress,
        bodySource: TSQuotedMessageContentSource,
        body: String? = nil,
        bodyRanges: MessageBodyRanges? = nil,
        thumbnailImage: UIImage? = nil,
        thumbnailViewFactory: ((SpoilerRenderState) -> UIView?)? = nil,
        mimeType: String? = nil,
        contentType: TSResourceContentType? = nil,
        sourceFilename: String? = nil,
        attachmentStream: TSAttachmentStream? = nil,
        attachmentType: TSAttachmentType? = nil,
        canTapToDownload: Bool = false,
        reactionEmoji: String? = nil,
        isGiftBadge: Bool = false,
        isPayment: Bool = false
    ) {
        self.timestamp = timestamp
        self.authorAddress = authorAddress
        self.bodySource = bodySource
        self.body = body
        self.bodyRanges = bodyRanges
        self.thumbnailImage = thumbnailImage
        self.thumbnailViewFactory = thumbnailViewFactory
        self.mimeType = mimeType
        self.contentType = contentType
        self.sourceFilename = sourceFilename
        self.attachmentStream = attachmentStream
        self.attachmentType = attachmentType
        self.canTapToDownload = canTapToDownload
        self.reactionEmoji = reactionEmoji
        self.isGiftBadge = isGiftBadge
        self.isPayment = isPayment
        super.init()
    }
}
