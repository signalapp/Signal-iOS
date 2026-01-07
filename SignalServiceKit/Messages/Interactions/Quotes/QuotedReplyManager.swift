//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public struct ValidatedQuotedReply {
    public let quotedReply: TSQuotedMessage
    public let thumbnailDataSource: QuotedReplyAttachmentDataSource?
}

// MARK: -

public protocol QuotedReplyManager {

    func validateAndBuildQuotedReply(
        from quoteProto: SSKProtoDataMessageQuote,
        threadUniqueId: String,
        tx: DBReadTransaction,
    ) throws -> ValidatedQuotedReply

    func buildDraftQuotedReply(
        originalMessage: TSMessage,
        tx: DBReadTransaction,
    ) -> DraftQuotedReplyModel?

    func buildDraftQuotedReplyForEditing(
        quotedReplyMessage: TSMessage,
        quotedReply: TSQuotedMessage,
        originalMessage: TSMessage?,
        tx: DBReadTransaction,
    ) -> DraftQuotedReplyModel

    func prepareDraftForSending(
        _ draft: DraftQuotedReplyModel,
    ) async throws -> DraftQuotedReplyModel.ForSending

    func prepareQuotedReplyForSending(
        draft: DraftQuotedReplyModel.ForSending,
        tx: DBReadTransaction,
    ) -> ValidatedQuotedReply

    func buildProtoForSending(
        _ quote: TSQuotedMessage,
        parentMessage: TSMessage,
        tx: DBReadTransaction,
    ) throws -> SSKProtoDataMessageQuote
}

// MARK: -

class QuotedReplyManagerImpl: QuotedReplyManager {

    private let attachmentManager: AttachmentManager
    private let attachmentStore: AttachmentStore
    private let attachmentValidator: AttachmentContentValidator
    private let db: any DB
    private let tsAccountManager: TSAccountManager

    init(
        attachmentManager: AttachmentManager,
        attachmentStore: AttachmentStore,
        attachmentValidator: AttachmentContentValidator,
        db: any DB,
        tsAccountManager: TSAccountManager,
    ) {
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
        self.attachmentValidator = attachmentValidator
        self.db = db
        self.tsAccountManager = tsAccountManager
    }

    func validateAndBuildQuotedReply(
        from quoteProto: SSKProtoDataMessageQuote,
        threadUniqueId: String,
        tx: DBReadTransaction,
    ) throws -> ValidatedQuotedReply {
        let timestamp = quoteProto.id
        guard timestamp != 0, SDS.fitsInInt64(timestamp) else {
            throw OWSAssertionError("Quoted message invalid timestamp! \(timestamp)")
        }

        guard
            let quoteAuthor = Aci.parseFrom(
                serviceIdBinary: quoteProto.authorAciBinary,
                serviceIdString: quoteProto.authorAci,
            )
        else {
            throw OWSAssertionError("Quoted message missing or invalid author!")
        }

        let originalMessage = InteractionFinder.findMessage(
            withTimestamp: timestamp,
            threadId: threadUniqueId,
            author: .init(quoteAuthor),
            transaction: tx,
        )
        if let originalMessage {
            // Prefer to generate the quoted content locally if available.
            do {
                return try localQuotedMessage(
                    originalMessage: originalMessage,
                    quoteProto: quoteProto,
                    quoteAuthor: quoteAuthor,
                    tx: tx,
                )
            } catch {
                Logger.warn("Failed to build quote message locally! \(error)")
            }
        }

        // If we couldn't generate the quoted content from local data, we can
        // generate it from the proto.
        return try remoteQuotedMessage(
            quoteProto: quoteProto,
            quoteAuthor: quoteAuthor,
            quoteTimestamp: timestamp,
            tx: tx,
        )
    }

    /// Builds a remote message from the proto payload
    /// NOTE: Quoted messages constructed from proto material may not be representative of the original source content. This
    /// should be flagged to the user. (See: ``QuotedReplyModel.isRemotelySourced``)
    private func remoteQuotedMessage(
        quoteProto: SSKProtoDataMessageQuote,
        quoteAuthor: Aci,
        quoteTimestamp: UInt64,
        tx: DBReadTransaction,
    ) throws -> ValidatedQuotedReply {
        let quoteAuthorAddress = SignalServiceAddress(quoteAuthor)

        // This is untrusted content from other users that may not be well-formed.
        // The GiftBadge type has no content/attachments, so don't read those
        // fields if the type is GiftBadge.
        if
            quoteProto.hasType,
            quoteProto.unwrappedType == .giftBadge
        {
            return ValidatedQuotedReply(
                quotedReply: TSQuotedMessage(
                    timestamp: quoteTimestamp,
                    authorAddress: quoteAuthorAddress,
                    body: nil,
                    bodyRanges: nil,
                    bodySource: .remote,
                    receivedQuotedAttachmentInfo: nil,
                    isGiftBadge: true,
                    isTargetMessageViewOnce: false,
                    isPoll: false,
                ),
                thumbnailDataSource: nil,
            )
        }

        let body = quoteProto.text?.nilIfEmpty
        let bodyRanges = quoteProto.bodyRanges.isEmpty ? nil : MessageBodyRanges(protos: quoteProto.bodyRanges)

        let thumbnailAttachmentInfo: OWSAttachmentInfo?
        let thumbnailDataSource: QuotedReplyAttachmentDataSource?
        if
            // We're only interested in the first attachment
            let quotedAttachment = quoteProto.attachments.first,
            let thumbnailProto = quotedAttachment.thumbnail
        {
            let mimeType: String = quotedAttachment.contentType?.nilIfEmpty
                ?? MimeType.applicationOctetStream.rawValue

            thumbnailAttachmentInfo = OWSAttachmentInfo(
                originalAttachmentMimeType: mimeType,
                originalAttachmentSourceFilename: quotedAttachment.fileName,
            )
            thumbnailDataSource = .notFoundLocallyAttachment(.init(
                thumbnailPointerProto: thumbnailProto,
                originalAttachmentMimeType: mimeType,
            ))
        } else if
            let quotedAttachment = quoteProto.attachments.first,
            let mimeType = quotedAttachment.contentType
        {
            thumbnailAttachmentInfo = OWSAttachmentInfo(
                originalAttachmentMimeType: mimeType,
                originalAttachmentSourceFilename: quotedAttachment.fileName,
            )
            thumbnailDataSource = nil
        } else {
            thumbnailAttachmentInfo = nil
            thumbnailDataSource = nil
        }

        if body?.nilIfEmpty == nil, thumbnailAttachmentInfo == nil {
            throw OWSAssertionError("Remote quoted message proto missing content!")
        }

        return ValidatedQuotedReply(
            quotedReply: TSQuotedMessage(
                timestamp: quoteTimestamp,
                authorAddress: quoteAuthorAddress,
                body: body,
                bodyRanges: bodyRanges,
                bodySource: .remote,
                receivedQuotedAttachmentInfo: thumbnailAttachmentInfo,
                isGiftBadge: false,
                isTargetMessageViewOnce: false,
                isPoll: false,
            ),
            thumbnailDataSource: thumbnailDataSource,
        )
    }

    /// Builds a quoted message from the original source message
    private func localQuotedMessage(
        originalMessage: TSMessage,
        quoteProto: SSKProtoDataMessageQuote,
        quoteAuthor: Aci,
        tx: DBReadTransaction,
    ) throws -> ValidatedQuotedReply {
        let authorAddress: SignalServiceAddress
        if let incomingOriginal = originalMessage as? TSIncomingMessage {
            authorAddress = incomingOriginal.authorAddress
        } else if originalMessage is TSOutgoingMessage {
            guard
                let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiers(
                    tx: tx,
                )?.aciAddress
            else {
                throw NotRegisteredError()
            }
            authorAddress = localAddress
        } else {
            throw OWSAssertionError("Received message of type: \(type(of: originalMessage))")
        }

        if originalMessage.isViewOnceMessage {
            // We construct a quote that does not include any of the quoted message's renderable content.
            return ValidatedQuotedReply(
                quotedReply: TSQuotedMessage(
                    timestamp: originalMessage.timestamp,
                    authorAddress: authorAddress,
                    body: nil,
                    bodyRanges: nil,
                    bodySource: .local,
                    receivedQuotedAttachmentInfo: nil,
                    isGiftBadge: false,
                    isTargetMessageViewOnce: true,
                    isPoll: false,
                ),
                thumbnailDataSource: nil,
            )
        }

        let body: String?
        let bodyRanges: MessageBodyRanges?
        var isGiftBadge: Bool
        var isPoll: Bool

        if originalMessage is OWSPaymentMessage {
            // This really should recalculate the string from payment metadata.
            // But it does not.
            body = quoteProto.text
            bodyRanges = nil
            isGiftBadge = false
            isPoll = false
        } else if let messageBody = originalMessage.body?.nilIfEmpty {
            body = messageBody
            bodyRanges = originalMessage.bodyRanges
            isGiftBadge = false
            isPoll = originalMessage.isPoll
        } else if let contactName = originalMessage.contactShare?.name.displayName.nilIfEmpty {
            // Contact share bodies are special-cased in OWSQuotedReplyModel
            // We need to account for that here.
            body = "👤 " + contactName
            bodyRanges = nil
            isGiftBadge = false
            isPoll = false
        } else if let storyReactionEmoji = originalMessage.storyReactionEmoji?.nilIfEmpty {
            let formatString: String = {
                if authorAddress.isLocalAddress {
                    return OWSLocalizedString(
                        "STORY_REACTION_QUOTE_FORMAT_SECOND_PERSON",
                        comment: "quote text for a reaction to a story by the user (the header on the bubble says \"You\"). Embeds {{reaction emoji}}",
                    )
                } else {
                    return OWSLocalizedString(
                        "STORY_REACTION_QUOTE_FORMAT_THIRD_PERSON",
                        comment: "quote text for a reaction to a story by some other user (the header on the bubble says their name, e.g. \"Bob\"). Embeds {{reaction emoji}}",
                    )
                }
            }()
            body = String(format: formatString, storyReactionEmoji)
            bodyRanges = nil
            isGiftBadge = false
            isPoll = false
        } else {
            isGiftBadge = originalMessage.giftBadge != nil
            body = nil
            bodyRanges = nil
            isPoll = false
        }

        let thumbnailAttachmentInfo: OWSAttachmentInfo?
        let thumbnailDataSource: QuotedReplyAttachmentDataSource?
        if
            let (info, dataSource) = quotedReplyAttachmentInfo(
                originalMessage: originalMessage,
                quoteProto: quoteProto,
                tx: tx,
            )
        {
            thumbnailAttachmentInfo = info
            thumbnailDataSource = dataSource
        } else {
            thumbnailAttachmentInfo = nil
            thumbnailDataSource = nil
        }

        if
            body?.nilIfEmpty == nil,
            thumbnailAttachmentInfo == nil,
            !isGiftBadge
        {
            throw OWSAssertionError("Quoted message has no content!")
        }

        return ValidatedQuotedReply(
            quotedReply: TSQuotedMessage(
                timestamp: originalMessage.timestamp,
                authorAddress: authorAddress,
                body: body,
                bodyRanges: bodyRanges,
                bodySource: .local,
                receivedQuotedAttachmentInfo: thumbnailAttachmentInfo,
                isGiftBadge: isGiftBadge,
                // Checked above
                isTargetMessageViewOnce: false,
                isPoll: isPoll,
            ),
            thumbnailDataSource: thumbnailDataSource,
        )
    }

    private func quotedReplyAttachmentInfo(
        originalMessage: TSMessage,
        quoteProto: SSKProtoDataMessageQuote,
        tx: DBReadTransaction,
    ) -> (OWSAttachmentInfo, QuotedReplyAttachmentDataSource)? {
        if quoteProto.attachments.isEmpty {
            // If the quote we got has no attachments, ignore any attachments
            // on the original message.
            return nil
        }

        if
            let originalMessageRowId = originalMessage.sqliteRowId,
            let originalReference = attachmentStore.attachmentToUseInQuote(
                originalMessageRowId: originalMessageRowId,
                tx: tx,
            ),
            let originalAttachment = attachmentStore.fetch(
                id: originalReference.attachmentRowId,
                tx: tx,
            )
        {
            let attachmentInfo = OWSAttachmentInfo(
                originalAttachmentMimeType: originalAttachment.mimeType,
                originalAttachmentSourceFilename: originalReference.sourceFilename,
            )

            let dataSource: QuotedReplyAttachmentDataSource = .originalAttachment(.init(
                id: originalAttachment.id,
                mimeType: originalAttachment.mimeType,
                renderingFlag: originalReference.renderingFlag,
                sourceFilename: originalReference.sourceFilename,
                sourceUnencryptedByteCount: originalReference.sourceUnencryptedByteCount,
                sourceMediaSizePixels: originalReference.sourceMediaSizePixels,
                thumbnailPointerFromSender: quoteProto.attachments.first?.thumbnail,
            ))

            return (attachmentInfo, dataSource)
        } else {
            // This could happen if a sender spoofs their quoted message proto.
            // Our quoted message will include no thumbnails.
            owsFailDebug("Sender sent \(quoteProto.attachments.count) quoted attachments. Local copy has none.")
            return nil
        }
    }

    // MARK: - Creating draft

    func buildDraftQuotedReply(
        originalMessage: TSMessage,
        tx: DBReadTransaction,
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
                content: content,
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
                let attachment = attachmentStore.fetchAnyReferencedAttachment(
                    for: .messageSticker(messageRowId: originalMessageRowId),
                    tx: tx,
                ),
                let stickerData = try? attachment.attachment.asStream()?.decryptedRawData()
            else {
                owsFailDebug("Couldn't load sticker data")
                return nil
            }

            // Sticker type metadata isn't reliable, so determine the sticker type by examining the actual sticker data.
            let stickerType: StickerType
            let imageMetadata = DataImageSource(stickerData).imageMetadata()
            switch imageMetadata?.imageFormat {
            case .png:
                stickerType = .apng

            case .gif:
                stickerType = .gif

            case .webp:
                stickerType = .webp

            case nil:
                owsFailDebug("Unknown sticker data format")
                return nil

            case .some(let imageFormat):
                owsFailDebug("Invalid sticker data format: \(imageFormat)")
                return nil
            }

            let maxThumbnailSizePixels: CGFloat = 512
            let thumbnailImage: UIImage? = { () -> UIImage? in
                switch stickerType {
                case .webp:
                    let image: UIImage? = DataImageSource(stickerData).stillForWebpData()
                    return image
                case .apng:
                    return UIImage(data: stickerData)
                case .gif:
                    do {
                        let image = try OWSMediaUtils.thumbnail(
                            forImageData: stickerData,
                            maxDimensionPixels: maxThumbnailSizePixels,
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
                thumbnailImage: resizedThumbnailImage,
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
                        maxDimensionPoints: AttachmentThumbnailQuality.thumbnailDimensionPointsForQuotedReply,
                    )
                else {
                    owsFailDebug("Couldn't generate thumbnail.")
                    return nil
                }

                return createDraftReply(content: .attachment(
                    originalMessageBody(),
                    attachmentRef: attachmentRef,
                    attachment: stream.attachment,
                    thumbnailImage: resizedThumbnailImage,
                ))
            } else if attachment?.mimeType == MimeType.textXSignalPlain.rawValue {
                // If the attachment is "oversize text", try the quote as a reply to text, not as
                // a reply to an attachment.
                if
                    let oversizeTextData = try? attachment?.asStream()?.decryptedRawData(),
                    let oversizeText = String(data: oversizeTextData, encoding: .utf8)
                {
                    // We don't need to include the entire text body of the message, just enough
                    // to render a snippet.  OWSMediaUtils.kOversizeTextMessageSizeThresholdBytes
                    // is our limit on how long text should be in protos since they'll be stored in
                    // the database. We apply this constant here for the same reasons.
                    let truncatedText = oversizeText.trimToUtf8ByteCount(OWSMediaUtils.kOversizeTextMessageSizeThresholdBytes)
                    return createDraftReply(content: .text(
                        MessageBody(text: truncatedText, ranges: originalMessage.bodyRanges ?? .empty),
                    ))
                } else {
                    return createTextDraftReplyOrNil()
                }
            } else if let attachment, MimeTypeUtil.isSupportedVisualMediaMimeType(attachment.mimeType) {
                return createDraftReply(content: .attachment(
                    originalMessageBody(),
                    attachmentRef: attachmentRef,
                    attachment: attachment,
                    thumbnailImage: attachment.blurHash.flatMap(BlurHash.image(for:)),
                ))
            } else if
                let stub = QuotedMessageAttachmentReference.Stub(
                    mimeType: attachment?.mimeType,
                    sourceFilename: attachmentRef.sourceFilename,
                )
            {
                return createDraftReply(content: .attachmentStub(
                    originalMessageBody(),
                    stub,
                ))
            } else {
                return createTextDraftReplyOrNil()
            }
        }

        if let storyReactionEmoji = originalMessage.storyReactionEmoji?.nilIfEmpty {
            return createDraftReply(content: .storyReactionEmoji(storyReactionEmoji))
        }

        if originalMessage.isPoll {
            guard let body = originalMessage.body else {
                owsFailDebug("Poll message has no question body.")
                return nil
            }
            return createDraftReply(content: .poll(body))
        }

        return createTextDraftReplyOrNil()
    }

    func buildDraftQuotedReplyForEditing(
        quotedReplyMessage: TSMessage,
        quotedReply: TSQuotedMessage,
        originalMessage: TSMessage?,
        tx: DBReadTransaction,
    ) -> DraftQuotedReplyModel {
        if
            let originalMessage,
            let innerContent = self.buildDraftQuotedReply(
                originalMessage: originalMessage,
                tx: tx,
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
                    content: innerContent.content,
                ),
            )
        } else {
            // Couldn't find the message or build contents.
            // If we can't find the original, use the body we have.
            let isOriginalMessageAuthorLocalUser = tsAccountManager.localIdentifiers(tx: tx)?.aciAddress
                .isEqualToAddress(quotedReply.authorAddress) ?? false

            let innerContent: DraftQuotedReplyModel.Content = {
                let messageBody = quotedReply.body.map { MessageBody(text: $0, ranges: quotedReply.bodyRanges ?? .empty) }
                if
                    let quotedAttachmentReference = attachmentStore.quotedAttachmentReference(
                        parentMessage: quotedReplyMessage,
                        tx: tx,
                    )
                {
                    switch quotedAttachmentReference {
                    case .thumbnail(let attachmentRef):
                        if let attachment = attachmentStore.fetch(id: attachmentRef.attachmentRowId, tx: tx) {
                            return .attachment(
                                messageBody,
                                attachmentRef: attachmentRef,
                                attachment: attachment,
                                thumbnailImage: attachment.asStream()?.thumbnailImageSync(quality: .small),
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
                    content: innerContent,
                ),
            )
        }
    }

    func prepareDraftForSending(
        _ draft: DraftQuotedReplyModel,
    ) async throws -> DraftQuotedReplyModel.ForSending {
        switch draft.content {
        case .edit(_, let tsQuotedMessage, _):
            return DraftQuotedReplyModel.ForSending(
                originalMessageTimestamp: draft.originalMessageTimestamp,
                originalMessageAuthorAddress: draft.originalMessageAuthorAddress,
                originalMessageIsGiftBadge: draft.content.isGiftBadge,
                originalMessageIsViewOnce: draft.content.isViewOnce,
                originalMessageIsPoll: draft.content.isPoll,
                threadUniqueId: draft.threadUniqueId,
                quoteBody: draft.bodyForSending,
                attachment: nil,
                quotedMessageFromEdit: tsQuotedMessage,
            )
        default:
            break
        }

        // Find the original message and any attachment
        let originalAttachmentReference: AttachmentReference?
        let originalAttachment: Attachment?
        (
            originalAttachmentReference,
            originalAttachment,
        ) = db.read { tx in
            guard
                let originalMessageTimestamp = draft.originalMessageTimestamp,
                let originalMessage = InteractionFinder.findMessage(
                    withTimestamp: originalMessageTimestamp,
                    threadId: draft.threadUniqueId,
                    author: draft.originalMessageAuthorAddress,
                    transaction: tx,
                )
            else {
                return (nil, nil)
            }
            let attachmentReference = attachmentStore.attachmentToUseInQuote(
                originalMessageRowId: originalMessage.sqliteRowId!,
                tx: tx,
            )
            let attachment = attachmentStore.fetch(ids: [attachmentReference?.attachmentRowId].compacted(), tx: tx).first
            return (attachmentReference, attachment)
        }

        let quoteAttachment = await { () -> DraftQuotedReplyModel.ForSending.Attachment? in
            guard
                let originalAttachmentReference,
                let originalAttachment
            else {
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
                let dataSource = try await attachmentValidator.prepareQuotedReplyThumbnail(
                    fromOriginalAttachment: originalAttachmentStream,
                    originalReference: originalAttachmentReference,
                )
                return .thumbnail(
                    dataSource,
                    originalAttachmentSourceFilename: originalAttachmentReference.sourceFilename,
                )
            } catch {
                // If we experience errors, just fall back to a stub.
                return .stub(.init(mimeType: originalAttachment.mimeType, sourceFilename: originalAttachmentReference.sourceFilename))
            }
        }()

        return DraftQuotedReplyModel.ForSending(
            originalMessageTimestamp: draft.originalMessageTimestamp,
            originalMessageAuthorAddress: draft.originalMessageAuthorAddress,
            originalMessageIsGiftBadge: draft.content.isGiftBadge,
            originalMessageIsViewOnce: draft.content.isViewOnce,
            originalMessageIsPoll: draft.content.isPoll,
            threadUniqueId: draft.threadUniqueId,
            quoteBody: draft.bodyForSending,
            attachment: quoteAttachment,
            quotedMessageFromEdit: nil,
        )
    }

    func prepareQuotedReplyForSending(
        draft: DraftQuotedReplyModel.ForSending,
        tx: DBReadTransaction,
    ) -> ValidatedQuotedReply {
        if let tsQuotedMessage = draft.quotedMessageFromEdit {
            return ValidatedQuotedReply(
                quotedReply: tsQuotedMessage,
                thumbnailDataSource: nil,
            )
        }

        // Find the original message.
        guard
            let originalMessageTimestamp = draft.originalMessageTimestamp,
            let originalMessage = InteractionFinder.findMessage(
                withTimestamp: originalMessageTimestamp,
                threadId: draft.threadUniqueId,
                author: draft.originalMessageAuthorAddress,
                transaction: tx,
            )
        else {
            return ValidatedQuotedReply(
                quotedReply: TSQuotedMessage(
                    timestamp: draft.originalMessageTimestamp ?? 0,
                    authorAddress: draft.originalMessageAuthorAddress,
                    body: OWSLocalizedString(
                        "QUOTED_REPLY_CONTENT_FROM_REMOTE_SOURCE",
                        comment: "Footer label that appears below quoted messages when the quoted content was not derived locally. When the local user doesn't have a copy of the message being quoted, e.g. if it had since been deleted, we instead show the content specified by the sender.",
                    ),
                    bodyRanges: nil,
                    bodySource: .remote,
                    receivedQuotedAttachmentInfo: nil,
                    isGiftBadge: false,
                    isTargetMessageViewOnce: false,
                    isPoll: false,
                ),
                thumbnailDataSource: nil,
            )
        }

        let body = draft.quoteBody

        func buildQuotedMessage(_ attachmentInfo: OWSAttachmentInfo?) -> TSQuotedMessage {
            return TSQuotedMessage(
                timestamp: draft.originalMessageTimestamp.map(NSNumber.init(value:)),
                authorAddress: draft.originalMessageAuthorAddress,
                body: body?.text,
                bodyRanges: body?.ranges,
                quotedAttachmentForSending: attachmentInfo,
                isGiftBadge: draft.originalMessageIsGiftBadge,
                isTargetMessageViewOnce: draft.originalMessageIsViewOnce,
                isPoll: draft.originalMessageIsPoll,
            )
        }

        guard
            let quotedAttachment = draft.attachment,
            !originalMessage.isViewOnceMessage
        else {
            return ValidatedQuotedReply(
                quotedReply: buildQuotedMessage(nil),
                thumbnailDataSource: nil,
            )
        }

        switch quotedAttachment {
        case .stub(let stub):
            let thumbnailAttachmentInfo = OWSAttachmentInfo(
                originalAttachmentMimeType: stub.mimeType ?? MimeType.applicationOctetStream.rawValue,
                originalAttachmentSourceFilename: stub.sourceFilename,
            )

            return ValidatedQuotedReply(
                quotedReply: buildQuotedMessage(thumbnailAttachmentInfo),
                thumbnailDataSource: nil,
            )
        case .thumbnail(let dataSource, let originalAttachmentSourceFilename):
            let thumbnailAttachmentInfo = OWSAttachmentInfo(
                originalAttachmentMimeType: dataSource.originalAttachmentMimeType,
                originalAttachmentSourceFilename: originalAttachmentSourceFilename,
            )

            return ValidatedQuotedReply(
                quotedReply: buildQuotedMessage(thumbnailAttachmentInfo),
                thumbnailDataSource: dataSource,
            )
        }
    }

    private func lastResortQuotedReplyDraftContent() -> DraftQuotedReplyModel.Content {
        return .text(MessageBody(
            text: OWSLocalizedString(
                "QUOTED_REPLY_CONTENT_FROM_REMOTE_SOURCE",
                comment: "Footer label that appears below quoted messages when the quoted content was not derived locally. When the local user doesn't have a copy of the message being quoted, e.g. if it had since been deleted, we instead show the content specified by the sender.",
            ),
            ranges: .empty,
        ))
    }

    // MARK: - Outgoing proto

    func buildProtoForSending(
        _ quote: TSQuotedMessage,
        parentMessage: TSMessage,
        tx: DBReadTransaction,
    ) throws -> SSKProtoDataMessageQuote {
        guard let timestamp = quote.timestampValue?.uint64Value else {
            throw OWSAssertionError("Missing timestamp")
        }
        let quoteBuilder = SSKProtoDataMessageQuote.builder(id: timestamp)

        guard let authorAci = quote.authorAddress.aci else {
            throw OWSAssertionError("It should be impossible to quote a message without a UUID")
        }
        if BuildFlags.serviceIdStrings {
            quoteBuilder.setAuthorAci(authorAci.serviceIdString)
        }
        if BuildFlags.serviceIdBinaryConstantOverhead {
            quoteBuilder.setAuthorAciBinary(authorAci.serviceIdBinary)
        }

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
                    comment: "inbox cell and notification text for an already viewed view-once media message.",
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
        tx: DBReadTransaction,
    ) -> SSKProtoDataMessageQuoteQuotedAttachment? {
        guard
            let reference = attachmentStore.quotedAttachmentReference(
                parentMessage: parentMessage,
                tx: tx,
            )
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
                    tx: tx,
                )
            {
                mimeType = attachment.mimeType
                if
                    let pointer = attachment.asTransitTierPointer(),
                    case let .digestSHA256Ciphertext(digestSHA256Ciphertext) = pointer.info.integrityCheck
                {
                    let attachmentProto = attachmentManager.buildProtoForSending(
                        from: attachmentRef,
                        pointer: pointer,
                        digestSHA256Ciphertext: digestSHA256Ciphertext,
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
