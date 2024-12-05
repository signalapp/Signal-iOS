//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

class MessageBackupTSOutgoingMessageArchiver {
    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<MessageBackup.InteractionUniqueId>
    private typealias RestoreFrameError = MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>

    private let contentsArchiver: MessageBackupTSMessageContentsArchiver
    private let dateProvider: DateProvider
    private let editHistoryArchiver: MessageBackupTSMessageEditHistoryArchiver<TSOutgoingMessage>
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

    func archiveOutgoingMessage(
        _ outgoingMessage: TSOutgoingMessage,
        context: MessageBackup.ChatArchivingContext
    ) -> MessageBackup.ArchiveInteractionResult<Details> {
        var partialErrors = [ArchiveFrameError]()

        let outgoingMessageDetails: Details
        switch editHistoryArchiver.archiveMessageAndEditHistory(
            outgoingMessage,
            context: context,
            builder: self
        ).bubbleUp(Details.self, partialErrors: &partialErrors) {
        case .continue(let _outgoingMessageDetails):
            outgoingMessageDetails = _outgoingMessageDetails
        case .bubbleUpError(let errorResult):
            return errorResult
        }

        if partialErrors.isEmpty {
            return .success(outgoingMessageDetails)
        } else {
            return .partialFailure(outgoingMessageDetails, partialErrors)
        }
    }

    // MARK: - Restoring

    func restoreChatItem(
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

// MARK: -

private extension MessageBackup {
    /// Maps cases in ``BackupProto_SendStatus/Failed/FailureReason`` to raw
    /// error codes used in ``TSOutgoingMessageRecipientState/errorCode``.
    enum SendStatusFailureErrorCode: Int {
        /// Derived from ``OWSErrorCode/untrustedIdentity``, which is itself
        /// used in ``UntrustedIdentityError``.
        case identityKeyMismatch = 777427

        /// ``TSOutgoingMessageRecipientState/errorCode`` can contain literally
        /// the error code of any error thrown during message sending. To that
        /// end, we don't know what persisted error codes refer, now or in the
        /// past, to a network error. However, we want to be able to export
        /// network errors that we previously restored from a backup.
        ///
        /// This case serves as a sentinel value for network errors restored
        /// from a backup, so we can round-trip export them as network errors.
        ///
        /// - SeeAlso ``MessageSender``
        case networkError = 123456

        /// Derived from ``OWSErrorCode/genericFailure``.
        case unknown = 32

        /// Non-failable init where unknown raw values are coerced into
        /// `.unknown`.
        init(rawValue: Int) {
            switch rawValue {
            case SendStatusFailureErrorCode.identityKeyMismatch.rawValue:
                self = .identityKeyMismatch
            case SendStatusFailureErrorCode.networkError.rawValue:
                self = .networkError
            default:
                self = .unknown
            }
        }
    }
}

// MARK: - MessageBackupTSMessageEditHistoryBuilder

extension MessageBackupTSOutgoingMessageArchiver: MessageBackupTSMessageEditHistoryBuilder {
    typealias EditHistoryMessageType = TSOutgoingMessage

    // MARK: - Archiving

    func buildMessageArchiveDetails(
        message outgoingMessage: EditHistoryMessageType,
        editRecord: EditRecord?,
        context: MessageBackup.ChatArchivingContext
    ) -> MessageBackup.ArchiveInteractionResult<Details> {
        var partialErrors = [ArchiveFrameError]()

        let wasAnySendSealedSender: Bool
        let outgoingDetails: BackupProto_ChatItem.OutgoingMessageDetails
        switch buildOutgoingMessageDetails(
            outgoingMessage,
            recipientContext: context.recipientContext
        ).bubbleUp(Details.self, partialErrors: &partialErrors) {
        case .continue(let (_outgoingDetails, _wasAnySendSealedSender)):
            outgoingDetails = _outgoingDetails
            wasAnySendSealedSender = _wasAnySendSealedSender
        case .bubbleUpError(let errorResult):
            return errorResult
        }

        let chatItemType: MessageBackup.InteractionArchiveDetails.ChatItemType
        switch contentsArchiver.archiveMessageContents(
            outgoingMessage,
            context: context.recipientContext
        ).bubbleUp(Details.self, partialErrors: &partialErrors) {
        case .continue(let t):
            chatItemType = t
        case .bubbleUpError(let errorResult):
            return errorResult
        }

        let expireStartDate: UInt64?
        if outgoingMessage.expireStartedAt > 0 {
            expireStartDate = outgoingMessage.expireStartedAt
        } else {
            expireStartDate = nil
        }

        let details = Details(
            author: context.recipientContext.localRecipientId,
            directionalDetails: .outgoing(outgoingDetails),
            dateCreated: outgoingMessage.timestamp,
            expireStartDate: expireStartDate,
            expiresInMs: UInt64(outgoingMessage.expiresInSeconds) * 1000,
            isSealedSender: wasAnySendSealedSender,
            chatItemType: chatItemType,
            isSmsPreviouslyRestoredFromBackup: outgoingMessage.isSmsMessageRestoredFromBackup
        )

        if partialErrors.isEmpty {
            return .success(details)
        } else {
            return .partialFailure(details, partialErrors)
        }
    }

    private func buildOutgoingMessageDetails(
        _ message: TSOutgoingMessage,
        recipientContext: MessageBackup.RecipientArchivingContext
    ) -> MessageBackup.ArchiveInteractionResult<(
        outgoingDetails: BackupProto_ChatItem.OutgoingMessageDetails,
        wasAnySendSealedSender: Bool
    )> {
        var perRecipientErrors = [ArchiveFrameError]()

        var wasAnySendSealedSender = false
        var outgoingDetails = BackupProto_ChatItem.OutgoingMessageDetails()

        for (address, sendState) in message.recipientAddressStates ?? [:] {
            guard let recipientAddress = address.asSingleServiceIdBackupAddress()?.asArchivingAddress() else {
                perRecipientErrors.append(.archiveFrameError(
                    .invalidOutgoingMessageRecipient,
                    message.uniqueInteractionId
                ))
                continue
            }
            guard let recipientId = recipientContext[recipientAddress] else {
                perRecipientErrors.append(.archiveFrameError(
                    .referencedRecipientIdMissing(recipientAddress),
                    message.uniqueInteractionId
                ))
                continue
            }

            let deliveryStatus: BackupProto_SendStatus.OneOf_DeliveryStatus
            switch sendState.status {
            case .sent:
                var sentStatus = BackupProto_SendStatus.Sent()
                sentStatus.sealedSender = sendState.wasSentByUD

                deliveryStatus = .sent(sentStatus)
            case .delivered:
                var deliveredStatus = BackupProto_SendStatus.Delivered()
                deliveredStatus.sealedSender = sendState.wasSentByUD

                deliveryStatus = .delivered(deliveredStatus)
            case .read:
                var readStatus = BackupProto_SendStatus.Read()
                readStatus.sealedSender = sendState.wasSentByUD

                deliveryStatus = .read(readStatus)
            case .viewed:
                var viewedStatus = BackupProto_SendStatus.Viewed()
                viewedStatus.sealedSender = sendState.wasSentByUD

                deliveryStatus = .viewed(viewedStatus)
            case .failed:
                var failedStatus = BackupProto_SendStatus.Failed()
                failedStatus.reason = { () -> BackupProto_SendStatus.Failed.FailureReason in
                    guard let errorCode = sendState.errorCode else {
                        return .unknown
                    }

                    switch MessageBackup.SendStatusFailureErrorCode(rawValue: errorCode) {
                    case .unknown:
                        return .unknown
                    case .networkError:
                        return .network
                    case .identityKeyMismatch:
                        return .identityKeyMismatch
                    }
                }()

                deliveryStatus = .failed(failedStatus)
            case .sending, .pending:
                deliveryStatus = .pending(BackupProto_SendStatus.Pending())
            case .skipped:
                deliveryStatus = .skipped(BackupProto_SendStatus.Skipped())
            }

            var sendStatus = BackupProto_SendStatus()
            sendStatus.recipientID = recipientId.value
            sendStatus.timestamp = sendState.statusTimestamp
            sendStatus.deliveryStatus = deliveryStatus

            outgoingDetails.sendStatus.append(sendStatus)

            if sendState.wasSentByUD {
                wasAnySendSealedSender = true
            }
        }

        if perRecipientErrors.isEmpty {
            return .success((
                outgoingDetails: outgoingDetails,
                wasAnySendSealedSender: wasAnySendSealedSender
            ))
        } else {
            return .partialFailure(
                (
                    outgoingDetails: outgoingDetails,
                    wasAnySendSealedSender: wasAnySendSealedSender
                ),
                perRecipientErrors
            )
        }
    }

    // MARK: - Restoring

    /// An error representing a `TSMessage` failing to insert, since
    /// ``TSMessage/anyInsert`` fails silently.
    private struct MessageInsertionError: Error {}

    func restoreMessage(
        _ chatItem: BackupProto_ChatItem,
        isPastRevision: Bool,
        hasPastRevisions: Bool,
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatItemRestoringContext
    ) -> MessageBackup.RestoreInteractionResult<EditHistoryMessageType> {
        guard let chatItemType = chatItem.item else {
            // Unrecognized item type!
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.chatItemMissingItem),
                chatItem.id
            )])
        }

        let outgoingDetails: BackupProto_ChatItem.OutgoingMessageDetails
        switch chatItem.directionalDetails {
        case .outgoing(let _outgoingDetails):
            outgoingDetails = _outgoingDetails
        case nil, .incoming, .directionless:
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.revisionOfOutgoingMessageMissingOutgoingDetails),
                chatItem.id
            )])
        }

        var partialErrors = [RestoreFrameError]()

        guard
            let contents = contentsArchiver.restoreContents(
                chatItemType,
                chatItemId: chatItem.id,
                chatThread: chatThread,
                context: context
            ).unwrap(partialErrors: &partialErrors)
        else {
            return .messageFailure(partialErrors)
        }

        let editState: TSEditState = {
            if isPastRevision {
                return .pastRevision
            } else if hasPastRevisions {
                // Outgoing messages are implicitly read.
                return .latestRevisionRead
            } else {
                return .none
            }
        }()

        guard
            let outgoingMessage = restoreAndInsertOutgoingMessage(
                chatItem: chatItem,
                contents: contents,
                outgoingDetails: outgoingDetails,
                editState: editState,
                context: context,
                chatThread: chatThread
            ).unwrap(partialErrors: &partialErrors)
        else {
            return .messageFailure(partialErrors)
        }

        guard
            contentsArchiver.restoreDownstreamObjects(
                message: outgoingMessage,
                thread: chatThread,
                chatItemId: chatItem.id,
                restoredContents: contents,
                context: context
            ).unwrap(partialErrors: &partialErrors)
        else {
            return .messageFailure(partialErrors)
        }

        if partialErrors.isEmpty {
            return .success(outgoingMessage)
        } else {
            return .partialRestore(outgoingMessage, partialErrors)
        }
    }

    private func restoreAndInsertOutgoingMessage(
        chatItem: BackupProto_ChatItem,
        contents: MessageBackup.RestoredMessageContents,
        outgoingDetails: BackupProto_ChatItem.OutgoingMessageDetails,
        editState: TSEditState,
        context: MessageBackup.ChatItemRestoringContext,
        chatThread: MessageBackup.ChatThread
    ) -> MessageBackup.RestoreInteractionResult<TSOutgoingMessage> {
        guard SDS.fitsInInt64(chatItem.dateSent), chatItem.dateSent > 0 else {
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.chatItemInvalidDateSent),
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

        var partialErrors = [RestoreFrameError]()

        var recipientAddressStates = [MessageBackup.InteropAddress: TSOutgoingMessageRecipientState]()
        for sendStatus in outgoingDetails.sendStatus {
            let recipientAddress: MessageBackup.InteropAddress
            let recipientID = sendStatus.destinationRecipientId
            switch context.recipientContext[recipientID] {
            case .contact(let address):
                recipientAddress = address.asInteropAddress()
            case .localAddress:
                recipientAddress = context.recipientContext.localIdentifiers.aciAddress
            case .none:
                // Missing recipient! Fail this one recipient but keep going.
                partialErrors.append(.restoreFrameError(
                    .invalidProtoData(.recipientIdNotFound(recipientID)),
                    chatItem.id
                ))
                continue
            case .group, .distributionList, .releaseNotesChannel, .callLink:
                // Recipients can only be contacts.
                partialErrors.append(.restoreFrameError(
                    .invalidProtoData(.outgoingNonContactMessageRecipient),
                    chatItem.id
                ))
                continue
            }

            guard
                let recipientState = recipientState(
                    for: sendStatus,
                    partialErrors: &partialErrors,
                    chatItemId: chatItem.id
                )
            else {
                continue
            }

            recipientAddressStates[recipientAddress] = recipientState
        }

        if recipientAddressStates.isEmpty && outgoingDetails.sendStatus.isEmpty.negated {
            // We put up with some failures, but if we get no recipients at all
            // fail the whole thing.
            return .messageFailure(partialErrors)
        }

        let expireStartDate: UInt64
        if chatItem.hasExpireStartDate {
            expireStartDate = chatItem.expireStartDate
        } else if
            expiresInSeconds > 0,
            TSOutgoingMessage.isEligibleToStartExpireTimer(recipientStates: Array(recipientAddressStates.values))
        {
            // If there is an expire timer and the message is eligible to start expiring,
            // set the expire start time to now even if unset in the proto.
            expireStartDate = dateProvider().ows_millisecondsSince1970
        } else {
            expireStartDate = 0
        }

        let outgoingMessage: TSOutgoingMessage = {
            /// A "base" message builder, onto which we attach the data we
            /// unwrap from `contents`.
            let outgoingMessageBuilder = TSOutgoingMessageBuilder(
                thread: chatThread.tsThread,
                timestamp: chatItem.dateSent,
                receivedAtTimestamp: nil,
                messageBody: nil,
                bodyRanges: nil,
                editState: editState,
                expiresInSeconds: expiresInSeconds,
                // Backed up messages don't set the chat timer; version is irrelevant.
                expireTimerVersion: nil,
                expireStartedAt: expireStartDate,
                isVoiceMessage: false,
                groupMetaMessage: .unspecified,
                isSmsMessageRestoredFromBackup: chatItem.sms,
                isViewOnceMessage: false,
                isViewOnceComplete: false,
                wasRemotelyDeleted: false,
                groupChangeProtoData: nil,
                // We never restore stories.
                storyAuthorAci: nil,
                storyTimestamp: nil,
                storyReactionEmoji: nil,
                quotedMessage: nil,
                contactShare: nil,
                linkPreview: nil,
                messageSticker: nil,
                giftBadge: nil
            )

            switch contents {
            case .archivedPayment(let archivedPayment):
                return OWSOutgoingArchivedPaymentMessage(
                    outgoingArchivedPaymentMessageWith: outgoingMessageBuilder,
                    amount: archivedPayment.amount,
                    fee: archivedPayment.fee,
                    note: archivedPayment.note,
                    recipientAddressStates: recipientAddressStates
                )
            case .remoteDeleteTombstone:
                outgoingMessageBuilder.wasRemotelyDeleted = true
            case .text(let text):
                outgoingMessageBuilder.messageBody = text.body?.text
                outgoingMessageBuilder.bodyRanges = text.body?.ranges
                outgoingMessageBuilder.quotedMessage = text.quotedMessage
                outgoingMessageBuilder.linkPreview = text.linkPreview
                outgoingMessageBuilder.isVoiceMessage = text.isVoiceMessage
            case .contactShare(let contactShare):
                outgoingMessageBuilder.contactShare = contactShare.contact
            case .stickerMessage(let stickerMessage):
                outgoingMessageBuilder.messageSticker = stickerMessage.sticker
            case .giftBadge(let giftBadge):
                outgoingMessageBuilder.giftBadge = giftBadge.giftBadge
            case .viewOnceMessage(let viewOnceMessage):
                outgoingMessageBuilder.isViewOnceMessage = true
                switch viewOnceMessage.state {
                case .unviewed:
                    outgoingMessageBuilder.isViewOnceComplete = false
                case .complete:
                    outgoingMessageBuilder.isViewOnceComplete = true
                }
            }

            return TSOutgoingMessage(
                outgoingMessageWith: outgoingMessageBuilder,
                recipientAddressStates: recipientAddressStates
            )
        }()

        do {
            try interactionStore.insert(
                outgoingMessage,
                in: chatThread,
                chatId: chatItem.typedChatId,
                directionalDetails: outgoingDetails,
                context: context
            )
        } catch let error {
            return .messageFailure(partialErrors + [.restoreFrameError(.databaseInsertionFailed(error), chatItem.id)])
        }

        guard outgoingMessage.sqliteRowId != nil else {
            // Failed insert!
            return .messageFailure(partialErrors + [.restoreFrameError(
                .databaseInsertionFailed(MessageInsertionError()),
                chatItem.id
            )])
        }

        if partialErrors.isEmpty {
            return .success(outgoingMessage)
        } else {
            return .partialRestore(outgoingMessage, partialErrors)
        }
    }

    private func recipientState(
        for sendStatus: BackupProto_SendStatus,
        partialErrors: inout [RestoreFrameError],
        chatItemId: MessageBackup.ChatItemId
    ) -> TSOutgoingMessageRecipientState? {
        guard let deliveryStatus = sendStatus.deliveryStatus else {
            partialErrors.append(.restoreFrameError(
                .invalidProtoData(.unrecognizedMessageSendStatus),
                chatItemId
            ))
            return nil
        }

        let recipientStatus: OWSOutgoingMessageRecipientStatus
        var wasSentByUD: Bool = false
        var errorCode: Int?
        switch deliveryStatus {
        case .pending(_):
            recipientStatus = .pending
        case .sent(let sent):
            recipientStatus = .sent
            wasSentByUD = sent.sealedSender
        case .delivered(let delivered):
            recipientStatus = .delivered
            wasSentByUD = delivered.sealedSender
        case .read(let read):
            recipientStatus = .read
            wasSentByUD = read.sealedSender
        case .viewed(let viewed):
            recipientStatus = .viewed
            wasSentByUD = viewed.sealedSender
        case .skipped(_):
            recipientStatus = .skipped
        case .failed(let failed):
            let failureErrorCode: MessageBackup.SendStatusFailureErrorCode = {
                switch failed.reason {
                case .UNRECOGNIZED, .unknown: return .unknown
                case .identityKeyMismatch: return .identityKeyMismatch
                case .network: return .networkError
                }
            }()

            recipientStatus = .failed
            errorCode = failureErrorCode.rawValue
        }

        return TSOutgoingMessageRecipientState(
            status: recipientStatus,
            statusTimestamp: sendStatus.timestamp,
            wasSentByUD: wasSentByUD,
            errorCode: errorCode
        )
    }
}
