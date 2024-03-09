//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

// View model which has already fetched any attachments.

public class QuotedReplyModel: NSObject {

    public let timestamp: UInt64?
    public let authorAddress: SignalServiceAddress
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

    public convenience init?(storyMessage: StoryMessage, reactionEmoji: String? = nil, transaction: SDSAnyReadTransaction) {
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

        self.init(
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

    private convenience init?(storyReplyMessage message: TSMessage, transaction: SDSAnyReadTransaction) {
        guard message.isStoryReply else { return nil }

        guard let storyTimestamp = message.storyTimestamp?.uint64Value, let storyAuthorAci = message.storyAuthorAci else {
            return nil
        }

        guard let storyMessage = StoryFinder.story(
            timestamp: storyTimestamp,
            author: storyAuthorAci.wrappedAciValue,
            transaction: transaction
        ) else {
            // Story message does not exist, return generic reply.
            self.init(
                timestamp: storyTimestamp,
                authorAddress: SignalServiceAddress(storyAuthorAci.wrappedAciValue),
                bodySource: .story,
                body: OWSLocalizedString(
                    "STORY_NO_LONGER_AVAILABLE",
                    comment: "Text indicating a story that was replied to is no longer available."
                ),
                bodyRanges: .empty,
                reactionEmoji: message.storyReactionEmoji
            )
            return
        }

        self.init(storyMessage: storyMessage, reactionEmoji: message.storyReactionEmoji, transaction: transaction)
    }

    // Used for persisted quoted replies, both incoming and outgoing.
    public convenience init?(message: TSMessage, transaction: SDSAnyReadTransaction) {
        if message.isStoryReply {
            self.init(storyReplyMessage: message, transaction: transaction)
            return
        }

        guard let quotedMessage = message.quotedMessage else {
            return nil
        }

        let attachmentMetadata = quotedMessage.fetchThumbnailAttachmentMetadata(
            forParentMessage: message,
            transaction: transaction
        )
        let displayableThumbnail: DisplayableQuotedThumbnailAttachment? = attachmentMetadata.map {
            quotedMessage.displayableThumbnailAttachment(
                for: $0,
                parentMessage: message,
                transaction: transaction
            )
        } ?? nil

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

        self.init(
            timestamp: quotedMessage.timestampValue?.uint64Value,
            authorAddress: quotedMessage.authorAddress,
            bodySource: quotedMessage.bodySource,
            body: body,
            bodyRanges: bodyRanges,
            thumbnailImage: displayableThumbnail?.thumbnailImage,
            mimeType: attachmentMetadata?.mimeType,
            contentType: nil,
            sourceFilename: attachmentMetadata?.sourceFilename,
            attachmentType: displayableThumbnail?.attachmentType,
            canTapToDownload: displayableThumbnail?.failedAttachmentPointer != nil,
            isGiftBadge: quotedMessage.isGiftBadge,
            isPayment: isPayment
        )
    }

    // Builds a not-yet-sent QuotedReplyModel
    public static func forSending(item: CVItemViewModel, transaction: SDSAnyReadTransaction) -> QuotedReplyModel? {

        guard let message = item.interaction as? TSMessage else {
            owsFailDebug("unexpected reply message: \(item.interaction)")
            return nil
        }

        let timestamp = message.timestamp

        let authorAddress: SignalServiceAddress? = {
            if message is TSOutgoingMessage {
                return DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)?.aciAddress
            }
            if let incomingMessage = message as? TSIncomingMessage {
                return incomingMessage.authorAddress
            }
            owsFailDebug("Unexpected message type: \(message.self)")
            return nil
        }()
        guard let authorAddress, authorAddress.isValid else {
            owsFailDebug("No authorAddress or address is not valid.")
            return nil
        }

        if message.isViewOnceMessage {
            // We construct a quote that does not include any of the quoted message's renderable content.
            let body = OWSLocalizedString(
                "PER_MESSAGE_EXPIRATION_NOT_VIEWABLE",
                comment: "inbox cell and notification text for an already viewed view-once media message."
            )
            return QuotedReplyModel(
                timestamp: timestamp,
                authorAddress: authorAddress,
                bodySource: .local,
                body: body
            )
        }

        if let contactShare = item.contactShare {
            // TODO We deliberately always pass `nil` for `thumbnailImage`, even though we might have a
            // contactShare.avatarImage because the QuotedReplyViewModel has some hardcoded assumptions that only quoted
            // attachments have thumbnails. Until we address that we want to be consistent about neither showing nor sending
            // the contactShare avatar in the quoted reply.
            return QuotedReplyModel(
                timestamp: timestamp,
                authorAddress: authorAddress,
                bodySource: .local,
                body: "👤 " + contactShare.displayName
            )
        }

        if item.isGiftBadge {
            return QuotedReplyModel(
                timestamp: timestamp,
                authorAddress: authorAddress,
                bodySource: .local,
                isGiftBadge: true
            )
        }

        let isStickerMessage = item.stickerInfo != nil || item.stickerAttachment != nil || item.stickerMetadata != nil
        if isStickerMessage {
            guard
                item.stickerInfo != nil,
                let stickerAttachment = item.stickerAttachment,
                let stickerMetadata = item.stickerMetadata
            else {
                owsFailDebug("Incomplete sticker message.")
                return nil
            }

            guard let stickerData = try? Data(contentsOf: stickerMetadata.stickerDataUrl) else {
                owsFailDebug("Couldn't load sticker data")
                return nil
            }

            // Sticker type metadata isn't reliable, so determine the sticker type by examining the actual sticker data.
            let stickerType: StickerType
            let mimeType: String?
            if stickerMetadata.stickerType == .webp {
                let imageMetadata = (stickerData as NSData).imageMetadata(withPath: nil, mimeType: nil)
                mimeType = imageMetadata.mimeType

                switch imageMetadata.imageFormat {
                case .png:
                    stickerType = .apng

                case .gif:
                    stickerType = .gif

                case .webp:
                    stickerType = .webp

                case .lottieSticker:
                    stickerType = .signalLottie

                case .unknown:
                    owsFailDebug("Unknown sticker data format")
                    return nil

                default:
                    owsFailDebug("Invalid sticker data format: \(NSStringForImageFormat(imageMetadata.imageFormat))")
                    return nil
                }
            } else {
                stickerType = stickerMetadata.stickerType
                mimeType = stickerMetadata.contentType
            }

            let maxThumbnailSizePixels: CGFloat = 512
            let thumbnailImage: UIImage? = {
                switch stickerType {
                case .webp:
                    return (stickerData as NSData).stillForWebpData()
                case .signalLottie:
                    return nil
                case .apng:
                    return UIImage(data: stickerData)
                case .gif:
                    do {
                        let image = try OWSMediaUtils.thumbnail(
                            forImageAtPath: stickerMetadata.stickerDataUrl.path,
                            maxDimensionPixels: maxThumbnailSizePixels
                        )
                        return image
                    } catch {
                        owsFailDebug("Error: \(error)")
                        return nil
                    }
                }
            }()
            guard let resizedThumbnailImage = thumbnailImage?.resized(withMaxDimensionPixels: maxThumbnailSizePixels) else {
                owsFailDebug("Couldn't generate thumbnail for sticker.")
                return nil
            }

            let attachmentType: TSAttachmentType?
            if let message = item.interaction as? TSMessage {
               attachmentType = stickerAttachment.attachmentType(forContainingMessage: message, transaction: transaction)
            } else {
                attachmentType = nil
            }

            return QuotedReplyModel(
                timestamp: timestamp,
                authorAddress: authorAddress,
                bodySource: .local,
                thumbnailImage: resizedThumbnailImage,
                mimeType: mimeType,
                contentType: nil,
                sourceFilename: stickerAttachment.sourceFilename,
                attachmentStream: stickerAttachment,
                attachmentType: attachmentType
            )
        }

        var quotedText: String?
        if let messageBody = message.body, !messageBody.isEmpty {
            quotedText = messageBody
        } else if let storyReactionEmoji = message.storyReactionEmoji, !storyReactionEmoji.isEmpty {
            let formatString: String
            if authorAddress.isLocalAddress {
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
            quotedText = String(
                format: formatString,
                storyReactionEmoji
            )
        }

        var hasText = !quotedText.isEmptyOrNil

        var quotedAttachment: TSAttachmentStream?
        if let attachmentStream = message.bodyAttachments(transaction: transaction).first as? TSAttachmentStream {
            // If the attachment is "oversize text", try the quote as a reply to text, not as
            // a reply to an attachment.
            if !hasText && attachmentStream.contentType == OWSMimeTypeOversizeTextMessage {
                hasText = true
                quotedText = ""

                if  let originalFilePath = attachmentStream.originalFilePath,
                    let oversizeTextData = try? Data(contentsOf: URL(fileURLWithPath: originalFilePath)),
                    let oversizeText = String(data: oversizeTextData, encoding: .utf8) {
                    // We don't need to include the entire text body of the message, just
                    // enough to render a snippet.  kOversizeTextMessageSizeThreshold is our
                    // limit on how long text should be in protos since they'll be stored in
                    // the database. We apply this constant here for the same reasons.
                    // First, truncate to the rough max characters.
                    var truncatedText = oversizeText.substring(to: Int(kOversizeTextMessageSizeThreshold) - 1)
                    // But kOversizeTextMessageSizeThreshold is in _bytes_, not characters,
                    // so we need to continue to trim the string until it fits.
                    var truncatedTextDataSize = truncatedText.data(using: .utf8)?.count ?? 0
                    while truncatedText.count > 0 && truncatedTextDataSize >= kOversizeTextMessageSizeThreshold {
                        // A very coarse binary search by halving is acceptable, since
                        // kOversizeTextMessageSizeThreshold is much longer than our target
                        // length of "three short lines of text on any device we might
                        // display this on.
                        //
                        // The search will always converge since in the worst case (namely
                        // a single character which in utf-8 is >= 1024 bytes) the loop will
                        // exit when the string is empty.
                        truncatedText = truncatedText.substring(to: truncatedText.count / 2)
                        truncatedTextDataSize = truncatedText.data(using: .utf8)?.count ?? 0
                    }
                    if truncatedTextDataSize < kOversizeTextMessageSizeThreshold {
                        quotedText = truncatedText
                    } else {
                        owsFailDebug("Missing valid text snippet.")
                    }
                }
            } else {
                quotedAttachment = attachmentStream
            }
        }

        if  quotedAttachment == nil, item.linkPreview != nil,
            let linkPreviewAttachment = item.linkPreviewAttachment as? TSAttachmentStream {

            quotedAttachment = linkPreviewAttachment
        }

        let hasAttachment = quotedAttachment != nil
        if !hasText && !hasAttachment {
            owsFailDebug("quoted message has neither text nor attachment")
        }

        let thumbnailImage: UIImage?
        if let quotedAttachment, quotedAttachment.isValidVisualMedia {
            thumbnailImage = quotedAttachment.thumbnailImageSmallSync()
        } else {
            thumbnailImage = nil
        }

        let attachmentType: TSAttachmentType?
        if let message = item.interaction as? TSMessage {
           attachmentType = quotedAttachment?.attachmentType(forContainingMessage: message, transaction: transaction)
        } else {
            attachmentType = nil
        }

        return QuotedReplyModel(
            timestamp: timestamp,
            authorAddress: authorAddress,
            bodySource: .local,
            body: quotedText,
            bodyRanges: message.bodyRanges,
            thumbnailImage: thumbnailImage,
            mimeType: quotedAttachment?.mimeType,
            sourceFilename: quotedAttachment?.sourceFilename,
            attachmentStream: quotedAttachment,
            attachmentType: attachmentType
        )
    }

    public func buildQuotedMessageForSending() -> TSQuotedMessage {
        // Legit usage of senderTimestamp to reference existing message
        return TSQuotedMessage(
            timestamp: timestamp.map { NSNumber(value: $0) },
            authorAddress: authorAddress,
            body: body,
            bodyRanges: bodyRanges,
            quotedAttachmentForSending: attachmentStream,
            isGiftBadge: isGiftBadge
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
