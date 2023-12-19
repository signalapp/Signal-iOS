//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

internal class CloudBackupTSIncomingMessageArchiver: CloudBackupInteractionArchiver {

    private let contentsArchiver: CloudBackupTSMessageContentsArchiver
    private let interactionStore: InteractionStore

    internal init(
        contentsArchiver: CloudBackupTSMessageContentsArchiver,
        interactionStore: InteractionStore
    ) {
        self.contentsArchiver = contentsArchiver
        self.interactionStore = interactionStore
    }

    // MARK: - Archiving

    static func canArchiveInteraction(_ interaction: TSInteraction) -> Bool {
        return interaction is TSIncomingMessage
    }

    func archiveInteraction(
        _ interaction: TSInteraction,
        context: CloudBackup.ChatArchivingContext,
        tx: DBReadTransaction
    ) -> CloudBackup.ArchiveInteractionResult<Details> {
        guard let message = interaction as? TSIncomingMessage else {
            // Should be impossible.
            return .completeFailure(OWSAssertionError("Invalid interaction type"))
        }

        var partialErrors = [CloudBackupChatItemArchiver.ArchiveMultiFrameResult.Error]()

        let directionalDetails: Details.DirectionalDetails
        switch buildIncomingMessageDetails(message) {
        case .success(let details):
            directionalDetails = details
        case .isPastRevision:
            return .isPastRevision
        case .notYetImplemented:
            return .notYetImplemented
        case let .partialFailure(details, errors):
            directionalDetails = details
            partialErrors.append(contentsOf: errors)
        case .messageFailure(let errors):
            partialErrors.append(contentsOf: errors)
            return .messageFailure(partialErrors)
        case .completeFailure(let error):
            return .completeFailure(error)
        }

        guard
            let authorAddress = CloudBackup.ContactAddress(
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
        let type: CloudBackup.ChatItemMessageType
        switch contentsResult {
        case .success(let component):
            type = component
        case .isPastRevision:
            return .isPastRevision
        case .notYetImplemented:
            return .notYetImplemented
        case let .partialFailure(component, errors):
            type = component
            partialErrors.append(contentsOf: errors)
        case .messageFailure(let errors):
            partialErrors.append(contentsOf: errors)
            return .messageFailure(partialErrors)
        case .completeFailure(let error):
            return .completeFailure(error)
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
    ) -> CloudBackup.ArchiveInteractionResult<Details.DirectionalDetails> {
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

    static func canRestoreChatItem(_ chatItem: BackupProtoChatItem) -> Bool {
        // TODO: will e.g. info messages have an incoming or outgoing field set?
        // if so we need some other differentiator.
        return chatItem.incoming != nil
    }

    func restoreChatItem(
        _ chatItem: BackupProtoChatItem,
        thread: CloudBackup.ChatThread,
        context: CloudBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) -> CloudBackup.RestoreInteractionResult<Void> {
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

        var partialErrors = [CloudBackup.RestoringFrameError]()

        let contentsResult = contentsArchiver.restoreContents(
            messageType,
            tx: tx
        )

        let contents: CloudBackup.RestoredMessageContents
        switch contentsResult {
        case .success(let value):
            contents = value
        case .partialRestore(let value, let errors):
            contents = value
            partialErrors.append(contentsOf: errors)
        case .messageFailure(let errors):
            partialErrors.append(contentsOf: errors)
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
            quotedMessage: nil,
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
        switch downstreamObjectsResult {
        case .success:
            break
        case .partialRestore(_, let errors):
            partialErrors.append(contentsOf: errors)
        case .messageFailure(let errors):
            partialErrors.append(contentsOf: errors)
            return .messageFailure(partialErrors)
        }

        if !partialErrors.isEmpty {
            return .partialRestore((), partialErrors)
        }

        return .success(())
    }
}
