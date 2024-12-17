//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension MessageBackup {

    /// Represents message content "types" as they are represented in iOS code, after
    /// being mapped from their representation in the backup proto. For example, normal
    /// text messages and quoted replies are a single "type" in the proto, but have separate
    /// class structures in the iOS code.
    ///
    /// This object will be passed back into the ``MessageBackupTSMessageContentsArchiver`` class
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
            let body: MessageBody?
            let quotedMessage: TSQuotedMessage?
            let linkPreview: OWSLinkPreview?
            let isVoiceMessage: Bool

            fileprivate let reactions: [BackupProto_Reaction]
            fileprivate let oversizeTextAttachment: BackupProto_FilePointer?
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

        case archivedPayment(Payment)
        case remoteDeleteTombstone
        case text(Text)
        case contactShare(ContactShare)
        case stickerMessage(StickerMessage)
        case giftBadge(GiftBadge)
        case viewOnceMessage(ViewOnceMessage)
    }
}

class MessageBackupTSMessageContentsArchiver: MessageBackupProtoArchiver {

    typealias ChatItemType = MessageBackup.InteractionArchiveDetails.ChatItemType

    typealias ArchiveInteractionResult = MessageBackup.ArchiveInteractionResult
    typealias RestoreInteractionResult = MessageBackup.RestoreInteractionResult

    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<MessageBackup.InteractionUniqueId>
    private typealias RestoreFrameError = MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>

    private let interactionStore: MessageBackupInteractionStore
    private let archivedPaymentStore: ArchivedPaymentStore
    private let attachmentsArchiver: MessageBackupMessageAttachmentArchiver
    private lazy var contactAttachmentArchiver = MessageBackupContactAttachmentArchiver(
        attachmentsArchiver: attachmentsArchiver
    )
    private let reactionArchiver: MessageBackupReactionArchiver

    init(
        interactionStore: MessageBackupInteractionStore,
        archivedPaymentStore: ArchivedPaymentStore,
        attachmentsArchiver: MessageBackupMessageAttachmentArchiver,
        reactionArchiver: MessageBackupReactionArchiver
    ) {
        self.interactionStore = interactionStore
        self.archivedPaymentStore = archivedPaymentStore
        self.attachmentsArchiver = attachmentsArchiver
        self.reactionArchiver = reactionArchiver
    }

    // MARK: - Archiving

    func archiveMessageContents(
        _ message: TSMessage,
        context: MessageBackup.RecipientArchivingContext
    ) -> ArchiveInteractionResult<ChatItemType> {
        guard let messageRowId = message.sqliteRowId else {
            return .completeFailure(.fatalArchiveError(
                .fetchedInteractionMissingRowId
            ))
        }

        if let paymentMessage = message as? OWSPaymentMessage {
            return archivePaymentMessageContents(
                paymentMessage,
                uniqueInteractionId: message.uniqueInteractionId,
                context: context
            )
        } else if let archivedPayment = message as? OWSArchivedPaymentMessage {
            return archivePaymentArchiveContents(
                archivedPayment,
                uniqueInteractionId: message.uniqueInteractionId,
                context: context
            )
        } else if message.wasRemotelyDeleted {
            return archiveRemoteDeleteTombstone(
                message,
                context: context
            )
        } else if let contactShare = message.contactShare {
            return archiveContactShareMessageContents(
                message,
                contactShare: contactShare,
                messageRowId: messageRowId,
                context: context
            )
        } else if let messageSticker = message.messageSticker {
            return archiveStickerMessageContents(
                message,
                messageSticker: messageSticker,
                messageRowId: messageRowId,
                context: context
            )
        } else if let giftBadge = message.giftBadge {
            return archiveGiftBadge(
                giftBadge,
                context: context
            )
        } else if message.isViewOnceMessage {
            return archiveViewOnceMessage(
                message,
                messageRowId: messageRowId,
                context: context
            )
        } else {
            return archiveStandardMessageContents(
                message,
                messageRowId: messageRowId,
                context: context
            )
        }
    }

    // MARK: -

    private func archivePaymentArchiveContents(
        _ archivedPaymentMessage: OWSArchivedPaymentMessage,
        uniqueInteractionId: MessageBackup.InteractionUniqueId,
        context: MessageBackup.RecipientArchivingContext
    ) -> MessageBackup.ArchiveInteractionResult<ChatItemType> {
        let historyItem: ArchivedPayment?
        do {
            historyItem = try archivedPaymentStore.fetch(
                for: archivedPaymentMessage,
                interactionUniqueId: uniqueInteractionId.value,
                tx: context.tx
            )
        } catch {
            return .messageFailure([.archiveFrameError(.paymentInfoFetchFailed(error), uniqueInteractionId)])
        }
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
        uniqueInteractionId: MessageBackup.InteractionUniqueId,
        context: MessageBackup.RecipientArchivingContext
    ) -> MessageBackup.ArchiveInteractionResult<ChatItemType> {
        guard
            let paymentNotification = message.paymentNotification,
            let model = PaymentFinder.paymentModels(
                forMcReceiptData: paymentNotification.mcReceiptData,
                transaction: SDSDB.shimOnlyBridge(context.tx)
            ).first
        else {
            return .messageFailure([.archiveFrameError(.missingPaymentInformation, uniqueInteractionId)])
        }

        var paymentNotificationProto = BackupProto_PaymentNotification()

        if
            let amount = model.paymentAmount,
            let amountString = PaymentsFormat.format(
                picoMob: amount.picoMob,
                isShortForm: true
            )
        {
            paymentNotificationProto.amountMob = amountString
        }
        if
            let fee = model.mobileCoin?.feeAmount,
            let feeString = PaymentsFormat.format(
                picoMob: fee.picoMob,
                isShortForm: true
            )
        {
            paymentNotificationProto.feeMob = feeString
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
        context: MessageBackup.RecipientArchivingContext
    ) -> ArchiveInteractionResult<ChatItemType> {
        let remoteDeletedMessage = BackupProto_RemoteDeletedMessage()
        return .success(.remoteDeletedMessage(remoteDeletedMessage))
    }

    // MARK: -

    private func archiveStandardMessageContents(
        _ message: TSMessage,
        messageRowId: Int64,
        context: MessageBackup.RecipientArchivingContext
    ) -> ArchiveInteractionResult<ChatItemType> {
        var standardMessage = BackupProto_StandardMessage()
        var partialErrors = [ArchiveFrameError]()

        // Every "StandardMessage" must have either a body or body attachments;
        // if neither is set this stays false and we fail the message.
        var hasPrimaryContent = false
        var hasText = false

        if let messageBody = message.body?.nilIfEmpty {
            hasPrimaryContent = true

            let text: BackupProto_Text
            let textResult = archiveText(
                MessageBody(text: messageBody, ranges: message.bodyRanges ?? .empty),
                interactionUniqueId: message.uniqueInteractionId
            )
            switch textResult.bubbleUp(ChatItemType.self, partialErrors: &partialErrors) {
            case .continue(let value):
                text = value
            case .bubbleUpError(let errorResult):
                return errorResult
            }
            standardMessage.text = text
            hasText = true

            // Oversize text is only ever a thing _alongside_ body text, the body
            // text is a prefix of the oversize text.

            // Returns nil if no oversize text; this is both how we check and how we archive.
            let oversizeTextResult = attachmentsArchiver.archiveOversizeTextAttachment(
                messageRowId: messageRowId,
                messageId: message.uniqueInteractionId,
                context: context
            )
            switch oversizeTextResult.bubbleUp(ChatItemType.self, partialErrors: &partialErrors) {
            case .continue(let oversizeTextAttachmentProto):
                oversizeTextAttachmentProto.map { standardMessage.longText = $0 }
            case .bubbleUpError(let errorResult):
                return errorResult
            }
        }

        let bodyAttachmentsResult = attachmentsArchiver.archiveBodyAttachments(
            messageId: message.uniqueInteractionId,
            messageRowId: messageRowId,
            context: context
        )
        switch bodyAttachmentsResult.bubbleUp(ChatItemType.self, partialErrors: &partialErrors) {
        case .continue(var bodyAttachmentProtos):
            if !bodyAttachmentProtos.isEmpty {
                hasPrimaryContent = true
                if hasText, bodyAttachmentProtos.first?.flag == .voiceMessage {
                    // Drop the voice message flag if text is nonempty.
                    bodyAttachmentProtos = bodyAttachmentProtos.map {
                        guard $0.flag == .voiceMessage else {
                            return $0
                        }
                        var proto = $0
                        proto.flag = .none
                        return proto
                    }
                }
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
            return .skippableChatUpdate(.emptyBodyMessage)
        }

        if let quotedMessage = message.quotedMessage {
            let quote: BackupProto_Quote
            let quoteResult = archiveQuote(
                quotedMessage,
                interactionUniqueId: message.uniqueInteractionId,
                messageRowId: messageRowId,
                context: context
            )
            switch quoteResult.bubbleUp(ChatItemType.self, partialErrors: &partialErrors) {
            case .continue(let _quote):
                quote = _quote
            case .bubbleUpError(let errorResult):
                return errorResult
            }

            standardMessage.quote = quote
        }

        if let linkPreview = message.linkPreview {
            let linkPreviewResult = self.archiveLinkPreview(
                linkPreview,
                messageBody: standardMessage.text.body,
                interactionUniqueId: message.uniqueInteractionId,
                context: context,
                messageRowId: messageRowId
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
            context: context
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
        interactionUniqueId: MessageBackup.InteractionUniqueId
    ) -> ArchiveInteractionResult<BackupProto_Text> {
        var text = BackupProto_Text()
        text.body = messageBody.text

        for bodyRangeParam in messageBody.ranges.toProtoBodyRanges() {
            var bodyRange = BackupProto_BodyRange()
            bodyRange.start = bodyRangeParam.start
            bodyRange.length = bodyRangeParam.length

            if let mentionAci = Aci.parseFrom(aciString: bodyRangeParam.mentionAci) {
                bodyRange.associatedValue = .mentionAci(
                    mentionAci.serviceIdBinary.asData
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
        interactionUniqueId: MessageBackup.InteractionUniqueId,
        messageRowId: Int64,
        context: MessageBackup.RecipientArchivingContext
    ) -> ArchiveInteractionResult<BackupProto_Quote> {
        var partialErrors = [ArchiveFrameError]()

        guard let authorAddress = quotedMessage.authorAddress.asSingleServiceIdBackupAddress() else {
            // Fail the whole message if we fail archiving a quote.
            return .messageFailure([.archiveFrameError(.invalidQuoteAuthor, interactionUniqueId)])
        }
        guard let authorId = context[.contact(authorAddress)] else {
            // Fail the whole message if we fail archiving a quote.
            return .messageFailure([.archiveFrameError(
                .referencedRecipientIdMissing(.contact(authorAddress)),
                interactionUniqueId
            )])
        }

        var quote = BackupProto_Quote()
        quote.authorID = authorId.value
        if quotedMessage.isGiftBadge {
            quote.type = .giftBadge
        } else if quotedMessage.isTargetMessageViewOnce {
            quote.type = .viewOnce
        } else {
            quote.type = .normal
        }

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
        if let targetSentTimestamp, targetSentTimestamp > 0 {
            quote.targetSentTimestamp = targetSentTimestamp
        }

        if let body = quotedMessage.body {
            let textResult = archiveText(
                MessageBody(text: body, ranges: quotedMessage.bodyRanges ?? .empty),
                interactionUniqueId: interactionUniqueId
            )
            let text: BackupProto_Text
            switch textResult.bubbleUp(BackupProto_Quote.self, partialErrors: &partialErrors) {
            case .continue(let value):
                text = value
            case .bubbleUpError(let errorResult):
                return errorResult
            }

            quote.text = { () -> BackupProto_Text in
                var quoteText = BackupProto_Text()
                quoteText.body = text.body
                quoteText.bodyRanges = text.bodyRanges
                return quoteText
            }()
        }

        if let attachmentInfo = quotedMessage.attachmentInfo() {
            let quoteAttachmentResult = self.archiveQuoteAttachment(
                attachmentInfo: attachmentInfo,
                interactionUniqueId: interactionUniqueId,
                messageRowId: messageRowId,
                context: context
            )
            switch quoteAttachmentResult.bubbleUp(BackupProto_Quote.self, partialErrors: &partialErrors) {
            case .continue(let quoteAttachmentProto):
                quote.attachments = [quoteAttachmentProto]
            case .bubbleUpError(let errorResult):
                return errorResult
            }
        }

        if partialErrors.isEmpty {
            return .success(quote)
        } else {
            return .partialFailure(quote, partialErrors)
        }
    }

    private func archiveQuoteAttachment(
        attachmentInfo: OWSAttachmentInfo,
        interactionUniqueId: MessageBackup.InteractionUniqueId,
        messageRowId: Int64,
        context: MessageBackup.ArchivingContext
    ) -> MessageBackup.ArchiveInteractionResult<BackupProto_Quote.QuotedAttachment> {
        var partialErrors = [MessageBackup.ArchiveFrameError<MessageBackup.InteractionUniqueId>]()

        var proto = BackupProto_Quote.QuotedAttachment()
        if let mimeType = attachmentInfo.originalAttachmentMimeType {
            proto.contentType = mimeType
        }
        if let sourceFilename = attachmentInfo.originalAttachmentSourceFilename {
            proto.fileName = sourceFilename
        }

        let imageResult = attachmentsArchiver.archiveQuotedReplyThumbnailAttachment(
            messageId: interactionUniqueId,
            messageRowId: messageRowId,
            context: context
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
        interactionUniqueId: MessageBackup.InteractionUniqueId,
        context: MessageBackup.RecipientArchivingContext,
        messageRowId: Int64
    ) -> ArchiveInteractionResult<BackupProto_LinkPreview?> {
        var partialErrors = [ArchiveFrameError]()

        guard let url = linkPreview.urlString else {
            // If we have no url, consider this a partial failure. The message
            // without the link preview is still valid, so just don't set a link preview
            // by returning nil.
            partialErrors.append(.archiveFrameError(
                .linkPreviewMissingUrl,
                interactionUniqueId
            ))
            return .partialFailure(nil, partialErrors)
        }

        guard messageBody.contains(url) else {
            partialErrors.append(.archiveFrameError(
                .linkPreviewUrlNotInBody,
                interactionUniqueId
            ))
            return .partialFailure(nil, partialErrors)
        }

        var proto = BackupProto_LinkPreview()
        proto.url = url
        linkPreview.title.map { proto.title = $0 }
        linkPreview.previewDescription.map { proto.description_p = $0 }
        linkPreview.date.map { proto.date = $0.ows_millisecondsSince1970 }

        // Returns nil if no link preview image; this is both how we check presence and how we archive.
        let imageResult = attachmentsArchiver.archiveLinkPreviewAttachment(
            messageRowId: messageRowId,
            messageId: interactionUniqueId,
            context: context
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
        context: MessageBackup.RecipientArchivingContext
    ) -> ArchiveInteractionResult<ChatItemType> {
        var partialErrors = [ArchiveFrameError]()

        var proto = BackupProto_ContactMessage()

        let contactResult = contactAttachmentArchiver.archiveContact(
            contactShare,
            uniqueInteractionId: message.uniqueInteractionId,
            messageRowId: messageRowId,
            context: context
        )
        switch contactResult.bubbleUp(ChatItemType.self, partialErrors: &partialErrors) {
        case .continue(let contactProto):
            proto.contact = [contactProto]
        case .bubbleUpError(let errorResult):
            return errorResult
        }

        let reactions: [BackupProto_Reaction]
        let reactionsResult = reactionArchiver.archiveReactions(
            message,
            context: context
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
        context: MessageBackup.RecipientArchivingContext
    ) -> ArchiveInteractionResult<ChatItemType> {
        var partialErrors = [ArchiveFrameError]()

        var proto = BackupProto_StickerMessage()

        var stickerProto = BackupProto_Sticker()
        stickerProto.packID = messageSticker.packId
        stickerProto.packKey = messageSticker.packKey
        stickerProto.stickerID = messageSticker.stickerId
        messageSticker.emoji.map { stickerProto.emoji = $0 }

        let stickerAttachmentResult = attachmentsArchiver.archiveStickerAttachment(
            messageId: message.uniqueInteractionId,
            messageRowId: messageRowId,
            context: context
        )

        switch stickerAttachmentResult.bubbleUp(ChatItemType.self, partialErrors: &partialErrors) {
        case .continue(let stickerAttachmentProto):
            guard let stickerAttachmentProto else {
                // We can't have a sticker without an attachment.
                return .messageFailure(partialErrors + [.archiveFrameError(
                    .stickerMessageMissingStickerAttachment,
                    message.uniqueInteractionId
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
            context: context
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
        context: MessageBackup.RecipientArchivingContext
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
        context: MessageBackup.RecipientArchivingContext
    ) -> ArchiveInteractionResult<ChatItemType> {
        var partialErrors = [ArchiveFrameError]()

        var proto = BackupProto_ViewOnceMessage()

        if !message.isViewOnceComplete {
            let attachmentResult = attachmentsArchiver.archiveBodyAttachments(
                messageId: message.uniqueInteractionId,
                messageRowId: messageRowId,
                context: context
            )
            switch attachmentResult.bubbleUp(ChatItemType.self, partialErrors: &partialErrors) {
            case .continue(let value):
                guard let first = value.first else {
                    return .messageFailure(partialErrors + [.archiveFrameError(
                        .unviewedViewOnceMessageMissingAttachment,
                        message.uniqueInteractionId
                    )])
                }
                if value.count > 1 {
                    partialErrors.append(.archiveFrameError(
                        .unviewedViewOnceMessageTooManyAttachments(value.count),
                        message.uniqueInteractionId
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
            context: context
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

    // MARK: - Restoring

    /// Parses the proto structure of message contents into
    /// into ``MessageBackup.RestoredMessageContents``, which map more directly
    /// to the ``TSMessage`` values in our database.
    ///
    /// Does NOT create the ``TSMessage``; callers are expected to utilize the
    /// restored contents to construct and insert the message.
    ///
    /// Callers MUST call ``restoreDownstreamObjects`` after creating and
    /// inserting the ``TSMessage``.
    func restoreContents(
        _ chatItemType: ChatItemType,
        chatItemId: MessageBackup.ChatItemId,
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatItemRestoringContext
    ) -> RestoreInteractionResult<MessageBackup.RestoredMessageContents> {
        switch chatItemType {
        case .paymentNotification(let paymentNotification):
            return restorePaymentNotification(
                paymentNotification,
                chatItemId: chatItemId,
                thread: chatThread,
                context: context
            )
        case .remoteDeletedMessage(let remoteDeletedMessage):
            return restoreRemoteDeleteTombstone(
                remoteDeletedMessage,
                chatItemId: chatItemId,
                chatThread: chatThread,
                context: context
            )
        case .standardMessage(let standardMessage):
            return restoreStandardMessage(
                standardMessage,
                chatItemId: chatItemId,
                chatThread: chatThread,
                context: context
            )
        case .contactMessage(let contactMessage):
            return restoreContactMessage(
                contactMessage,
                chatItemId: chatItemId,
                chatThread: chatThread,
                context: context
            )
        case .stickerMessage(let stickerMessage):
            return restoreStickerMessage(
                stickerMessage,
                chatItemId: chatItemId,
                chatThread: chatThread,
                context: context
            )
        case .giftBadge(let giftBadge):
            return restoreGiftBadge(
                giftBadge,
                chatItemId: chatItemId,
                context: context
            )
        case .viewOnceMessage(let viewOnceMessage):
            return restoreViewOnceMessage(
                viewOnceMessage,
                chatItemId: chatItemId,
                chatThread: chatThread,
                context: context
            )
        case .updateMessage:
            return .messageFailure([.restoreFrameError(
                .developerError(OWSAssertionError("Chat update has no contents to restore!")),
                chatItemId
            )])
        }
    }

    /// After a caller creates a ``TSMessage`` from the results of ``restoreContents``, they MUST call this method
    /// to create and insert all "downstream" objects: those that reference the ``TSMessage`` and require it for their own creation.
    ///
    /// This method will create and insert all necessary objects (e.g. reactions).
    func restoreDownstreamObjects(
        message: TSMessage,
        thread: MessageBackup.ChatThread,
        chatItemId: MessageBackup.ChatItemId,
        restoredContents: MessageBackup.RestoredMessageContents,
        context: MessageBackup.ChatItemRestoringContext
    ) -> RestoreInteractionResult<Void> {
        guard let messageRowId = message.sqliteRowId else {
            return .messageFailure([.restoreFrameError(
                .databaseModelMissingRowId(modelClass: type(of: message)),
                chatItemId
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
                context: context
            ))
        case .text(let text):
            downstreamObjectResults.append(reactionArchiver.restoreReactions(
                text.reactions,
                chatItemId: chatItemId,
                message: message,
                context: context.recipientContext
            ))
            if let oversizeTextAttachment = text.oversizeTextAttachment {
                downstreamObjectResults.append(attachmentsArchiver.restoreOversizeTextAttachment(
                    oversizeTextAttachment,
                    chatItemId: chatItemId,
                    messageRowId: messageRowId,
                    message: message,
                    thread: thread,
                    context: context
                ))
            }
            if text.bodyAttachments.isEmpty.negated {
                downstreamObjectResults.append(attachmentsArchiver.restoreBodyAttachments(
                    text.bodyAttachments,
                    chatItemId: chatItemId,
                    messageRowId: messageRowId,
                    message: message,
                    thread: thread,
                    context: context
                ))
            }
            if let quotedMessageThumbnail = text.quotedMessageThumbnail {
                downstreamObjectResults.append(attachmentsArchiver.restoreQuotedReplyThumbnailAttachment(
                    quotedMessageThumbnail,
                    chatItemId: chatItemId,
                    messageRowId: messageRowId,
                    message: message,
                    thread: thread,
                    context: context
                ))
            }
            if let linkPreviewImage = text.linkPreviewImage {
                downstreamObjectResults.append(attachmentsArchiver.restoreLinkPreviewAttachment(
                    linkPreviewImage,
                    chatItemId: chatItemId,
                    messageRowId: messageRowId,
                    message: message,
                    thread: thread,
                    context: context
                ))
            }
        case .contactShare(let contactShare):
            downstreamObjectResults.append(reactionArchiver.restoreReactions(
                contactShare.reactions,
                chatItemId: chatItemId,
                message: message,
                context: context.recipientContext
            ))
            if let avatarAttachment = contactShare.avatarAttachment {
                downstreamObjectResults.append(attachmentsArchiver.restoreContactAvatarAttachment(
                    avatarAttachment,
                    chatItemId: chatItemId,
                    messageRowId: messageRowId,
                    message: message,
                    thread: thread,
                    context: context
                ))
            }
        case .stickerMessage(let stickerMessage):
            downstreamObjectResults.append(reactionArchiver.restoreReactions(
                stickerMessage.reactions,
                chatItemId: chatItemId,
                message: message,
                context: context.recipientContext
            ))
            downstreamObjectResults.append(attachmentsArchiver.restoreStickerAttachment(
                stickerMessage.attachment,
                stickerPackId: stickerMessage.sticker.packId,
                stickerId: stickerMessage.sticker.stickerId,
                chatItemId: chatItemId,
                messageRowId: messageRowId,
                message: message,
                thread: thread,
                context: context
            ))
        case .viewOnceMessage(let viewOnceMessage):
            downstreamObjectResults.append(reactionArchiver.restoreReactions(
                viewOnceMessage.reactions,
                chatItemId: chatItemId,
                message: message,
                context: context.recipientContext
            ))
            switch viewOnceMessage.state {
            case .unviewed(let attachment):
                downstreamObjectResults.append(attachmentsArchiver.restoreBodyAttachments(
                    [attachment],
                    chatItemId: chatItemId,
                    messageRowId: messageRowId,
                    message: message,
                    thread: thread,
                    context: context
                ))
            case .complete:
                break
            }
        case .remoteDeleteTombstone, .giftBadge:
            // Nothing downstream to restore.
            break
        }

        return downstreamObjectResults.reduce(.success(()), {
            $0.combine($1)
        })
    }

    // MARK: -

    private func restoreArchivedPaymentContents(
        _ transaction: MessageBackup.RestoredMessageContents.Payment,
        chatItemId: MessageBackup.ChatItemId,
        thread: MessageBackup.ChatThread,
        message: TSMessage,
        context: MessageBackup.RestoringContext
    ) -> MessageBackup.RestoreInteractionResult<Void> {
        let senderOrRecipientAci: Aci? = {
            switch thread.threadType {
            case .contact(let thread):
                // Payments only supported for 1:1 chats
                return thread.contactAddress.aci
            case .groupV2:
                return nil
            }
        }()

        let direction: ArchivedPayment.Direction
        switch message {
        case message as TSIncomingMessage:
            direction = .incoming
        case message as TSOutgoingMessage:
            direction = .outgoing
        default:
            return .messageFailure([.restoreFrameError(
                .developerError(OWSAssertionError("Invalid message type passed in for paymentRestore")),
                chatItemId
            )])
        }
        guard
            let senderOrRecipientAci,
            let archivedPayment = ArchivedPayment.fromBackup(
                transaction,
                senderOrRecipientAci: senderOrRecipientAci,
                direction: direction,
                interactionUniqueId: message.uniqueId
            ) else {
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.unrecognizedPaymentTransaction),
                chatItemId
            )])
        }
        do {
            try archivedPaymentStore.insert(archivedPayment, tx: context.tx)
        } catch {
            return .messageFailure([
                .restoreFrameError(.databaseInsertionFailed(error), chatItemId)
            ])
        }
        return .success(())
    }

    private func restorePaymentNotification(
        _ paymentNotification: BackupProto_PaymentNotification,
        chatItemId: MessageBackup.ChatItemId,
        thread: MessageBackup.ChatThread,
        context: MessageBackup.ChatItemRestoringContext
    ) -> RestoreInteractionResult<MessageBackup.RestoredMessageContents> {
        let status: MessageBackup.RestoredMessageContents.Payment.Status
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

        return .success(.archivedPayment(MessageBackup.RestoredMessageContents.Payment(
            amount: paymentNotification.hasAmountMob ? paymentNotification.amountMob : nil,
            fee: paymentNotification.hasFeeMob ? paymentNotification.feeMob : nil,
            note: paymentNotification.hasNote ? paymentNotification.note : nil,
            status: status,
            payment: paymentTransaction
        )))
    }

    // MARK: -

    private func restoreRemoteDeleteTombstone(
        _ remoteDeleteTombstone: BackupProto_RemoteDeletedMessage,
        chatItemId: MessageBackup.ChatItemId,
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatItemRestoringContext
    ) -> RestoreInteractionResult<MessageBackup.RestoredMessageContents> {
        return .success(.remoteDeleteTombstone)
    }

    // MARK: -

    private func restoreStandardMessage(
        _ standardMessage: BackupProto_StandardMessage,
        chatItemId: MessageBackup.ChatItemId,
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatItemRestoringContext
    ) -> RestoreInteractionResult<MessageBackup.RestoredMessageContents> {
        var partialErrors = [RestoreFrameError]()

        let quotedMessage: TSQuotedMessage?
        let quotedMessageThumbnail: BackupProto_MessageAttachment?
        if standardMessage.hasQuote {
            guard
                let quoteResult = restoreQuote(
                    standardMessage.quote,
                    chatItemId: chatItemId,
                    thread: chatThread,
                    context: context
                ).unwrap(partialErrors: &partialErrors)
            else {
                return .messageFailure(partialErrors)
            }
            (quotedMessage, quotedMessageThumbnail) = quoteResult
        } else {
            quotedMessage = nil
            quotedMessageThumbnail = nil
        }

        let linkPreview: OWSLinkPreview?
        let linkPreviewAttachment: BackupProto_FilePointer?
        if let linkPreviewProto = standardMessage.linkPreview.first {
            guard
                let linkPreviewResult = restoreLinkPreview(
                    linkPreviewProto,
                    standardMessage: standardMessage,
                    chatItemId: chatItemId,
                    context: context
                ).unwrap(partialErrors: &partialErrors)
            else {
                return .messageFailure(partialErrors)
            }
            if let linkPreviewResult {
                (linkPreview, linkPreviewAttachment) = linkPreviewResult
            } else {
                linkPreview = nil
                linkPreviewAttachment = nil
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

        if oversizeTextAttachment != nil && standardMessage.text.body.isEmpty {
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.longTextStandardMessageMissingBody),
                chatItemId
            )])
        }

        if standardMessage.text.body.isEmpty && standardMessage.attachments.isEmpty {
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.emptyStandardMessage),
                chatItemId
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

        let messageBodyResult = restoreMessageBody(text, chatItemId: chatItemId)
        switch messageBodyResult {
        case .success(let body):
            let contents = MessageBackup.RestoredMessageContents.text(.init(
                body: body,
                quotedMessage: quotedMessage,
                linkPreview: linkPreview,
                isVoiceMessage: isVoiceMessage,
                reactions: standardMessage.reactions,
                oversizeTextAttachment: oversizeTextAttachment,
                bodyAttachments: standardMessage.attachments,
                quotedMessageThumbnail: quotedMessageThumbnail,
                linkPreviewImage: linkPreviewAttachment
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
                    oversizeTextAttachment: oversizeTextAttachment,
                    bodyAttachments: standardMessage.attachments,
                    quotedMessageThumbnail: quotedMessageThumbnail,
                    linkPreviewImage: linkPreviewAttachment
                )),
                partialErrors + messageBodyErrors
            )
        case .messageFailure(let messageBodyErrors):
            return .messageFailure(partialErrors + messageBodyErrors)
        }
    }

    private func restoreMessageBody(
        _ text: BackupProto_Text,
        chatItemId: MessageBackup.ChatItemId
    ) -> RestoreInteractionResult<MessageBody?> {
        guard text.body.isEmpty.negated else {
            return .success(nil)
        }
        return restoreMessageBody(
            text: text.body,
            bodyRangeProtos: text.bodyRanges,
            chatItemId: chatItemId
        )
    }

    private func restoreMessageBody(
        text: String,
        bodyRangeProtos: [BackupProto_BodyRange],
        chatItemId: MessageBackup.ChatItemId
    ) -> RestoreInteractionResult<MessageBody?> {
        var partialErrors = [RestoreFrameError]()
        var bodyMentions = [NSRange: Aci]()
        var bodyStyles = [NSRangedValue<MessageBodyRanges.SingleStyle>]()
        for bodyRange in bodyRangeProtos {
            guard bodyRange.hasStart, bodyRange.hasLength else {
                continue
            }
            let bodyRangeStart = bodyRange.start
            let bodyRangeLength = bodyRange.length

            let range = NSRange(location: Int(bodyRangeStart), length: Int(bodyRangeLength))
            switch bodyRange.associatedValue {
            case .mentionAci(let aciData):
                guard let mentionAci = try? Aci.parseFrom(serviceIdBinary: aciData) else {
                    partialErrors.append(.restoreFrameError(
                        .invalidProtoData(.invalidAci(protoClass: BackupProto_BodyRange.self)),
                        chatItemId
                    ))
                    continue
                }
                bodyMentions[range] = mentionAci
            case .style(let protoBodyRangeStyle):
                let swiftStyle: MessageBodyRanges.SingleStyle
                switch protoBodyRangeStyle {
                case .none, .UNRECOGNIZED:
                    partialErrors.append(.restoreFrameError(
                        .invalidProtoData(.unrecognizedBodyRangeStyle),
                        chatItemId
                    ))
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
                    chatItemId
                ))
                continue
            }
        }
        let bodyRanges = MessageBodyRanges(mentions: bodyMentions, styles: bodyStyles)
        let body = MessageBody(text: text, ranges: bodyRanges)
        if partialErrors.isEmpty {
            return .success(body)
        } else {
            // We still get text, albeit without any mentions or styles, if
            // we have these failures. So count as a partial restore, not
            // complete failure.
            return .partialRestore(body, partialErrors)
        }
    }

    private func restoreQuote(
        _ quote: BackupProto_Quote,
        chatItemId: MessageBackup.ChatItemId,
        thread: MessageBackup.ChatThread,
        context: MessageBackup.ChatItemRestoringContext
    ) -> RestoreInteractionResult<(TSQuotedMessage, BackupProto_MessageAttachment?)> {
        let authorAddress: MessageBackup.InteropAddress
        switch context.recipientContext[quote.authorRecipientId] {
        case .none:
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.recipientIdNotFound(quote.authorRecipientId)),
                chatItemId
            )])
        case .localAddress:
            authorAddress = context.recipientContext.localIdentifiers.aciAddress
        case .group, .distributionList, .releaseNotesChannel, .callLink:
            // Groups and distritibution lists cannot be an authors of a message!
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.incomingMessageNotFromAciOrE164),
                chatItemId
            )])
        case .contact(let contactAddress):
            guard contactAddress.aci != nil || contactAddress.e164 != nil else {
                return .messageFailure([.restoreFrameError(
                    .invalidProtoData(.incomingMessageNotFromAciOrE164),
                    chatItemId
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
            guard
                let bodyResult = restoreMessageBody(
                    text: quote.text.body,
                    bodyRangeProtos: quote.text.bodyRanges,
                    chatItemId: chatItemId
                ).unwrap(partialErrors: &partialErrors)
            else {
                return .messageFailure(partialErrors)
            }

            quoteBody = bodyResult
        } else {
            quoteBody = nil
        }

        let isGiftBadge: Bool
        let isTargetMessageViewOnce: Bool
        switch quote.type {
        case .UNRECOGNIZED, .unknown, .normal:
            isGiftBadge = false
            isTargetMessageViewOnce = false
        case .viewOnce:
            isGiftBadge = false
            isTargetMessageViewOnce = true
        case .giftBadge:
            isGiftBadge = true
            isTargetMessageViewOnce = false
        }

        let quotedAttachmentInfo: OWSAttachmentInfo?
        let quotedAttachmentThumbnail: BackupProto_MessageAttachment?
        if let quotedAttachmentProto = quote.attachments.first {
            let mimeType = quotedAttachmentProto.contentType.nilIfEmpty
            ?? MimeType.applicationOctetStream.rawValue
            let sourceFilename = quotedAttachmentProto.fileName.nilIfEmpty

            if quotedAttachmentProto.hasThumbnail {
                quotedAttachmentInfo = .forThumbnailReference(
                    withOriginalAttachmentMimeType: mimeType,
                    originalAttachmentSourceFilename: sourceFilename
                )
                quotedAttachmentThumbnail = quotedAttachmentProto.thumbnail
            } else {
                quotedAttachmentInfo = .stub(
                    withOriginalAttachmentMimeType: mimeType,
                    originalAttachmentSourceFilename: sourceFilename
                )
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
                chatItemId
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
            isTargetMessageViewOnce: isTargetMessageViewOnce
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
        chatItemId: MessageBackup.ChatItemId,
        context: MessageBackup.RestoringContext
    ) -> RestoreInteractionResult<(OWSLinkPreview, BackupProto_FilePointer?)?> {
        guard let url = linkPreviewProto.url.nilIfEmpty else {
            return .partialRestore(nil, [.restoreFrameError(
                .invalidProtoData(.linkPreviewEmptyUrl),
                chatItemId
            )])
        }
        guard standardMessage.text.body.contains(url) else {
            return .partialRestore(nil, [.restoreFrameError(
                .invalidProtoData(.linkPreviewUrlNotInBody),
                chatItemId
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
            date: date
        )

        if linkPreviewProto.hasImage {
            let linkPreview = OWSLinkPreview(
                metadata: metadata
            )
            return .success((linkPreview, linkPreviewProto.image))
        } else {
            let linkPreview = OWSLinkPreview(
                metadata: metadata
            )
            return .success((linkPreview, nil))
        }
    }

    // MARK: -

    private func restoreContactMessage(
        _ contactMessage: BackupProto_ContactMessage,
        chatItemId: MessageBackup.ChatItemId,
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatItemRestoringContext
    ) -> RestoreInteractionResult<MessageBackup.RestoredMessageContents> {
        var partialErrors = [RestoreFrameError]()

        guard
            contactMessage.contact.count == 1,
            let contactAttachment = contactMessage.contact.first
        else {
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.contactMessageNonSingularContactAttachmentCount),
                chatItemId
            )])
        }

        let contactResult = contactAttachmentArchiver.restoreContact(
            contactAttachment,
            chatItemId: chatItemId
        )
        guard let contact = contactResult.unwrap(partialErrors: &partialErrors) else {
            return .messageFailure(partialErrors)
        }

        let avatar: BackupProto_FilePointer?
        if contactAttachment.hasAvatar {
            avatar = contactAttachment.avatar
        } else {
            avatar = nil
        }

        let contents = MessageBackup.RestoredMessageContents.contactShare(.init(
            contact: contact,
            avatarAttachment: avatar,
            reactions: contactMessage.reactions
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
        chatItemId: MessageBackup.ChatItemId,
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatItemRestoringContext
    ) -> RestoreInteractionResult<MessageBackup.RestoredMessageContents> {
        let stickerProto = stickerMessage.sticker
        let messageSticker = MessageSticker(
            info: .init(
                packId: stickerProto.packID,
                packKey: stickerProto.packKey,
                stickerId: stickerProto.stickerID
            ),
            emoji: stickerProto.emoji.nilIfEmpty
        )

        return .success(.stickerMessage(.init(
            sticker: messageSticker,
            attachment: stickerProto.data,
            reactions: stickerMessage.reactions
        )))
    }

    // MARK: -

    private func restoreGiftBadge(
        _ giftBadgeProto: BackupProto_GiftBadge,
        chatItemId: MessageBackup.ChatItemId,
        context: MessageBackup.ChatItemRestoringContext
    ) -> RestoreInteractionResult<MessageBackup.RestoredMessageContents> {
        let giftBadge: OWSGiftBadge
        switch giftBadgeProto.state {
        case .unopened:
            giftBadge = .restoreFromBackup(
                receiptCredentialPresentation: giftBadgeProto.receiptCredentialPresentation,
                redemptionState: .pending
            )
        case .opened:
            giftBadge = .restoreFromBackup(
                receiptCredentialPresentation: giftBadgeProto.receiptCredentialPresentation,
                redemptionState: .opened
            )
        case .redeemed:
            giftBadge = .restoreFromBackup(
                receiptCredentialPresentation: giftBadgeProto.receiptCredentialPresentation,
                redemptionState: .redeemed
            )
        case .failed:
            /// Passing `receiptCredentialPresentation: nil` will make this a
            /// non-functional gift badge in practice. At the time of writing
            /// iOS doesn't have a "failed" gift badge state, so we'll use this
            /// instead.
            giftBadge = .restoreFromBackup(
                receiptCredentialPresentation: nil,
                redemptionState: .pending
            )
        case .UNRECOGNIZED(_):
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.unrecognizedGiftBadgeState),
                chatItemId
            )])
        }

        return .success(.giftBadge(MessageBackup.RestoredMessageContents.GiftBadge(
            giftBadge: giftBadge
        )))
    }

    // MARK: -

    private func restoreViewOnceMessage(
        _ viewOnceMessage: BackupProto_ViewOnceMessage,
        chatItemId: MessageBackup.ChatItemId,
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatItemRestoringContext
    ) -> RestoreInteractionResult<MessageBackup.RestoredMessageContents> {
        let state: MessageBackup.RestoredMessageContents.ViewOnceMessage.State
        if viewOnceMessage.hasAttachment {
            state = .unviewed(viewOnceMessage.attachment)
        } else {
            state = .complete
        }
        return .success(.viewOnceMessage(.init(
            state: state,
            reactions: viewOnceMessage.reactions
        )))
    }
}

// MARK: -

private extension ArchivedPayment {
    static func fromBackup(
        _ backup: MessageBackup.RestoredMessageContents.Payment,
        senderOrRecipientAci: Aci,
        direction: Direction,
        interactionUniqueId: String?
    ) -> ArchivedPayment? {
        var archivedPayment: ArchivedPayment?
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
                interactionUniqueId: interactionUniqueId
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
                interactionUniqueId: interactionUniqueId
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
