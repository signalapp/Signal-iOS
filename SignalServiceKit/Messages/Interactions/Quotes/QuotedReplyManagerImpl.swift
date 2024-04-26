//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class QuotedReplyManagerImpl: QuotedReplyManager {

    private let attachmentManager: TSResourceManager
    private let attachmentStore: TSResourceStore
    private let tsAccountManager: TSAccountManager

    public init(
        attachmentManager: TSResourceManager,
        attachmentStore: TSResourceStore,
        tsAccountManager: TSAccountManager
    ) {
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
        self.tsAccountManager = tsAccountManager
    }

    public func quotedMessage(
        for dataMessage: SSKProtoDataMessage,
        thread: TSThread,
        tx: DBWriteTransaction
    ) -> OwnedAttachmentBuilder<QuotedMessageInfo>? {
        guard let quote = dataMessage.quote else {
            return nil
        }
        let timestamp = quote.id
        guard timestamp != 0 else {
            owsFailDebug("quoted message missing id")
            return nil
        }
        guard SDS.fitsInInt64(timestamp) else {
            owsFailDebug("Invalid timestamp")
            return nil
        }
        guard let quoteAuthor = Aci.parseFrom(aciString: quote.authorAci) else {
            owsFailDebug("quoted message missing author")
            return nil
        }

        let originalMessage = InteractionFinder.findMessage(
            withTimestamp: timestamp,
            threadId: thread.uniqueId,
            author: .init(quoteAuthor),
            transaction: SDSDB.shimOnlyBridge(tx)
        )
        switch originalMessage {
        case .some(let originalMessage):
            // Prefer to generate the quoted content locally if available.
            if
                let localQuotedMessage = self.quotedMessage(
                    originalMessage: originalMessage,
                    quoteProto: quote,
                    author: quoteAuthor,
                    tx: tx
                )
            {
                return localQuotedMessage
            } else {
                fallthrough
            }
        case .none:
            // If we couldn't generate the quoted content from locally available info, we can generate it from the proto.
            return remoteQuotedMessage(
                quoteProto: quote,
                quoteAuthor: quoteAuthor,
                quoteTimestamp: timestamp,
                tx: tx
            )
        }
    }

    /// Builds a remote message from the proto payload
    /// NOTE: Quoted messages constructed from proto material may not be representative of the original source content. This
    /// should be flagged to the user. (See: ``QuotedReplyModel.isRemotelySourced``)
    private func remoteQuotedMessage(
        quoteProto: SSKProtoDataMessageQuote,
        quoteAuthor: Aci,
        quoteTimestamp: UInt64,
        tx: DBWriteTransaction
    ) -> OwnedAttachmentBuilder<QuotedMessageInfo>? {
        let quoteAuthorAddress = SignalServiceAddress(quoteAuthor)

        // This is untrusted content from other users that may not be well-formed.
        // The GiftBadge type has no content/attachments, so don't read those
        // fields if the type is GiftBadge.
        if
            quoteProto.hasType,
            quoteProto.unwrappedType == .giftBadge
        {
            return .withoutFinalizer(.init(
                quotedMessage: TSQuotedMessage(
                    timestamp: quoteTimestamp,
                    authorAddress: quoteAuthorAddress,
                    body: nil,
                    bodyRanges: nil,
                    bodySource: .remote,
                    receivedQuotedAttachmentInfo: nil,
                    isGiftBadge: true
                ),
                renderingFlag: .default
            ))
        }

        let body = quoteProto.text?.nilIfEmpty
        let bodyRanges =  quoteProto.bodyRanges.isEmpty ? nil : MessageBodyRanges(protos: quoteProto.bodyRanges)
        let attachmentBuilder: OwnedAttachmentBuilder<QuotedAttachmentInfo>?
        if
            // We're only interested in the first attachment
            let thumbnailProto = quoteProto.attachments.first?.thumbnail
        {
            do {
                let thumbnailAttachmentBuilder = try attachmentManager.createAttachmentPointerBuilder(
                    from: thumbnailProto,
                    tx: tx
                )
                attachmentBuilder = thumbnailAttachmentBuilder.wrap { attachmentInfo in
                    switch attachmentInfo {
                    case .legacy(let attachmentId):
                        return .init(
                            info: OWSAttachmentInfo(
                                legacyAttachmentId: attachmentId,
                                ofType: .untrustedPointer
                            ),
                            renderingFlag: .fromProto(thumbnailProto)
                        )
                    case .v2:
                        return .init(
                            info: OWSAttachmentInfo(forV2ThumbnailReference: ()),
                            renderingFlag: .fromProto(thumbnailProto)
                        )
                    }
                }
            } catch {
                // Invalid proto!
                return nil
            }
        } else if let attachmentProto = quoteProto.attachments.first, let mimeType = attachmentProto.contentType {
            attachmentBuilder = .withoutFinalizer(.init(
                info: OWSAttachmentInfo.init(
                    stubWithMimeType: mimeType,
                    sourceFilename: attachmentProto.fileName
                ),
                renderingFlag: .default
            ))
        } else {
            attachmentBuilder = nil
        }

        if body?.nilIfEmpty == nil, attachmentBuilder == nil {
            owsFailDebug("Failed to construct a valid quoted message from remote proto content")
            return nil
        }

        func quotedMessage(attachmentInfo: QuotedAttachmentInfo?) -> QuotedMessageInfo {
            return .init(
                quotedMessage: TSQuotedMessage(
                    timestamp: quoteTimestamp,
                    authorAddress: quoteAuthorAddress,
                    body: body,
                    bodyRanges: bodyRanges,
                    bodySource: .remote,
                    receivedQuotedAttachmentInfo: attachmentInfo?.info,
                    isGiftBadge: false
                ),
                renderingFlag: attachmentInfo?.renderingFlag ?? .default
            )
        }

        if let attachmentBuilder {
            return attachmentBuilder.wrap(quotedMessage(attachmentInfo:))
        } else {
            return .withoutFinalizer(quotedMessage(attachmentInfo: nil))
        }
    }

    /// Builds a quoted message from the original source message
    private func quotedMessage(
        originalMessage: TSMessage,
        quoteProto: SSKProtoDataMessageQuote,
        author: Aci,
        tx: DBWriteTransaction
    ) -> OwnedAttachmentBuilder<QuotedMessageInfo>? {
        let authorAddress: SignalServiceAddress
        if let incomingOriginal = originalMessage as? TSIncomingMessage {
            authorAddress = incomingOriginal.authorAddress
        } else if originalMessage is TSOutgoingMessage {
            guard
                let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiers(
                    tx: tx
                )?.aciAddress
            else {
                owsFailDebug("Not registered!")
                return nil
            }
            authorAddress = localAddress
        } else {
            owsFailDebug("Received message of type: \(type(of: originalMessage))")
            return nil
        }

        if originalMessage.isViewOnceMessage {
            // We construct a quote that does not include any of the quoted message's renderable content.
            let body = OWSLocalizedString(
                "PER_MESSAGE_EXPIRATION_NOT_VIEWABLE",
                comment: "inbox cell and notification text for an already viewed view-once media message."
            )
            return .withoutFinalizer(.init(
                quotedMessage: TSQuotedMessage(
                    timestamp: originalMessage.timestamp,
                    authorAddress: authorAddress,
                    body: body,
                    bodyRanges: nil,
                    bodySource: .local,
                    receivedQuotedAttachmentInfo: nil,
                    isGiftBadge: false
                ),
                renderingFlag: .default
            ))
        }

        let body: String?
        let bodyRanges: MessageBodyRanges?
        var isGiftBadge: Bool

        if originalMessage is OWSPaymentMessage {
            // This really should recalculate the string from payment metadata.
            // But it does not.
            body = quoteProto.text
            bodyRanges = nil
            isGiftBadge = false
        } else if let messageBody = originalMessage.body?.nilIfEmpty {
            body = messageBody
            bodyRanges = originalMessage.bodyRanges
            isGiftBadge = false
        } else if let contactName = originalMessage.contactShare?.name.displayName.nilIfEmpty {
            // Contact share bodies are special-cased in OWSQuotedReplyModel
            // We need to account for that here.
            body = "👤 " + contactName
            bodyRanges = nil
            isGiftBadge = false
        } else if let storyReactionEmoji = originalMessage.storyReactionEmoji?.nilIfEmpty  {
            let formatString: String = {
                if (authorAddress.isLocalAddress) {
                    return OWSLocalizedString(
                        "STORY_REACTION_QUOTE_FORMAT_SECOND_PERSON",
                        comment: "quote text for a reaction to a story by the user (the header on the bubble says \"You\"). Embeds {{reaction emoji}}"
                    )
                } else {
                    return OWSLocalizedString(
                        "STORY_REACTION_QUOTE_FORMAT_THIRD_PERSON",
                        comment: "quote text for a reaction to a story by some other user (the header on the bubble says their name, e.g. \"Bob\"). Embeds {{reaction emoji}}"
                    )
                }
            }()
            body = String(format: formatString, storyReactionEmoji)
            bodyRanges = nil
            isGiftBadge = false
        } else {
            isGiftBadge = originalMessage.giftBadge != nil
            body = nil
            bodyRanges = nil
        }

        let attachmentBuilder = self.attachmentBuilder(
            originalMessage: originalMessage,
            quoteProto: quoteProto,
            tx: tx
        )

        if
            body?.nilIfEmpty == nil,
            attachmentBuilder == nil,
            !isGiftBadge
        {
            owsFailDebug("quoted message has no content")
            return nil
        }

        func quotedMessage(attachmentInfo: QuotedAttachmentInfo?) -> QuotedMessageInfo {
            return .init(
                quotedMessage: TSQuotedMessage(
                    timestamp: originalMessage.timestamp,
                    authorAddress: authorAddress,
                    body: body,
                    bodyRanges: bodyRanges,
                    bodySource: .local,
                    receivedQuotedAttachmentInfo: attachmentInfo?.info,
                    isGiftBadge: isGiftBadge
                ),
                renderingFlag: attachmentInfo?.renderingFlag ?? .default
            )
        }

        if let attachmentBuilder {
            return attachmentBuilder.wrap(quotedMessage(attachmentInfo:))
        } else {
            return .withoutFinalizer(quotedMessage(attachmentInfo: nil))
        }
    }

    private func attachmentBuilder(
        originalMessage: TSMessage,
        quoteProto: SSKProtoDataMessageQuote,
        tx: DBWriteTransaction
    ) -> OwnedAttachmentBuilder<QuotedAttachmentInfo>? {
        if quoteProto.attachments.isEmpty {
            // If the quote we got has no attachments, ignore any attachments
            // on the original message.
            return nil
        }
        guard
            let attachmentBuilder = attachmentManager.newQuotedReplyMessageThumbnailBuilder(
                originalMessage: originalMessage,
                tx: tx
            )
        else {
            // This could happen if a sender spoofs their quoted message proto.
            // Our quoted message will include no thumbnails.
            owsFailDebug("Sender sent \(quoteProto.attachments.count) quoted attachments. Local copy has none.")
            return nil
        }
        return attachmentBuilder
    }

    // MARK: - Creating draft

    public func buildDraftQuotedReply(
        originalMessage: TSMessage,
        tx: DBReadTransaction
    ) -> DraftQuotedReplyModel? {
        if originalMessage is OWSPaymentMessage {
            owsFailDebug("Use dedicated DraftQuotedReplyModel initializer for payment messages")
        }

        let timestamp = originalMessage.timestamp

        let authorAddress: SignalServiceAddress? = {
            if originalMessage is TSOutgoingMessage {
                return tsAccountManager.localIdentifiers(tx: tx)?.aciAddress
            }
            if let incomingMessage = originalMessage as? TSIncomingMessage {
                return incomingMessage.authorAddress
            }
            owsFailDebug("Unexpected message type: \(originalMessage.self)")
            return nil
        }()
        guard let authorAddress, authorAddress.isValid else {
            owsFailDebug("No authorAddress or address is not valid.")
            return nil
        }

        let originalMessageBody: () -> MessageBody? = {
            guard let body = originalMessage.body else {
                return nil
            }
            return MessageBody(text: body, ranges: originalMessage.bodyRanges ?? .empty)
        }

        func createDraftReply(content: DraftQuotedReplyModel.Content) -> DraftQuotedReplyModel {
            return DraftQuotedReplyModel(
                originalMessageTimestamp: timestamp,
                originalMessageAuthorAddress: authorAddress,
                isOriginalMessageAuthorLocalUser: originalMessage is TSOutgoingMessage,
                content: content
            )
        }

        func createTextDraftReplyOrNil() -> DraftQuotedReplyModel? {
            if let originalMessageBody = originalMessageBody() {
                return createDraftReply(content: .text(originalMessageBody))
            } else {
                return nil
            }
        }

        if originalMessage.isViewOnceMessage {
            return createDraftReply(content: .viewOnce)
        }

        if let contactShare = originalMessage.contactShare {
            return createDraftReply(content: .contactShare(contactShare))
        }

        if originalMessage.giftBadge != nil {
            return createDraftReply(content: .giftBadge)
        }

        if originalMessage.messageSticker != nil {
            guard
                let attachmentRef = attachmentStore.stickerAttachment(for: originalMessage, tx: tx),
                let attachment = attachmentStore.fetch(attachmentRef.resourceId, tx: tx),
                let stickerData = try? attachment.asResourceStream()?.decryptedRawDataSync()
            else {
                owsFailDebug("Couldn't load sticker data")
                return nil
            }

            // Sticker type metadata isn't reliable, so determine the sticker type by examining the actual sticker data.
            let stickerType: StickerType
            let imageMetadata = stickerData.imageMetadata(withPath: nil, mimeType: nil)
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
                owsFailDebug("Invalid sticker data format: \(imageMetadata.imageFormat)")
                return nil
            }

            let maxThumbnailSizePixels: CGFloat = 512
            let thumbnailImage: UIImage? = { () -> UIImage? in
                switch stickerType {
                case .webp:
                    let image: UIImage? = stickerData.stillForWebpData()
                    return image
                case .signalLottie:
                    return nil
                case .apng:
                    return UIImage(data: stickerData)
                case .gif:
                    do {
                        let image = try OWSMediaUtils.thumbnail(
                            forImageData: stickerData,
                            maxDimensionPixels: maxThumbnailSizePixels
                        )
                        return image
                    } catch {
                        owsFailDebug("Error: \(error)")
                        return nil
                    }
                }
            }()
            guard let resizedThumbnailImage = thumbnailImage?.resized(maxDimensionPixels: maxThumbnailSizePixels) else {
                owsFailDebug("Couldn't generate thumbnail for sticker.")
                return nil
            }

            return createDraftReply(content: .attachment(
                nil,
                attachmentRef: attachmentRef,
                attachment: attachment,
                thumbnailImage: resizedThumbnailImage
            ))
        }

        if let attachmentRef = attachmentStore.attachmentToUseInQuote(originalMessage: originalMessage, tx: tx) {
            let attachment = attachmentStore.fetch(attachmentRef.resourceId, tx: tx)
            if
                let stream = attachment?.asResourceStream(),
                MimeTypeUtil.isSupportedVisualMediaMimeType(stream.mimeType),
                let thumbnailImage = stream.thumbnailImageSync(quality: .small)
            {

                guard
                    let resizedThumbnailImage = thumbnailImage.resized(
                        maxDimensionPoints: AttachmentStream.thumbnailDimensionPointsForQuotedReply
                    )
                else {
                    owsFailDebug("Couldn't generate thumbnail.")
                    return nil
                }

                return createDraftReply(content: .attachment(
                    originalMessageBody(),
                    attachmentRef: attachmentRef,
                    attachment: stream,
                    thumbnailImage: resizedThumbnailImage
                ))
            } else if attachment?.mimeType == MimeType.textXSignalPlain.rawValue {
                // If the attachment is "oversize text", try the quote as a reply to text, not as
                // a reply to an attachment.
                if let oversizeTextData = try? attachment?.asResourceStream()?.decryptedRawDataSync(),
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
                        return createDraftReply(content: .text(
                            MessageBody(text: truncatedText, ranges: originalMessage.bodyRanges ?? .empty)
                        ))
                    } else {
                        owsFailDebug("Missing valid text snippet.")
                        return createTextDraftReplyOrNil()
                    }
                } else {
                    return createTextDraftReplyOrNil()
                }
            } else if let attachment, MimeTypeUtil.isSupportedVisualMediaMimeType(attachment.mimeType) {
                return createDraftReply(content: .attachment(
                    originalMessageBody(),
                    attachmentRef: attachmentRef,
                    attachment: attachment,
                    thumbnailImage: attachment.resourceBlurHash.flatMap(BlurHash.image(for:))
                ))
            } else if
                let stub = QuotedMessageAttachmentReference.Stub(
                    mimeType: attachment?.mimeType,
                    sourceFilename: attachmentRef.sourceFilename)
            {
                return createDraftReply(content: .attachmentStub(
                    originalMessageBody(),
                    stub
                ))
            } else {
                return createTextDraftReplyOrNil()
            }
        }

        if let storyReactionEmoji = originalMessage.storyReactionEmoji?.nilIfEmpty {
            return createDraftReply(content: .storyReactionEmoji(storyReactionEmoji))
        }

        return createTextDraftReplyOrNil()
    }

    public func buildDraftQuotedReplyForEditing(
        quotedReplyMessage: TSMessage,
        quotedReply: TSQuotedMessage,
        originalMessage: TSMessage?,
        tx: DBReadTransaction
    ) -> DraftQuotedReplyModel {
        if
            let originalMessage,
            let innerContent = self.buildDraftQuotedReply(
                originalMessage: originalMessage,
                tx: tx
            )
        {
            return DraftQuotedReplyModel(
                originalMessageTimestamp: innerContent.originalMessageTimestamp,
                originalMessageAuthorAddress: innerContent.originalMessageAuthorAddress,
                isOriginalMessageAuthorLocalUser: innerContent.isOriginalMessageAuthorLocalUser,
                content: .edit(
                    quotedReplyMessage,
                    quotedReply,
                    content: innerContent.content
                )
            )
        } else {
            // Couldn't find the message or build contents.
            // If we can't find the original, use the body we have.
            let isOriginalMessageAuthorLocalUser = tsAccountManager.localIdentifiers(tx: tx)?.aciAddress
                .isEqualToAddress(quotedReply.authorAddress) ?? false

            let innerContent: DraftQuotedReplyModel.Content = {
                let messageBody = quotedReply.body.map { MessageBody(text: $0, ranges: quotedReply.bodyRanges ?? .empty) }
                if
                    let attachmentInfo = quotedReply.attachmentInfo(),
                    let attachmentReference = attachmentStore.quotedAttachmentReference(
                        from: attachmentInfo,
                        parentMessage: quotedReplyMessage,
                        tx: tx
                    )
                {
                    switch attachmentReference {
                    case .thumbnail(let attachmentRef):
                        if let attachment = attachmentStore.fetch(attachmentRef.resourceId, tx: tx) {
                            return .attachment(
                                messageBody,
                                attachmentRef: attachmentRef,
                                attachment: attachment,
                                thumbnailImage: attachment.asResourceStream()?.thumbnailImageSync(quality: .small)
                            )
                        } else if let messageBody {
                            return .text(messageBody)
                        } else {
                            return lastResortQuotedReplyDraftContent()
                        }
                    case .stub(let stub):
                        return .attachmentStub(messageBody, stub)
                    }
                } else if let messageBody {
                    return .text(messageBody)
                } else {
                    return lastResortQuotedReplyDraftContent()
                }
            }()

            return DraftQuotedReplyModel(
                originalMessageTimestamp: quotedReply.timestampValue?.uint64Value,
                originalMessageAuthorAddress: quotedReply.authorAddress,
                isOriginalMessageAuthorLocalUser: isOriginalMessageAuthorLocalUser,
                content: .edit(
                    quotedReplyMessage,
                    quotedReply,
                    content: innerContent
                )
            )
        }
    }

    public func buildQuotedReplyForSending(
        draft: DraftQuotedReplyModel,
        threadUniqueId: String,
        tx: DBWriteTransaction
    ) -> OwnedAttachmentBuilder<QuotedMessageInfo> {
        // Find the original message.
        guard
            let originalMessageTimestamp = draft.originalMessageTimestamp,
            let originalMessage = InteractionFinder.findMessage(
                withTimestamp: originalMessageTimestamp,
                threadId: threadUniqueId,
                author: draft.originalMessageAuthorAddress,
                transaction: SDSDB.shimOnlyBridge(tx)
            )
        else {
            switch draft.content {
            case .edit(_, let tsQuotedMessage, let content):
                return .withoutFinalizer(.init(quotedMessage: tsQuotedMessage, renderingFlag: content.renderingFlag))
            default:
                return .withoutFinalizer(.init(
                    quotedMessage: TSQuotedMessage(
                        targetMessageTimestamp: draft.originalMessageTimestamp.map(NSNumber.init(value:)),
                        authorAddress: draft.originalMessageAuthorAddress,
                        body: OWSLocalizedString(
                            "QUOTED_REPLY_CONTENT_FROM_REMOTE_SOURCE",
                            comment: "Footer label that appears below quoted messages when the quoted content was not derived locally. When the local user doesn't have a copy of the message being quoted, e.g. if it had since been deleted, we instead show the content specified by the sender."
                        ),
                        bodyRanges: nil,
                        bodySource: .remote,
                        isGiftBadge: false
                    ),
                    renderingFlag: draft.content.renderingFlag
                ))
            }
        }

        let body = draft.bodyForSending

        func buildQuotedMessage(_ attachmentInfo: QuotedAttachmentInfo?) -> QuotedMessageInfo {
            return .init(
                quotedMessage: TSQuotedMessage(
                    timestamp: draft.originalMessageTimestamp.map(NSNumber.init(value:)),
                    authorAddress: draft.originalMessageAuthorAddress,
                    body: body?.text,
                    bodyRanges: body?.ranges,
                    quotedAttachmentForSending: attachmentInfo?.info,
                    isGiftBadge: draft.content.isGiftBadge
                ),
                renderingFlag: attachmentInfo?.renderingFlag ?? .default
            )
        }

        if
            originalMessage.isViewOnceMessage.negated,
            let attachmentBuilder = attachmentManager.newQuotedReplyMessageThumbnailBuilder(
                originalMessage: originalMessage,
                tx: tx
            )
        {
            return attachmentBuilder.wrap(buildQuotedMessage(_:))
        } else {
            return .withoutFinalizer(buildQuotedMessage(nil))
        }
    }

    private func lastResortQuotedReplyDraftContent() -> DraftQuotedReplyModel.Content {
        return .text(MessageBody(
            text: OWSLocalizedString(
                "QUOTED_REPLY_CONTENT_FROM_REMOTE_SOURCE",
                comment: "Footer label that appears below quoted messages when the quoted content was not derived locally. When the local user doesn't have a copy of the message being quoted, e.g. if it had since been deleted, we instead show the content specified by the sender."
            ),
            ranges: .empty
        ))
    }

    // MARK: - Outgoing proto

    public func buildProtoForSending(
        _ quote: TSQuotedMessage,
        parentMessage: TSMessage,
        tx: DBReadTransaction
    ) throws -> SSKProtoDataMessageQuote {
        guard let timestamp = quote.timestampValue?.uint64Value else {
            throw OWSAssertionError("Missing timestamp")
        }
        let quoteBuilder = SSKProtoDataMessageQuote.builder(id: timestamp)

        guard let authorAci = quote.authorAddress.aci else {
            throw OWSAssertionError("It should be impossible to quote a message without a UUID")
        }
        quoteBuilder.setAuthorAci(authorAci.serviceIdString)

        var hasQuotedText = false
        var hasQuotedAttachment = false
        var hasQuotedGiftBadge = false

        if let body = quote.body?.nilIfEmpty {
            hasQuotedText = true
            quoteBuilder.setText(body)
            if let bodyRanges = quote.bodyRanges {
                quoteBuilder.setBodyRanges(bodyRanges.toProtoBodyRanges(bodyLength: (body as NSString).length))
            }
        }

        if let attachmentProto = buildAttachmentProtoForSending(for: parentMessage, tx: tx) {
            hasQuotedAttachment = true
            quoteBuilder.setAttachments([attachmentProto])
        }

        if quote.isGiftBadge {
            hasQuotedGiftBadge = true
            quoteBuilder.setType(.giftBadge)
        }

        guard hasQuotedText || hasQuotedAttachment || hasQuotedGiftBadge else {
            throw OWSAssertionError("Invalid quoted message data.")
        }

        return try quoteBuilder.build()
    }

    private func buildAttachmentProtoForSending(
        for parentMessage: TSMessage,
        tx: DBReadTransaction
    ) -> SSKProtoDataMessageQuoteQuotedAttachment? {
        guard
            let reference = attachmentStore.quotedAttachmentReference(for: parentMessage, tx: tx)
        else {
            return nil
        }
        let builder = SSKProtoDataMessageQuoteQuotedAttachment.builder()
        let mimeType: String?
        let sourceFilename: String?
        switch reference {
        case .thumbnail(let attachmentRef):
            sourceFilename = attachmentRef.sourceFilename

            if
                let attachment = attachmentStore.fetch(
                    attachmentRef.resourceId,
                    tx: tx
                )
            {
                mimeType = attachment.mimeType
                if
                    let pointer = attachment.asTransitTierPointer(),
                    let attachmentProto = DependenciesBridge.shared.tsResourceManager.buildProtoForSending(
                        from: attachmentRef,
                        pointer: pointer
                    )
                {
                    builder.setThumbnail(attachmentProto)
                }
            } else {
                mimeType = nil
            }
        case .stub(let stub):
            mimeType = stub.mimeType
            sourceFilename = stub.sourceFilename
        }

        mimeType.map(builder.setContentType(_:))
        sourceFilename.map(builder.setFileName(_:))

        return builder.buildInfallibly()
    }
}
