//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

internal class MessageBackupTSIncomingMessageArchiver: MessageBackupInteractionArchiver {

    static let archiverType: MessageBackup.ChatItemArchiverType = .incomingMessage

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

    func archiveInteraction(
        _ interaction: TSInteraction,
        context: MessageBackup.ChatArchivingContext,
        tx: DBReadTransaction
    ) -> MessageBackup.ArchiveInteractionResult<Details> {
        guard let message = interaction as? TSIncomingMessage else {
            // Should be impossible.
            return .completeFailure(.fatalArchiveError(.developerError(
                OWSAssertionError("Invalid interaction type")
            )))
        }

        var partialErrors = [MessageBackupChatItemArchiver.ArchiveMultiFrameResult.ArchiveFrameError]()

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
        let incomingMessage = BackupProto.ChatItem.IncomingMessageDetails(
            dateReceived: message.receivedAtTimestamp,
            dateServerSent: message.serverDeliveryTimestamp,
            read: message.wasRead,
            sealedSender: message.wasReceivedByUD
        )

        return .success(.incoming(incomingMessage))
    }

    // MARK: - Restoring

    func restoreChatItem(
        _ chatItem: BackupProto.ChatItem,
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) -> MessageBackup.RestoreInteractionResult<Void> {
        let incomingDetails: BackupProto.ChatItem.IncomingMessageDetails
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
                .invalidProtoData(.unrecognizedChatItemType),
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

        let messageBody = contents.body

        let messageBuilder = TSIncomingMessageBuilder(
            thread: chatThread.tsThread,
            timestamp: incomingDetails.dateReceived,
            authorAci: authorAci,
            authorE164: authorE164,
            messageBody: messageBody?.text,
            bodyRanges: messageBody?.ranges,
            // [Backups] TODO: handle edit states
            editState: .none,
            expiresInSeconds: chatItem.expiresInMs.map { UInt32($0 / 1000) } ?? 0,
            expireStartedAt: chatItem.expireStartDate ?? 0,
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
        interactionStore.insertInteraction(message, tx: tx)

        let downstreamObjectsResult = contentsArchiver.restoreDownstreamObjects(
            message: message,
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
