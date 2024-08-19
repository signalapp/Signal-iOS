//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

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

// MARK: -

class MessageBackupTSOutgoingMessageArchiver: MessageBackupProtoArchiver {
    typealias Details = MessageBackup.InteractionArchiveDetails

    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<MessageBackup.InteractionUniqueId>

    private let contentsArchiver: MessageBackupTSMessageContentsArchiver
    private let interactionStore: InteractionStore
    private let sentMessageTranscriptReceiver: SentMessageTranscriptReceiver

    internal init(
        contentsArchiver: MessageBackupTSMessageContentsArchiver,
        interactionStore: InteractionStore,
        sentMessageTranscriptReceiver: SentMessageTranscriptReceiver
    ) {
        self.contentsArchiver = contentsArchiver
        self.interactionStore = interactionStore
        self.sentMessageTranscriptReceiver = sentMessageTranscriptReceiver
    }

    // MARK: - Archiving

    func archiveOutgoingMessage(
        _ message: TSOutgoingMessage,
        thread _: TSThread,
        context: MessageBackup.ChatArchivingContext,
        tx: DBReadTransaction
    ) -> MessageBackup.ArchiveInteractionResult<Details> {
        var partialErrors = [ArchiveFrameError]()

        let wasAnySendSealedSender: Bool
        let directionalDetails: Details.DirectionalDetails
        switch buildOutgoingMessageDetails(
            message,
            recipientContext: context.recipientContext
        ).bubbleUp(Details.self, partialErrors: &partialErrors) {
        case .continue(let details):
            directionalDetails = details.details
            wasAnySendSealedSender = details.wasAnySendSealedSender
        case .bubbleUpError(let errorResult):
            return errorResult
        }

        let contentsResult = contentsArchiver.archiveMessageContents(
            message,
            context: context.recipientContext,
            tx: tx
        )
        let chatItemType: MessageBackup.InteractionArchiveDetails.ChatItemType
        switch contentsResult.bubbleUp(Details.self, partialErrors: &partialErrors) {
        case .continue(let t):
            chatItemType = t
        case .bubbleUpError(let errorResult):
            return errorResult
        }

        let details = Details(
            author: context.recipientContext.localRecipientId,
            directionalDetails: directionalDetails,
            dateCreated: message.timestamp,
            expireStartDate: message.expireStartedAt,
            expiresInMs: UInt64(message.expiresInSeconds) * 1000,
            isSealedSender: wasAnySendSealedSender,
            chatItemType: chatItemType
        )
        if partialErrors.isEmpty {
            return .success(details)
        } else {
            return .partialFailure(details, partialErrors)
        }
    }

    struct OutgoingMessageDetails {
        let details: Details.DirectionalDetails
        let wasAnySendSealedSender: Bool
    }

    private func buildOutgoingMessageDetails(
        _ message: TSOutgoingMessage,
        recipientContext: MessageBackup.RecipientArchivingContext
    ) -> MessageBackup.ArchiveInteractionResult<OutgoingMessageDetails> {
        var perRecipientErrors = [ArchiveFrameError]()

        var wasAnySendSealedSender = false
        var outgoingMessage = BackupProto_ChatItem.OutgoingMessageDetails()

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
            let statusTimestamp: UInt64
            switch sendState.state {
            case OWSOutgoingMessageRecipientState.sent:

                if let readTimestamp = sendState.readTimestamp {
                    var readStatus = BackupProto_SendStatus.Read()
                    readStatus.sealedSender = sendState.wasSentByUD

                    deliveryStatus = .read(readStatus)
                    statusTimestamp = readTimestamp.uint64Value
                } else if let viewedTimestamp = sendState.viewedTimestamp {
                    var viewedStatus = BackupProto_SendStatus.Viewed()
                    viewedStatus.sealedSender = sendState.wasSentByUD

                    deliveryStatus = .viewed(viewedStatus)
                    statusTimestamp = viewedTimestamp.uint64Value
                } else if let deliveryTimestamp = sendState.deliveryTimestamp {
                    var deliveredStatus = BackupProto_SendStatus.Delivered()
                    deliveredStatus.sealedSender = sendState.wasSentByUD

                    deliveryStatus = .delivered(deliveredStatus)
                    statusTimestamp = deliveryTimestamp.uint64Value
                } else {
                    var sentStatus = BackupProto_SendStatus.Sent()
                    sentStatus.sealedSender = sendState.wasSentByUD

                    deliveryStatus = .sent(sentStatus)
                    statusTimestamp = message.timestamp
                }
            case OWSOutgoingMessageRecipientState.failed:
                var failedStatus = BackupProto_SendStatus.Failed()
                failedStatus.reason = { () -> BackupProto_SendStatus.Failed.FailureReason in
                    guard let errorCode = sendState.errorCode?.intValue else {
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
                statusTimestamp = message.timestamp
            case OWSOutgoingMessageRecipientState.sending, OWSOutgoingMessageRecipientState.pending:
                deliveryStatus = .pending(BackupProto_SendStatus.Pending())
                statusTimestamp = message.timestamp
            case OWSOutgoingMessageRecipientState.skipped:
                deliveryStatus = .skipped(BackupProto_SendStatus.Skipped())
                statusTimestamp = message.timestamp
            }

            var sendStatus = BackupProto_SendStatus()
            sendStatus.recipientID = recipientId.value
            sendStatus.timestamp = statusTimestamp
            sendStatus.deliveryStatus = deliveryStatus

            outgoingMessage.sendStatus.append(sendStatus)

            if sendState.wasSentByUD.negated {
                wasAnySendSealedSender = true
            }
        }

        if perRecipientErrors.isEmpty {
            return .success(OutgoingMessageDetails(
                details: .outgoing(outgoingMessage),
                wasAnySendSealedSender: wasAnySendSealedSender
            ))
        } else {
            return .partialFailure(
                OutgoingMessageDetails(
                    details: .outgoing(outgoingMessage),
                    wasAnySendSealedSender: wasAnySendSealedSender
                ),
                perRecipientErrors
            )
        }
    }

    // MARK: - Restoring

    func restoreChatItem(
        _ chatItem: BackupProto_ChatItem,
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) -> MessageBackup.RestoreInteractionResult<Void> {
        let outgoingDetails: BackupProto_ChatItem.OutgoingMessageDetails
        switch chatItem.directionalDetails {
        case .outgoing(let backupProtoChatItemOutgoingMessageDetails):
            outgoingDetails = backupProtoChatItemOutgoingMessageDetails
        case nil, .incoming, .directionless:
            // Should be impossible.
            return .messageFailure([.restoreFrameError(
                .developerError(OWSAssertionError("OutgoingMessageArchiver given non-outgoing message!")),
                chatItem.id
            )])
        }

        guard let chatItemType = chatItem.item else {
            // Unrecognized item type!
            return .messageFailure([.restoreFrameError(.invalidProtoData(.chatItemMissingItem), chatItem.id)])
        }

        var partialErrors = [MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>]()

        let contentsResult = contentsArchiver.restoreContents(
            chatItemType,
            chatItemId: chatItem.id,
            chatThread: chatThread,
            context: context,
            tx: tx
        )

        guard let contents = contentsResult.unwrap(partialErrors: &partialErrors) else {
            return .messageFailure(partialErrors)
        }

        let messageResult = self.restoreAndInsertMessage(
            chatItem: chatItem,
            contents: contents,
            outgoingDetails: outgoingDetails,
            context: context,
            chatThread: chatThread,
            tx: tx
        )

        guard let message = messageResult.unwrap(partialErrors: &partialErrors) else {
            return .messageFailure(partialErrors)
        }

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

        if partialErrors.isEmpty {
            return .success(())
        } else {
            return .partialRestore((), partialErrors)
        }
    }

    private func restoreAndInsertMessage(
        chatItem: BackupProto_ChatItem,
        contents: MessageBackup.RestoredMessageContents,
        outgoingDetails: BackupProto_ChatItem.OutgoingMessageDetails,
        context: MessageBackup.ChatRestoringContext,
        chatThread: MessageBackup.ChatThread,
        tx: DBWriteTransaction
    ) -> MessageBackup.RestoreInteractionResult<TSOutgoingMessage> {

        guard SDS.fitsInInt64(chatItem.dateSent), chatItem.dateSent > 0 else {
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.chatItemInvalidDateSent),
                chatItem.id
            )])
        }

        let expirationToken: DisappearingMessageToken = .token(forProtoExpireTimerMillis: chatItem.expiresInMs)

        var partialErrors = [MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>]()

        var recipientStates = [MessageBackup.InteropAddress: TSOutgoingMessageRecipientState]()
        for sendStatus in outgoingDetails.sendStatus {
            let recipientAddress: MessageBackup.InteropAddress
            let recipientID = sendStatus.destinationRecipientId
            switch context.recipientContext[recipientID] {
            case .contact(let address):
                recipientAddress = address.asInteropAddress()
            case .none:
                // Missing recipient! Fail this one recipient but keep going.
                partialErrors.append(.restoreFrameError(
                    .invalidProtoData(.recipientIdNotFound(recipientID)),
                    chatItem.id
                ))
                continue
            case .localAddress, .group, .distributionList, .releaseNotesChannel:
                // Recipients can only be contacts.
                partialErrors.append(.restoreFrameError(
                    .invalidProtoData(.outgoingNonContactMessageRecipient),
                    chatItem.id
                ))
                continue
            }

            guard
                let recipientState = Self.recipientState(
                    for: sendStatus,
                    partialErrors: &partialErrors,
                    chatItemId: chatItem.id
                )
            else {
                continue
            }

            recipientStates[recipientAddress] = recipientState
        }

        if recipientStates.isEmpty && outgoingDetails.sendStatus.isEmpty.negated {
            // We put up with some failures, but if we get no recipients at all
            // fail the whole thing.
            return .messageFailure(partialErrors)
        }

        let insertMessageResult: MessageBackup.RestoreInteractionResult<TSOutgoingMessage>
        switch contents {
        case .text(let text):
            insertMessageResult = restoreTextMessage(
                contents: text,
                chatThread: chatThread,
                chatItem: chatItem,
                expirationToken: expirationToken,
                tx: tx
            )
        case .archivedPayment(let archivedPayment):
            insertMessageResult = restorePaymentMessage(
                payment: archivedPayment,
                chatThread: chatThread,
                chatItem: chatItem,
                expirationToken: expirationToken,
                tx: tx
            )
        }

        guard let message = insertMessageResult.unwrap(partialErrors: &partialErrors) else {
            return .messageFailure(partialErrors)
        }

        guard message.sqliteRowId != nil else {
            // Failed insert!
            return .messageFailure(partialErrors + [.restoreFrameError(
                .databaseInsertionFailed(MessageInsertionError()),
                chatItem.id
            )])
        }

        interactionStore.updateRecipientsFromNonLocalDevice(
            message,
            recipientStates: recipientStates,
            isSentUpdate: false,
            tx: tx
        )
        if partialErrors.isEmpty {
            return .success(message)
        } else {
            return .partialRestore(message, partialErrors)
        }
    }

    /// TSMessage.insert doesn't give us useful errors when it fails to insert.
    /// Use this instead.
    private struct MessageInsertionError: Error {}

    private func restoreTextMessage(
        contents: MessageBackup.RestoredMessageContents.Text,
        chatThread: MessageBackup.ChatThread,
        chatItem: BackupProto_ChatItem,
        expirationToken: DisappearingMessageToken,
        tx: DBWriteTransaction
    ) -> MessageBackup.RestoreInteractionResult<TSOutgoingMessage> {
        let outgoingMessageBuilder = TSOutgoingMessageBuilder(
            thread: chatThread.tsThread,
            timestamp: chatItem.dateSent,
            receivedAtTimestamp: nil,
            messageBody: contents.body.text,
            bodyRanges: contents.body.ranges,
            editState: .none, // TODO: [Backups] Back up outgoing message edt state
            expiresInSeconds: expirationToken.durationSeconds,
            expireStartedAt: chatItem.expireStartDate,
            // TODO: [Backups] set true if this has a single body attachment w/ voice message flag
            isVoiceMessage: false,
            groupMetaMessage: .unspecified,
            // TODO: [Backups] pass along if this is view once after proto field is added
            isViewOnceMessage: false,
            changeActionsProtoData: nil,
            // We never restore stories.
            storyAuthorAci: nil,
            storyTimestamp: nil,
            storyReactionEmoji: nil,
            // TODO: [Backups] restore gift badges
            giftBadge: nil
        )
        let outgoingMessage = interactionStore.buildOutgoingMessage(builder: outgoingMessageBuilder, tx: tx)
        interactionStore.insertInteraction(outgoingMessage, tx: tx)

        return .success(outgoingMessage)
    }

    private func restorePaymentMessage(
        payment: MessageBackup.RestoredMessageContents.Payment,
        chatThread: MessageBackup.ChatThread,
        chatItem: BackupProto_ChatItem,
        expirationToken: DisappearingMessageToken,
        tx: DBWriteTransaction
    ) -> MessageBackup.RestoreInteractionResult<TSOutgoingMessage> {
        let builder = OWSOutgoingArchivedPaymentMessageBuilder(
            thread: chatThread.tsThread,
            timestamp: chatItem.dateSent,
            amount: payment.amount,
            fee: payment.fee,
            note: payment.note,
            expirationStartedAt: chatItem.expireStartDate,
            expirationDurationSeconds: expirationToken.durationSeconds
        )

        let message = interactionStore.buildOutgoingArchivedPaymentMessage(builder: builder, tx: tx)
        interactionStore.insertInteraction(message, tx: tx)

        return .success(message)
    }

    private static func recipientState(
        for sendStatus: BackupProto_SendStatus,
        partialErrors: inout [MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>],
        chatItemId: MessageBackup.ChatItemId
    ) -> TSOutgoingMessageRecipientState? {
        guard let deliveryStatus = sendStatus.deliveryStatus else {
            partialErrors.append(.restoreFrameError(
                .invalidProtoData(.unrecognizedMessageSendStatus),
                chatItemId
            ))
            return nil
        }

        guard let recipientState = TSOutgoingMessageRecipientState() else {
            partialErrors.append(.restoreFrameError(
                .databaseInsertionFailed(OWSAssertionError("Unable to create recipient state!")),
                chatItemId
            ))
            return nil
        }

        switch deliveryStatus {
        case .pending:
            recipientState.state = .pending
        case .sent(let sent):
            recipientState.state = .sent
            recipientState.wasSentByUD = sent.sealedSender
        case .delivered(let delivered):
            recipientState.state = .sent
            recipientState.deliveryTimestamp = NSNumber(value: sendStatus.timestamp)
            recipientState.wasSentByUD = delivered.sealedSender
        case .read(let read):
            recipientState.state = .sent
            recipientState.readTimestamp = NSNumber(value: sendStatus.timestamp)
            recipientState.wasSentByUD = read.sealedSender
        case .viewed(let viewed):
            recipientState.state = .sent
            recipientState.viewedTimestamp = NSNumber(value: sendStatus.timestamp)
            recipientState.wasSentByUD = viewed.sealedSender
        case .skipped(_):
            recipientState.state = .skipped
        case .failed(let failed):
            let failureErrorCode: MessageBackup.SendStatusFailureErrorCode = {
                switch failed.reason {
                case .UNRECOGNIZED, .unknown: return .unknown
                case .identityKeyMismatch: return .identityKeyMismatch
                case .network: return .networkError
                }
            }()

            recipientState.state = .failed
            recipientState.errorCode = NSNumber(value: failureErrorCode.rawValue)
        }

        return recipientState
    }
}
