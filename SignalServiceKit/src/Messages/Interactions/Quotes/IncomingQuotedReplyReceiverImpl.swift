//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class NoOpFinalizingAttachmentBuilder: QuotedMessageAttachmentBuilder {

    public let attachmentInfo: OWSAttachmentInfo

    public init(attachmentInfo: OWSAttachmentInfo) {
        self.attachmentInfo = attachmentInfo
    }

    fileprivate init(
        mimeType: String,
        sourceFilename: String?
    ) {
        attachmentInfo = OWSAttachmentInfo(
            attachmentId: nil,
            ofType: .unset,
            contentType: mimeType,
            sourceFilename: sourceFilename
        )
    }

    public private(set) var hasBeenFinalized: Bool = false
    public func finalize(newMessageRowId: Int64, tx: DBWriteTransaction) {
        hasBeenFinalized = true
    }
}

public class IncomingQuotedReplyReceiverImpl: IncomingQuotedReplyReceiver {

    private let attachmentManager: TSResourceManager
    private let attachmentStore: TSResourceStore

    public init(
        attachmentManager: TSResourceManager,
        attachmentStore: TSResourceStore
    ) {
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
    }

    public func quotedMessage(
        for dataMessage: SSKProtoDataMessage,
        thread: TSThread,
        tx: DBWriteTransaction
    ) -> QuotedMessageBuilder? {
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
    ) -> QuotedMessageBuilder? {
        let quoteAuthorAddress = SignalServiceAddress(quoteAuthor)

        // This is untrusted content from other users that may not be well-formed.
        // The GiftBadge type has no content/attachments, so don't read those
        // fields if the type is GiftBadge.
        if
            quoteProto.hasType,
            quoteProto.unwrappedType == .giftBadge
        {
            return QuotedMessageBuilder(
                quotedMessage: TSQuotedMessage(
                    timestamp: quoteTimestamp,
                    authorAddress: quoteAuthorAddress,
                    body: nil,
                    bodyRanges: nil,
                    bodySource: .remote,
                    receivedQuotedAttachmentInfo: nil,
                    isGiftBadge: true
                ),
                attachmentBuilder: nil
            )
        }

        let body = quoteProto.text?.nilIfEmpty
        let bodyRanges =  quoteProto.bodyRanges.isEmpty ? nil : MessageBodyRanges(protos: quoteProto.bodyRanges)
        let attachmentBuilder: QuotedMessageAttachmentBuilder?
        if
            // We're only interested in the first attachment
            let thumbnailProto = quoteProto.attachments.first?.thumbnail,
            let thumbnailAttachmentBuilder = attachmentManager.createQuotedReplyAttachmentBuilder(
                fromUntrustedRemote: thumbnailProto,
                tx: tx
            )
        {
            attachmentBuilder = thumbnailAttachmentBuilder
        } else if let attachmentProto = quoteProto.attachments.first, let mimeType = attachmentProto.contentType {
            attachmentBuilder = NoOpFinalizingAttachmentBuilder(
                mimeType: mimeType,
                sourceFilename: attachmentProto.fileName
            )
        } else {
            attachmentBuilder = nil
        }

        if body?.nilIfEmpty == nil, attachmentBuilder == nil {
            owsFailDebug("Failed to construct a valid quoted message from remote proto content")
            return nil
        }
        return QuotedMessageBuilder(
            quotedMessage: TSQuotedMessage(
                timestamp: quoteTimestamp,
                authorAddress: quoteAuthorAddress,
                body: body,
                bodyRanges: bodyRanges,
                bodySource: .remote,
                receivedQuotedAttachmentInfo: attachmentBuilder?.attachmentInfo,
                isGiftBadge: false
            ),
            attachmentBuilder: attachmentBuilder
        )
    }

    /// Builds a quoted message from the original source message
    private func quotedMessage(
        originalMessage: TSMessage,
        quoteProto: SSKProtoDataMessageQuote,
        author: Aci,
        tx: DBWriteTransaction
    ) -> QuotedMessageBuilder? {
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
            return QuotedMessageBuilder(
                quotedMessage: TSQuotedMessage(
                    timestamp: originalMessage.timestamp,
                    authorAddress: authorAddress,
                    body: body,
                    bodyRanges: nil,
                    bodySource: .local,
                    receivedQuotedAttachmentInfo: nil,
                    isGiftBadge: false
                ),
                attachmentBuilder: nil
            )
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

        return QuotedMessageBuilder(
            quotedMessage: TSQuotedMessage(
                timestamp: originalMessage.timestamp,
                authorAddress: authorAddress,
                body: body,
                bodyRanges: bodyRanges,
                bodySource: .local,
                receivedQuotedAttachmentInfo: attachmentBuilder?.attachmentInfo,
                isGiftBadge: isGiftBadge
            ),
            attachmentBuilder: attachmentBuilder
        )
    }

    private func attachmentBuilder(
        originalMessage: TSMessage,
        quoteProto: SSKProtoDataMessageQuote,
        tx: DBWriteTransaction
    ) -> QuotedMessageAttachmentBuilder? {
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
}
