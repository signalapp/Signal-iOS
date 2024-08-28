//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

class MessageBackupTSIncomingMessageArchiver {
    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<MessageBackup.InteractionUniqueId>
    private typealias RestoreFrameError = MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>

    private let contentsArchiver: MessageBackupTSMessageContentsArchiver
    private let editHistoryArchiver: MessageBackupTSMessageEditHistoryArchiver<TSIncomingMessage>
    private let interactionStore: InteractionStore

    init(
        contentsArchiver: MessageBackupTSMessageContentsArchiver,
        editMessageStore: EditMessageStore,
        interactionStore: InteractionStore
    ) {
        self.contentsArchiver = contentsArchiver
        self.editHistoryArchiver = MessageBackupTSMessageEditHistoryArchiver(
            editMessageStore: editMessageStore
        )
        self.interactionStore = interactionStore
    }

    // MARK: - Archiving

    func archiveIncomingMessage(
        _ incomingMessage: TSIncomingMessage,
        thread: TSThread,
        context: MessageBackup.ChatArchivingContext,
        tx: DBReadTransaction
    ) -> MessageBackup.ArchiveInteractionResult<Details> {
        var partialErrors = [ArchiveFrameError]()

        let incomingMessageDetails: Details
        switch editHistoryArchiver.archiveMessageAndEditHistory(
            incomingMessage,
            thread: thread,
            context: context,
            builder: self,
            tx: tx
        ).bubbleUp(Details.self, partialErrors: &partialErrors) {
        case .continue(let _incomingMessageDetails):
            incomingMessageDetails = _incomingMessageDetails
        case .bubbleUpError(let errorResult):
            return errorResult
        }

        if partialErrors.isEmpty {
            return .success(incomingMessageDetails)
        } else {
            return .partialFailure(incomingMessageDetails, partialErrors)
        }
    }

    // MARK: - Restoring

    func restoreIncomingChatItem(
        _ topLevelChatItem: BackupProto_ChatItem,
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) -> MessageBackup.RestoreInteractionResult<Void> {
        var partialErrors = [RestoreFrameError]()

        guard
            editHistoryArchiver.restoreMessageAndEditHistory(
                topLevelChatItem,
                chatThread: chatThread,
                context: context,
                builder: self,
                tx: tx
            ).unwrap(partialErrors: &partialErrors)
        else {
            return .messageFailure(partialErrors)
        }

        if partialErrors.isEmpty {
            return .success(())
        } else {
            return .partialRestore((), partialErrors)
        }
    }
}

// MARK: - MessageBackupTSMessageEditHistoryBuilder

extension MessageBackupTSIncomingMessageArchiver: MessageBackupTSMessageEditHistoryBuilder {
    typealias EditHistoryMessageType = TSIncomingMessage

    // MARK: - Archiving

    func buildMessageArchiveDetails(
        message incomingMessage: EditHistoryMessageType,
        editRecord: EditRecord?,
        context: MessageBackup.ChatArchivingContext,
        tx: DBReadTransaction
    ) -> MessageBackup.ArchiveInteractionResult<Details> {
        var partialErrors = [ArchiveFrameError]()

        guard
            let authorAddress = MessageBackup.ContactAddress(
                // Incoming message authors are always ACIs, not PNIs
                aci: Aci.parseFrom(aciString: incomingMessage.authorUUID),
                e164: E164(incomingMessage.authorPhoneNumber)
            )?.asArchivingAddress()
        else {
            // This is an invalid message.
            return .messageFailure([.archiveFrameError(.invalidIncomingMessageAuthor, incomingMessage.uniqueInteractionId)])
        }
        guard let author = context.recipientContext[authorAddress] else {
            return .messageFailure([.archiveFrameError(
                .referencedRecipientIdMissing(authorAddress),
                incomingMessage.uniqueInteractionId
            )])
        }

        let chatItemType: MessageBackupTSMessageContentsArchiver.ChatItemType
        switch contentsArchiver.archiveMessageContents(
            incomingMessage,
            context: context.recipientContext,
            tx: tx
        ).bubbleUp(Details.self, partialErrors: &partialErrors) {
        case .continue(let _chatItemType):
            chatItemType = _chatItemType
        case .bubbleUpError(let errorResult):
            return errorResult
        }

        let incomingMessageDetails: BackupProto_ChatItem.IncomingMessageDetails = buildIncomingMessageDetails(
            incomingMessage,
            editRecord: editRecord
        )

        let details = Details(
            author: author,
            directionalDetails: .incoming(incomingMessageDetails),
            dateCreated: incomingMessage.timestamp,
            expireStartDate: incomingMessage.expireStartedAt,
            expiresInMs: UInt64(incomingMessage.expiresInSeconds) * 1000,
            isSealedSender: incomingMessage.wasReceivedByUD.negated,
            chatItemType: chatItemType
        )

        if partialErrors.isEmpty {
            return .success(details)
        } else {
            return .partialFailure(details, partialErrors)
        }
    }

    private func buildIncomingMessageDetails(
        _ incomingMessage: TSIncomingMessage,
        editRecord: EditRecord?
    ) -> BackupProto_ChatItem.IncomingMessageDetails {
        var incomingDetails = BackupProto_ChatItem.IncomingMessageDetails()
        incomingDetails.dateReceived = incomingMessage.receivedAtTimestamp
        incomingDetails.dateServerSent = incomingMessage.serverTimestamp?.uint64Value ?? 0
        // The message may not have been marked read if it's a past revision,
        // but its edit record will have been.
        incomingDetails.read = editRecord?.read ?? incomingMessage.wasRead
        incomingDetails.sealedSender = incomingMessage.wasReceivedByUD

        return incomingDetails
    }

    // MARK: - Restoring

    func restoreMessage(
        _ chatItem: BackupProto_ChatItem,
        isPastRevision: Bool,
        hasPastRevisions: Bool,
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatRestoringContext,
        tx: any DBWriteTransaction
    ) -> MessageBackup.RestoreInteractionResult<EditHistoryMessageType> {
        guard let chatItemItem = chatItem.item else {
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.chatItemMissingItem),
                chatItem.id
            )])
        }

        let incomingDetails: BackupProto_ChatItem.IncomingMessageDetails
        switch chatItem.directionalDetails {
        case .incoming(let _incomingDetails):
            incomingDetails = _incomingDetails
        case nil, .outgoing, .directionless:
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.revisionOfIncomingMessageMissingIncomingDetails),
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

        let editState: TSEditState = {
            if isPastRevision {
                return .pastRevision
            } else if hasPastRevisions {
                if incomingDetails.read {
                    return .latestRevisionRead
                } else {
                    return .latestRevisionUnread
                }
            } else {
                return .none
            }
        }()

        var partialErrors = [RestoreFrameError]()

        guard
            let contents = contentsArchiver.restoreContents(
                chatItemItem,
                chatItemId: chatItem.id,
                chatThread: chatThread,
                context: context,
                tx: tx
            ).unwrap(partialErrors: &partialErrors)
        else {
            return .messageFailure(partialErrors)
        }

        let message: TSIncomingMessage = {
            /// A "base" message builder, onto which we attach the data we
            /// unwrap from `contents`.
            let messageBuilder = TSIncomingMessageBuilder(
                thread: chatThread.tsThread,
                timestamp: chatItem.dateSent,
                receivedAtTimestamp: incomingDetails.dateReceived,
                authorAci: authorAci,
                authorE164: authorE164,
                messageBody: nil,
                bodyRanges: nil,
                editState: editState,
                expiresInSeconds: UInt32(chatItem.expiresInMs / 1000),
                // Backed up messages don't set the chat timer; version is irrelevant.
                expireTimerVersion: nil,
                expireStartedAt: chatItem.expireStartDate,
                read: incomingDetails.read,
                serverTimestamp: incomingDetails.dateServerSent,
                serverDeliveryTimestamp: 0,
                serverGuid: nil,
                wasReceivedByUD: incomingDetails.sealedSender,
                // TODO: [Backups] pass along if this is view once after proto field is added
                isViewOnceMessage: false,
                // TODO: [Backups] always treat view-once media in Backups as viewed
                isViewOnceComplete: false,
                wasRemotelyDeleted: false,
                storyAuthorAci: nil,
                storyTimestamp: nil,
                storyReactionEmoji: nil,
                quotedMessage: nil,
                // TODO: [Backups] restore contact shares
                contactShare: nil,
                linkPreview: nil,
                // TODO: [Backups] restore message stickers
                messageSticker: nil,
                // TODO: [Backups] restore gift badges
                giftBadge: nil,
                paymentNotification: nil
            )

            switch contents {
            case .archivedPayment(let archivedPayment):
                return OWSIncomingArchivedPaymentMessage(
                    incomingMessageWith: messageBuilder,
                    amount: archivedPayment.amount,
                    fee: archivedPayment.fee,
                    note: archivedPayment.note
                )
            case .remoteDeleteTombstone:
                messageBuilder.wasRemotelyDeleted = true
            case .text(let text):
                messageBuilder.messageBody = text.body?.text
                messageBuilder.bodyRanges = text.body?.ranges
                messageBuilder.quotedMessage = text.quotedMessage
                messageBuilder.linkPreview = text.linkPreview
            case .contactShare(let contactShare):
                messageBuilder.contactShare = contactShare.contact
            case .stickerMessage(let stickerMessage):
                messageBuilder.messageSticker = stickerMessage.sticker
            case .giftBadge(let giftBadge):
                messageBuilder.giftBadge = giftBadge.giftBadge
            }

            return messageBuilder.build()
        }()

        interactionStore.insertInteraction(message, tx: tx)

        guard
            contentsArchiver.restoreDownstreamObjects(
                message: message,
                thread: chatThread,
                chatItemId: chatItem.id,
                restoredContents: contents,
                context: context,
                tx: tx
            ).unwrap(partialErrors: &partialErrors)
        else {
            return .messageFailure(partialErrors)
        }

        if partialErrors.isEmpty {
            return .success(message)
        } else {
            return .partialRestore(message, partialErrors)
        }
    }
}
