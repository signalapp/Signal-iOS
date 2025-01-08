//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class QuotedReplyManagerImpl: QuotedReplyManager {

    private let attachmentManager: AttachmentManager
    private let attachmentStore: AttachmentStore
    private let attachmentValidator: AttachmentContentValidator
    private let db: any DB
    private let tsAccountManager: TSAccountManager

    public init(
        attachmentManager: AttachmentManager,
        attachmentStore: AttachmentStore,
        attachmentValidator: AttachmentContentValidator,
        db: any DB,
        tsAccountManager: TSAccountManager
    ) {
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
        self.attachmentValidator = attachmentValidator
        self.db = db
        self.tsAccountManager = tsAccountManager
    }

    public func quotedMessage(
        for dataMessage: SSKProtoDataMessage,
        thread: TSThread,
        tx: DBWriteTransaction
    ) -> OwnedAttachmentBuilder<TSQuotedMessage>? {
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
    ) -> OwnedAttachmentBuilder<TSQuotedMessage>? {
        let quoteAuthorAddress = SignalServiceAddress(quoteAuthor)

        // This is untrusted content from other users that may not be well-formed.
        // The GiftBadge type has no content/attachments, so don't read those
        // fields if the type is GiftBadge.
        if
            quoteProto.hasType,
            quoteProto.unwrappedType == .giftBadge
        {
            return .withoutFinalizer(TSQuotedMessage(
                timestamp: quoteTimestamp,
                authorAddress: quoteAuthorAddress,
                body: nil,
                bodyRanges: nil,
                bodySource: .remote,
                receivedQuotedAttachmentInfo: nil,
                isGiftBadge: true,
                isTargetMessageViewOnce: false
            ))
        }

        let body = quoteProto.text?.nilIfEmpty
        let bodyRanges =  quoteProto.bodyRanges.isEmpty ? nil : MessageBodyRanges(protos: quoteProto.bodyRanges)
        let attachmentBuilder: OwnedAttachmentBuilder<QuotedAttachmentInfo>?
        if
            // We're only interested in the first attachment
            let quotedAttachment = quoteProto.attachments.first,
            let thumbnailProto = quotedAttachment.thumbnail
        {
            let mimeType: String = quotedAttachment.contentType?.nilIfEmpty
                ?? MimeType.applicationOctetStream.rawValue
            let sourceFilename = quotedAttachment.fileName

            do {
                let thumbnailAttachmentBuilder = try attachmentManager.createAttachmentPointerBuilder(
                    from: thumbnailProto,
                    tx: tx
                )
                attachmentBuilder = thumbnailAttachmentBuilder.wrap {
                    return QuotedAttachmentInfo(
                        info: .forThumbnailReference(
                            withOriginalAttachmentMimeType: mimeType,
                            originalAttachmentSourceFilename: sourceFilename
                        ),
                        renderingFlag: .fromProto(thumbnailProto)
                    )
                }
            } catch {
                // Invalid proto!
                return nil
            }
        } else if let attachmentProto = quoteProto.attachments.first, let mimeType = attachmentProto.contentType {
            attachmentBuilder = .withoutFinalizer(QuotedAttachmentInfo(
                info: .stub(
                    withOriginalAttachmentMimeType: mimeType,
                    originalAttachmentSourceFilename: attachmentProto.fileName
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

        func quotedMessage(attachmentInfo: QuotedAttachmentInfo?) -> TSQuotedMessage {
            return TSQuotedMessage(
                timestamp: quoteTimestamp,
                authorAddress: quoteAuthorAddress,
                body: body,
                bodyRanges: bodyRanges,
                bodySource: .remote,
                receivedQuotedAttachmentInfo: attachmentInfo?.info,
                isGiftBadge: false,
                isTargetMessageViewOnce: false
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
    ) -> OwnedAttachmentBuilder<TSQuotedMessage>? {
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
            return .withoutFinalizer(TSQuotedMessage(
                timestamp: originalMessage.timestamp,
                authorAddress: authorAddress,
                body: nil,
                bodyRanges: nil,
                bodySource: .local,
                receivedQuotedAttachmentInfo: nil,
                isGiftBadge: false,
                isTargetMessageViewOnce: true
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

        func quotedMessage(attachmentInfo: QuotedAttachmentInfo?) -> TSQuotedMessage {
            return TSQuotedMessage(
                timestamp: originalMessage.timestamp,
                authorAddress: authorAddress,
                body: body,
                bodyRanges: bodyRanges,
                bodySource: .local,
                receivedQuotedAttachmentInfo: attachmentInfo?.info,
                isGiftBadge: isGiftBadge,
                isTargetMessageViewOnce: false
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

        if
            let originalMessageRowId = originalMessage.sqliteRowId,
            let originalReference = attachmentStore.attachmentToUseInQuote(
                originalMessageRowId: originalMessageRowId,
                tx: tx
            ),
            let originalAttachment = attachmentStore.fetch(
                id: originalReference.attachmentRowId,
                tx: tx
            )
        {
            return attachmentManager.createQuotedReplyMessageThumbnailBuilder(
                from: .fromOriginalAttachment(
                    originalAttachment,
                    originalReference: originalReference,
                    thumbnailPointerFromSender: quoteProto.attachments.first?.thumbnail
                ),
                tx: tx
            )
        } else {
            // This could happen if a sender spoofs their quoted message proto.
            // Our quoted message will include no thumbnails.
            owsFailDebug("Sender sent \(quoteProto.attachments.count) quoted attachments. Local copy has none.")
            return nil
        }
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
                threadUniqueId: originalMessage.uniqueThreadId,
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
                let originalMessageRowId = originalMessage.sqliteRowId,
                let attachment = attachmentStore.fetchFirstReferencedAttachment(
                    for: .messageSticker(messageRowId: originalMessageRowId),
                    tx: tx
                ),
                let stickerData = try? attachment.attachment.asStream()?.decryptedRawData()
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
                attachmentRef: attachment.reference,
                attachment: attachment.attachment,
                thumbnailImage: resizedThumbnailImage
            ))
        }

        if
            let originalMessageRowId = originalMessage.sqliteRowId,
            let attachmentRef = attachmentStore.attachmentToUseInQuote(originalMessageRowId: originalMessageRowId, tx: tx)
        {
            let attachment = attachmentStore.fetch(id: attachmentRef.attachmentRowId, tx: tx)
            if
                let stream = attachment?.asStream(),
                stream.contentType.isVisualMedia,
                let thumbnailImage = stream.thumbnailImageSync(quality: .small)
            {

                guard
                    let resizedThumbnailImage = thumbnailImage.resized(
                        maxDimensionPoints: AttachmentThumbnailQuality.thumbnailDimensionPointsForQuotedReply
                    )
                else {
                    owsFailDebug("Couldn't generate thumbnail.")
                    return nil
                }

                return createDraftReply(content: .attachment(
                    originalMessageBody(),
                    attachmentRef: attachmentRef,
                    attachment: stream.attachment,
                    thumbnailImage: resizedThumbnailImage
                ))
            } else if attachment?.mimeType == MimeType.textXSignalPlain.rawValue {
                // If the attachment is "oversize text", try the quote as a reply to text, not as
                // a reply to an attachment.
                if
                    let oversizeTextData = try? attachment?.asStream()?.decryptedRawData(),
                    let oversizeText = String(data: oversizeTextData, encoding: .utf8)
                {
                    // We don't need to include the entire text body of the message, just
                    // enough to render a snippet.  kOversizeTextMessageSizeThreshold is our
                    // limit on how long text should be in protos since they'll be stored in
                    // the database. We apply this constant here for the same reasons.
                    let truncatedText = oversizeText.trimToUtf8ByteCount(Int(kOversizeTextMessageSizeThreshold))
                    return createDraftReply(content: .text(
                        MessageBody(text: truncatedText, ranges: originalMessage.bodyRanges ?? .empty)
                    ))
                } else {
                    return createTextDraftReplyOrNil()
                }
            } else if let attachment, MimeTypeUtil.isSupportedVisualMediaMimeType(attachment.mimeType) {
                return createDraftReply(content: .attachment(
                    originalMessageBody(),
                    attachmentRef: attachmentRef,
                    attachment: attachment,
                    thumbnailImage: attachment.blurHash.flatMap(BlurHash.image(for:))
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
                threadUniqueId: quotedReplyMessage.uniqueThreadId,
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
                        if let attachment = attachmentStore.fetch(id: attachmentRef.attachmentRowId, tx: tx) {
                            return .attachment(
                                messageBody,
                                attachmentRef: attachmentRef,
                                attachment: attachment,
                                thumbnailImage: attachment.asStream()?.thumbnailImageSync(quality: .small)
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
                threadUniqueId: quotedReplyMessage.uniqueThreadId,
                content: .edit(
                    quotedReplyMessage,
                    quotedReply,
                    content: innerContent
                )
            )
        }
    }

    public func prepareDraftForSending(
        _ draft: DraftQuotedReplyModel
    ) throws -> DraftQuotedReplyModel.ForSending {
        switch draft.content {
        case .edit(_, let tsQuotedMessage, _):
            return .init(
                originalMessageTimestamp: draft.originalMessageTimestamp,
                originalMessageAuthorAddress: draft.originalMessageAuthorAddress,
                originalMessageIsGiftBadge: draft.content.isGiftBadge,
                originalMessageIsViewOnce: draft.content.isViewOnce,
                threadUniqueId: draft.threadUniqueId,
                quoteBody: draft.bodyForSending,
                attachment: nil,
                quotedMessageFromEdit: tsQuotedMessage
            )
        default:
            break
        }

        // Find the original message and any attachment
        let (originalAttachmentReference, originalAttachment): (
            AttachmentReference?,
            Attachment?
        ) = db.read { tx in
            guard
                let originalMessageTimestamp = draft.originalMessageTimestamp,
                let originalMessage = InteractionFinder.findMessage(
                    withTimestamp: originalMessageTimestamp,
                    threadId: draft.threadUniqueId,
                    author: draft.originalMessageAuthorAddress,
                    transaction: SDSDB.shimOnlyBridge(tx)
                )
            else {
                return (nil, nil)
            }
            let attachmentReference = attachmentStore.attachmentToUseInQuote(
                originalMessageRowId: originalMessage.sqliteRowId!,
                tx: tx
            )
            let attachment = attachmentStore.fetch(ids: [attachmentReference?.attachmentRowId].compacted(), tx: tx).first
            return (attachmentReference, attachment)
        }

        let quoteAttachment = { () -> DraftQuotedReplyModel.ForSending.Attachment? in
            guard let originalAttachmentReference, let originalAttachment else {
                return nil
            }
            let isVisualMedia: Bool = {
                if let contentType = originalAttachment.asStream()?.contentType {
                    return contentType.isVisualMedia
                } else {
                    return MimeTypeUtil.isSupportedVisualMediaMimeType(originalAttachment.mimeType)
                }
            }()
            guard isVisualMedia, let originalAttachmentStream = originalAttachment.asStream() else {
                // Just return a stub for non-visual or undownloaded media.
                return .stub(.init(mimeType: originalAttachment.mimeType, sourceFilename: originalAttachmentReference.sourceFilename))
            }
            do {
                let dataSource = try attachmentValidator.prepareQuotedReplyThumbnail(
                    fromOriginalAttachment: originalAttachmentStream,
                    originalReference: originalAttachmentReference
                )
                return .thumbnail(dataSource: dataSource)
            } catch {
                // If we experience errors, just fall back to a stub.
                return .stub(.init(mimeType: originalAttachment.mimeType, sourceFilename: originalAttachmentReference.sourceFilename))
            }
        }()

        return .init(
            originalMessageTimestamp: draft.originalMessageTimestamp,
            originalMessageAuthorAddress: draft.originalMessageAuthorAddress,
            originalMessageIsGiftBadge: draft.content.isGiftBadge,
            originalMessageIsViewOnce: draft.content.isViewOnce,
            threadUniqueId: draft.threadUniqueId,
            quoteBody: draft.bodyForSending,
            attachment: quoteAttachment,
            quotedMessageFromEdit: nil
        )
    }

    public func buildQuotedReplyForSending(
        draft: DraftQuotedReplyModel.ForSending,
        tx: DBWriteTransaction
    ) -> OwnedAttachmentBuilder<TSQuotedMessage> {
        if let tsQuotedMessage = draft.quotedMessageFromEdit {
            return .withoutFinalizer(tsQuotedMessage)
        }

        // Find the original message.
        guard
            let originalMessageTimestamp = draft.originalMessageTimestamp,
            let originalMessage = InteractionFinder.findMessage(
                withTimestamp: originalMessageTimestamp,
                threadId: draft.threadUniqueId,
                author: draft.originalMessageAuthorAddress,
                transaction: SDSDB.shimOnlyBridge(tx)
            )
        else {
            return .withoutFinalizer(TSQuotedMessage(
                timestamp: draft.originalMessageTimestamp ?? 0,
                authorAddress: draft.originalMessageAuthorAddress,
                body: OWSLocalizedString(
                    "QUOTED_REPLY_CONTENT_FROM_REMOTE_SOURCE",
                    comment: "Footer label that appears below quoted messages when the quoted content was not derived locally. When the local user doesn't have a copy of the message being quoted, e.g. if it had since been deleted, we instead show the content specified by the sender."
                ),
                bodyRanges: nil,
                bodySource: .remote,
                receivedQuotedAttachmentInfo: nil,
                isGiftBadge: false,
                isTargetMessageViewOnce: false
            ))
        }

        let body = draft.quoteBody

        func buildQuotedMessage(_ attachmentInfo: QuotedAttachmentInfo?) -> TSQuotedMessage {
            return TSQuotedMessage(
                timestamp: draft.originalMessageTimestamp.map(NSNumber.init(value:)),
                authorAddress: draft.originalMessageAuthorAddress,
                body: body?.text,
                bodyRanges: body?.ranges,
                quotedAttachmentForSending: attachmentInfo?.info,
                isGiftBadge: draft.originalMessageIsGiftBadge,
                isTargetMessageViewOnce: draft.originalMessageIsViewOnce
            )
        }

        guard let quotedAttachment = draft.attachment, originalMessage.isViewOnceMessage.negated else {
            return .withoutFinalizer(buildQuotedMessage(nil))
        }

        switch quotedAttachment {
        case .stub(let stub):
            return .withoutFinalizer(buildQuotedMessage(QuotedAttachmentInfo(
                info: .stub(
                    withOriginalAttachmentMimeType: stub.mimeType ?? MimeType.applicationOctetStream.rawValue,
                    originalAttachmentSourceFilename: stub.sourceFilename
                ),
                renderingFlag: .default
            )))
        case .thumbnail(let dataSource):
            let attachmentBuilder = attachmentManager.createQuotedReplyMessageThumbnailBuilder(
                from: dataSource,
                tx: tx
            )
            return attachmentBuilder.wrap(buildQuotedMessage(_:))
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

        if quote.isTargetMessageViewOnce {
            if !hasQuotedText {
                quoteBuilder.setText(OWSLocalizedString(
                    "PER_MESSAGE_EXPIRATION_NOT_VIEWABLE",
                    comment: "inbox cell and notification text for an already viewed view-once media message."
                ))
            }
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
                    id: attachmentRef.attachmentRowId,
                    tx: tx
                )
            {
                mimeType = attachment.mimeType
                if
                    let pointer = attachment.asTransitTierPointer()
                {
                    let attachmentProto = attachmentManager.buildProtoForSending(
                        from: attachmentRef,
                        pointer: pointer
                    )
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
