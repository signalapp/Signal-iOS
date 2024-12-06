//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

class MessageBackupTSIncomingMessageArchiver {
    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<MessageBackup.InteractionUniqueId>
    private typealias RestoreFrameError = MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>

    private let contentsArchiver: MessageBackupTSMessageContentsArchiver
    private let dateProvider: DateProvider
    private let editHistoryArchiver: MessageBackupTSMessageEditHistoryArchiver<TSIncomingMessage>
    private let interactionStore: MessageBackupInteractionStore

    init(
        contentsArchiver: MessageBackupTSMessageContentsArchiver,
        dateProvider: @escaping DateProvider,
        editMessageStore: EditMessageStore,
        interactionStore: MessageBackupInteractionStore
    ) {
        self.contentsArchiver = contentsArchiver
        self.dateProvider = dateProvider
        self.editHistoryArchiver = MessageBackupTSMessageEditHistoryArchiver(
            dateProvider: dateProvider,
            editMessageStore: editMessageStore
        )
        self.interactionStore = interactionStore
    }

    // MARK: - Archiving

    func archiveIncomingMessage(
        _ incomingMessage: TSIncomingMessage,
        context: MessageBackup.ChatArchivingContext
    ) -> MessageBackup.ArchiveInteractionResult<Details> {
        var partialErrors = [ArchiveFrameError]()

        let incomingMessageDetails: Details
        switch editHistoryArchiver.archiveMessageAndEditHistory(
            incomingMessage,
            context: context,
            builder: self
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
        context: MessageBackup.ChatItemRestoringContext
    ) -> MessageBackup.RestoreInteractionResult<Void> {
        var partialErrors = [RestoreFrameError]()

        guard
            editHistoryArchiver.restoreMessageAndEditHistory(
                topLevelChatItem,
                chatThread: chatThread,
                context: context,
                builder: self
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
        context: MessageBackup.ChatArchivingContext
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
            context: context.recipientContext
        ).bubbleUp(Details.self, partialErrors: &partialErrors) {
        case .continue(let _chatItemType):
            chatItemType = _chatItemType
        case .bubbleUpError(let errorResult):
            return errorResult
        }

        let directionalDetails: BackupProto_ChatItem.OneOf_DirectionalDetails
        if author == context.recipientContext.localRecipientId {
            // Incoming messages from self are not allowed in backups
            // but have been observed in real-world databases.
            // If we encounter these, fudge them a bit and pretend
            // they were outgoing messages.
            var outgoingDetails = BackupProto_ChatItem.OutgoingMessageDetails()
            var sendStatus = BackupProto_SendStatus()
            sendStatus.recipientID = context.recipientContext.localRecipientId.value
            sendStatus.timestamp = incomingMessage.receivedAtTimestamp
            var viewedStatus = BackupProto_SendStatus.Viewed()
            viewedStatus.sealedSender = incomingMessage.wasReceivedByUD
            sendStatus.deliveryStatus = .viewed(viewedStatus)
            outgoingDetails.sendStatus = [sendStatus]
            directionalDetails = .outgoing(outgoingDetails)
            partialErrors.append(.archiveFrameError(
                .incomingMessageFromSelf,
                incomingMessage.uniqueInteractionId
            ))
        } else {
            let incomingMessageDetails: BackupProto_ChatItem.IncomingMessageDetails = buildIncomingMessageDetails(
                incomingMessage,
                editRecord: editRecord
            )
            directionalDetails = .incoming(incomingMessageDetails)
        }

        let expireStartDate: UInt64?
        if incomingMessage.expireStartedAt > 0 {
            expireStartDate = incomingMessage.expireStartedAt
        } else {
            expireStartDate = nil
        }

        let details = Details(
            author: author,
            directionalDetails: directionalDetails,
            dateCreated: incomingMessage.timestamp,
            expireStartDate: expireStartDate,
            expiresInMs: UInt64(incomingMessage.expiresInSeconds) * 1000,
            isSealedSender: incomingMessage.wasReceivedByUD.negated,
            chatItemType: chatItemType,
            isSmsPreviouslyRestoredFromBackup: incomingMessage.isSmsMessageRestoredFromBackup
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
        if let dateServerSent = incomingMessage.serverTimestamp?.uint64Value {
            incomingDetails.dateServerSent = dateServerSent
        }
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
        context: MessageBackup.ChatItemRestoringContext
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

        let expiresInSeconds: UInt32
        if chatItem.hasExpiresInMs {
            guard let _expiresInSeconds: UInt32 = .msToSecs(chatItem.expiresInMs) else {
                return .messageFailure([.restoreFrameError(
                    .invalidProtoData(.expirationTimerOverflowedLocalType),
                    chatItem.id
                )])
            }
            expiresInSeconds = _expiresInSeconds
        } else {
            // 0 == no expiration
            expiresInSeconds = 0
        }
        let expireStartDate: UInt64
        if chatItem.hasExpireStartDate {
            expireStartDate = chatItem.expireStartDate
        } else if
            expiresInSeconds > 0,
            incomingDetails.read
        {
            // If marked as read but the chat timer hasn't started,
            // thats a bug on the export side but we can recover
            // from it now by starting the timer now.
            expireStartDate = dateProvider().ows_millisecondsSince1970
        } else {
            // 0 = hasn't started expiring.
            expireStartDate = 0
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
                context: context
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
                expiresInSeconds: expiresInSeconds,
                // Backed up messages don't set the chat timer; version is irrelevant.
                expireTimerVersion: nil,
                expireStartedAt: expireStartDate,
                read: incomingDetails.read,
                serverTimestamp: incomingDetails.dateServerSent,
                serverDeliveryTimestamp: 0,
                serverGuid: nil,
                wasReceivedByUD: incomingDetails.sealedSender,
                isSmsMessageRestoredFromBackup: chatItem.sms,
                isViewOnceMessage: false,
                isViewOnceComplete: false,
                wasRemotelyDeleted: false,
                storyAuthorAci: nil,
                storyTimestamp: nil,
                storyReactionEmoji: nil,
                quotedMessage: nil,
                contactShare: nil,
                linkPreview: nil,
                messageSticker: nil,
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
            case .viewOnceMessage(let viewOnceMessage):
                messageBuilder.isViewOnceMessage = true
                switch viewOnceMessage.state {
                case .unviewed:
                    messageBuilder.isViewOnceComplete = false
                case .complete:
                    messageBuilder.isViewOnceComplete = true
                }
            }

            return messageBuilder.build()
        }()

        do {
            try interactionStore.insert(
                message,
                in: chatThread,
                chatId: chatItem.typedChatId,
                senderAci: authorAci,
                directionalDetails: incomingDetails,
                context: context
            )
        } catch let error {
            return .messageFailure(partialErrors + [.restoreFrameError(.databaseInsertionFailed(error), chatItem.id)])
        }

        guard
            contentsArchiver.restoreDownstreamObjects(
                message: message,
                thread: chatThread,
                chatItemId: chatItem.id,
                restoredContents: contents,
                context: context
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
