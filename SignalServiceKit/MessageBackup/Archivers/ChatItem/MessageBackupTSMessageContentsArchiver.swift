//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension MessageBackup {

    // TODO: Flesh this out. Not sure how exactly we will map
    // from the "types" in the proto to the "types" in our database.

    /// Represents message content "types" as they are represented in iOS code, after
    /// being mapped from their representation in the backup proto. For example, normal
    /// text messages and quoted replies are a single "type" in the proto, but have separate
    /// class structures in the iOS code.
    /// This object will be passed back into the ``MessageBackupTSMessageContentsArchiver`` class
    /// after the TSMessage has been created, so that downstream objects that require the TSMessage exist
    /// can be created afterwards. So anything needed for that (but not needed to create the TSMessage)
    /// can be made a fileprivate variable in these structs.
    internal enum RestoredMessageContents {
        struct Text {

            // Internal - these fields are exposed for TSMessage construction.

            internal let body: MessageBody
            internal let quotedMessage: TSQuotedMessage?

            // Private - these fields are used by ``restoreDownstreamObjects`` to
            //     construct objects that are parsed from the backup proto but require
            //     the TSMessage to exist first before they can be created/inserted.

            fileprivate let reactions: [BackupProto.Reaction]
        }

        struct Payment {
            enum Status {
                case success(BackupProto.PaymentNotification.TransactionDetails.Transaction.Status)
                case failure(BackupProto.PaymentNotification.TransactionDetails.FailedTransaction.FailureReason)
            }

            internal let amount: String?
            internal let fee: String?
            internal let note: String?

            fileprivate let status: Status

            fileprivate let payment: BackupProto.PaymentNotification.TransactionDetails.Transaction?
        }

        case text(Text)
        case archivedPayment(Payment)
    }
}

extension MessageBackup.RestoredMessageContents {

    var body: MessageBody? {
        switch self {
        case .text(let text):
            return text.body
        case .archivedPayment:
            return nil
        }
    }

    var quotedMessage: TSQuotedMessage? {
        switch self {
        case .text(let text):
            return text.quotedMessage
        case .archivedPayment:
            return nil
        }
    }
}

internal class MessageBackupTSMessageContentsArchiver: MessageBackupProtoArchiver {

    typealias ChatItemType = MessageBackup.InteractionArchiveDetails.ChatItemType

    typealias ArchiveInteractionResult = MessageBackup.ArchiveInteractionResult
    typealias RestoreInteractionResult = MessageBackup.RestoreInteractionResult

    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<MessageBackup.InteractionUniqueId>
    private typealias RestoreFrameError = MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>

    private let interactionStore: InteractionStore
    private let archivedPaymentStore: ArchivedPaymentStore
    private let reactionArchiver: MessageBackupReactionArchiver

    init(
        interactionStore: InteractionStore,
        archivedPaymentStore: ArchivedPaymentStore,
        reactionArchiver: MessageBackupReactionArchiver
    ) {
        self.interactionStore = interactionStore
        self.archivedPaymentStore = archivedPaymentStore
        self.reactionArchiver = reactionArchiver
    }

    // MARK: - Archiving

    func archiveMessageContents(
        _ message: TSMessage,
        context: MessageBackup.RecipientArchivingContext,
        tx: DBReadTransaction
    ) -> ArchiveInteractionResult<ChatItemType> {
        if let paymentMessage = message as? OWSPaymentMessage {
            return archivePaymentMessageContents(
                paymentMessage,
                uniqueInteractionId: message.uniqueInteractionId,
                context: context,
                tx: tx
            )
        } else if let archivedPayment = message as? OWSArchivedPaymentMessage {
            return archivePaymentArchiveContents(
                archivedPayment,
                uniqueInteractionId: message.uniqueInteractionId,
                context: context,
                tx: tx
            )
        } else {
            return archiveStandardMessageContents(message, context: context, tx: tx)
        }
    }

    private func archiveStandardMessageContents(
        _ message: TSMessage,
        context: MessageBackup.RecipientArchivingContext,
        tx: DBReadTransaction
    ) -> ArchiveInteractionResult<ChatItemType> {
        guard let body = message.body else {
            // TODO: handle non simple text messages.
            return .notYetImplemented
        }

        var standardMessage = BackupProto.StandardMessage()
        var partialErrors = [ArchiveFrameError]()

        let text: BackupProto.Text
        let textResult = archiveText(
            .init(text: body, ranges: message.bodyRanges ?? .empty),
            interactionUniqueId: message.uniqueInteractionId
        )
        switch textResult.bubbleUp(ChatItemType.self, partialErrors: &partialErrors) {
        case .continue(let value):
            text = value
        case .bubbleUpError(let errorResult):
            return errorResult
        }
        standardMessage.text = text

        let quote: BackupProto.Quote?
        if let quotedMessage = message.quotedMessage {
            let quoteResult = archiveQuote(
                quotedMessage,
                interactionUniqueId: message.uniqueInteractionId,
                context: context
            )
            switch quoteResult.bubbleUp(ChatItemType.self, partialErrors: &partialErrors) {
            case .continue(let value):
                quote = value
            case .bubbleUpError(let errorResult):
                return errorResult
            }
        } else {
            quote = nil
        }
        standardMessage.quote = quote

        let reactions: [BackupProto.Reaction]
        let reactionsResult = reactionArchiver.archiveReactions(
            message,
            context: context,
            tx: tx
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

    private func archivePaymentArchiveContents(
        _ archivedPaymentMessage: OWSArchivedPaymentMessage,
        uniqueInteractionId: MessageBackup.InteractionUniqueId,
        context: MessageBackup.RecipientArchivingContext,
        tx: DBReadTransaction
    ) -> MessageBackup.ArchiveInteractionResult<ChatItemType> {
        guard let historyItem = archivedPaymentStore.fetch(for: archivedPaymentMessage, tx: tx) else {
            return .messageFailure([.archiveFrameError(.missingPaymentInformation, uniqueInteractionId)])
        }

        var paymentNotificationProto = BackupProto.PaymentNotification()
        paymentNotificationProto.amountMob = archivedPaymentMessage.archivedPaymentInfo.amount
        paymentNotificationProto.feeMob = archivedPaymentMessage.archivedPaymentInfo.fee
        paymentNotificationProto.note = archivedPaymentMessage.archivedPaymentInfo.note
        paymentNotificationProto.transactionDetails = historyItem.toTransactionDetailsProto()

        return .success(.paymentNotification(paymentNotificationProto))
    }

    private func archivePaymentMessageContents(
        _ message: OWSPaymentMessage,
        uniqueInteractionId: MessageBackup.InteractionUniqueId,
        context: MessageBackup.RecipientArchivingContext,
        tx: DBReadTransaction
    ) -> MessageBackup.ArchiveInteractionResult<ChatItemType> {
        guard
            let paymentNotification = message.paymentNotification,
            let model = PaymentFinder.paymentModels(
                forMcReceiptData: paymentNotification.mcReceiptData,
                transaction: SDSDB.shimOnlyBridge(tx)
            ).first
        else {
            return .messageFailure([.archiveFrameError(.missingPaymentInformation, uniqueInteractionId)])
        }

        var paymentNotificationProto = BackupProto.PaymentNotification()

        if let amount = model.paymentAmount {
            paymentNotificationProto.amountMob = PaymentsFormat.format(
                picoMob: amount.picoMob,
                isShortForm: true
            )
        }
        if let fee = model.mobileCoin?.feeAmount {
            paymentNotificationProto.feeMob = PaymentsFormat.format(
                picoMob: fee.picoMob,
                isShortForm: true
            )
        }
        paymentNotificationProto.note = paymentNotification.memoMessage
        paymentNotificationProto.transactionDetails = model.asArchivedPayment().toTransactionDetailsProto()

        return .success(.paymentNotification(paymentNotificationProto))
    }

    private func archiveText(
        _ messageBody: MessageBody,
        interactionUniqueId: MessageBackup.InteractionUniqueId
    ) -> ArchiveInteractionResult<BackupProto.Text> {
        var text = BackupProto.Text(body: messageBody.text)

        for bodyRangeParam in messageBody.ranges.toProtoBodyRanges() {
            var bodyRange = BackupProto.BodyRange()
            bodyRange.start = bodyRangeParam.start
            bodyRange.length = bodyRangeParam.length

            if let mentionAci = Aci.parseFrom(aciString: bodyRangeParam.mentionAci) {
                bodyRange.associatedValue = .mentionAci(
                    mentionAci.serviceIdBinary.asData
                )
            } else if let style = bodyRangeParam.style {
                let backupProtoStyle: BackupProto.BodyRange.Style = {
                    switch style {
                    case .none: return .NONE
                    case .bold: return .BOLD
                    case .italic: return .ITALIC
                    case .spoiler: return .SPOILER
                    case .strikethrough: return .STRIKETHROUGH
                    case .monospace: return .MONOSPACE
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
        context: MessageBackup.RecipientArchivingContext
    ) -> ArchiveInteractionResult<BackupProto.Quote> {
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

        var quote = BackupProto.Quote(
            authorId: authorId.value,
            type: quotedMessage.isGiftBadge ? .GIFTBADGE : .NORMAL
        )
        quote.targetSentTimestamp = quotedMessage.timestampValue?.uint64Value

        if let body = quotedMessage.body {
            let textResult = archiveText(
                .init(text: body, ranges: quotedMessage.bodyRanges ?? .empty),
                interactionUniqueId: interactionUniqueId
            )
            let text: BackupProto.Text
            switch textResult.bubbleUp(BackupProto.Quote.self, partialErrors: &partialErrors) {
            case .continue(let value):
                text = value
            case .bubbleUpError(let errorResult):
                return errorResult
            }
            quote.text = text.body
            quote.bodyRanges = text.bodyRanges
        }

        // TODO: set attachments on the quote

        return .success(quote)
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
        context: MessageBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) -> RestoreInteractionResult<MessageBackup.RestoredMessageContents> {
        switch chatItemType {
        case .standardMessage(let standardMessage):
            return restoreStandardMessage(
                standardMessage,
                chatItemId: chatItemId,
                chatThread: chatThread,
                context: context,
                tx: tx
            )
        case .updateMessage:
            return .messageFailure([.restoreFrameError(
                .developerError(OWSAssertionError("Chat update has no contents to restore!")),
                chatItemId
            )])
        case .paymentNotification(let paymentNotification):
            return restorePaymentNotification(
                paymentNotification,
                chatItemId: chatItemId,
                thread: chatThread,
                context: context,
                tx: tx
            )
        case .contactMessage, .stickerMessage, .remoteDeletedMessage, .giftBadge:
            // Other types not supported yet.
            return .messageFailure([.restoreFrameError(.unimplemented, chatItemId)])
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
        context: MessageBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) -> RestoreInteractionResult<Void> {
        let restoreInteractionResult: RestoreInteractionResult<Void>
        switch restoredContents {
        case .text(let text):
            restoreInteractionResult = reactionArchiver.restoreReactions(
                text.reactions,
                chatItemId: chatItemId,
                message: message,
                context: context.recipientContext,
                tx: tx
            )
        case .archivedPayment(let archivedPayment):
            restoreInteractionResult = restoreArchivedPaymentContents(
                archivedPayment,
                chatItemId: chatItemId,
                thread: thread,
                message: message,
                tx: tx
            )
        }

        return restoreInteractionResult
    }

    // MARK: Helpers

    private func restoreArchivedPaymentContents(
        _ transaction: MessageBackup.RestoredMessageContents.Payment,
        chatItemId: MessageBackup.ChatItemId,
        thread: MessageBackup.ChatThread,
        message: TSMessage,
        tx: DBWriteTransaction
    ) -> MessageBackup.RestoreInteractionResult<Void> {
        let senderOrRecipientAci: Aci? = {
            switch thread {
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
        archivedPaymentStore.insert(archivedPayment, tx: tx)
        return .success(())
    }

    private func restorePaymentNotification(
        _ paymentNotification: BackupProto.PaymentNotification,
        chatItemId: MessageBackup.ChatItemId,
        thread: MessageBackup.ChatThread,
        context: MessageBackup.ChatRestoringContext,
        tx: DBReadTransaction
    ) -> RestoreInteractionResult<MessageBackup.RestoredMessageContents> {
        let status: MessageBackup.RestoredMessageContents.Payment.Status
        let paymentTransaction: BackupProto.PaymentNotification.TransactionDetails.Transaction?
        switch paymentNotification.transactionDetails?.payment {
        case .failedTransaction(let failedTransaction):
            status = .failure(failedTransaction.reason)
            paymentTransaction = nil
        case .transaction(let payment):
            status = .success(payment.status)
            paymentTransaction = payment
        case .none:
            // Default to 'success' if there is no included information
            status = .success(.SUCCESSFUL)
            paymentTransaction = nil
        }

        return .success(.archivedPayment(.init(
            amount: paymentNotification.amountMob,
            fee: paymentNotification.feeMob,
            note: paymentNotification.note,
            status: status,
            payment: paymentTransaction
        )))
    }

    private func restoreStandardMessage(
        _ standardMessage: BackupProto.StandardMessage,
        chatItemId: MessageBackup.ChatItemId,
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatRestoringContext,
        tx: DBReadTransaction
    ) -> RestoreInteractionResult<MessageBackup.RestoredMessageContents> {
        var partialErrors = [RestoreFrameError]()

        let quotedMessage: TSQuotedMessage?
        if let quoteProto = standardMessage.quote {
            guard
                let quoteResult = restoreQuote(
                    quoteProto,
                    chatItemId: chatItemId,
                    thread: chatThread,
                    context: context,
                    tx: tx
                ).unwrap(partialErrors: &partialErrors)
            else {
                return .messageFailure(partialErrors)
            }
            quotedMessage = quoteResult
        } else {
            quotedMessage = nil
        }

        guard let text = standardMessage.text else {
            // Non-text not supported yet.
            return .messageFailure([.restoreFrameError(.unimplemented, chatItemId)])
        }

        let messageBodyResult = restoreMessageBody(text, chatItemId: chatItemId)
        switch messageBodyResult {
        case .success(let body):
            return .success(.text(.init(
                body: body,
                quotedMessage: quotedMessage,
                reactions: standardMessage.reactions
            )))
        case .partialRestore(let body, let partialErrors):
            return .partialRestore(
                .text(.init(
                    body: body,
                    quotedMessage: quotedMessage,
                    reactions: standardMessage.reactions
                )),
                partialErrors
            )
        case .messageFailure(let errors):
            return .messageFailure(errors)
        }
    }

    func restoreMessageBody(
        _ text: BackupProto.Text,
        chatItemId: MessageBackup.ChatItemId
    ) -> RestoreInteractionResult<MessageBody> {
        return restoreMessageBody(
            text: text.body,
            bodyRangeProtos: text.bodyRanges,
            chatItemId: chatItemId
        )
    }

    private func restoreMessageBody(
        text: String,
        bodyRangeProtos: [BackupProto.BodyRange],
        chatItemId: MessageBackup.ChatItemId
    ) -> RestoreInteractionResult<MessageBody> {
        var partialErrors = [RestoreFrameError]()
        var bodyMentions = [NSRange: Aci]()
        var bodyStyles = [NSRangedValue<MessageBodyRanges.SingleStyle>]()
        for bodyRange in bodyRangeProtos {
            guard let bodyRangeStart = bodyRange.start, let bodyRangeLength = bodyRange.length else {
                continue
            }

            let range = NSRange(location: Int(bodyRangeStart), length: Int(bodyRangeLength))
            switch bodyRange.associatedValue {
            case .mentionAci(let aciData):
                guard let mentionAci = try? Aci.parseFrom(serviceIdBinary: aciData) else {
                    partialErrors.append(.restoreFrameError(
                        .invalidProtoData(.invalidAci(protoClass: BackupProto.BodyRange.self)),
                        chatItemId
                    ))
                    continue
                }
                bodyMentions[range] = mentionAci
            case .style(let protoBodyRangeStyle):
                let swiftStyle: MessageBodyRanges.SingleStyle
                switch protoBodyRangeStyle {
                case .NONE:
                    partialErrors.append(.restoreFrameError(
                        .invalidProtoData(.unrecognizedBodyRangeStyle),
                        chatItemId
                    ))
                    continue
                case .BOLD:
                    swiftStyle = .bold
                case .ITALIC:
                    swiftStyle = .italic
                case .MONOSPACE:
                    swiftStyle = .monospace
                case .SPOILER:
                    swiftStyle = .spoiler
                case .STRIKETHROUGH:
                    swiftStyle = .strikethrough
                }
                bodyStyles.append(.init(swiftStyle, range: range))
            case nil:
                partialErrors.append(.restoreFrameError(
                    .invalidProtoData(.invalidAci(protoClass: BackupProto.BodyRange.self)),
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

    func restoreQuote(
        _ quote: BackupProto.Quote,
        chatItemId: MessageBackup.ChatItemId,
        thread: MessageBackup.ChatThread,
        context: MessageBackup.ChatRestoringContext,
        tx: DBReadTransaction
    ) -> RestoreInteractionResult<TSQuotedMessage> {
        let authorAddress: MessageBackup.InteropAddress
        switch context.recipientContext[quote.authorRecipientId] {
        case .none:
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.recipientIdNotFound(quote.authorRecipientId)),
                chatItemId
            )])
        case .localAddress:
            authorAddress = context.recipientContext.localIdentifiers.aciAddress
        case .group, .distributionList, .releaseNotesChannel:
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
        if
            let targetSentTimestamp = quote.targetSentTimestamp,
            SDS.fitsInInt64(targetSentTimestamp)
        {
            targetMessageTimestamp = NSNumber(value: targetSentTimestamp)
        } else {
            targetMessageTimestamp = nil
        }

        // Try and find the targeted message, and use that as the source.
        // If this turns out to be a big perf hit, maybe we skip this and just
        // always use the contents of the proto?
        let targetMessage = findTargetMessageForQuote(quote: quote, thread: thread, tx: tx)

        let quoteBody: MessageBody?
        let bodySource: TSQuotedMessageContentSource
        if let targetMessage {
            bodySource = .local

            if let text = targetMessage.body {
                quoteBody = .init(text: text, ranges: targetMessage.bodyRanges ?? .empty)
            } else {
                quoteBody = nil
            }
        } else {
            bodySource = .remote

            if let text = quote.text {
                guard let bodyResult = restoreMessageBody(
                    text: text,
                    bodyRangeProtos: quote.bodyRanges,
                    chatItemId: chatItemId
                )
                    .unwrap(partialErrors: &partialErrors)
                else {
                    return .messageFailure(partialErrors)
                }
                quoteBody = bodyResult
            } else {
                quoteBody = nil
            }
        }

        let isGiftBadge: Bool
        switch quote.type {
        case .UNKNOWN, .NORMAL:
            isGiftBadge = false
        case .GIFTBADGE:
            isGiftBadge = true
        }

        guard let quoteBody else {
            // Non-text not supported yet.
            return .messageFailure([.restoreFrameError(.unimplemented, chatItemId)])
        }

        // TODO: support attachments

        let quotedMessage = TSQuotedMessage(
            targetMessageTimestamp: targetMessageTimestamp,
            authorAddress: authorAddress,
            body: quoteBody.text,
            bodyRanges: quoteBody.ranges,
            bodySource: bodySource,
            isGiftBadge: isGiftBadge
        )

        if partialErrors.isEmpty {
            return .success(quotedMessage)
        } else {
            return .partialRestore(quotedMessage, partialErrors)
        }
    }

    private func findTargetMessageForQuote(
        quote: BackupProto.Quote,
        thread: MessageBackup.ChatThread,
        tx: DBReadTransaction
    ) -> TSMessage? {
        guard let targetSentTimestamp = quote.targetSentTimestamp else {
            return nil
        }
        let messageCandidates: [TSInteraction] = (try? interactionStore
            .interactions(
                withTimestamp: targetSentTimestamp,
                tx: tx
            )
        ) ?? []

        let filteredMessages = messageCandidates
            .lazy
            .compactMap { $0 as? TSMessage }
            .filter { $0.uniqueThreadId == thread.uniqueId.value }

        if filteredMessages.count > 1 {
            // We found more than one matching message. We don't know which
            // to use, so lets just use whats in the quote proto.
            return nil
        } else {
            return filteredMessages.first
        }
    }
}

fileprivate extension ArchivedPayment {
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
            let transactionIdentifier = payment?.mobileCoinIdentification?.nilIfEmpty.map {
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
                transaction: payment?.transaction,
                receipt: payment?.receipt,
                senderOrRecipientAci: senderOrRecipientAci,
                interactionUniqueId: interactionUniqueId
            )
        }
        return archivedPayment
    }
}

extension BackupProto.PaymentNotification.TransactionDetails.FailedTransaction.FailureReason {
    func asFailureType() -> ArchivedPayment.FailureReason {
        switch self {
        case .GENERIC: return .genericFailure
        case .NETWORK: return .networkFailure
        case .INSUFFICIENT_FUNDS: return .insufficientFundsFailure
        }
    }
}

extension BackupProto.PaymentNotification.TransactionDetails.Transaction.Status {
    func asStatusType() -> ArchivedPayment.Status {
        switch self {
        case .INITIAL: return .initial
        case .SUBMITTED: return .submitted
        case .SUCCESSFUL: return .successful
        }
    }
}

extension BackupProto.PaymentNotification.TransactionDetails.MobileCoinTxoIdentification {
    var nilIfEmpty: Self? {
        (publicKey.isEmpty && keyImages.isEmpty) ? nil : self
    }
}
