//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

class MessageBackupTSIncomingMessageArchiver: MessageBackupProtoArchiver {
    typealias Details = MessageBackup.InteractionArchiveDetails

    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<MessageBackup.InteractionUniqueId>

    private let contentsArchiver: MessageBackupTSMessageContentsArchiver
    private let interactionStore: InteractionStore

    internal init(
        contentsArchiver: MessageBackupTSMessageContentsArchiver,
        interactionStore: InteractionStore
    ) {
        self.contentsArchiver = contentsArchiver
        self.interactionStore = interactionStore
    }

    // MARK: - Archiving

    func archiveIncomingMessage(
        _ message: TSIncomingMessage,
        thread _: TSThread,
        context: MessageBackup.ChatArchivingContext,
        tx: DBReadTransaction
    ) -> MessageBackup.ArchiveInteractionResult<Details> {
        var partialErrors = [ArchiveFrameError]()

        let directionalDetails: Details.DirectionalDetails
        switch buildIncomingMessageDetails(message).bubbleUp(Details.self, partialErrors: &partialErrors) {
        case .continue(let details):
            directionalDetails = details
        case .bubbleUpError(let errorResult):
            return errorResult
        }

        guard
            let authorAddress = MessageBackup.ContactAddress(
                // Incoming message authors are always Acis, not Pnis
                aci: Aci.parseFrom(aciString: message.authorUUID),
                e164: E164(message.authorPhoneNumber)
            )?.asArchivingAddress()
        else {
            // This is an invalid message.
            return .messageFailure([.archiveFrameError(.invalidIncomingMessageAuthor, message.uniqueInteractionId)])
        }
        guard let author = context.recipientContext[authorAddress] else {
            return .messageFailure([.archiveFrameError(
                .referencedRecipientIdMissing(authorAddress),
                message.uniqueInteractionId
            )])
        }

        let contentsResult = contentsArchiver.archiveMessageContents(
            message,
            context: context.recipientContext,
            tx: tx
        )
        let chatItemType: MessageBackupTSMessageContentsArchiver.ChatItemType
        switch contentsResult.bubbleUp(Details.self, partialErrors: &partialErrors) {
        case .continue(let t):
            chatItemType = t
        case .bubbleUpError(let errorResult):
            return errorResult
        }

        let details = Details(
            author: author,
            directionalDetails: directionalDetails,
            expireStartDate: message.expireStartedAt,
            expiresInMs: UInt64(message.expiresInSeconds) * 1000,
            isSealedSender: message.wasReceivedByUD.negated,
            chatItemType: chatItemType
        )
        if partialErrors.isEmpty {
            return .success(details)
        } else {
            return .partialFailure(details, partialErrors)
        }
    }

    private func buildIncomingMessageDetails(
        _ message: TSIncomingMessage
    ) -> MessageBackup.ArchiveInteractionResult<Details.DirectionalDetails> {
        var incomingMessage = BackupProto_ChatItem.IncomingMessageDetails()
        incomingMessage.dateReceived = message.receivedAtTimestamp
        incomingMessage.dateServerSent = message.serverDeliveryTimestamp
        incomingMessage.read = message.wasRead
        incomingMessage.sealedSender = message.wasReceivedByUD

        return .success(.incoming(incomingMessage))
    }

    // MARK: - Restoring

    func restoreIncomingChatItem(
        _ chatItem: BackupProto_ChatItem,
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) -> MessageBackup.RestoreInteractionResult<Void> {
        let incomingDetails: BackupProto_ChatItem.IncomingMessageDetails
        switch chatItem.directionalDetails {
        case .incoming(let incomingMessageDetails):
            incomingDetails = incomingMessageDetails
        case nil, .outgoing, .directionless:
            // Should be impossible.
            return .messageFailure([.restoreFrameError(
                .developerError(OWSAssertionError("IncomingMessageArchiver given non-incoming message!")),
                chatItem.id
            )])
        }

        let authorAci: Aci?
        let authorE164: E164?
        switch context.recipientContext[chatItem.authorRecipientId] {
        case .contact(let address):
            authorAci = address.aci
            authorE164 = address.e164
            if authorAci == nil && authorE164 == nil {
                // Don't accept pni-only addresses. An incoming
                // message can only come from an aci, or if its
                // a legacy message, possibly from an e164.
                fallthrough
            }
        default:
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.incomingMessageNotFromAciOrE164),
                chatItem.id
            )])
        }

        guard let messageType = chatItem.item else {
            // Unrecognized item type!
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.chatItemMissingItem),
                chatItem.id
            )])
        }

        var partialErrors = [MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>]()

        let contentsResult = contentsArchiver.restoreContents(
            messageType,
            chatItemId: chatItem.id,
            chatThread: chatThread,
            context: context,
            tx: tx
        )

        guard let contents = contentsResult.unwrap(partialErrors: &partialErrors) else {
            return .messageFailure(partialErrors)
        }

        let message: TSIncomingMessage = {
            switch contents {
            case .archivedPayment(let archivedPayment):
                let messageBuilder = TSIncomingMessageBuilder(
                    thread: chatThread.tsThread,
                    timestamp: incomingDetails.dateReceived,
                    authorAci: authorAci,
                    authorE164: authorE164,
                    messageBody: nil,
                    bodyRanges: nil,
                    editState: .none,
                    expiresInSeconds: UInt32(chatItem.expiresInMs / 1000),
                    expireStartedAt: chatItem.expireStartDate,
                    read: incomingDetails.read,
                    serverTimestamp: nil,
                    serverDeliveryTimestamp: chatItem.dateSent,
                    serverGuid: nil,
                    wasReceivedByUD: incomingDetails.sealedSender,
                    isViewOnceMessage: false,
                    storyAuthorAci: nil,
                    storyTimestamp: nil,
                    storyReactionEmoji: nil,
                    giftBadge: nil,
                    paymentNotification: nil
                )
                return OWSIncomingArchivedPaymentMessage(
                    incomingMessageWith: messageBuilder,
                    amount: archivedPayment.amount,
                    fee: archivedPayment.fee,
                    note: archivedPayment.note
                )
            case .text(let text):
                let messageBody = text.body
                let messageBuilder = TSIncomingMessageBuilder(
                    thread: chatThread.tsThread,
                    timestamp: incomingDetails.dateReceived,
                    authorAci: authorAci,
                    authorE164: authorE164,
                    messageBody: messageBody.text,
                    bodyRanges: messageBody.ranges,
                    // TODO: [Backups] handle edit states
                    editState: .none,
                    expiresInSeconds: UInt32(chatItem.expiresInMs / 1000),
                    expireStartedAt: chatItem.expireStartDate,
                    read: incomingDetails.read,
                    serverTimestamp: nil,
                    serverDeliveryTimestamp: chatItem.dateSent,
                    serverGuid: nil,
                    wasReceivedByUD: incomingDetails.sealedSender,
                    isViewOnceMessage: false,
                    storyAuthorAci: nil,
                    storyTimestamp: nil,
                    storyReactionEmoji: nil,
                    giftBadge: nil,
                    paymentNotification: nil
                )
                let message = messageBuilder.build()
                contents.quotedMessage.map { interactionStore.update(message, with: $0, tx: tx) }
                return message
            }
        }()

        interactionStore.insertInteraction(message, tx: tx)

        let downstreamObjectsResult = contentsArchiver.restoreDownstreamObjects(
            message: message,
            thread: chatThread,
            chatItemId: chatItem.id,
            restoredContents: contents,
            context: context,
            tx: tx
        )
        guard downstreamObjectsResult.unwrap(partialErrors: &partialErrors) else {
            return .messageFailure(partialErrors)
        }

        if !partialErrors.isEmpty {
            return .partialRestore((), partialErrors)
        }

        return .success(())
    }
}
