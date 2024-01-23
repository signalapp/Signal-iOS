//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

internal class MessageBackupTSIncomingMessageArchiver: MessageBackupInteractionArchiver {

    private let contentsArchiver: MessageBackupTSMessageContentsArchiver
    private let interactionStore: InteractionStore

    internal init(
        contentsArchiver: MessageBackupTSMessageContentsArchiver,
        interactionStore: InteractionStore
    ) {
        self.contentsArchiver = contentsArchiver
        self.interactionStore = interactionStore
    }

    static let archiverType = MessageBackup.InteractionArchiverType.incomingMessage

    // MARK: - Archiving

    func archiveInteraction(
        _ interaction: TSInteraction,
        context: MessageBackup.ChatArchivingContext,
        tx: DBReadTransaction
    ) -> MessageBackup.ArchiveInteractionResult<Details> {
        guard let message = interaction as? TSIncomingMessage else {
            // Should be impossible.
            return .completeFailure(OWSAssertionError("Invalid interaction type"))
        }

        var partialErrors = [MessageBackupChatItemArchiver.ArchiveMultiFrameResult.Error]()

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
            return .messageFailure([.init(objectId: message.chatItemId, error: .invalidMessageAddress)])
        }
        guard let author = context.recipientContext[authorAddress] else {
            return .messageFailure([.init(
                objectId: message.chatItemId,
                error: .referencedIdMissing(.recipient(authorAddress))
            )])
        }

        let contentsResult = contentsArchiver.archiveMessageContents(
            message,
            context: context.recipientContext,
            tx: tx
        )
        let type: MessageBackup.ChatItemMessageType
        switch contentsResult.bubbleUp(Details.self, partialErrors: &partialErrors) {
        case .continue(let t):
            type = t
        case .bubbleUpError(let errorResult):
            return errorResult
        }

        let details = Details(
            author: author,
            directionalDetails: directionalDetails,
            expireStartDate: message.expireStartedAt,
            expiresInMs: UInt64(message.expiresInSeconds) * 1000,
            isSealedSender: message.wasReceivedByUD.negated,
            type: type
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
        let incomingMessageProtoBuilder = BackupProtoChatItemIncomingMessageDetails.builder(
            dateReceived: message.receivedAtTimestamp,
            dateServerSent: message.serverDeliveryTimestamp,
            read: message.wasRead
        )
        do {
            let incomingMessageProto = try incomingMessageProtoBuilder.build()
            return .success(.incoming(incomingMessageProto))
        } catch let error {
            return .messageFailure([.init(objectId: message.chatItemId, error: .protoSerializationError(error))])
        }
    }

    // MARK: - Restoring

    func restoreChatItem(
        _ chatItem: BackupProtoChatItem,
        thread: MessageBackup.ChatThread,
        context: MessageBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) -> MessageBackup.RestoreInteractionResult<Void> {
        guard let incomingDetails = chatItem.incoming else {
            // Should be impossible.
            return .messageFailure([.invalidProtoData])
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
            return .messageFailure([.invalidProtoData])
        }

        guard let messageType = chatItem.messageType else {
            // Unrecognized item type!
            return .messageFailure([.unknownFrameType])
        }

        var partialErrors = [MessageBackup.RestoringFrameError]()

        let contentsResult = contentsArchiver.restoreContents(
            messageType,
            thread: thread,
            context: context,
            tx: tx
        )

        guard let contents = contentsResult.unwrap(partialErrors: &partialErrors) else {
            return .messageFailure(partialErrors)
        }

        let messageBody = contents.body

        let messageBuilder = TSIncomingMessageBuilder.builder(
            thread: thread.thread,
            timestamp: incomingDetails.dateReceived,
            authorAci: authorAci,
            authorE164: authorE164,
            messageBody: messageBody?.text,
            bodyRanges: messageBody?.ranges,
            attachmentIds: nil,
            // TODO: handle edit states
            editState: .none,
            // TODO: expose + set expire start time
            expiresInSeconds: UInt32(chatItem.expiresInMs),
            quotedMessage: contents.quotedMessage,
            contactShare: nil,
            linkPreview: nil,
            messageSticker: nil,
            serverTimestamp: nil,
            serverDeliveryTimestamp: chatItem.dateSent,
            serverGuid: nil,
            wasReceivedByUD: chatItem.sealedSender.negated,
            isViewOnceMessage: false,
            storyAuthorAci: nil,
            storyTimestamp: nil,
            storyReactionEmoji: nil,
            giftBadge: nil,
            paymentNotification: nil
        )
        let message = messageBuilder.build()
        interactionStore.insertInteraction(message, tx: tx)

        let downstreamObjectsResult = contentsArchiver.restoreDownstreamObjects(
            message: message,
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
