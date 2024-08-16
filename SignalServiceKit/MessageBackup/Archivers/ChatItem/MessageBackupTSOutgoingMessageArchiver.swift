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

        let transcriptResult = RestoredSentMessageTranscript.from(
            chatItem: chatItem,
            contents: contents,
            outgoingDetails: outgoingDetails,
            context: context,
            chatThread: chatThread
        )

        guard let transcript = transcriptResult.unwrap(partialErrors: &partialErrors) else {
            return .messageFailure(partialErrors)
        }

        let messageResult = sentMessageTranscriptReceiver.process(
            transcript,
            localIdentifiers: context.recipientContext.localIdentifiers,
            tx: tx
        )
        let message: TSOutgoingMessage
        switch messageResult {
        case .success(let outgoingMessage):
            guard let outgoingMessage else {
                return .messageFailure(partialErrors)
            }
            message = outgoingMessage
        case .failure(let error):
            partialErrors.append(.restoreFrameError(.databaseInsertionFailed(error), chatItem.id))
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
}

// MARK: -

/// Restoring an outgoing message from a backup isn't any different from learning about
/// an outgoing message sent on a linked device and synced to the local device.
///
/// So we represent restored messages as "transcripts" that we can plug into the same
/// transcript processing pipes as synced message transcripts.
private class RestoredSentMessageTranscript: SentMessageTranscript {

    let type: SentMessageTranscriptType

    let timestamp: UInt64

    // Not applicable
    var requiredProtocolVersion: UInt32? { nil }

    let recipientStates: [MessageBackup.InteropAddress: TSOutgoingMessageRecipientState]

    static func from(
        chatItem: BackupProto_ChatItem,
        contents: MessageBackup.RestoredMessageContents,
        outgoingDetails: BackupProto_ChatItem.OutgoingMessageDetails,
        context: MessageBackup.ChatRestoringContext,
        chatThread: MessageBackup.ChatThread
    ) -> MessageBackup.RestoreInteractionResult<RestoredSentMessageTranscript> {

        let expirationToken: DisappearingMessageToken = .token(forProtoExpireTimerMillis: chatItem.expiresInMs)

        let target: SentMessageTranscriptTarget
        switch chatThread.threadType {
        case .contact(let contactThread):
            target = .contact(contactThread, expirationToken)
        case .groupV2(let groupThread):
            target = .group(groupThread)
        }

        let messageType: SentMessageTranscriptType
        switch contents {
        case .text(let text):
            messageType = restoreMessageTranscript(
                contents: text,
                target: target,
                chatItem: chatItem,
                expirationToken: expirationToken
            )
        case .archivedPayment(let archivedPayment):
            messageType = restorePaymentTranscript(
                payment: archivedPayment,
                target: target,
                chatItem: chatItem,
                expirationToken: expirationToken
            )
        }

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
                let recipientState = recipientState(
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

        let transcript = RestoredSentMessageTranscript(
            type: messageType,
            timestamp: chatItem.dateSent,
            recipientStates: recipientStates
        )
        if partialErrors.isEmpty {
            return .success(transcript)
        } else {
            return .partialRestore(transcript, partialErrors)
        }
    }

    private static func restoreMessageTranscript(
        contents: MessageBackup.RestoredMessageContents.Text,
        target: SentMessageTranscriptTarget,
        chatItem: BackupProto_ChatItem,
        expirationToken: DisappearingMessageToken
    ) -> SentMessageTranscriptType {
        let messageParams = SentMessageTranscriptType.Message(
            target: target,
            body: contents.body.text,
            bodyRanges: contents.body.ranges,
            // TODO: [Backups] Attachments
            attachmentPointerProtos: [],
            // TODO: [Backups] Handle attachments in quotes
            makeQuotedMessageBuilder: { [contents] _ in
                contents.quotedMessage.map {
                    return OwnedAttachmentBuilder<TSQuotedMessage>.withoutFinalizer($0)
                }
            },
            // TODO: [Backups] Contact message
            makeContactBuilder: { _ in nil },
            // TODO: [Backups] linkPreview message
            makeLinkPreviewBuilder: { _ in nil },
            // TODO: [Backups] Gift badge message
            giftBadge: nil,
            // TODO: [Backups] Sticker message
            makeMessageStickerBuilder: { _ in nil },
            // TODO: [Backups] isViewOnceMessage
            isViewOnceMessage: false,
            expirationStartedAt: chatItem.expireStartDate,
            expirationDurationSeconds: expirationToken.durationSeconds,
            // We never restore stories.
            storyTimestamp: nil,
            storyAuthorAci: nil
        )

        return .message(messageParams)
    }

    private static func restorePaymentTranscript(
        payment: MessageBackup.RestoredMessageContents.Payment,
        target: SentMessageTranscriptTarget,
        chatItem: BackupProto_ChatItem,
        expirationToken: DisappearingMessageToken
    ) -> SentMessageTranscriptType {
        return .archivedPayment(
            SentMessageTranscriptType.ArchivedPayment(
                target: target,
                amount: payment.amount,
                fee: payment.fee,
                note: payment.note,
                expirationStartedAt: chatItem.expireStartDate,
                expirationDurationSeconds: expirationToken.durationSeconds
            )
        )
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
        case .skipped(let skipped):
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

    private init(
        type: SentMessageTranscriptType,
        timestamp: UInt64,
        recipientStates: [MessageBackup.InteropAddress: TSOutgoingMessageRecipientState]
    ) {
        self.type = type
        self.timestamp = timestamp
        self.recipientStates = recipientStates
    }
}
