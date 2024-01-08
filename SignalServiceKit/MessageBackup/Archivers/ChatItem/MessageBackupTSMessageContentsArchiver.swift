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

            fileprivate let reactions: [BackupProtoReaction]
        }

        case text(Text)
    }
}

extension MessageBackup.RestoredMessageContents {

    var body: MessageBody? {
        switch self {
        case .text(let text):
            return text.body
        }
    }

    var quotedMessage: TSQuotedMessage? {
        switch self {
        case .text(let text):
            return text.quotedMessage
        }
    }
}

internal class MessageBackupTSMessageContentsArchiver: MessageBackupProtoArchiver {

    typealias ChatItemMessageType = MessageBackup.ChatItemMessageType

    private let interactionStore: InteractionStore
    private let reactionArchiver: MessageBackupReactionArchiver

    init(
        interactionStore: InteractionStore,
        reactionArchiver: MessageBackupReactionArchiver
    ) {
        self.interactionStore = interactionStore
        self.reactionArchiver = reactionArchiver
    }

    // MARK: - Archiving

    func archiveMessageContents(
        _ message: TSMessage,
        context: MessageBackup.RecipientArchivingContext,
        tx: DBReadTransaction
    ) -> MessageBackup.ArchiveInteractionResult<ChatItemMessageType> {
        guard let body = message.body else {
            // TODO: handle non simple text messages.
            return .notYetImplemented
        }

        var partialErrors = [MessageBackup.ArchiveInteractionResult<ChatItemMessageType>.Error]()

        let standardMessageBuilder = BackupProtoStandardMessage.builder()

        let textResult = archiveText(
            .init(text: body, ranges: message.bodyRanges ?? .empty),
            chatItemId: message.chatItemId
        )
        let text: BackupProtoText
        switch textResult.bubbleUp(ChatItemMessageType.self, partialErrors: &partialErrors) {
        case .continue(let value):
            text = value
        case .bubbleUpError(let errorResult):
            return errorResult
        }
        standardMessageBuilder.setText(text)

        let quote: BackupProtoQuote?
        if let quotedMessage = message.quotedMessage {
            let quoteResult = archiveQuote(
                quotedMessage,
                chatItemId: message.chatItemId,
                context: context
            )
            switch quoteResult.bubbleUp(ChatItemMessageType.self, partialErrors: &partialErrors) {
            case .continue(let value):
                quote = value
            case .bubbleUpError(let errorResult):
                return errorResult
            }
        } else {
            quote = nil
        }
        if let quote {
            standardMessageBuilder.setQuote(quote)
        }

        let reactionsResult = reactionArchiver.archiveReactions(
            message,
            context: context,
            tx: tx
        )

        let reactions: [BackupProtoReaction]
        switch reactionsResult.bubbleUp(ChatItemMessageType.self, partialErrors: &partialErrors) {
        case .continue(let values):
            reactions = values
        case .bubbleUpError(let errorResult):
            return errorResult
        }
        standardMessageBuilder.setReactions(reactions)

        let standardMessageProto: BackupProtoStandardMessage
        do {
            standardMessageProto = try standardMessageBuilder.build()
        } catch let error {
            return .messageFailure([.init(objectId: message.chatItemId, error: .protoSerializationError(error))])
        }

        if partialErrors.isEmpty {
            return .success(.standard(standardMessageProto))
        } else {
            return .partialFailure(.standard(standardMessageProto), partialErrors)
        }
    }

    private func archiveText(
        _ messageBody: MessageBody,
        chatItemId: MessageBackup.ChatItemId
    ) -> MessageBackup.ArchiveInteractionResult<BackupProtoText> {
        let textBuilder = BackupProtoText.builder(body: messageBody.text)

        var partialErrors = [MessageBackup.ArchiveInteractionResult<ChatItemMessageType>.Error]()

        for bodyRange in messageBody.ranges.toProtoBodyRanges() {
            let bodyRangeProtoBuilder = BackupProtoBodyRange.builder()
            bodyRangeProtoBuilder.setStart(bodyRange.start)
            bodyRangeProtoBuilder.setLength(bodyRange.length)
            if
                let rawMentionAci = bodyRange.mentionAci,
                let mentionUuid = UUID(uuidString: rawMentionAci)
            {
                bodyRangeProtoBuilder.setMentionAci(Aci(fromUUID: mentionUuid).serviceIdBinary.asData)
            } else if let style = bodyRange.style {
                switch style {
                case .none:
                    bodyRangeProtoBuilder.setStyle(.none)
                case .bold:
                    bodyRangeProtoBuilder.setStyle(.bold)
                case .italic:
                    bodyRangeProtoBuilder.setStyle(.italic)
                case .spoiler:
                    bodyRangeProtoBuilder.setStyle(.spoiler)
                case .strikethrough:
                    bodyRangeProtoBuilder.setStyle(.strikethrough)
                case .monospace:
                    bodyRangeProtoBuilder.setStyle(.monospace)
                }
            }
            do {
                let bodyRangeProto = try bodyRangeProtoBuilder.build()
                textBuilder.addBodyRanges(bodyRangeProto)
            } catch let error {
                // TODO: should these failures fail the whole message?
                // For now, just ignore the one body range and keep going.
                partialErrors.append(.init(objectId: chatItemId, error: .protoSerializationError(error)))
            }
        }
        do {
            let textProto = try textBuilder.build()
            if partialErrors.isEmpty {
                return .success(textProto)
            } else {
                return .partialFailure(textProto, partialErrors)
            }
        } catch let error {
            // Count this as a complete and total failure of the message.
            return .messageFailure([.init(objectId: chatItemId, error: .protoSerializationError(error))])
        }
    }

    private func archiveQuote(
        _ quotedMessage: TSQuotedMessage,
        chatItemId: MessageBackup.ChatItemId,
        context: MessageBackup.RecipientArchivingContext
    ) -> MessageBackup.ArchiveInteractionResult<BackupProtoQuote> {
        var partialErrors = [MessageBackup.ArchiveInteractionResult<ChatItemMessageType>.Error]()

        guard let authorAddress = quotedMessage.authorAddress.asSingleServiceIdBackupAddress() else {
            // Fail the whole message if we fail archiving a quote.
            return .messageFailure([.init(objectId: chatItemId, error: .invalidMessageAddress)])
        }
        guard let authorId = context[.contact(authorAddress)] else {
            // Fail the whole message if we fail archiving a quote.
            return .messageFailure([.init(
                objectId: chatItemId,
                error: .referencedIdMissing(.recipient(.contact(authorAddress)))
            )])
        }

        let quoteBuilder = BackupProtoQuote.builder(authorID: authorId.value)
        if let targetSentTimestamp = quotedMessage.timestampValue?.uint64Value {
            quoteBuilder.setTargetSentTimestamp(targetSentTimestamp)
        }
        if let body = quotedMessage.body {
            let textResult = archiveText(
                .init(text: body, ranges: quotedMessage.bodyRanges ?? .empty),
                chatItemId: chatItemId
            )
            let text: BackupProtoText
            switch textResult.bubbleUp(BackupProtoQuote.self, partialErrors: &partialErrors) {
            case .continue(let value):
                text = value
            case .bubbleUpError(let errorResult):
                return errorResult
            }
            quoteBuilder.setText(text.body)
            quoteBuilder.setBodyRanges(text.bodyRanges)
        }

        // TODO: set attachments on the quote

        if quotedMessage.isGiftBadge {
            quoteBuilder.setType(.giftbadge)
        } else {
            quoteBuilder.setType(.normal)
        }

        do {
            let quote = try quoteBuilder.build()
            return .success(quote)
        } catch {
            return .messageFailure([.init(objectId: chatItemId, error: .protoSerializationError(error))])
        }
    }

    // MARK: - Restoring

    typealias RestoreResult = MessageBackup.RestoreInteractionResult<MessageBackup.RestoredMessageContents>

    /// Parses the contents of ``MessageBackup.ChatItemMessageType`` (which represents the proto structure of message contents)
    /// into ``MessageBackup.RestoredMessageContents``, which maps more directly to the ``TSMessage`` values in our database.
    ///
    /// Does NOT create the ``TSMessage``; callers are expected to utilize the restored contents to construct and insert the message.
    ///
    /// Callers MUST call ``restoreDownstreamObjects`` after creating and inserting the ``TSMessage``.
    func restoreContents(
        _ chatItemType: ChatItemMessageType,
        thread: MessageBackup.ChatThread,
        context: MessageBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) -> RestoreResult {
        switch chatItemType {
        case .standard(let standardMessage):
            return restoreStandardMessage(standardMessage, thread: thread, context: context, tx: tx)
        case .contact, .voice, .sticker, .remotelyDeleted, .chatUpdate:
            // Other types not supported yet.
            return .messageFailure([.unimplemented])
        }
    }

    /// After a caller creates a ``TSMessage`` from the results of ``restoreContents``, they MUST call this method
    /// to create and insert all "downstream" objects: those that reference the ``TSMessage`` and require it for their own creation.
    ///
    /// This method will create and insert all necessary objects (e.g. reactions).
    func restoreDownstreamObjects(
        message: TSMessage,
        restoredContents: MessageBackup.RestoredMessageContents,
        context: MessageBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) -> MessageBackup.RestoreInteractionResult<Void> {
        let restoreReactionsResult: MessageBackup.RestoreInteractionResult<Void>
        switch restoredContents {
        case .text(let text):
            restoreReactionsResult = reactionArchiver.restoreReactions(
                text.reactions,
                message: message,
                context: context.recipientContext,
                tx: tx
            )
        }

        return restoreReactionsResult
    }

    // MARK: Helpers

    private func restoreStandardMessage(
        _ standardMessage: BackupProtoStandardMessage,
        thread: MessageBackup.ChatThread,
        context: MessageBackup.ChatRestoringContext,
        tx: DBReadTransaction
    ) -> RestoreResult {
        var partialErrors = [MessageBackup.RestoringFrameError]()

        let quotedMessage: TSQuotedMessage?
        if let quoteProto = standardMessage.quote {
            guard let quoteResult = restoreQuote(quoteProto, thread: thread, context: context, tx: tx)
                .unwrap(partialErrors: &partialErrors)
            else {
                return .messageFailure(partialErrors)
            }
            quotedMessage = quoteResult
        } else {
            quotedMessage = nil
        }

        guard let text = standardMessage.text else {
            // Non-text not supported yet.
            return .messageFailure([.unimplemented])
        }

        let messageBodyResult = restoreMessageBody(text)
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

    func restoreMessageBody(_ text: BackupProtoText) -> MessageBackup.RestoreInteractionResult<MessageBody> {
        return restoreMessageBody(text: text.body, bodyRangeProtos: text.bodyRanges)
    }

    private func restoreMessageBody(
        text: String,
        bodyRangeProtos: [BackupProtoBodyRange]
    ) -> MessageBackup.RestoreInteractionResult<MessageBody> {
        var partialErrors = [MessageBackup.RestoringFrameError]()
        var bodyMentions = [NSRange: Aci]()
        var bodyStyles = [NSRangedValue<MessageBodyRanges.SingleStyle>]()
        for bodyRange in bodyRangeProtos {
            let range = NSRange(location: Int(bodyRange.start), length: Int(bodyRange.length))
            if let rawMentionAci = bodyRange.mentionAci {
                guard let mentionAci = try? Aci.parseFrom(serviceIdBinary: rawMentionAci) else {
                    partialErrors.append(.invalidProtoData)
                    continue
                }
                bodyMentions[range] = mentionAci
            } else if bodyRange.hasStyle {
                let swiftStyle: MessageBodyRanges.SingleStyle
                switch bodyRange.style {
                case .some(.none):
                    // Unrecognized enum value
                    partialErrors.append(.unknownFrameType)
                    continue
                case nil:
                    // Missing enum value
                    partialErrors.append(.invalidProtoData)
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
        _ quote: BackupProtoQuote,
        thread: MessageBackup.ChatThread,
        context: MessageBackup.ChatRestoringContext,
        tx: DBReadTransaction
    ) -> MessageBackup.RestoreInteractionResult<TSQuotedMessage> {
        let authorAddress: MessageBackup.InteropAddress
        switch context.recipientContext[quote.authorRecipientId] {
        case .none:
            return .messageFailure([.identifierNotFound(.recipient(quote.authorRecipientId))])
        case .localAddress:
            authorAddress = context.recipientContext.localIdentifiers.aciAddress
        case .group:
            // A group cannot be an author for a message!
            return .messageFailure([.invalidProtoData])
        case .contact(let contactAddress):
            authorAddress = contactAddress.asInteropAddress()
        }

        var partialErrors = [MessageBackup.RestoringFrameError]()

        // 0 is treated as a null value.
        let targetMessageTimestamp: NSNumber?
        if quote.targetSentTimestamp != 0, SDS.fitsInInt64(quote.targetSentTimestamp) {
            targetMessageTimestamp = NSNumber(value: quote.targetSentTimestamp)
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
                guard let bodyResult = restoreMessageBody(text: text, bodyRangeProtos: quote.bodyRanges)
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
        case .unknown, .none, .normal:
            isGiftBadge = false
        case .giftbadge:
            isGiftBadge = true
        }

        guard let quoteBody else {
            // Non-text not supported yet.
            return .messageFailure([.unimplemented])
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
        quote: BackupProtoQuote,
        thread: MessageBackup.ChatThread,
        tx: DBReadTransaction
    ) -> TSMessage? {
        guard quote.targetSentTimestamp > 0 else {
            return nil
        }
        let messageCandidates: [TSInteraction] = (try? interactionStore
            .interactions(
                withTimestamp: quote.targetSentTimestamp,
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
