//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension BackupArchive {

    /// Represents message content "types" as they are represented in iOS code, after
    /// being mapped from their representation in the backup proto. For example, normal
    /// text messages and quoted replies are a single "type" in the proto, but have separate
    /// class structures in the iOS code.
    ///
    /// This object will be passed back into the ``BackupArchiveTSMessageContentsArchiver`` class
    /// after the TSMessage has been created, so that downstream objects that require the TSMessage exist
    /// can be created afterwards. Anything needed for that step, but not needed to create the TSMessage,
    /// should be made a fileprivate variable in these structs.
    enum RestoredMessageContents {
        struct Payment {
            enum Status {
                case success(BackupProto_PaymentNotification.TransactionDetails.Transaction.Status)
                case failure(BackupProto_PaymentNotification.TransactionDetails.FailedTransaction.FailureReason)
            }

            let amount: String?
            let fee: String?
            let note: String?

            fileprivate let status: Status
            fileprivate let payment: BackupProto_PaymentNotification.TransactionDetails.Transaction?
        }

        struct Text {
            struct RestoredMessageBody: ValidatedInlineMessageBody {
                enum OversizeText {
                    // The exporter presumably hadn't downloaded the attachment
                    // at export time, so all we have is a pointer.
                    case attachmentPointer(BackupProto_FilePointer)
                    // Any time the exporter has downloaded the oversize text
                    // attachment, they inline the text in the backup proto.
                    // We will unfold it back into a restored attachment stream.
                    case inlined(String)
                }

                // This is the body we put on the message
                let inlinedBody: MessageBody
                fileprivate let oversizeText: OversizeText?

                init(inlinedBody: MessageBody, oversizeText: OversizeText?) {
                    self.inlinedBody = inlinedBody
                    self.oversizeText = oversizeText
                }
            }

            let body: RestoredMessageBody?
            let quotedMessage: TSQuotedMessage?
            let linkPreview: OWSLinkPreview?
            let isVoiceMessage: Bool

            fileprivate let reactions: [BackupProto_Reaction]
            fileprivate let bodyAttachments: [BackupProto_MessageAttachment]
            fileprivate let quotedMessageThumbnail: BackupProto_MessageAttachment?
            fileprivate let linkPreviewImage: BackupProto_FilePointer?
        }

        /// Note: not a "Contact" in the Signal sense (not a Recipient or SignalAccount), just a message
        /// that includes contact info taken from system contacts; the user must interact with it to do
        /// anything, such as adding the shared contact info to a new system contact.
        struct ContactShare {
            let contact: OWSContact

            fileprivate let avatarAttachment: BackupProto_FilePointer?
            fileprivate let reactions: [BackupProto_Reaction]
        }

        struct StickerMessage {
            let sticker: MessageSticker

            fileprivate let attachment: BackupProto_FilePointer
            fileprivate let reactions: [BackupProto_Reaction]
        }

        struct GiftBadge {
            let giftBadge: OWSGiftBadge
        }

        struct ViewOnceMessage {
            enum State {
                case complete
                case unviewed(BackupProto_MessageAttachment)
            }

            let state: State

            fileprivate let reactions: [BackupProto_Reaction]
        }

        struct StoryReply {
            enum ReplyType {
                struct TextReply {
                    let body: Text.RestoredMessageBody
                }

                case textReply(TextReply)
                case emoji(String)
            }

            let replyType: ReplyType
            fileprivate let reactions: [BackupProto_Reaction]
        }

        struct Poll {
            let poll: BackupsPollData
            let question: Text.RestoredMessageBody

            fileprivate let reactions: [BackupProto_Reaction]
        }

        case archivedPayment(Payment)
        case remoteDeleteTombstone
        case text(Text)
        case contactShare(ContactShare)
        case stickerMessage(StickerMessage)
        case giftBadge(GiftBadge)
        case viewOnceMessage(ViewOnceMessage)
        /// Note: only includes 1:1 story replies, not group story replies.
        case storyReply(StoryReply)
        case poll(Poll)
    }
}

class BackupArchiveTSMessageContentsArchiver: BackupArchiveProtoStreamWriter {

    typealias ChatItemType = BackupArchive.InteractionArchiveDetails.ChatItemType

    typealias ArchiveInteractionResult = BackupArchive.ArchiveInteractionResult
    typealias RestoreInteractionResult = BackupArchive.RestoreInteractionResult

    private typealias ArchiveFrameError = BackupArchive.ArchiveFrameError<BackupArchive.InteractionUniqueId>
    private typealias RestoreFrameError = BackupArchive.RestoreFrameError<BackupArchive.ChatItemId>

    private let interactionStore: BackupArchiveInteractionStore
    private let archivedPaymentStore: ArchivedPaymentStore
    private let attachmentsArchiver: BackupArchiveMessageAttachmentArchiver
    private lazy var contactAttachmentArchiver = BackupArchiveContactAttachmentArchiver(
        attachmentsArchiver: attachmentsArchiver,
    )
    private let oversizeTextArchiver: BackupArchiveInlinedOversizeTextArchiver
    private let reactionArchiver: BackupArchiveReactionArchiver
    private let pollArchiver: BackupArchivePollArchiver
    private let pinnedMessageManager: PinnedMessageManager

    init(
        interactionStore: BackupArchiveInteractionStore,
        archivedPaymentStore: ArchivedPaymentStore,
        attachmentsArchiver: BackupArchiveMessageAttachmentArchiver,
        oversizeTextArchiver: BackupArchiveInlinedOversizeTextArchiver,
        reactionArchiver: BackupArchiveReactionArchiver,
        pollArchiver: BackupArchivePollArchiver,
        pinnedMessageManager: PinnedMessageManager,
    ) {
        self.interactionStore = interactionStore
        self.archivedPaymentStore = archivedPaymentStore
        self.attachmentsArchiver = attachmentsArchiver
        self.oversizeTextArchiver = oversizeTextArchiver
        self.reactionArchiver = reactionArchiver
        self.pollArchiver = pollArchiver
        self.pinnedMessageManager = pinnedMessageManager
    }

    // MARK: - Archiving

    func archiveMessageContents(
        _ message: TSMessage,
        context: BackupArchive.ChatArchivingContext,
    ) -> ArchiveInteractionResult<ChatItemType> {
        guard let messageRowId = message.sqliteRowId else {
            return .completeFailure(.fatalArchiveError(
                .fetchedInteractionMissingRowId,
            ))
        }

        if let paymentMessage = message as? OWSPaymentMessage {
            return archivePaymentMessageContents(
                paymentMessage,
                uniqueInteractionId: message.uniqueInteractionId,
                context: context.recipientContext,
            )
        } else if let archivedPayment = message as? OWSArchivedPaymentMessage {
            return archivePaymentArchiveContents(
                archivedPayment,
                uniqueInteractionId: message.uniqueInteractionId,
                context: context.recipientContext,
            )
        } else if message.wasRemotelyDeleted {
            return archiveRemoteDeleteTombstone(
                message,
                context: context.recipientContext,
            )
        } else if let contactShare = message.contactShare {
            return archiveContactShareMessageContents(
                message,
                contactShare: contactShare,
                messageRowId: messageRowId,
                context: context.recipientContext,
            )
        } else if let messageSticker = message.messageSticker {
            return archiveStickerMessageContents(
                message,
                messageSticker: messageSticker,
                messageRowId: messageRowId,
                context: context.recipientContext,
            )
        } else if let giftBadge = message.giftBadge {
            return archiveGiftBadge(
                giftBadge,
                context: context.recipientContext,
            )
        } else if message.isViewOnceMessage {
            return archiveViewOnceMessage(
                message,
                messageRowId: messageRowId,
                context: context,
            )
        } else if message.isStoryReply, !message.isGroupStoryReply {
            return archiveDirectStoryReplyMessage(
                message,
                interactionUniqueId: message.uniqueInteractionId,
                messageRowId: messageRowId,
                context: context,
            )
        } else if message.isPoll {
            return pollArchiver.archivePoll(
                message,
                messageRowId: messageRowId,
                interactionUniqueId: message.uniqueInteractionId,
                context: context,
            )
        } else {
            return archiveStandardMessageContents(
                message,
                messageRowId: messageRowId,
                context: context.recipientContext,
            )
        }
    }

    // MARK: -

    private func archivePaymentArchiveContents(
        _ archivedPaymentMessage: OWSArchivedPaymentMessage,
        uniqueInteractionId: BackupArchive.InteractionUniqueId,
        context: BackupArchive.RecipientArchivingContext,
    ) -> BackupArchive.ArchiveInteractionResult<ChatItemType> {
        let historyItem = archivedPaymentStore.fetch(
            for: archivedPaymentMessage,
            interactionUniqueId: uniqueInteractionId.value,
            tx: context.tx,
        )
        guard let historyItem else {
            return .messageFailure([.archiveFrameError(.missingPaymentInformation, uniqueInteractionId)])
        }

        var paymentNotificationProto = BackupProto_PaymentNotification()
        if let amount = archivedPaymentMessage.archivedPaymentInfo.amount {
            paymentNotificationProto.amountMob = amount
        }
        if let fee = archivedPaymentMessage.archivedPaymentInfo.fee {
            paymentNotificationProto.feeMob = fee
        }
        if let note = archivedPaymentMessage.archivedPaymentInfo.note {
            paymentNotificationProto.note = note
        }
        paymentNotificationProto.transactionDetails = historyItem.toTransactionDetailsProto()

        return .success(.paymentNotification(paymentNotificationProto))
    }

    private func archivePaymentMessageContents(
        _ message: OWSPaymentMessage,
        uniqueInteractionId: BackupArchive.InteractionUniqueId,
        context: BackupArchive.RecipientArchivingContext,
    ) -> BackupArchive.ArchiveInteractionResult<ChatItemType> {
        guard
            let paymentNotification = message.paymentNotification,
            let model = PaymentFinder.paymentModels(
                forMcReceiptData: paymentNotification.mcReceiptData,
                transaction: context.tx,
            ).first
        else {
            return .messageFailure([.archiveFrameError(.missingPaymentInformation, uniqueInteractionId)])
        }

        var paymentNotificationProto = BackupProto_PaymentNotification()
        if
            let amount = model.paymentAmount?.picoMob,
            let formattedAmount = PaymentsFormat.formatForArchive(picoMob: amount)
        {
            paymentNotificationProto.amountMob = formattedAmount
        }
        if
            let fee = model.mobileCoin?.feeAmount?.picoMob,
            let formattedFee = PaymentsFormat.formatForArchive(picoMob: fee)
        {
            paymentNotificationProto.feeMob = formattedFee
        }
        if let memoMessage = paymentNotification.memoMessage {
            paymentNotificationProto.note = memoMessage
        }
        paymentNotificationProto.transactionDetails = model.asArchivedPayment().toTransactionDetailsProto()

        return .success(.paymentNotification(paymentNotificationProto))
    }

    // MARK: -

    private func archiveRemoteDeleteTombstone(
        _ remoteDeleteTombstone: TSMessage,
        context: BackupArchive.RecipientArchivingContext,
    ) -> ArchiveInteractionResult<ChatItemType> {
        let remoteDeletedMessage = BackupProto_RemoteDeletedMessage()
        return .success(.remoteDeletedMessage(remoteDeletedMessage))
    }

    // MARK: -

    private func archiveStandardMessageContents(
        _ message: TSMessage,
        messageRowId: Int64,
        context: BackupArchive.RecipientArchivingContext,
    ) -> ArchiveInteractionResult<ChatItemType> {
        var standardMessage = BackupProto_StandardMessage()
        var partialErrors = [ArchiveFrameError]()

        // Every "StandardMessage" must have either a body or body attachments;
        // if neither is set this stays false and we fail the message.
        var hasPrimaryContent = false

        if let messageBody = message.body?.nilIfEmpty {
            hasPrimaryContent = true

            let oversizeTextResult = oversizeTextArchiver.archiveMessageBody(
                text: messageBody,
                messageRowId: messageRowId,
                messageId: message.uniqueInteractionId,
                context: context,
            )

            let archivedBody: BackupArchive.ArchivedMessageBody
            switch oversizeTextResult.bubbleUp(ChatItemType.self, partialErrors: &partialErrors) {
            case .continue(let _archivedBody):
                archivedBody = _archivedBody
            case .bubbleUpError(let errorResult):
                return errorResult
            }

            let text: BackupProto_Text
            let textResult = archiveText(
                MessageBody(text: archivedBody.inlinedText, ranges: message.bodyRanges ?? .empty),
                interactionUniqueId: message.uniqueInteractionId,
            )
            switch textResult.bubbleUp(ChatItemType.self, partialErrors: &partialErrors) {
            case .continue(let value):
                text = value
            case .bubbleUpError(let errorResult):
                return errorResult
            }
            standardMessage.text = text
            if let oversizedTextPointer = archivedBody.oversizedTextPointer {
                standardMessage.longText = oversizedTextPointer
            }
        }

        let bodyAttachmentsResult = attachmentsArchiver.archiveBodyAttachments(
            messageId: message.uniqueInteractionId,
            messageRowId: messageRowId,
            context: context,
        )
        switch bodyAttachmentsResult.bubbleUp(ChatItemType.self, partialErrors: &partialErrors) {
        case .continue(let bodyAttachmentProtos):
            if !bodyAttachmentProtos.isEmpty {
                hasPrimaryContent = true
                standardMessage.attachments = bodyAttachmentProtos
            }
        case .bubbleUpError(let errorResult):
            return errorResult
        }

        guard hasPrimaryContent else {
            // If we got this far without a body or body attachments,
            // this message is invalid and should be dropped.
            // We would hard-error here, but we know these exist in the wild
            // and don't want to hard error any user that has them when we can
            // just skip.
            return .skippableInteraction(.emptyBodyMessage)
        }

        if let quotedMessage = message.quotedMessage {
            let quoteResult = archiveQuote(
                quotedMessage,
                interactionUniqueId: message.uniqueInteractionId,
                messageRowId: messageRowId,
                context: context,
            )
            switch quoteResult.bubbleUp(ChatItemType.self, partialErrors: &partialErrors) {
            case .continue(let quote):
                quote.map { standardMessage.quote = $0 }
            case .bubbleUpError(let errorResult):
                return errorResult
            }
        }

        if let linkPreview = message.linkPreview {
            let linkPreviewResult = self.archiveLinkPreview(
                linkPreview,
                messageBody: standardMessage.text.body,
                interactionUniqueId: message.uniqueInteractionId,
                context: context,
                messageRowId: messageRowId,
            )
            switch linkPreviewResult.bubbleUp(ChatItemType.self, partialErrors: &partialErrors) {
            case .continue(let linkPreviewProto):
                standardMessage.linkPreview = [linkPreviewProto].compacted()
            case .bubbleUpError(let errorResult):
                return errorResult
            }
        }

        let reactions: [BackupProto_Reaction]
        let reactionsResult = reactionArchiver.archiveReactions(
            message,
            context: context,
        )
        switch reactionsResult.bubbleUp(ChatItemType.self, partialErrors: &partialErrors) {
        case .continue(let values):
            reactions = values
        case .bubbleUpError(let errorResult):
            return errorResult
        }
        standardMessage.reactions = reactions

        if partialErrors.isEmpty {
            return .success(.standardMessage(standardMessage))
        } else {
            return .partialFailure(.standardMessage(standardMessage), partialErrors)
        }
    }

    private func archiveText(
        _ messageBody: MessageBody,
        interactionUniqueId: BackupArchive.InteractionUniqueId,
    ) -> ArchiveInteractionResult<BackupProto_Text> {
        var text = BackupProto_Text()
        text.body = messageBody.text

        for bodyRangeParam in messageBody.ranges.toProtoBodyRanges() {
            var bodyRange = BackupProto_BodyRange()
            bodyRange.start = bodyRangeParam.start
            bodyRange.length = bodyRangeParam.length

            if
                let mentionAci = Aci.parseFrom(
                    serviceIdBinary: bodyRangeParam.mentionAciBinary,
                    serviceIdString: bodyRangeParam.mentionAci,
                )
            {
                bodyRange.associatedValue = .mentionAci(
                    mentionAci.serviceIdBinary,
                )
            } else if let style = bodyRangeParam.style {
                let backupProtoStyle: BackupProto_BodyRange.Style = {
                    switch style {
                    case .none: return .none
                    case .bold: return .bold
                    case .italic: return .italic
                    case .spoiler: return .spoiler
                    case .strikethrough: return .strikethrough
                    case .monospace: return .monospace
                    }
                }()

                bodyRange.associatedValue = .style(backupProtoStyle)
            }

            text.bodyRanges.append(bodyRange)
        }

        return .success(text)
    }

    private func archiveQuote(
        _ quotedMessage: TSQuotedMessage,
        interactionUniqueId: BackupArchive.InteractionUniqueId,
        messageRowId: Int64,
        context: BackupArchive.RecipientArchivingContext,
    ) -> ArchiveInteractionResult<BackupProto_Quote?> {
        var partialErrors = [ArchiveFrameError]()

        guard let authorAddress = quotedMessage.authorAddress.asSingleServiceIdBackupAddress() else {
            // Fail the whole message if we fail archiving a quote.
            return .messageFailure([.archiveFrameError(.invalidQuoteAuthor, interactionUniqueId)])
        }
        guard let authorId = context[.contact(authorAddress)] else {
            // Fail the whole message if we fail archiving a quote.
            return .messageFailure([.archiveFrameError(
                .referencedRecipientIdMissing(.contact(authorAddress)),
                interactionUniqueId,
            )])
        }

        var quote = BackupProto_Quote()
        quote.authorID = authorId.value

        let targetSentTimestamp: UInt64? = {
            switch quotedMessage.bodySource {
            case .local, .unknown:
                return quotedMessage.timestampValue?.uint64Value
            case .remote, .story:
                return nil
            @unknown default:
                return nil
            }
        }()
        // The proto's targetSentTimestamp is an optional field
        // and should be unset (not 0) if the target message could
        // not be found at the time the quote was received.
        BackupArchive.Timestamps.setTimestampIfValid(
            from: targetSentTimestamp,
            \.self,
            on: &quote,
            \.targetSentTimestamp,
            allowZero: false,
        )

        var didArchiveText = false
        var didArchiveAttachments = false

        if let body = quotedMessage.body?.nilIfEmpty {
            let textResult = archiveText(
                MessageBody(text: body, ranges: quotedMessage.bodyRanges ?? .empty),
                interactionUniqueId: interactionUniqueId,
            )
            let text: BackupProto_Text
            switch textResult.bubbleUp(Optional<BackupProto_Quote>.self, partialErrors: &partialErrors) {
            case .continue(let value):
                text = value
            case .bubbleUpError(let errorResult):
                return errorResult
            }

            let quoteText = { () -> BackupProto_Text? in
                var quoteText = BackupProto_Text()
                // We do not allow oversize text in quotes; truncate if some historical bug
                // cause quotes to contain more than the usual oversize text threshold.
                let trimmedQuoteText = text.body.trimToUtf8ByteCount(OWSMediaUtils.kOversizeTextMessageSizeThresholdBytes)
                // If, after trimming the quote text, we end up with an empty string,
                // skip setting a quote text entirely
                if let quoteTextBody = trimmedQuoteText.nilIfEmpty {
                    quoteText.body = quoteTextBody
                    quoteText.bodyRanges = text.bodyRanges
                    return quoteText
                } else {
                    return nil
                }
            }()
            if let quoteText {
                quote.text = quoteText
                didArchiveText = true
            }
        }

        if let attachmentInfo = quotedMessage.attachmentInfo() {
            let quoteAttachmentResult = self.archiveQuoteAttachment(
                attachmentInfo: attachmentInfo,
                interactionUniqueId: interactionUniqueId,
                messageRowId: messageRowId,
                context: context,
            )
            switch quoteAttachmentResult.bubbleUp(Optional<BackupProto_Quote>.self, partialErrors: &partialErrors) {
            case .continue(let quoteAttachmentProto):
                quote.attachments = [quoteAttachmentProto]
            case .bubbleUpError(let errorResult):
                return errorResult
            }

            didArchiveAttachments = true
        }

        if quotedMessage.isGiftBadge {
            quote.type = .giftBadge
        } else if quotedMessage.isTargetMessageViewOnce {
            quote.type = .viewOnce
        } else if quotedMessage.isPoll {
            quote.type = .poll
        } else {
            guard didArchiveText || didArchiveAttachments else {
                // NORMAL-type quotes must have either text or attachments, lest
                // they be rejected by the validator.
                partialErrors.append(.archiveFrameError(
                    .quoteTypeNormalMissingTextAndAttachments,
                    interactionUniqueId,
                ))

                return .partialFailure(nil, partialErrors)
            }

            quote.type = .normal
        }

        if partialErrors.isEmpty {
            return .success(quote)
        } else {
            return .partialFailure(quote, partialErrors)
        }
    }

    private func archiveQuoteAttachment(
        attachmentInfo: OWSAttachmentInfo,
        interactionUniqueId: BackupArchive.InteractionUniqueId,
        messageRowId: Int64,
        context: BackupArchive.ArchivingContext,
    ) -> BackupArchive.ArchiveInteractionResult<BackupProto_Quote.QuotedAttachment> {
        var partialErrors = [BackupArchive.ArchiveFrameError<BackupArchive.InteractionUniqueId>]()

        var proto = BackupProto_Quote.QuotedAttachment()
        if let mimeType = attachmentInfo.originalAttachmentMimeType {
            proto.contentType = mimeType
        }
        if let sourceFilename = attachmentInfo.originalAttachmentSourceFilename {
            proto.fileName = sourceFilename
        }

        let imageResult = attachmentsArchiver.archiveQuotedReplyThumbnailAttachment(
            messageRowId: messageRowId,
            context: context,
        )
        switch imageResult.bubbleUp(BackupProto_Quote.QuotedAttachment.self, partialErrors: &partialErrors) {
        case .continue(let pointerProto):
            pointerProto.map { proto.thumbnail = $0 }
        case .bubbleUpError(let result):
            return result
        }

        if partialErrors.isEmpty {
            return .success(proto)
        } else {
            return .partialFailure(proto, partialErrors)
        }
    }

    private func archiveLinkPreview(
        _ linkPreview: OWSLinkPreview,
        messageBody: String,
        interactionUniqueId: BackupArchive.InteractionUniqueId,
        context: BackupArchive.RecipientArchivingContext,
        messageRowId: Int64,
    ) -> ArchiveInteractionResult<BackupProto_LinkPreview?> {
        var partialErrors = [ArchiveFrameError]()

        guard let url = linkPreview.urlString else {
            // If we have no url, consider this a partial failure. The message
            // without the link preview is still valid, so just don't set a link preview
            // by returning nil.
            partialErrors.append(.archiveFrameError(
                .linkPreviewMissingUrl,
                interactionUniqueId,
            ))
            return .partialFailure(nil, partialErrors)
        }

        guard messageBody.contains(url) else {
            partialErrors.append(.archiveFrameError(
                .linkPreviewUrlNotInBody,
                interactionUniqueId,
            ))
            return .partialFailure(nil, partialErrors)
        }

        var proto = BackupProto_LinkPreview()
        proto.url = url
        linkPreview.title.map { proto.title = $0 }
        linkPreview.previewDescription.map { proto.description_p = $0 }

        // Link preview dates could be arbitrarily old, and .ows_millisecondsSince1970
        // crashes if date.timeIntervalSince1970 is negative.
        if
            let date = linkPreview.date,
            date.timeIntervalSince1970 >= 0
        {
            BackupArchive.Timestamps.setTimestampIfValid(
                from: date,
                \.ows_millisecondsSince1970,
                on: &proto,
                \.date,
                allowZero: true,
            )
        }

        // Returns nil if no link preview image; this is both how we check presence and how we archive.
        let imageResult = attachmentsArchiver.archiveLinkPreviewAttachment(
            messageRowId: messageRowId,
            context: context,
        )
        switch imageResult.bubbleUp(Optional<BackupProto_LinkPreview>.self, partialErrors: &partialErrors) {
        case .continue(let pointerProto):
            pointerProto.map { proto.image = $0 }
        case .bubbleUpError(let archiveInteractionResult):
            return archiveInteractionResult
        }

        if partialErrors.isEmpty {
            return .success(proto)
        } else {
            return .partialFailure(proto, partialErrors)
        }
    }

    // MARK: -

    private func archiveContactShareMessageContents(
        _ message: TSMessage,
        contactShare: OWSContact,
        messageRowId: Int64,
        context: BackupArchive.RecipientArchivingContext,
    ) -> ArchiveInteractionResult<ChatItemType> {
        var partialErrors = [ArchiveFrameError]()

        var proto = BackupProto_ContactMessage()

        let contactResult = contactAttachmentArchiver.archiveContact(
            contactShare,
            uniqueInteractionId: message.uniqueInteractionId,
            messageRowId: messageRowId,
            context: context,
        )
        switch contactResult.bubbleUp(ChatItemType.self, partialErrors: &partialErrors) {
        case .continue(let contactProto):
            proto.contact = contactProto
        case .bubbleUpError(let errorResult):
            return errorResult
        }

        let reactions: [BackupProto_Reaction]
        let reactionsResult = reactionArchiver.archiveReactions(
            message,
            context: context,
        )
        switch reactionsResult.bubbleUp(ChatItemType.self, partialErrors: &partialErrors) {
        case .continue(let values):
            reactions = values
        case .bubbleUpError(let errorResult):
            return errorResult
        }
        proto.reactions = reactions

        if partialErrors.isEmpty {
            return .success(.contactMessage(proto))
        } else {
            return .partialFailure(.contactMessage(proto), partialErrors)
        }
    }

    private func archiveStickerMessageContents(
        _ message: TSMessage,
        messageSticker: MessageSticker,
        messageRowId: Int64,
        context: BackupArchive.RecipientArchivingContext,
    ) -> ArchiveInteractionResult<ChatItemType> {
        var partialErrors = [ArchiveFrameError]()

        var proto = BackupProto_StickerMessage()

        var stickerProto = BackupProto_Sticker()
        stickerProto.packID = messageSticker.packId
        stickerProto.packKey = messageSticker.packKey
        stickerProto.stickerID = messageSticker.stickerId
        messageSticker.emoji.map { stickerProto.emoji = $0 }

        let stickerAttachmentResult = attachmentsArchiver.archiveStickerAttachment(
            messageRowId: messageRowId,
            context: context,
        )

        switch stickerAttachmentResult.bubbleUp(ChatItemType.self, partialErrors: &partialErrors) {
        case .continue(let stickerAttachmentProto):
            guard let stickerAttachmentProto else {
                // We can't have a sticker without an attachment.
                return .messageFailure(partialErrors + [.archiveFrameError(
                    .stickerMessageMissingStickerAttachment,
                    message.uniqueInteractionId,
                )])
            }
            stickerProto.data = stickerAttachmentProto
        case .bubbleUpError(let errorResult):
            return errorResult
        }

        proto.sticker = stickerProto

        let reactions: [BackupProto_Reaction]
        let reactionsResult = reactionArchiver.archiveReactions(
            message,
            context: context,
        )
        switch reactionsResult.bubbleUp(ChatItemType.self, partialErrors: &partialErrors) {
        case .continue(let values):
            reactions = values
        case .bubbleUpError(let errorResult):
            return errorResult
        }
        proto.reactions = reactions

        if partialErrors.isEmpty {
            return .success(.stickerMessage(proto))
        } else {
            return .partialFailure(.stickerMessage(proto), partialErrors)
        }
    }

    // MARK: -

    private func archiveGiftBadge(
        _ giftBadge: OWSGiftBadge,
        context: BackupArchive.RecipientArchivingContext,
    ) -> ArchiveInteractionResult<ChatItemType> {
        var giftBadgeProto = BackupProto_GiftBadge()

        if let redemptionCredential = giftBadge.redemptionCredential {
            giftBadgeProto.receiptCredentialPresentation = redemptionCredential
            giftBadgeProto.state = { () -> BackupProto_GiftBadge.State in
                switch giftBadge.redemptionState {
                case .pending: return .unopened
                case .redeemed: return .redeemed
                case .opened: return .opened
                }
            }()
        } else {
            giftBadgeProto.receiptCredentialPresentation = Data()
            giftBadgeProto.state = .failed
        }

        return .success(.giftBadge(giftBadgeProto))
    }

    // MARK: -

    private func archiveViewOnceMessage(
        _ message: TSMessage,
        messageRowId: Int64,
        context: BackupArchive.ChatArchivingContext,
    ) -> ArchiveInteractionResult<ChatItemType> {
        var partialErrors = [ArchiveFrameError]()

        var proto = BackupProto_ViewOnceMessage()

        if
            !context.includedContentFilter.shouldTombstoneViewOnce,
            !message.isViewOnceComplete
        {
            let attachmentResult = attachmentsArchiver.archiveBodyAttachments(
                messageId: message.uniqueInteractionId,
                messageRowId: messageRowId,
                context: context,
            )
            switch attachmentResult.bubbleUp(ChatItemType.self, partialErrors: &partialErrors) {
            case .continue(let value):
                guard let first = value.first else {
                    return .messageFailure(partialErrors + [.archiveFrameError(
                        .unviewedViewOnceMessageMissingAttachment,
                        message.uniqueInteractionId,
                    )])
                }
                if value.count > 1 {
                    partialErrors.append(.archiveFrameError(
                        .unviewedViewOnceMessageTooManyAttachments(value.count),
                        message.uniqueInteractionId,
                    ))
                }
                proto.attachment = first
            case .bubbleUpError(let errorResult):
                return errorResult
            }
        }

        let reactions: [BackupProto_Reaction]
        let reactionsResult = reactionArchiver.archiveReactions(
            message,
            context: context.recipientContext,
        )
        switch reactionsResult.bubbleUp(ChatItemType.self, partialErrors: &partialErrors) {
        case .continue(let values):
            reactions = values
        case .bubbleUpError(let errorResult):
            return errorResult
        }
        proto.reactions = reactions

        if partialErrors.isEmpty {
            return .success(.viewOnceMessage(proto))
        } else {
            return .partialFailure(.viewOnceMessage(proto), partialErrors)
        }
    }

    // MARK: -

    /// Note this only covers 1:1 story replies which are rendered in-chat;
    /// group story replies are rendered in the story UI and are not backed
    /// up since stories are not backed up.
    private func archiveDirectStoryReplyMessage(
        _ message: TSMessage,
        interactionUniqueId: BackupArchive.InteractionUniqueId,
        messageRowId: Int64,
        context: BackupArchive.ChatArchivingContext,
    ) -> ArchiveInteractionResult<ChatItemType> {
        guard
            let chatId = context[message.uniqueThreadIdentifier],
            let threadInfo = context[chatId]
        else {
            return .messageFailure([.archiveFrameError(
                .referencedThreadIdMissing(message.uniqueThreadIdentifier),
                interactionUniqueId,
            )])
        }

        switch threadInfo {
        case .groupThread:
            return .messageFailure([.archiveFrameError(
                .storyReplyInGroupThread,
                interactionUniqueId,
            )])
        case .noteToSelfThread:
            // See comment on skippable update enum case.
            return .skippableInteraction(.directStoryReplyInNoteToSelf)
        case .contactThread:
            break
        }

        guard !message.isGroupStoryReply else {
            return .messageFailure([.archiveFrameError(
                .storyReplyInGroupThread,
                interactionUniqueId,
            )])
        }

        var partialErrors = [ArchiveFrameError]()

        var proto = BackupProto_DirectStoryReplyMessage()

        // We don't put the story author aci on the proto; it can be inferred
        // since you can't 1:1 reply to your own stories.
        // If this is an outgoing reply, it must be to a story from the contact
        // in the contact thread containing it.
        // If this an incoming reply, it must be a story from the local user.

        if let emoji = message.storyReactionEmoji {
            guard !emoji.isEmpty else {
                return .messageFailure([.archiveFrameError(
                    .storyReplyEmptyContents,
                    interactionUniqueId,
                )])
            }
            proto.reply = .emoji(emoji)
        } else if let body = message.body {
            guard !body.isEmpty else {
                return .messageFailure([.archiveFrameError(
                    .storyReplyEmptyContents,
                    interactionUniqueId,
                )])
            }

            let oversizeTextResult = oversizeTextArchiver.archiveMessageBody(
                text: body,
                messageRowId: messageRowId,
                messageId: message.uniqueInteractionId,
                context: context,
            )

            let archivedBody: BackupArchive.ArchivedMessageBody
            switch oversizeTextResult.bubbleUp(ChatItemType.self, partialErrors: &partialErrors) {
            case .continue(let _archivedBody):
                archivedBody = _archivedBody
            case .bubbleUpError(let errorResult):
                return errorResult
            }

            let textResult = archiveText(
                MessageBody(text: archivedBody.inlinedText, ranges: message.bodyRanges ?? .empty),
                interactionUniqueId: interactionUniqueId,
            )
            let text: BackupProto_Text
            switch textResult.bubbleUp(ChatItemType.self, partialErrors: &partialErrors) {
            case .continue(let value):
                text = value
            case .bubbleUpError(let errorResult):
                return errorResult
            }
            var textReply = BackupProto_DirectStoryReplyMessage.TextReply()
            textReply.text = text
            if let oversizedTextPointer = archivedBody.oversizedTextPointer {
                textReply.longText = oversizedTextPointer
            }

            proto.reply = .textReply(textReply)
        }

        let reactions: [BackupProto_Reaction]
        let reactionsResult = reactionArchiver.archiveReactions(
            message,
            context: context.recipientContext,
        )
        switch reactionsResult.bubbleUp(ChatItemType.self, partialErrors: &partialErrors) {
        case .continue(let values):
            reactions = values
        case .bubbleUpError(let errorResult):
            return errorResult
        }
        proto.reactions = reactions

        if partialErrors.isEmpty {
            return .success(.directStoryReplyMessage(proto))
        } else {
            return .partialFailure(.directStoryReplyMessage(proto), partialErrors)
        }
    }

    // MARK: - Restoring

    /// Parses the proto structure of message contents into
    /// into ``BackupArchive.RestoredMessageContents``, which map more directly
    /// to the ``TSMessage`` values in our database.
    ///
    /// Does NOT create the ``TSMessage``; callers are expected to utilize the
    /// restored contents to construct and insert the message.
    ///
    /// Callers MUST call ``restoreDownstreamObjects`` after creating and
    /// inserting the ``TSMessage``.
    func restoreContents(
        _ chatItemType: ChatItemType,
        chatItemId: BackupArchive.ChatItemId,
        chatThread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext,
    ) -> RestoreInteractionResult<BackupArchive.RestoredMessageContents> {
        switch chatItemType {
        case .paymentNotification(let paymentNotification):
            return restorePaymentNotification(
                paymentNotification,
                chatItemId: chatItemId,
                thread: chatThread,
                context: context,
            )
        case .remoteDeletedMessage(let remoteDeletedMessage):
            return restoreRemoteDeleteTombstone(
                remoteDeletedMessage,
                chatItemId: chatItemId,
                chatThread: chatThread,
                context: context,
            )
        case .standardMessage(let standardMessage):
            return restoreStandardMessage(
                standardMessage,
                chatItemId: chatItemId,
                chatThread: chatThread,
                context: context,
            )
        case .contactMessage(let contactMessage):
            return restoreContactMessage(
                contactMessage,
                chatItemId: chatItemId,
                chatThread: chatThread,
                context: context,
            )
        case .stickerMessage(let stickerMessage):
            return restoreStickerMessage(
                stickerMessage,
                chatItemId: chatItemId,
                chatThread: chatThread,
                context: context,
            )
        case .giftBadge(let giftBadge):
            return restoreGiftBadge(
                giftBadge,
                chatItemId: chatItemId,
                context: context,
            )
        case .viewOnceMessage(let viewOnceMessage):
            return restoreViewOnceMessage(
                viewOnceMessage,
                chatItemId: chatItemId,
                chatThread: chatThread,
                context: context,
            )
        case .directStoryReplyMessage(let storyReply):
            return restoreDirectStoryReplyMessage(
                storyReply,
                chatItemId: chatItemId,
                chatThread: chatThread,
                context: context,
            )
        case .poll(let poll):
            return restorePollMessage(
                poll,
                chatItemId: chatItemId,
                chatThread: chatThread,
                context: context,
            )
        case .updateMessage:
            return .messageFailure([.restoreFrameError(
                .developerError(OWSAssertionError("Chat update has no contents to restore!")),
                chatItemId,
            )])
        }
    }

    /// After a caller creates a ``TSMessage`` from the results of ``restoreContents``, they MUST call this method
    /// to create and insert all "downstream" objects: those that reference the ``TSMessage`` and require it for their own creation.
    ///
    /// This method will create and insert all necessary objects (e.g. reactions).
    func restoreDownstreamObjects(
        message: TSMessage,
        thread: BackupArchive.ChatThread,
        chatItemId: BackupArchive.ChatItemId,
        pinDetails: BackupProto_ChatItem.PinDetails?,
        restoredContents: BackupArchive.RestoredMessageContents,
        context: BackupArchive.ChatItemRestoringContext,
    ) -> RestoreInteractionResult<Void> {
        guard let messageRowId = message.sqliteRowId else {
            return .messageFailure([.restoreFrameError(
                .databaseModelMissingRowId(modelClass: type(of: message)),
                chatItemId,
            )])
        }

        var downstreamObjectResults = [RestoreInteractionResult<Void>]()
        switch restoredContents {
        case .archivedPayment(let archivedPayment):
            downstreamObjectResults.append(restoreArchivedPaymentContents(
                archivedPayment,
                chatItemId: chatItemId,
                thread: thread,
                message: message,
                context: context,
            ))
        case .text(let text):
            downstreamObjectResults.append(reactionArchiver.restoreReactions(
                text.reactions,
                chatItemId: chatItemId,
                message: message,
                context: context.recipientContext,
            ))
            if let oversizeText = text.body?.oversizeText {
                downstreamObjectResults.append(oversizeTextArchiver.restoreOversizeText(
                    oversizeText,
                    messageRowId: messageRowId,
                    message: message,
                    thread: thread,
                    chatItemId: chatItemId,
                    context: context,
                ))
            }
            if text.bodyAttachments.isEmpty.negated {
                downstreamObjectResults.append(attachmentsArchiver.restoreBodyAttachments(
                    text.bodyAttachments,
                    chatItemId: chatItemId,
                    messageRowId: messageRowId,
                    message: message,
                    thread: thread,
                    context: context,
                ))
            }
            if let quotedMessageThumbnail = text.quotedMessageThumbnail {
                downstreamObjectResults.append(attachmentsArchiver.restoreQuotedReplyThumbnailAttachment(
                    quotedMessageThumbnail,
                    chatItemId: chatItemId,
                    messageRowId: messageRowId,
                    message: message,
                    thread: thread,
                    context: context,
                ))
            }
            if let linkPreviewImage = text.linkPreviewImage {
                downstreamObjectResults.append(attachmentsArchiver.restoreLinkPreviewAttachment(
                    linkPreviewImage,
                    chatItemId: chatItemId,
                    messageRowId: messageRowId,
                    message: message,
                    thread: thread,
                    context: context,
                ))
            }
        case .contactShare(let contactShare):
            downstreamObjectResults.append(reactionArchiver.restoreReactions(
                contactShare.reactions,
                chatItemId: chatItemId,
                message: message,
                context: context.recipientContext,
            ))
            if let avatarAttachment = contactShare.avatarAttachment {
                downstreamObjectResults.append(attachmentsArchiver.restoreContactAvatarAttachment(
                    avatarAttachment,
                    chatItemId: chatItemId,
                    messageRowId: messageRowId,
                    message: message,
                    thread: thread,
                    context: context,
                ))
            }
        case .stickerMessage(let stickerMessage):
            downstreamObjectResults.append(reactionArchiver.restoreReactions(
                stickerMessage.reactions,
                chatItemId: chatItemId,
                message: message,
                context: context.recipientContext,
            ))
            downstreamObjectResults.append(attachmentsArchiver.restoreStickerAttachment(
                stickerMessage.attachment,
                stickerPackId: stickerMessage.sticker.packId,
                stickerId: stickerMessage.sticker.stickerId,
                chatItemId: chatItemId,
                messageRowId: messageRowId,
                message: message,
                thread: thread,
                context: context,
            ))
        case .viewOnceMessage(let viewOnceMessage):
            downstreamObjectResults.append(reactionArchiver.restoreReactions(
                viewOnceMessage.reactions,
                chatItemId: chatItemId,
                message: message,
                context: context.recipientContext,
            ))
            switch viewOnceMessage.state {
            case .unviewed(let attachment):
                downstreamObjectResults.append(attachmentsArchiver.restoreBodyAttachments(
                    [attachment],
                    chatItemId: chatItemId,
                    messageRowId: messageRowId,
                    message: message,
                    thread: thread,
                    context: context,
                ))
            case .complete:
                break
            }
        case .storyReply(let storyReply):
            downstreamObjectResults.append(reactionArchiver.restoreReactions(
                storyReply.reactions,
                chatItemId: chatItemId,
                message: message,
                context: context.recipientContext,
            ))

            switch storyReply.replyType {
            case .textReply(let textReply):
                if let oversizeText = textReply.body.oversizeText {
                    downstreamObjectResults.append(oversizeTextArchiver.restoreOversizeText(
                        oversizeText,
                        messageRowId: messageRowId,
                        message: message,
                        thread: thread,
                        chatItemId: chatItemId,
                        context: context,
                    ))
                }
            case .emoji:
                break
            }
        case .poll(let poll):
            downstreamObjectResults.append(reactionArchiver.restoreReactions(
                poll.reactions,
                chatItemId: chatItemId,
                message: message,
                context: context.recipientContext,
            ))

            downstreamObjectResults.append(
                pollArchiver.restorePoll(
                    poll,
                    chatItemId: chatItemId,
                    message: message,
                    context: context.recipientContext,
                ),
            )
        case .remoteDeleteTombstone, .giftBadge:
            // Nothing downstream to restore.
            break
        }

        if let pinDetails {
            downstreamObjectResults.append(
                restorePinMessage(
                    pinDetails: pinDetails,
                    message: message,
                    chatItemId: chatItemId,
                    chatThread: thread,
                    context: context,
                ),
            )
        }

        return downstreamObjectResults.reduce(.success(()), {
            $0.combine($1)
        })
    }

    // MARK: -

    private func restoreArchivedPaymentContents(
        _ transaction: BackupArchive.RestoredMessageContents.Payment,
        chatItemId: BackupArchive.ChatItemId,
        thread: BackupArchive.ChatThread,
        message: TSMessage,
        context: BackupArchive.RestoringContext,
    ) -> BackupArchive.RestoreInteractionResult<Void> {
        let senderOrRecipientAci: Aci? = {
            switch thread.threadType {
            case .contact(let thread):
                // Payments only supported for 1:1 chats
                return thread.contactAddress.aci
            case .groupV2:
                return nil
            }
        }()
        guard let senderOrRecipientAci else {
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.paymentNotificationInGroup),
                chatItemId,
            )])
        }

        let direction: ArchivedPayment.Direction
        switch message {
        case message as TSIncomingMessage:
            direction = .incoming
        case message as TSOutgoingMessage:
            direction = .outgoing
        default:
            return .messageFailure([.restoreFrameError(
                .developerError(OWSAssertionError("Invalid message type passed in for paymentRestore")),
                chatItemId,
            )])
        }
        let archivedPayment = ArchivedPayment.fromBackup(
            transaction,
            senderOrRecipientAci: senderOrRecipientAci,
            direction: direction,
            interactionUniqueId: message.uniqueId,
        )
        archivedPaymentStore.insert(archivedPayment, tx: context.tx)
        return .success(())
    }

    private func restorePaymentNotification(
        _ paymentNotification: BackupProto_PaymentNotification,
        chatItemId: BackupArchive.ChatItemId,
        thread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext,
    ) -> RestoreInteractionResult<BackupArchive.RestoredMessageContents> {
        let status: BackupArchive.RestoredMessageContents.Payment.Status
        let paymentTransaction: BackupProto_PaymentNotification.TransactionDetails.Transaction?
        if
            paymentNotification.hasTransactionDetails,
            let paymentDetails = paymentNotification.transactionDetails.payment
        {
            switch paymentDetails {
            case .failedTransaction(let failedTransaction):
                status = .failure(failedTransaction.reason)
                paymentTransaction = nil
            case .transaction(let payment):
                status = .success(payment.status)
                paymentTransaction = payment
            }
        } else {
            // Default to 'success' if there is no included information
            status = .success(.successful)
            paymentTransaction = nil
        }

        return .success(.archivedPayment(BackupArchive.RestoredMessageContents.Payment(
            amount: paymentNotification.hasAmountMob ? paymentNotification.amountMob : nil,
            fee: paymentNotification.hasFeeMob ? paymentNotification.feeMob : nil,
            note: paymentNotification.hasNote ? paymentNotification.note : nil,
            status: status,
            payment: paymentTransaction,
        )))
    }

    // MARK: -

    private func restoreRemoteDeleteTombstone(
        _ remoteDeleteTombstone: BackupProto_RemoteDeletedMessage,
        chatItemId: BackupArchive.ChatItemId,
        chatThread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext,
    ) -> RestoreInteractionResult<BackupArchive.RestoredMessageContents> {
        return .success(.remoteDeleteTombstone)
    }

    // MARK: -

    private func restoreStandardMessage(
        _ standardMessage: BackupProto_StandardMessage,
        chatItemId: BackupArchive.ChatItemId,
        chatThread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext,
    ) -> RestoreInteractionResult<BackupArchive.RestoredMessageContents> {
        var partialErrors = [RestoreFrameError]()

        let quotedMessage: TSQuotedMessage?
        let quotedMessageThumbnail: BackupProto_MessageAttachment?
        if standardMessage.hasQuote {
            switch self
                .restoreQuote(
                    standardMessage.quote,
                    chatItemId: chatItemId,
                    thread: chatThread,
                    context: context,
                )
                .bubbleUp(
                    BackupArchive.RestoredMessageContents.self,
                    partialErrors: &partialErrors,
                )
            {
            case .continue(let component):
                quotedMessage = component.0
                quotedMessageThumbnail = component.1
            case .bubbleUpError(let error):
                return error
            }
        } else {
            quotedMessage = nil
            quotedMessageThumbnail = nil
        }

        let linkPreview: OWSLinkPreview?
        let linkPreviewAttachment: BackupProto_FilePointer?
        if let linkPreviewProto = standardMessage.linkPreview.first {
            switch self
                .restoreLinkPreview(
                    linkPreviewProto,
                    standardMessage: standardMessage,
                    chatItemId: chatItemId,
                    context: context,
                )
                .bubbleUp(
                    BackupArchive.RestoredMessageContents.self,
                    partialErrors: &partialErrors,
                )
            {
            case .continue(let component):
                if let component {
                    linkPreview = component.0
                    linkPreviewAttachment = component.1
                } else {
                    linkPreview = nil
                    linkPreviewAttachment = nil
                }
            case .bubbleUpError(let error):
                return error
            }
        } else {
            linkPreview = nil
            linkPreviewAttachment = nil
        }

        let oversizeTextAttachment: BackupProto_FilePointer?
        if standardMessage.hasLongText {
            oversizeTextAttachment = standardMessage.longText
        } else {
            oversizeTextAttachment = nil
        }

        if standardMessage.text.body.isEmpty, standardMessage.attachments.isEmpty {
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.emptyStandardMessage),
                chatItemId,
            )])
        }
        let text = standardMessage.text

        let isVoiceMessage: Bool
        if
            standardMessage.attachments.count == 1,
            standardMessage.attachments.first?.flag == .voiceMessage
        {
            isVoiceMessage = true
        } else {
            isVoiceMessage = false
        }

        let messageBodyResult = restoreMessageBody(
            text,
            oversizeTextAttachment: oversizeTextAttachment,
            chatItemId: chatItemId,
        )
        switch messageBodyResult {
        case .success(let body):
            let contents = BackupArchive.RestoredMessageContents.text(.init(
                body: body,
                quotedMessage: quotedMessage,
                linkPreview: linkPreview,
                isVoiceMessage: isVoiceMessage,
                reactions: standardMessage.reactions,
                bodyAttachments: standardMessage.attachments,
                quotedMessageThumbnail: quotedMessageThumbnail,
                linkPreviewImage: linkPreviewAttachment,
            ))
            if partialErrors.isEmpty {
                return .success(contents)
            } else {
                return .partialRestore(contents, partialErrors)
            }
        case .partialRestore(let body, let messageBodyErrors):
            return .partialRestore(
                .text(.init(
                    body: body,
                    quotedMessage: quotedMessage,
                    linkPreview: linkPreview,
                    isVoiceMessage: isVoiceMessage,
                    reactions: standardMessage.reactions,
                    bodyAttachments: standardMessage.attachments,
                    quotedMessageThumbnail: quotedMessageThumbnail,
                    linkPreviewImage: linkPreviewAttachment,
                )),
                partialErrors + messageBodyErrors,
            )
        case .unrecognizedEnum(let error):
            return .unrecognizedEnum(error)
        case .messageFailure(let messageBodyErrors):
            return .messageFailure(partialErrors + messageBodyErrors)
        }
    }

    typealias RestoredMessageBody = BackupArchive.RestoredMessageContents.Text.RestoredMessageBody

    private func restoreMessageBody(
        _ text: BackupProto_Text,
        oversizeTextAttachment: BackupProto_FilePointer?,
        chatItemId: BackupArchive.ChatItemId,
    ) -> RestoreInteractionResult<RestoredMessageBody?> {
        guard text.body.isEmpty.negated else {
            return .success(nil)
        }
        return restoreMessageBody(
            text: text.body,
            bodyRangeProtos: text.bodyRanges,
            oversizeTextAttachment: oversizeTextAttachment,
            chatItemId: chatItemId,
        )
    }

    private func restoreMessageBody(
        text: String,
        bodyRangeProtos: [BackupProto_BodyRange],
        oversizeTextAttachment: BackupProto_FilePointer?,
        chatItemId: BackupArchive.ChatItemId,
    ) -> RestoreInteractionResult<RestoredMessageBody?> {
        var partialErrors = [RestoreFrameError]()
        var bodyMentions = [NSRange: Aci]()
        var bodyStyles = [NSRangedValue<MessageBodyRanges.SingleStyle>]()
        for bodyRange in bodyRangeProtos {
            let bodyRangeStart = bodyRange.start
            let bodyRangeLength = bodyRange.length

            let range = NSRange(location: Int(bodyRangeStart), length: Int(bodyRangeLength))
            switch bodyRange.associatedValue {
            case .mentionAci(let aciData):
                guard let mentionAci = try? Aci.parseFrom(serviceIdBinary: aciData) else {
                    partialErrors.append(.restoreFrameError(
                        .invalidProtoData(.invalidAci(protoClass: BackupProto_BodyRange.self)),
                        chatItemId,
                    ))
                    continue
                }
                bodyMentions[range] = mentionAci
            case .style(let protoBodyRangeStyle):
                let swiftStyle: MessageBodyRanges.SingleStyle
                switch protoBodyRangeStyle {
                case .none, .UNRECOGNIZED:
                    continue
                case .bold:
                    swiftStyle = .bold
                case .italic:
                    swiftStyle = .italic
                case .monospace:
                    swiftStyle = .monospace
                case .spoiler:
                    swiftStyle = .spoiler
                case .strikethrough:
                    swiftStyle = .strikethrough
                }
                bodyStyles.append(.init(swiftStyle, range: range))
            case nil:
                partialErrors.append(.restoreFrameError(
                    .invalidProtoData(.invalidAci(protoClass: BackupProto_BodyRange.self)),
                    chatItemId,
                ))
                continue
            }
        }
        let bodyRanges = MessageBodyRanges(mentions: bodyMentions, styles: bodyStyles)

        let restoredBody: RestoredMessageBody?
        switch oversizeTextArchiver.restoreMessageBody(
            text,
            bodyRanges: bodyRanges,
            oversizeTextAttachment: oversizeTextAttachment,
            chatItemId: chatItemId,
        ).bubbleUp(Optional<RestoredMessageBody>.self, partialErrors: &partialErrors) {
        case .continue(let component):
            restoredBody = component
        case .bubbleUpError(let error):
            return error
        }

        if partialErrors.isEmpty {
            return .success(restoredBody)
        } else {
            // We still get text, albeit without any mentions or styles, if
            // we have these failures. So count as a partial restore, not
            // complete failure.
            return .partialRestore(restoredBody, partialErrors)
        }
    }

    private func restoreQuote(
        _ quote: BackupProto_Quote,
        chatItemId: BackupArchive.ChatItemId,
        thread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext,
    ) -> RestoreInteractionResult<(TSQuotedMessage, BackupProto_MessageAttachment?)> {
        let authorAddress: BackupArchive.InteropAddress
        switch context.recipientContext[quote.authorRecipientId] {
        case .none:
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.recipientIdNotFound(quote.authorRecipientId)),
                chatItemId,
            )])
        case .localAddress:
            authorAddress = context.recipientContext.localIdentifiers.aciAddress
        case .group, .distributionList, .releaseNotesChannel, .callLink:
            // Groups and distritibution lists cannot be an authors of a message!
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.incomingMessageNotFromAciOrE164),
                chatItemId,
            )])
        case .contact(let contactAddress):
            guard contactAddress.aci != nil || contactAddress.e164 != nil else {
                return .messageFailure([.restoreFrameError(
                    .invalidProtoData(.incomingMessageNotFromAciOrE164),
                    chatItemId,
                )])
            }
            authorAddress = contactAddress.asInteropAddress()
        }

        var partialErrors = [RestoreFrameError]()

        let targetMessageTimestamp: NSNumber?
        let bodySource: TSQuotedMessageContentSource
        if
            quote.hasTargetSentTimestamp,
            quote.targetSentTimestamp > 0,
            SDS.fitsInInt64(quote.targetSentTimestamp)
        {
            targetMessageTimestamp = NSNumber(value: quote.targetSentTimestamp)
            // non-nil timestamp means the client that created the backup had
            // the target message at receive time (local state was .local)
            bodySource = .local
        } else {
            targetMessageTimestamp = nil
            // nil timestamp means the client that created the backup did not have
            // the target message at receive time (local state was .remote)
            bodySource = .remote
        }

        let quoteBody: MessageBody?
        if quote.hasText {
            switch self
                .restoreMessageBody(
                    text: quote.text.body,
                    bodyRangeProtos: quote.text.bodyRanges,
                    // Quotes don't support oversize text
                    oversizeTextAttachment: nil,
                    chatItemId: chatItemId,
                )
                .bubbleUp(
                    (TSQuotedMessage, BackupProto_MessageAttachment?).self,
                    partialErrors: &partialErrors,
                )
            {
            case .continue(let component):
                // We drop oversize text for quotes, if any.
                if component?.oversizeText != nil {
                    partialErrors.append(.restoreFrameError(
                        .invalidProtoData(.quotedMessageOversizeText),
                        chatItemId,
                    ))
                }
                quoteBody = component?.inlinedBody
            case .bubbleUpError(let error):
                return error
            }
        } else {
            quoteBody = nil
        }

        let isGiftBadge: Bool
        let isTargetMessageViewOnce: Bool
        let isPoll: Bool
        switch quote.type {
        case .UNRECOGNIZED, .unknown, .normal:
            isGiftBadge = false
            isTargetMessageViewOnce = false
            isPoll = false
        case .viewOnce:
            isGiftBadge = false
            isTargetMessageViewOnce = true
            isPoll = false
        case .giftBadge:
            isGiftBadge = true
            isTargetMessageViewOnce = false
            isPoll = false
        case .poll:
            isGiftBadge = false
            isTargetMessageViewOnce = false
            isPoll = true
        }

        let quotedAttachmentInfo: OWSAttachmentInfo?
        let quotedAttachmentThumbnail: BackupProto_MessageAttachment?
        if let quotedAttachmentProto = quote.attachments.first {
            let mimeType = quotedAttachmentProto.contentType.nilIfEmpty ?? MimeType.applicationOctetStream.rawValue
            let sourceFilename = quotedAttachmentProto.fileName.nilIfEmpty

            quotedAttachmentInfo = OWSAttachmentInfo(
                originalAttachmentMimeType: mimeType,
                originalAttachmentSourceFilename: sourceFilename,
            )
            if quotedAttachmentProto.hasThumbnail {
                quotedAttachmentThumbnail = quotedAttachmentProto.thumbnail
            } else {
                quotedAttachmentThumbnail = nil
            }
        } else {
            quotedAttachmentInfo = nil
            quotedAttachmentThumbnail = nil
        }

        if
            quoteBody == nil,
            quotedAttachmentInfo == nil,
            !isGiftBadge,
            !isTargetMessageViewOnce
        {
            partialErrors.append(.restoreFrameError(
                .invalidProtoData(.quotedMessageEmptyContent),
                chatItemId,
            ))
        }

        let quotedMessage = TSQuotedMessage(
            fromBackupWithTargetMessageTimestamp: targetMessageTimestamp,
            authorAddress: authorAddress,
            body: quoteBody?.text,
            bodyRanges: quoteBody?.ranges,
            bodySource: bodySource,
            quotedAttachmentInfo: quotedAttachmentInfo,
            isGiftBadge: isGiftBadge,
            isTargetMessageViewOnce: isTargetMessageViewOnce,
            isPoll: isPoll,
        )

        if partialErrors.isEmpty {
            return .success((quotedMessage, quotedAttachmentThumbnail))
        } else {
            return .partialRestore((quotedMessage, quotedAttachmentThumbnail), partialErrors)
        }
    }

    private func restoreLinkPreview(
        _ linkPreviewProto: BackupProto_LinkPreview,
        standardMessage: BackupProto_StandardMessage,
        chatItemId: BackupArchive.ChatItemId,
        context: BackupArchive.RestoringContext,
    ) -> RestoreInteractionResult<(OWSLinkPreview, BackupProto_FilePointer?)?> {
        guard let url = linkPreviewProto.url.nilIfEmpty else {
            return .partialRestore(nil, [.restoreFrameError(
                .invalidProtoData(.linkPreviewEmptyUrl),
                chatItemId,
            )])
        }
        guard standardMessage.text.body.contains(url) else {
            return .partialRestore(nil, [.restoreFrameError(
                .invalidProtoData(.linkPreviewUrlNotInBody),
                chatItemId,
            )])
        }
        let date: Date?
        if linkPreviewProto.hasDate {
            date = .init(millisecondsSince1970: linkPreviewProto.date)
        } else {
            date = nil
        }

        let metadata = OWSLinkPreview.Metadata(
            urlString: url,
            title: linkPreviewProto.title.nilIfEmpty,
            previewDescription: linkPreviewProto.description_p.nilIfEmpty,
            date: date,
        )

        if linkPreviewProto.hasImage {
            let linkPreview = OWSLinkPreview(
                metadata: metadata,
            )
            return .success((linkPreview, linkPreviewProto.image))
        } else {
            let linkPreview = OWSLinkPreview(
                metadata: metadata,
            )
            return .success((linkPreview, nil))
        }
    }

    // MARK: -

    private func restoreContactMessage(
        _ contactMessage: BackupProto_ContactMessage,
        chatItemId: BackupArchive.ChatItemId,
        chatThread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext,
    ) -> RestoreInteractionResult<BackupArchive.RestoredMessageContents> {
        var partialErrors = [RestoreFrameError]()

        guard contactMessage.hasContact else {
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.contactMessageMissingContactAttachment),
                chatItemId,
            )])
        }
        let contactAttachment = contactMessage.contact

        let contactResult = contactAttachmentArchiver.restoreContact(
            contactAttachment,
            chatItemId: chatItemId,
        )
        let contact: OWSContact
        switch contactResult
            .bubbleUp(
                BackupArchive.RestoredMessageContents.self,
                partialErrors: &partialErrors,
            )
        {
        case .continue(let component):
            contact = component
        case .bubbleUpError(let error):
            return error
        }

        let avatar: BackupProto_FilePointer?
        if contactAttachment.hasAvatar {
            avatar = contactAttachment.avatar
        } else {
            avatar = nil
        }

        let contents = BackupArchive.RestoredMessageContents.contactShare(.init(
            contact: contact,
            avatarAttachment: avatar,
            reactions: contactMessage.reactions,
        ))
        if partialErrors.isEmpty {
            return .success(contents)
        } else {
            return .partialRestore(contents, partialErrors)
        }
    }

    // MARK: -

    private func restoreStickerMessage(
        _ stickerMessage: BackupProto_StickerMessage,
        chatItemId: BackupArchive.ChatItemId,
        chatThread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext,
    ) -> RestoreInteractionResult<BackupArchive.RestoredMessageContents> {
        let stickerProto = stickerMessage.sticker
        let messageSticker = MessageSticker(
            info: .init(
                packId: stickerProto.packID,
                packKey: stickerProto.packKey,
                stickerId: stickerProto.stickerID,
            ),
            emoji: stickerProto.emoji.nilIfEmpty,
        )

        return .success(.stickerMessage(.init(
            sticker: messageSticker,
            attachment: stickerProto.data,
            reactions: stickerMessage.reactions,
        )))
    }

    // MARK: -

    private func restoreGiftBadge(
        _ giftBadgeProto: BackupProto_GiftBadge,
        chatItemId: BackupArchive.ChatItemId,
        context: BackupArchive.ChatItemRestoringContext,
    ) -> RestoreInteractionResult<BackupArchive.RestoredMessageContents> {
        let giftBadge: OWSGiftBadge
        switch giftBadgeProto.state {
        case .unopened, .UNRECOGNIZED:
            giftBadge = .restoreFromBackup(
                receiptCredentialPresentation: giftBadgeProto.receiptCredentialPresentation,
                redemptionState: .pending,
            )
        case .opened:
            giftBadge = .restoreFromBackup(
                receiptCredentialPresentation: giftBadgeProto.receiptCredentialPresentation,
                redemptionState: .opened,
            )
        case .redeemed:
            giftBadge = .restoreFromBackup(
                receiptCredentialPresentation: giftBadgeProto.receiptCredentialPresentation,
                redemptionState: .redeemed,
            )
        case .failed:
            /// Passing `receiptCredentialPresentation: nil` will make this a
            /// non-functional gift badge in practice. At the time of writing
            /// iOS doesn't have a "failed" gift badge state, so we'll use this
            /// instead.
            giftBadge = .restoreFromBackup(
                receiptCredentialPresentation: nil,
                redemptionState: .pending,
            )
        }

        return .success(.giftBadge(BackupArchive.RestoredMessageContents.GiftBadge(
            giftBadge: giftBadge,
        )))
    }

    // MARK: -

    private func restoreViewOnceMessage(
        _ viewOnceMessage: BackupProto_ViewOnceMessage,
        chatItemId: BackupArchive.ChatItemId,
        chatThread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext,
    ) -> RestoreInteractionResult<BackupArchive.RestoredMessageContents> {
        let state: BackupArchive.RestoredMessageContents.ViewOnceMessage.State
        if viewOnceMessage.hasAttachment {
            state = .unviewed(viewOnceMessage.attachment)
        } else {
            state = .complete
        }
        return .success(.viewOnceMessage(.init(
            state: state,
            reactions: viewOnceMessage.reactions,
        )))
    }

    // MARK: -

    /// Note this only covers 1:1 story replies which are rendered in-chat;
    /// group story replies are rendered in the story UI and are not backed
    /// up since stories are not backed up.
    private func restoreDirectStoryReplyMessage(
        _ storyReply: BackupProto_DirectStoryReplyMessage,
        chatItemId: BackupArchive.ChatItemId,
        chatThread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext,
    ) -> RestoreInteractionResult<BackupArchive.RestoredMessageContents> {
        var partialErrors = [RestoreFrameError]()

        let replyType: BackupArchive.RestoredMessageContents.StoryReply.ReplyType

        switch storyReply.reply {
        case .textReply(let textReply):
            let oversizeTextAttachment: BackupProto_FilePointer? = if textReply.hasLongText {
                textReply.longText
            } else {
                nil
            }

            let messageBody: RestoredMessageBody?
            switch self
                .restoreMessageBody(
                    textReply.text,
                    oversizeTextAttachment: oversizeTextAttachment,
                    chatItemId: chatItemId,
                )
                .bubbleUp(
                    BackupArchive.RestoredMessageContents.self,
                    partialErrors: &partialErrors,
                )
            {
            case .continue(let component):
                messageBody = component
            case .bubbleUpError(let error):
                return error
            }

            if let messageBody {
                replyType = .textReply(.init(
                    body: messageBody,
                ))
            } else {
                let restoreErrorType: RestoreFrameError.ErrorType
                if oversizeTextAttachment != nil {
                    restoreErrorType = .invalidProtoData(.directStoryReplyMessageEmptyWithLongText)
                } else {
                    restoreErrorType = .invalidProtoData(.directStoryReplyMessageEmpty)
                }

                return .messageFailure([.restoreFrameError(
                    restoreErrorType,
                    chatItemId,
                )] + partialErrors)
            }
        case .emoji(let string):
            replyType = .emoji(string)
        case .none:
            return .unrecognizedEnum(BackupArchive.UnrecognizedEnumError(
                enumType: BackupProto_DirectStoryReplyMessage.OneOf_Reply.self,
            ))
        }

        return .success(.storyReply(.init(
            replyType: replyType,
            reactions: storyReply.reactions,
        )))
    }

    // MARK: -

    typealias BackupsPollVote = BackupsPollData.BackupsPollOption.BackupsPollVote
    typealias BackupsPollOption = BackupsPollData.BackupsPollOption

    /// Polls
    private func restorePollMessage(
        _ poll: BackupProto_Poll,
        chatItemId: BackupArchive.ChatItemId,
        chatThread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext,
    ) -> RestoreInteractionResult<BackupArchive.RestoredMessageContents> {
        var partialErrors = [RestoreFrameError]()

        var options: [BackupsPollData.BackupsPollOption] = []
        for optionProto in poll.options {
            var votes: [BackupsPollVote] = []
            for voteProto in optionProto.votes {
                var voteAuthorId: SignalRecipient.RowId?
                let recipientId = BackupArchive.RecipientId(value: voteProto.voterID)
                switch context.recipientContext[recipientId] {
                case .localAddress:
                    voteAuthorId = context.recipientContext.localSignalRecipientRowId
                case .contact:
                    voteAuthorId = context.recipientContext.recipientDbRowId(forBackupRecipientId: recipientId)
                default:
                    partialErrors += [.restoreFrameError(
                        .invalidProtoData(.pollVoteAuthorNotContact),
                        chatItemId,
                    )]
                }

                guard let voteAuthorId else {
                    partialErrors += [.restoreFrameError(
                        .invalidProtoData(.recipientIdNotFound(recipientId)),
                        chatItemId,
                    )]
                    continue
                }
                votes.append(BackupsPollVote(voteAuthorId: voteAuthorId, voteCount: voteProto.voteCount))
            }
            options.append(BackupsPollOption(text: optionProto.option, votes: votes))
        }

        let pollData = BackupsPollData(
            question: poll.question,
            allowMultiple: poll.allowMultiple,
            isEnded: poll.hasEnded_p,
            options: options,
        )

        var pollQuestion: RestoredMessageBody

        switch self
            .restoreMessageBody(
                text: poll.question,
                bodyRangeProtos: [],
                oversizeTextAttachment: nil,
                chatItemId: chatItemId,
            )
            .bubbleUp(
                BackupArchive.RestoredMessageContents.self,
                partialErrors: &partialErrors,
            )
        {
        case .continue(let component):
            guard let component else {
                return .messageFailure([.restoreFrameError(
                    .invalidProtoData(.pollQuestionEmpty),
                    chatItemId,
                )] + partialErrors)
            }
            pollQuestion = component
        case .bubbleUpError(let error):
            return error
        }

        let poll = BackupArchive.RestoredMessageContents.Poll(
            poll: pollData,
            question: pollQuestion,
            reactions: poll.reactions,
        )

        if partialErrors.isEmpty {
            return .success(
                .poll(poll),
            )
        } else {
            return .partialRestore(
                .poll(poll),
                partialErrors,
            )
        }
    }

    // MARK: -

    private func restorePinMessage(
        pinDetails: BackupProto_ChatItem.PinDetails,
        message: TSMessage,
        chatItemId: BackupArchive.ChatItemId,
        chatThread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext,
    ) -> BackupArchive.RestoreInteractionResult<Void> {

        let threadId: Int64?
        switch chatThread.threadType {
        case .contact(let contactThread):
            threadId = contactThread.sqliteRowId
        case .groupV2(let groupThread):
            threadId = groupThread.sqliteRowId
        }

        guard let threadId else {
            return .messageFailure([.restoreFrameError(
                .databaseModelMissingRowId(modelClass: TSThread.self),
                chatItemId,
            )])
        }

        var expiresAtTimestamp: UInt64?
        switch pinDetails.pinExpiry {
        case .pinExpiresAtTimestamp(let timestamp):
            guard BackupArchive.Timestamps.isValid(timestamp) else {
                return .partialRestore((), [.restoreFrameError(
                    .invalidProtoData(.chatItemInvalidDateSent),
                    chatItemId,
                )])
            }
            expiresAtTimestamp = timestamp
        case .pinNeverExpires, .none:
            break
        }

        guard BackupArchive.Timestamps.isValid(pinDetails.pinnedAtTimestamp) else {
            return .partialRestore((), [.restoreFrameError(
                .invalidProtoData(.chatItemInvalidDateSent),
                chatItemId,
            )])
        }

        let details = PinMessageDetails(pinnedAtTimestamp: pinDetails.pinnedAtTimestamp, expiresAtTimestamp: expiresAtTimestamp)

        let applyPinMessageResult = pinnedMessageManager.applyPinMessageFromBackup(
            message: message,
            threadId: threadId,
            pinDetails: details,
            chatItemId: chatItemId,
            tx: context.tx,
        )

        switch applyPinMessageResult {
        case .success:
            return .success(())
        case .unrecognizedEnum(let error):
            return .unrecognizedEnum(error)
        case .partialRestore(let errors):
            return .partialRestore((), errors)
        case .failure(let error):
            return .messageFailure(error)
        }
    }
}

// MARK: -

private extension ArchivedPayment {
    static func fromBackup(
        _ backup: BackupArchive.RestoredMessageContents.Payment,
        senderOrRecipientAci: Aci,
        direction: Direction,
        interactionUniqueId: String?,
    ) -> ArchivedPayment {
        var archivedPayment: ArchivedPayment
        switch backup.status {
        case .failure(let reason):
            archivedPayment = ArchivedPayment(
                amount: nil,
                fee: nil,
                note: nil,
                mobileCoinIdentification: nil,
                status: .error,
                failureReason: reason.asFailureType(),
                direction: direction,
                timestamp: nil,
                blockIndex: nil,
                blockTimestamp: nil,
                transaction: nil,
                receipt: nil,
                senderOrRecipientAci: senderOrRecipientAci,
                interactionUniqueId: interactionUniqueId,
            )
        case .success(let status):
            let payment = backup.payment
            let transactionIdentifier = payment?.mobileCoinIdentification.nilIfEmpty.map {
                TransactionIdentifier(publicKey: $0.publicKey, keyImages: $0.keyImages)
            }

            archivedPayment = ArchivedPayment(
                amount: backup.amount,
                fee: backup.fee,
                note: backup.note,
                mobileCoinIdentification: transactionIdentifier,
                status: status.asStatusType(),
                failureReason: .none,
                direction: direction,
                timestamp: payment?.timestamp,
                blockIndex: payment?.blockIndex,
                blockTimestamp: payment?.blockTimestamp,
                transaction: payment?.transaction.nilIfEmpty,
                receipt: payment?.receipt,
                senderOrRecipientAci: senderOrRecipientAci,
                interactionUniqueId: interactionUniqueId,
            )
        }
        return archivedPayment
    }
}

private extension BackupProto_PaymentNotification.TransactionDetails.FailedTransaction.FailureReason {
    func asFailureType() -> ArchivedPayment.FailureReason {
        switch self {
        case .UNRECOGNIZED, .generic: return .genericFailure
        case .network: return .networkFailure
        case .insufficientFunds: return .insufficientFundsFailure
        }
    }
}

private extension BackupProto_PaymentNotification.TransactionDetails.Transaction.Status {
    func asStatusType() -> ArchivedPayment.Status {
        switch self {
        case .UNRECOGNIZED, .initial: return .initial
        case .submitted: return .submitted
        case .successful: return .successful
        }
    }
}

private extension BackupProto_PaymentNotification.TransactionDetails.MobileCoinTxoIdentification {
    var nilIfEmpty: Self? {
        (publicKey.isEmpty && keyImages.isEmpty) ? nil : self
    }
}
