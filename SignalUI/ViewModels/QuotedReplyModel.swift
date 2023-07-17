//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

// View model which has already fetched any attachments.

public class QuotedReplyModel: NSObject {

    public let timestamp: UInt64
    public let authorAddress: SignalServiceAddress
    public let attachmentStream: TSAttachmentStream?
    public let failedThumbnailAttachmentPointer: TSAttachmentPointer?

    // This property should be set IFF we are quoting a text message
    // or attachment with caption.
    public let body: String?
    public let bodyRanges: MessageBodyRanges?
    private let bodySource: TSQuotedMessageContentSource
    public let reactionEmoji: String?

    public var isRemotelySourced: Bool { bodySource == .remote }

    public var isStory: Bool { bodySource == .story }

    public let isGiftBadge: Bool

    // MARK: Attachments

    // This is a MIME type.
    //
    // This property should be set IFF we are quoting an attachment message.
    public let contentType: String?

    public let sourceFilename: String?

    public let thumbnailImage: UIImage?
    public let thumbnailViewFactory: ((SpoilerRenderState) -> UIView?)?

    public convenience init?(storyMessage: StoryMessage, reactionEmoji: String? = nil, transaction: SDSAnyReadTransaction) {
        let thumbnailImage = storyMessage.thumbnailImage(transaction: transaction)
        let thumbnailViewFactory: ((SpoilerRenderState) -> UIView?)?
        if thumbnailImage == nil {
            thumbnailViewFactory = { return storyMessage.thumbnailView(spoilerState: $0) }
        } else {
            thumbnailViewFactory = nil
        }

        let attachmentStream: TSAttachmentStream?
        let failedAttachmentPointer: TSAttachmentPointer?
        let quotedAttachment = storyMessage.quotedAttachment(transaction: transaction)
        if let quotedAttachmentStream = quotedAttachment as? TSAttachmentStream {
            attachmentStream = quotedAttachmentStream
            failedAttachmentPointer = nil
        } else if let attachmentPointer = quotedAttachment as? TSAttachmentPointer {
            attachmentStream = nil
            failedAttachmentPointer = attachmentPointer
        } else {
            attachmentStream = nil
            failedAttachmentPointer = nil
        }

        let body = storyMessage.quotedBody(transaction: transaction)

        self.init(
            timestamp: storyMessage.timestamp,
            authorAddress: storyMessage.authorAddress,
            bodySource: .story,
            body: body?.text,
            bodyRanges: body?.ranges,
            thumbnailImage: thumbnailImage,
            thumbnailViewFactory: thumbnailViewFactory,
            contentType: attachmentStream?.contentType,
            attachmentStream: attachmentStream,
            failedThumbnailAttachmentPointer: failedAttachmentPointer,
            reactionEmoji: reactionEmoji
        )
     }

    private convenience init?(storyReplyMessage message: TSMessage, transaction: SDSAnyReadTransaction) {
        guard message.isStoryReply else { return nil }

        guard let storyTimestamp = message.storyTimestamp?.uint64Value, let storyAuthorAddress = message.storyAuthorAddress else {
            return nil
        }

        guard let storyMessage = StoryFinder.story(
            timestamp: storyTimestamp,
            author: storyAuthorAddress,
            transaction: transaction
        ) else {
            // Story message does not exist, return generic reply.
            self.init(
                timestamp: storyTimestamp,
                authorAddress: storyAuthorAddress,
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

        let thumbnailImage: UIImage?
        let failedAttachmentPointer: TSAttachmentPointer?

        let attachment = message.fetchQuotedMessageThumbnail(with: transaction)
        if let attachmentStream = attachment as? TSAttachmentStream {
            thumbnailImage = attachmentStream.thumbnailImageSmallSync()
            failedAttachmentPointer = nil
        } else if !quotedMessage.isThumbnailOwned {
            // If the quoted message isn't owning the thumbnail attachment, it's going to be referencing
            // some other attachment (e.g. undownloaded media). In this case, let's just use the blur hash
            if let blurHash = attachment?.blurHash {
                thumbnailImage = BlurHash.image(for: blurHash)
            } else {
                thumbnailImage = nil
            }
            failedAttachmentPointer = nil
        } else if let attachmentPointer = attachment as? TSAttachmentPointer {
            // If the quoted message has ownership of the thumbnail, but it hasn't been downloaded yet,
            // we should surface this in the view.
            thumbnailImage = nil
            failedAttachmentPointer = attachmentPointer
        } else {
            thumbnailImage = nil
            failedAttachmentPointer = nil
        }
        self.init(
            timestamp: quotedMessage.timestamp,
            authorAddress: quotedMessage.authorAddress,
            bodySource: quotedMessage.bodySource,
            body: quotedMessage.body,
            bodyRanges: quotedMessage.bodyRanges,
            thumbnailImage: thumbnailImage,
            contentType: quotedMessage.contentType,
            sourceFilename: quotedMessage.sourceFilename,
            failedThumbnailAttachmentPointer: failedAttachmentPointer,
            isGiftBadge: quotedMessage.isGiftBadge
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
                return TSAccountManager.localAddress(with: transaction)
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
            let contentType: String?
            if stickerMetadata.stickerType == .webp {
                let imageMetadata = (stickerData as NSData).imageMetadata(withPath: nil, mimeType: nil)
                contentType = imageMetadata.mimeType

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
                contentType = stickerMetadata.contentType
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

            return QuotedReplyModel(
                timestamp: timestamp,
                authorAddress: authorAddress,
                bodySource: .local,
                thumbnailImage: resizedThumbnailImage,
                contentType: contentType,
                sourceFilename: stickerAttachment.sourceFilename,
                attachmentStream: stickerAttachment
            )
        }

        var quotedText: String?
        if let messageBody = message.body, !messageBody.isEmpty {
            quotedText = messageBody
        } else if let storyReactionEmoji = message.storyReactionEmoji, !storyReactionEmoji.isEmpty {
            quotedText = String(
                format: OWSLocalizedString(
                    "STORY_REACTION_QUOTE_FORMAT",
                    comment: "quote text for a reaction to a story. Embeds {{reaction emoji}}"
                ),
                storyReactionEmoji
            )
        }

        var hasText = !quotedText.isEmptyOrNil

        var quotedAttachment: TSAttachmentStream?
        if let attachmentStream = message.bodyAttachments(with: transaction.unwrapGrdbRead).first as? TSAttachmentStream {
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

        return QuotedReplyModel(
            timestamp: timestamp,
            authorAddress: authorAddress,
            bodySource: .local,
            body: quotedText,
            bodyRanges: message.bodyRanges,
            thumbnailImage: thumbnailImage,
            contentType: quotedAttachment?.contentType,
            sourceFilename: quotedAttachment?.sourceFilename,
            attachmentStream: quotedAttachment
        )
    }

    public func buildQuotedMessageForSending() -> TSQuotedMessage {
        // Legit usage of senderTimestamp to reference existing message
        return TSQuotedMessage(
            timestamp: timestamp,
            authorAddress: authorAddress,
            body: body,
            bodyRanges: bodyRanges,
            quotedAttachmentForSending: attachmentStream,
            isGiftBadge: isGiftBadge
        )
    }

    private init(
        timestamp: UInt64,
        authorAddress: SignalServiceAddress,
        bodySource: TSQuotedMessageContentSource,
        body: String? = nil,
        bodyRanges: MessageBodyRanges? = nil,
        thumbnailImage: UIImage? = nil,
        thumbnailViewFactory: ((SpoilerRenderState) -> UIView?)? = nil,
        contentType: String? = nil,
        sourceFilename: String? = nil,
        attachmentStream: TSAttachmentStream? = nil,
        failedThumbnailAttachmentPointer: TSAttachmentPointer? = nil,
        reactionEmoji: String? = nil,
        isGiftBadge: Bool = false
    ) {
        self.timestamp = timestamp
        self.authorAddress = authorAddress
        self.bodySource = bodySource
        self.body = body
        self.bodyRanges = bodyRanges
        self.thumbnailImage = thumbnailImage
        self.thumbnailViewFactory = thumbnailViewFactory
        self.contentType = contentType
        self.sourceFilename = sourceFilename
        self.attachmentStream = attachmentStream
        self.failedThumbnailAttachmentPointer = failedThumbnailAttachmentPointer
        self.reactionEmoji = reactionEmoji
        self.isGiftBadge = isGiftBadge
        super.init()
    }
}
