//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

internal class MessageBackupTSOutgoingMessageArchiver: MessageBackupInteractionArchiver {

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

    static func canArchiveInteraction(_ interaction: TSInteraction) -> Bool {
        return interaction is TSOutgoingMessage
    }

    func archiveInteraction(
        _ interaction: TSInteraction,
        context: MessageBackup.ChatArchivingContext,
        tx: DBReadTransaction
    ) -> MessageBackup.ArchiveInteractionResult<Details> {
        guard let message = interaction as? TSOutgoingMessage else {
            // Should be impossible.
            return .completeFailure(OWSAssertionError("Invalid interaction type"))
        }

        var partialErrors = [MessageBackupChatItemArchiver.ArchiveMultiFrameResult.Error]()

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

        guard let author = context.recipientContext[.localAddress] else {
            partialErrors.append(.init(
                objectId: interaction.chatItemId,
                error: .referencedIdMissing(.recipient(.localAddress))
            ))
            return .messageFailure(partialErrors)
        }

        let contentsResult = contentsArchiver.archiveMessageContents(
            message,
            context: context.recipientContext,
            tx: tx
        )
        let type: MessageBackup.ChatItemMessageType
        switch contentsResult.bubbleUp(Details.self, partialErrors: &partialErrors) {
        case .continue(let t):
            type = t
        case .bubbleUpError(let errorResult):
            return errorResult
        }

        let details = Details(
            author: author,
            directionalDetails: directionalDetails,
            expireStartDate: message.expireStartedAt,
            expiresInMs: UInt64(message.expiresInSeconds) * 1000,
            isSealedSender: wasAnySendSealedSender,
            type: type
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
        var perRecipientErrors = [MessageBackup.ArchiveInteractionResult<Details.DirectionalDetails>.Error]()

        var wasAnySendSealedSender = false
        let outgoingMessageProtoBuilder = BackupProtoChatItemOutgoingMessageDetails.builder()

        for (address, sendState) in message.recipientAddressStates ?? [:] {
            guard let recipientAddress = address.asSingleServiceIdBackupAddress()?.asArchivingAddress() else {
                perRecipientErrors.append(.init(
                    objectId: message.chatItemId,
                    error: .invalidMessageAddress
                ))
                continue
            }
            guard let recipientId = recipientContext[recipientAddress] else {
                perRecipientErrors.append(.init(
                    objectId: message.chatItemId,
                    error: .referencedIdMissing(.recipient(recipientAddress))
                ))
                continue
            }
            var isNetworkFailure = false
            var isIdentityKeyMismatchFailure = false
            let protoDeliveryStatus: BackupProtoSendStatusStatus
            let statusTimestamp: UInt64
            switch sendState.state {
            case OWSOutgoingMessageRecipientState.sent:
                if let readTimestamp = sendState.readTimestamp {
                    protoDeliveryStatus = .read
                    statusTimestamp = readTimestamp.uint64Value
                } else if let viewedTimestamp = sendState.viewedTimestamp {
                    protoDeliveryStatus = .viewed
                    statusTimestamp = viewedTimestamp.uint64Value
                } else if let deliveryTimestamp = sendState.deliveryTimestamp {
                    protoDeliveryStatus = .delivered
                    statusTimestamp = deliveryTimestamp.uint64Value
                } else {
                    protoDeliveryStatus = .sent
                    statusTimestamp = message.timestamp
                }
            case OWSOutgoingMessageRecipientState.failed:
                // TODO: identify specific errors. for now call everything network.
                isNetworkFailure = true
                isIdentityKeyMismatchFailure = false
                protoDeliveryStatus = .failed
                statusTimestamp = message.timestamp
            case OWSOutgoingMessageRecipientState.sending, OWSOutgoingMessageRecipientState.pending:
                protoDeliveryStatus = .pending
                statusTimestamp = message.timestamp
            case OWSOutgoingMessageRecipientState.skipped:
                protoDeliveryStatus = .skipped
                statusTimestamp = message.timestamp
            }

            let sendStatusBuilder: BackupProtoSendStatusBuilder = BackupProtoSendStatus.builder(
                recipientID: recipientId.value,
                networkFailure: isNetworkFailure,
                identityKeyMismatch: isIdentityKeyMismatchFailure,
                sealedSender: sendState.wasSentByUD.negated,
                lastStatusUpdateTimestamp: statusTimestamp
            )
            sendStatusBuilder.setDeliveryStatus(protoDeliveryStatus)
            do {
                let sendStatus = try sendStatusBuilder.build()
                outgoingMessageProtoBuilder.addSendStatus(sendStatus)
            } catch let error {
                perRecipientErrors.append(
                    .init(objectId: message.chatItemId, error: .protoSerializationError(error))
                )
            }

            if sendState.wasSentByUD.negated {
                wasAnySendSealedSender = true
            }
        }

        let outgoingMessageProto: BackupProtoChatItemOutgoingMessageDetails
        do {
            outgoingMessageProto = try outgoingMessageProtoBuilder.build()
        } catch let error {
            return .messageFailure(
                [.init(objectId: message.chatItemId, error: .protoSerializationError(error))]
                + perRecipientErrors
            )
        }

        if perRecipientErrors.isEmpty {
            return .success(.init(
                details: .outgoing(outgoingMessageProto),
                wasAnySendSealedSender: wasAnySendSealedSender
            ))
        } else {
            return .partialFailure(
                .init(
                    details: .outgoing(outgoingMessageProto),
                    wasAnySendSealedSender: wasAnySendSealedSender
                ),
                perRecipientErrors
            )
        }
    }

    // MARK: - Restoring

    static func canRestoreChatItem(_ chatItem: BackupProtoChatItem) -> Bool {
        // TODO: will e.g. info messages have an incoming or outgoing field set?
        // if so we need some other differentiator.
        return chatItem.outgoing != nil
    }

    func restoreChatItem(
        _ chatItem: BackupProtoChatItem,
        thread: MessageBackup.ChatThread,
        context: MessageBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) -> MessageBackup.RestoreInteractionResult<Void> {
        guard let outgoingDetails = chatItem.outgoing else {
            // Should be impossible.
            return .messageFailure([.invalidProtoData])
        }

        guard let messageType = chatItem.messageType else {
            // Unrecognized item type!
            return .messageFailure([.unknownFrameType])
        }

        var partialErrors = [MessageBackup.RestoringFrameError]()

        let contentsResult = contentsArchiver.restoreContents(
            messageType,
            thread: thread,
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
            thread: thread
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
            partialErrors.append(.databaseInsertionFailed(error))
            return .messageFailure(partialErrors)
        }

        let downstreamObjectsResult = contentsArchiver.restoreDownstreamObjects(
            message: message,
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
