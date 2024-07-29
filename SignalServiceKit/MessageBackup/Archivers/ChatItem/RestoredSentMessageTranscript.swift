//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/// Restoring an outgoing message from a backup isn't any different from learning about
/// an outgoing message sent on a linked device and synced to the local device.
///
/// So we represent restored messages as "transcripts" that we can plug into the same
/// transcript processing pipes as synced message transcripts.
class RestoredSentMessageTranscript: SentMessageTranscript {

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
        guard let recipientState = TSOutgoingMessageRecipientState() else {
            partialErrors.append(.restoreFrameError(
                .databaseInsertionFailed(OWSAssertionError("Unable to create recipient state!")),
                chatItemId
            ))
            return nil
        }

        recipientState.wasSentByUD = sendStatus.sealedSender.negated

        switch sendStatus.deliveryStatus {
        case .unknown, .UNRECOGNIZED:
            partialErrors.append(.restoreFrameError(.invalidProtoData(.unrecognizedMessageSendStatus), chatItemId))
            return nil
        case .pending:
            recipientState.state = .pending
            recipientState.errorCode = nil
            return recipientState
        case .sent:
            recipientState.state = .sent
            recipientState.errorCode = nil
            return recipientState
        case .delivered:
            recipientState.state = .sent
            recipientState.deliveryTimestamp = NSNumber(value: sendStatus.lastStatusUpdateTimestamp)
            recipientState.errorCode = nil
            return recipientState
        case .read:
            recipientState.state = .sent
            recipientState.readTimestamp = NSNumber(value: sendStatus.lastStatusUpdateTimestamp)
            recipientState.errorCode = nil
            return recipientState
        case .viewed:
            recipientState.state = .sent
            recipientState.viewedTimestamp = NSNumber(value: sendStatus.lastStatusUpdateTimestamp)
            recipientState.errorCode = nil
            return recipientState
        case .skipped:
            recipientState.state = .skipped
            recipientState.errorCode = nil
            return recipientState
        case .failed:
            recipientState.state = .failed
            if sendStatus.identityKeyMismatch {
                // We want to explicitly represent identity key errors.
                // Other types we don't really care about.
                recipientState.errorCode = NSNumber(value: UntrustedIdentityError.errorCode)
            } else {
                recipientState.errorCode = NSNumber(value: OWSErrorCode.genericFailure.rawValue)
            }
            return recipientState
        }
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
