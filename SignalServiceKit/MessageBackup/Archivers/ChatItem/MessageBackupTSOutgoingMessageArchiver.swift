//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

internal class MessageBackupTSOutgoingMessageArchiver: MessageBackupInteractionArchiver {
    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<MessageBackup.InteractionUniqueId>

    static let archiverType: MessageBackup.ChatItemArchiverType = .outgoingMessage

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

    func archiveInteraction(
        _ interaction: TSInteraction,
        context: MessageBackup.ChatArchivingContext,
        tx: DBReadTransaction
    ) -> MessageBackup.ArchiveInteractionResult<Details> {
        guard let message = interaction as? TSOutgoingMessage else {
            // Should be impossible.
            return .completeFailure(.fatalArchiveError(.developerError(
                OWSAssertionError("Invalid interaction type")
            )))
        }

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
        var outgoingMessage = BackupProto.ChatItem.OutgoingMessageDetails()

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
            var isNetworkFailure = false
            var isIdentityKeyMismatchFailure = false
            let protoDeliveryStatus: BackupProto.SendStatus.Status
            let statusTimestamp: UInt64
            switch sendState.state {
            case OWSOutgoingMessageRecipientState.sent:
                if let readTimestamp = sendState.readTimestamp {
                    protoDeliveryStatus = .READ
                    statusTimestamp = readTimestamp.uint64Value
                } else if let viewedTimestamp = sendState.viewedTimestamp {
                    protoDeliveryStatus = .VIEWED
                    statusTimestamp = viewedTimestamp.uint64Value
                } else if let deliveryTimestamp = sendState.deliveryTimestamp {
                    protoDeliveryStatus = .DELIVERED
                    statusTimestamp = deliveryTimestamp.uint64Value
                } else {
                    protoDeliveryStatus = .SENT
                    statusTimestamp = message.timestamp
                }
            case OWSOutgoingMessageRecipientState.failed:
                // TODO: identify specific errors. for now call everything network.
                isNetworkFailure = true
                isIdentityKeyMismatchFailure = false
                protoDeliveryStatus = .FAILED
                statusTimestamp = message.timestamp
            case OWSOutgoingMessageRecipientState.sending, OWSOutgoingMessageRecipientState.pending:
                protoDeliveryStatus = .PENDING
                statusTimestamp = message.timestamp
            case OWSOutgoingMessageRecipientState.skipped:
                protoDeliveryStatus = .SKIPPED
                statusTimestamp = message.timestamp
            }

            var sendStatus = BackupProto.SendStatus(
                recipientId: recipientId.value,
                deliveryStatus: protoDeliveryStatus,
                networkFailure: isNetworkFailure,
                identityKeyMismatch: isIdentityKeyMismatchFailure,
                sealedSender: sendState.wasSentByUD.negated,
                lastStatusUpdateTimestamp: statusTimestamp
            )

            outgoingMessage.sendStatus.append(sendStatus)

            if sendState.wasSentByUD.negated {
                wasAnySendSealedSender = true
            }
        }

        if perRecipientErrors.isEmpty {
            return .success(.init(
                details: .outgoing(outgoingMessage),
                wasAnySendSealedSender: wasAnySendSealedSender
            ))
        } else {
            return .partialFailure(
                .init(
                    details: .outgoing(outgoingMessage),
                    wasAnySendSealedSender: wasAnySendSealedSender
                ),
                perRecipientErrors
            )
        }
    }

    // MARK: - Restoring

    func restoreChatItem(
        _ chatItem: BackupProto.ChatItem,
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) -> MessageBackup.RestoreInteractionResult<Void> {
        let outgoingDetails: BackupProto.ChatItem.OutgoingMessageDetails
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
            return .messageFailure([.restoreFrameError(.invalidProtoData(.unrecognizedChatItemType), chatItem.id)])
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
