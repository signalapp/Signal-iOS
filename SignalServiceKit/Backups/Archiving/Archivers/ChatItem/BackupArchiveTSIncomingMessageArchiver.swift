//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

final class BackupArchiveTSIncomingMessageArchiver {
    private typealias ArchiveFrameError = BackupArchive.ArchiveFrameError<BackupArchive.InteractionUniqueId>
    private typealias RestoreFrameError = BackupArchive.RestoreFrameError<BackupArchive.ChatItemId>

    private let contentsArchiver: BackupArchiveTSMessageContentsArchiver
    private let editHistoryArchiver: BackupArchiveTSMessageEditHistoryArchiver<TSIncomingMessage>
    private let interactionStore: BackupArchiveInteractionStore

    init(
        contentsArchiver: BackupArchiveTSMessageContentsArchiver,
        editMessageStore: EditMessageStore,
        interactionStore: BackupArchiveInteractionStore
    ) {
        self.contentsArchiver = contentsArchiver
        self.editHistoryArchiver = BackupArchiveTSMessageEditHistoryArchiver(
            editMessageStore: editMessageStore
        )
        self.interactionStore = interactionStore
    }

    // MARK: - Archiving

    func archiveIncomingMessage(
        _ incomingMessage: TSIncomingMessage,
        threadInfo: BackupArchive.ChatArchivingContext.CachedThreadInfo,
        context: BackupArchive.ChatArchivingContext
    ) -> BackupArchive.ArchiveInteractionResult<Details> {
        var partialErrors = [ArchiveFrameError]()

        let incomingMessageDetails: Details
        switch editHistoryArchiver.archiveMessageAndEditHistory(
            incomingMessage,
            threadInfo: threadInfo,
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
        chatThread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext
    ) -> BackupArchive.RestoreInteractionResult<Void> {
        var partialErrors = [RestoreFrameError]()

        switch editHistoryArchiver
            .restoreMessageAndEditHistory(
                topLevelChatItem,
                chatThread: chatThread,
                context: context,
                builder: self
            )
            .bubbleUp(Void.self, partialErrors: &partialErrors)
        {
        case .continue:
            break
        case .bubbleUpError(let error):
            return error
        }

        if partialErrors.isEmpty {
            return .success(())
        } else {
            return .partialRestore((), partialErrors)
        }
    }
}

// MARK: - BackupArchiveTSMessageEditHistoryBuilder

extension BackupArchiveTSIncomingMessageArchiver: BackupArchiveTSMessageEditHistoryBuilder {
    typealias EditHistoryMessageType = TSIncomingMessage

    // MARK: - Archiving

    func buildMessageArchiveDetails(
        message incomingMessage: EditHistoryMessageType,
        editRecord: EditRecord?,
        threadInfo: BackupArchive.ChatArchivingContext.CachedThreadInfo,
        context: BackupArchive.ChatArchivingContext
    ) -> BackupArchive.ArchiveInteractionResult<Details> {
        var partialErrors = [ArchiveFrameError]()

        guard
            let authorAddress = BackupArchive.ContactAddress(
                // Incoming message authors are always ACIs, not PNIs
                aci: Aci.parseFrom(aciString: incomingMessage.authorUUID),
                e164: E164(incomingMessage.authorPhoneNumber)
            )
        else {
            // This is an invalid message.
            return .messageFailure([.archiveFrameError(.invalidIncomingMessageAuthor, incomingMessage.uniqueInteractionId)])
        }
        guard let author = context.recipientContext[authorAddress.asArchivingAddress()] else {
            return .messageFailure([.archiveFrameError(
                .referencedRecipientIdMissing(authorAddress.asArchivingAddress()),
                incomingMessage.uniqueInteractionId
            )])
        }

        let chatItemType: BackupArchiveTSMessageContentsArchiver.ChatItemType
        switch contentsArchiver.archiveMessageContents(
            incomingMessage,
            context: context
        ).bubbleUp(Details.self, partialErrors: &partialErrors) {
        case .continue(let _chatItemType):
            chatItemType = _chatItemType
        case .bubbleUpError(let errorResult):
            return errorResult
        }

        func buildSwizzledOutgoingNoteToSelfMessage() -> (BackupProto_ChatItem.OneOf_DirectionalDetails, Details.AuthorAddress) {
            var outgoingDetails = BackupProto_ChatItem.OutgoingMessageDetails()
            outgoingDetails.dateReceived = incomingMessage.receivedAtTimestamp
            var sendStatus = BackupProto_SendStatus()
            sendStatus.recipientID = context.recipientContext.localRecipientId.value
            sendStatus.timestamp = incomingMessage.receivedAtTimestamp
            var viewedStatus = BackupProto_SendStatus.Viewed()
            viewedStatus.sealedSender = incomingMessage.wasReceivedByUD
            sendStatus.deliveryStatus = .viewed(viewedStatus)
            outgoingDetails.sendStatus = [sendStatus]
            return (.outgoing(outgoingDetails), .localUser)
        }

        let detailsAuthor: Details.AuthorAddress
        let directionalDetails: BackupProto_ChatItem.OneOf_DirectionalDetails

        if author == context.recipientContext.localRecipientId {
            // Incoming messages from self are not allowed in backups
            // but have been observed in real-world databases.
            // If we encounter these, fudge them a bit and pretend
            // they were outgoing messages.
            partialErrors.append(.archiveFrameError(
                .incomingMessageFromSelf,
                incomingMessage.uniqueInteractionId
            ))
            let pair = buildSwizzledOutgoingNoteToSelfMessage()
            directionalDetails = pair.0
            detailsAuthor = pair.1
        } else if case .noteToSelfThread = threadInfo {
            // Incoming messages in the note to self are not allowed in backups because:
            // 1. Messages not from self are not allowed in note to self
            // 2. Incoming messages from self are not allowed in general
            // So we swizzle this into an outgoing message from self.
            partialErrors.append(.archiveFrameError(
                .nonSelfAuthorInNoteToSelf,
                incomingMessage.uniqueInteractionId
            ))
            let pair = buildSwizzledOutgoingNoteToSelfMessage()
            directionalDetails = pair.0
            detailsAuthor = pair.1
        } else {
            let incomingMessageDetails: BackupProto_ChatItem.IncomingMessageDetails = buildIncomingMessageDetails(
                incomingMessage,
                editRecord: editRecord
            )
            directionalDetails = .incoming(incomingMessageDetails)
            detailsAuthor = .contact(authorAddress)
        }

        let expireStartDate: UInt64?
        if incomingMessage.expireStartedAt > 0 {
            expireStartDate = incomingMessage.expireStartedAt
        } else {
            expireStartDate = nil
        }

        let detailsResult = Details.validateAndBuild(
            interactionUniqueId: incomingMessage.uniqueInteractionId,
            author: detailsAuthor,
            directionalDetails: directionalDetails,
            dateCreated: incomingMessage.timestamp,
            expireStartDate: expireStartDate,
            expiresInMs: UInt64(incomingMessage.expiresInSeconds) * 1000,
            isSealedSender: incomingMessage.wasReceivedByUD.negated,
            chatItemType: chatItemType,
            isSmsPreviouslyRestoredFromBackup: incomingMessage.isSmsMessageRestoredFromBackup,
            threadInfo: threadInfo,
            context: context.recipientContext
        )

        let details: Details
        switch detailsResult.bubbleUp(Details.self, partialErrors: &partialErrors) {
        case .continue(let _details):
            details = _details
        case .bubbleUpError(let error):
            return error
        }

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
        chatThread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext
    ) -> BackupArchive.RestoreInteractionResult<EditHistoryMessageType> {
        guard let chatItemItem = chatItem.item else {
            return .unrecognizedEnum(BackupArchive.UnrecognizedEnumError(
                enumType: BackupProto_ChatItem.OneOf_Item.self
            ))
        }

        let incomingDetails: BackupProto_ChatItem.IncomingMessageDetails
        switch chatItem.directionalDetails {
        case .incoming(let _incomingDetails):
            incomingDetails = _incomingDetails
        case .outgoing, .directionless:
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.revisionOfIncomingMessageMissingIncomingDetails),
                chatItem.id
            )])
        case nil:
            return .unrecognizedEnum(BackupArchive.UnrecognizedEnumError(
                enumType: BackupProto_ChatItem.OneOf_DirectionalDetails.self
            ))
        }

        let authorAci: Aci?
        let authorE164: E164?
        switch context.recipientContext[chatItem.authorRecipientId] {
        case .contact(let address):
            // See NormalizedDatabaseRecordAddress for more details.
            authorAci = address.aci
            authorE164 = authorAci == nil ? address.e164 : nil
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
            expireStartDate = context.startTimestampMs
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

        let contents: BackupArchive.RestoredMessageContents
        switch contentsArchiver
            .restoreContents(
                chatItemItem,
                chatItemId: chatItem.id,
                chatThread: chatThread,
                context: context
            )
            .bubbleUp(EditHistoryMessageType.self, partialErrors: &partialErrors)
        {
        case .continue(let component):
            contents = component
        case .bubbleUpError(let error):
            return error
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
                paymentNotification: nil,
                isPoll: false // TODO(KC): fill in once polls are implemented in backups
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
                messageBuilder.setMessageBody(text.body)
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
            case .storyReply(let storyReply):
                switch storyReply.replyType {
                case .textReply(let textReply):
                    messageBuilder.setMessageBody(textReply.body)
                case .emoji(let emoji):
                    messageBuilder.storyReactionEmoji = emoji
                }
                // Peers can't reply to their own stories; if a 1:1 story reply is incoming
                // that means the author of the story being replied to was the local user.
                messageBuilder.storyAuthorAci = AciObjC(context.recipientContext.localIdentifiers.aci)
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

        if authorAci == nil {
            context.recipientContext.setHasIncomingMessagesMissingAci(recipientId: chatItem.authorRecipientId)
        }

        switch contentsArchiver
            .restoreDownstreamObjects(
                message: message,
                thread: chatThread,
                chatItemId: chatItem.id,
                restoredContents: contents,
                context: context
            )
            .bubbleUp(TSIncomingMessage.self, partialErrors: &partialErrors)
        {
        case .continue:
            break
        case .bubbleUpError(let error):
            return error
        }

        if partialErrors.isEmpty {
            return .success(message)
        } else {
            return .partialRestore(message, partialErrors)
        }
    }
}
