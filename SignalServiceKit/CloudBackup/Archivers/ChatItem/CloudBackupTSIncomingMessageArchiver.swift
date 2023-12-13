//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

internal class CloudBackupTSIncomingMessageArchiver: CloudBackupInteractionArchiver {

    private let contentsArchiver: CloudBackupTSMessageContentsArchiver
    private let interactionFetcher: CloudBackup.Shims.TSInteractionFetcher

    internal init(
        contentsArchiver: CloudBackupTSMessageContentsArchiver,
        interactionFetcher: CloudBackup.Shims.TSInteractionFetcher
    ) {
        self.contentsArchiver = contentsArchiver
        self.interactionFetcher = interactionFetcher
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
        case .isStoryMessage:
            return .isStoryMessage
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

        let authorAddress: CloudBackup.RecipientArchivingContext.Address
        if
            let authorAci = Aci.parseFrom(aciString: message.authorUUID)
        {
            authorAddress = .contactAci(authorAci)
        } else if
            let authorE164 = E164(message.authorPhoneNumber)
        {
            authorAddress = .contactE164(authorE164)
        } else {
            // This is an invalid message.
            return .messageFailure([.init(objectId: message.timestamp, error: .invalidMessageAddress)])
        }
        guard let author = context.recipientContext[authorAddress] else {
            return .messageFailure([.init(
                objectId: message.timestamp,
                error: .referencedIdMissing(.recipient(authorAddress))
            )])
        }

        let contentsResult = contentsArchiver.archiveMessageContents(
            message,
            tx: tx
        )
        let type: CloudBackup.ChatItemMessageType
        switch contentsResult {
        case .success(let component):
            type = component
        case .isPastRevision:
            return .isPastRevision
        case .isStoryMessage:
            return .isStoryMessage
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
            read: message.wasRead,
            sealedSender: message.wasReceivedByUD.negated
        )
        do {
            let incomingMessageProto = try incomingMessageProtoBuilder.build()
            return .success(.incoming(incomingMessageProto))
        } catch let error {
            return .messageFailure([.init(objectId: message.timestamp, error: .protoSerializationError(error))])
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
        thread: TSThread,
        context: CloudBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) -> RestoreFrameResult {
        guard let incomingDetails = chatItem.incoming else {
            // Should be impossible.
            return .failure(chatItem.dateSent, [.invalidProtoData])
        }

        let authorAci: Aci
        switch context.recipientContext[chatItem.authorRecipientId] {
        case .contact(let aci, _, _):
            guard let aci else {
                fallthrough
            }
            authorAci = aci
        default:
            // Messages can only come from Acis.
            return .failure(chatItem.dateSent, [.invalidProtoData])
        }

        guard let messageType = chatItem.messageType else {
            // Unrecognized item type!
            return .failure(chatItem.dateSent, [.unknownFrameType])
        }

        switch messageType {
        case .standard:
            break
        case .contact:
            // Unsupported, report success and skip.
            return .success
        case .voice:
            // Unsupported, report success and skip.
            return .success
        case .sticker:
            // Unsupported, report success and skip.
            return .success
        case .remotelyDeleted:
            // Unsupported, report success and skip.
            return .success
        case .chatUpdate:
            // Unsupported, report success and skip.
            return .success
        }

        var partialErrors = [CloudBackup.RestoringFrameError]()

        let (messageBody, bodyResult) = contentsArchiver.restoreMessageBody(messageType)
        switch bodyResult {
        case .success:
            break
        case .partialRestore(_, let errors):
            partialErrors.append(contentsOf: errors)
        case .failure(_, let errors):
            partialErrors.append(contentsOf: errors)
            return .failure(chatItem.dateSent, partialErrors)
        }

        let messageBuilder = TSIncomingMessageBuilder.builder(
            thread: thread,
            timestamp: incomingDetails.dateReceived,
            authorAci: .init(authorAci),
            // TODO: this needs to be added to the proto
            sourceDeviceId: 1,
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
            wasReceivedByUD: incomingDetails.sealedSender.negated,
            isViewOnceMessage: false,
            storyAuthorAci: nil,
            storyTimestamp: nil,
            storyReactionEmoji: nil,
            giftBadge: nil,
            paymentNotification: nil
        )
        let message = messageBuilder.build()
        interactionFetcher.insert(message, tx: tx)

        if partialErrors.isEmpty {
            return .success
        } else {
            return .partialRestore(chatItem.dateSent, partialErrors)
        }
    }
}
