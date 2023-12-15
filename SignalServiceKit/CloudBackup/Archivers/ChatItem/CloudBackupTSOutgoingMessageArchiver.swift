//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

internal class CloudBackupTSOutgoingMessageArchiver: CloudBackupInteractionArchiver {

    private let contentsArchiver: CloudBackupTSMessageContentsArchiver
    private let interactionStore: InteractionStore

    internal init(
        contentsArchiver: CloudBackupTSMessageContentsArchiver,
        interactionStore: InteractionStore
    ) {
        self.contentsArchiver = contentsArchiver
        self.interactionStore = interactionStore
    }

    // MARK: - Archiving

    static func canArchiveInteraction(_ interaction: TSInteraction) -> Bool {
        return interaction is TSOutgoingMessage
    }

    func archiveInteraction(
        _ interaction: TSInteraction,
        context: CloudBackup.ChatArchivingContext,
        tx: DBReadTransaction
    ) -> CloudBackup.ArchiveInteractionResult<Details> {
        guard let message = interaction as? TSOutgoingMessage else {
            // Should be impossible.
            return .completeFailure(OWSAssertionError("Invalid interaction type"))
        }

        var partialErrors = [CloudBackupChatItemArchiver.ArchiveMultiFrameResult.Error]()

        let wasAnySendSealedSender: Bool
        let directionalDetails: Details.DirectionalDetails
        switch buildOutgoingMessageDetails(message, recipientContext: context.recipientContext) {
        case .success(let details):
            directionalDetails = details.details
            wasAnySendSealedSender = details.wasAnySendSealedSender
        case .isPastRevision:
            return .isPastRevision
        case .notYetImplemented:
            return .notYetImplemented
        case let .partialFailure(details, errors):
            directionalDetails = details.details
            wasAnySendSealedSender = details.wasAnySendSealedSender
            partialErrors.append(contentsOf: errors)
        case .messageFailure(let errors):
            partialErrors.append(contentsOf: errors)
            return .messageFailure(partialErrors)
        case .completeFailure(let error):
            return .completeFailure(error)
        }

        guard let author = context.recipientContext[.noteToSelf] else {
            partialErrors.append(.init(
                objectId: interaction.chatItemId,
                error: .referencedIdMissing(.recipient(.noteToSelf))
            ))
            return .messageFailure(partialErrors)
        }

        let contentsResult = contentsArchiver.archiveMessageContents(
            message,
            context: context.recipientContext,
            tx: tx
        )
        let type: CloudBackup.ChatItemMessageType
        switch contentsResult {
        case .success(let component):
            type = component
        case .isPastRevision:
            return .isPastRevision
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
        recipientContext: CloudBackup.RecipientArchivingContext
    ) -> CloudBackup.ArchiveInteractionResult<OutgoingMessageDetails> {
        var perRecipientErrors = [CloudBackup.ArchiveInteractionResult<Details.DirectionalDetails>.Error]()

        var wasAnySendSealedSender = false
        let outgoingMessageProtoBuilder = BackupProtoChatItemOutgoingMessageDetails.builder()

        for (address, sendState) in message.recipientAddressStates ?? [:] {
            guard let recipientAddress = self.recipientAddress(from: address) else {
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

    private func recipientAddress(
        from recipientAddress: SignalServiceAddress
    ) -> CloudBackup.RecipientArchivingContext.Address? {
        if
            let aci = recipientAddress.aci
        {
            return .contactAci(aci)
        } else if
            let pni = recipientAddress.serviceId as? Pni
        {
            return .contactPni(pni)
        } else if
            let e164 = recipientAddress.e164
        {
            return .contactE164(e164)
        } else {
            return nil
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
        thread: TSThread,
        context: CloudBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) -> CloudBackup.RestoreInteractionResult<Void> {
        guard let outgoingDetails = chatItem.outgoing else {
            // Should be impossible.
            return .messageFailure([.invalidProtoData])
        }

        guard let messageType = chatItem.messageType else {
            // Unrecognized item type!
            return .messageFailure([.unknownFrameType])
        }

        var partialErrors = [CloudBackup.RestoringFrameError]()

        let contentsResult = contentsArchiver.restoreContents(
            messageType,
            tx: tx
        )

        let contents: CloudBackup.RestoredMessageContents
        switch contentsResult {
        case .success(let value):
            contents = value
        case .partialRestore(let value, let errors):
            contents = value
            partialErrors.append(contentsOf: errors)
        case .messageFailure(let errors):
            partialErrors.append(contentsOf: errors)
            return .messageFailure(partialErrors)
        }

        let messageBody = contents.body

        // TODO: this is going to determine the recipients _from the current thread state_.
        // thats not correct; the message may have been sent before the current set
        // of recipients came to be. We need to explicitly pass the recipient states
        // into this initializer instead.
        let messageBuilder = TSOutgoingMessageBuilder.builder(
            thread: thread,
            timestamp: chatItem.dateSent,
            messageBody: messageBody?.text,
            bodyRanges: messageBody?.ranges,
            attachmentIds: nil,
            expiresInSeconds: UInt32(chatItem.expiresInMs / 1000),
            expireStartedAt: chatItem.expireStartDate,
            isVoiceMessage: false,
            groupMetaMessage: .unspecified,
            quotedMessage: nil,
            contactShare: nil,
            linkPreview: nil,
            messageSticker: nil,
            isViewOnceMessage: false,
            changeActionsProtoData: nil,
            additionalRecipients: nil,
            skippedRecipients: nil,
            storyAuthorAci: nil,
            storyTimestamp: nil,
            storyReactionEmoji: nil,
            giftBadge: nil
        )

        let message = interactionStore.buildOutgoingMessage(builder: messageBuilder, tx: tx)
        interactionStore.insertInteraction(message, tx: tx)

        var didSucceedAtLeastOneRecipient = false
        for sendStatus in outgoingDetails.sendStatus {
            // TODO: ideally we don't use addresses in here at all, their
            // caching properties are problematic.
            let recipientAddress: SignalServiceAddress
            switch context.recipientContext[chatItem.authorRecipientId] {
            case .contact(let aci, let pni, let e164):
                recipientAddress = SignalServiceAddress(serviceId: aci ?? pni, e164: e164)
            case .none:
                // Missing recipient! Fail this one recipient but keep going.
                partialErrors.append(.identifierNotFound(.recipient(chatItem.authorRecipientId)))
                continue
            default:
                // Recipients can only be contacts.
                partialErrors.append(.invalidProtoData)
                continue
            }

            guard let deliveryStatus = sendStatus.deliveryStatus else {
                // Need a status!
                partialErrors.append(.invalidProtoData)
                continue
            }

            didSucceedAtLeastOneRecipient = true
            switch deliveryStatus {
            case .unknown:
                break
            case .pending:
                // This is the default, no need to update.
                break
            case .failed:
                interactionStore.update(
                    message,
                    withFailedRecipient: recipientAddress,
                    // TODO: can we use a more descriptive error?
                    error: OWSUnretryableMessageSenderError(),
                    tx: tx
                )
            case .sent:
                interactionStore.update(
                    message,
                    withSentRecipientAddress: recipientAddress,
                    wasSentByUD: sendStatus.sealedSender.negated,
                    tx: tx
                )
            case .delivered:
                interactionStore.update(
                    message,
                    withDeliveredRecipient: recipientAddress,
                    // TODO: eliminate device id as a required field
                    deviceId: 1,
                    deliveryTimestamp: sendStatus.lastStatusUpdateTimestamp,
                    context: PassthroughDeliveryReceiptContext(),
                    tx: tx
                )
            case .read:
                interactionStore.update(
                    message,
                    withReadRecipient: recipientAddress,
                    // TODO: eliminate device id as a required field
                    deviceId: 1,
                    readTimestamp: sendStatus.lastStatusUpdateTimestamp,
                    tx: tx
                )
            case .viewed:
                interactionStore.update(
                    message,
                    withViewedRecipient: recipientAddress,
                    // TODO: eliminate device id as a required field
                    deviceId: 1,
                    viewedTimestamp: sendStatus.lastStatusUpdateTimestamp,
                    tx: tx
                )
            case .skipped:
                interactionStore.update(
                    message,
                    withSkippedRecipient: recipientAddress,
                    tx: tx
                )
            }
        }

        guard didSucceedAtLeastOneRecipient else {
            // If every recipient failed, don't count this as a success at all.
            return .messageFailure(partialErrors)
        }

        let downstreamObjectsResult = contentsArchiver.restoreDownstreamObjects(
            message: message,
            restoredContents: contents,
            context: context,
            tx: tx
        )
        switch downstreamObjectsResult {
        case .success:
            break
        case .partialRestore(_, let errors):
            partialErrors.append(contentsOf: errors)
        case .messageFailure(let errors):
            partialErrors.append(contentsOf: errors)
            return .messageFailure(partialErrors)
        }

        if partialErrors.isEmpty {
            return .success(())
        } else {
            return .partialRestore((), partialErrors)
        }
    }
}
