//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class OWSIncomingSentMessageTranscript: SentMessageTranscript {

    public let type: SentMessageTranscriptType

    public var requiredProtocolVersion: UInt32?

    public let timestamp: UInt64

    public let recipientStates: [SignalServiceAddress: TSOutgoingMessageRecipientState]

    public static func from(
        sentProto: SSKProtoSyncMessageSent,
        serverTimestamp: UInt64,
        tx: DBWriteTransaction,
    ) -> OWSIncomingSentMessageTranscript? {
        let isEdit = sentProto.editMessage?.dataMessage != nil
        guard let dataMessage = sentProto.message ?? sentProto.editMessage?.dataMessage else {
            owsFailDebug("Missing message.")
            return nil
        }

        guard sentProto.timestamp != 0 else {
            owsFailDebug("Sent missing timestamp.")
            return nil
        }

        let recipientAddress: SignalServiceAddress?
        let groupId: GroupIdentifier?
        if let groupContextV2 = dataMessage.groupV2 {
            guard let masterKey = groupContextV2.masterKey else {
                owsFailDebug("Missing masterKey.")
                return nil
            }

            guard let contextInfo = try? GroupV2ContextInfo.deriveFrom(masterKeyData: masterKey) else {
                owsFailDebug("Couldn't parse contextInfo.")
                return nil
            }

            groupId = contextInfo.groupId
            recipientAddress = nil
        } else if sentProto.hasDestinationServiceID || sentProto.hasDestinationServiceIDBinary || sentProto.destinationE164 != nil {
            let serviceId = ServiceId.parseFrom(
                serviceIdBinary: sentProto.destinationServiceIDBinary,
                serviceIdString: sentProto.destinationServiceID,
            )
            let destinationAddress = SignalServiceAddress(
                serviceId: serviceId,
                legacyPhoneNumber: sentProto.destinationE164?.nilIfEmpty,
                cache: SSKEnvironment.shared.signalServiceAddressCacheRef,
            )
            guard destinationAddress.isValid else {
                owsFailDebug("Invalid destinationAddress.")
                return nil
            }
            groupId = nil
            recipientAddress = destinationAddress
        } else {
            owsFailDebug("Neither a group ID nor recipient address found!")
            return nil
        }

        var isExpirationTimerUpdate = false
        var isEndSessionMessage = false
        if dataMessage.hasFlags {
            let flags = Int32(dataMessage.flags)
            isExpirationTimerUpdate = (flags & SSKProtoDataMessageFlags.expirationTimerUpdate.rawValue) != 0
            isEndSessionMessage = (flags & SSKProtoDataMessageFlags.endSession.rawValue) != 0
        }

        let type: SentMessageTranscriptType
        if sentProto.isRecipientUpdate, !isEdit {
            guard
                let groupId,
                let groupThread = TSGroupThread.fetch(forGroupId: groupId, tx: tx)
            else {
                owsFailDebug("We should never receive a 'recipient update' for messages in contact threads.")
                return nil
            }
            type = .recipientUpdate(groupThread)
        } else if isExpirationTimerUpdate {
            guard
                let target = getTarget(
                    recipientAddress: recipientAddress,
                    groupId: groupId,
                    dataMessage: dataMessage,
                    tx: tx,
                )
            else {
                return nil
            }
            type = .expirationTimerUpdate(target)
        } else if isEndSessionMessage {
            guard let recipientAddress else {
                owsFailDebug("We should never receive a 'end session' for messages in group threads.")
                return nil
            }
            type = .endSessionUpdate(TSContactThread.getOrCreateThread(contactAddress: recipientAddress))
        } else if dataMessage.payment != nil {
            guard
                let target = getTarget(
                    recipientAddress: recipientAddress,
                    groupId: groupId,
                    dataMessage: dataMessage,
                    tx: tx,
                )
            else {
                return nil
            }
            guard let paymentModels = TSPaymentModels.parsePaymentProtos(dataMessage: dataMessage, thread: target.thread) else {
                return nil
            }
            let paymentServerTimestamp: UInt64
            if serverTimestamp > 0 {
                paymentServerTimestamp = serverTimestamp
            } else {
                // We fall back to the sent timestamp, even though this is called a server timestamp.
                // This was done historically and behavior is maintained.
                paymentServerTimestamp = sentProto.timestamp
            }
            owsAssertDebug(paymentServerTimestamp > 0)
            let paymentNotification = SentMessageTranscriptType.PaymentNotification(
                target: target,
                serverTimestamp: paymentServerTimestamp,
                notification: paymentModels.notification,
            )
            type = .paymentNotification(paymentNotification)
        } else {
            guard
                let target = getTarget(
                    recipientAddress: recipientAddress,
                    groupId: groupId,
                    dataMessage: dataMessage,
                    tx: tx,
                )
            else {
                return nil
            }
            guard
                let messageParams = self.parseMessageParams(
                    sentProto: sentProto,
                    serverTimestamp: serverTimestamp,
                    dataMessage: dataMessage,
                    target: target,
                    tx: tx,
                )
            else {
                return nil
            }
            type = .message(messageParams)
        }

        var recipientStates = [SignalServiceAddress: TSOutgoingMessageRecipientState]()
        for statusProto in sentProto.unidentifiedStatus {
            guard
                let serviceId = ServiceId.parseFrom(
                    serviceIdBinary: statusProto.destinationServiceIDBinary,
                    serviceIdString: statusProto.destinationServiceID,
                ),
                statusProto.hasUnidentified
            else {
                owsFailDebug("Delivery status proto is missing value.")
                continue
            }

            let recipientState = TSOutgoingMessageRecipientState(
                status: .sent,
                statusTimestamp: sentProto.timestamp,
                wasSentByUD: statusProto.unidentified,
                errorCode: nil,
            )
            recipientStates[SignalServiceAddress(serviceId)] = recipientState
        }

        guard validateTimestampsMatch(type: type, sentProto: sentProto, dataMessage: dataMessage) else {
            return nil
        }

        return .init(
            type: type,
            timestamp: sentProto.timestamp,
            recipientStates: recipientStates,
        )
    }

    private static func validateTimestampsMatch(
        type: SentMessageTranscriptType,
        sentProto: SSKProtoSyncMessageSent,
        dataMessage: SSKProtoDataMessage,
    ) -> Bool {
        switch type {
        case .message, .expirationTimerUpdate, .paymentNotification, .archivedPayment:
            // We only validate these types
            break
        case .recipientUpdate, .endSessionUpdate:
            // Don't validate these types, as was done historically.
            return true
        }
        guard sentProto.timestamp == dataMessage.timestamp else {
            owsFailDebug("Transcript timestamps do not match, discarding message.")
            // This transcript is invalid, discard it.
            return false
        }
        return true
    }

    private static func parseMessageParams(
        sentProto: SSKProtoSyncMessageSent,
        serverTimestamp: UInt64,
        dataMessage: SSKProtoDataMessage,
        target: SentMessageTranscriptTarget,
        tx: DBWriteTransaction,
    ) -> SentMessageTranscriptType.Message? {
        let isViewOnceMessage = dataMessage.hasIsViewOnce && dataMessage.isViewOnce

        let bodyRanges = dataMessage.bodyRanges.isEmpty ? MessageBodyRanges.empty : MessageBodyRanges(protos: dataMessage.bodyRanges)
        var body = dataMessage.body.map {
            DependenciesBridge.shared.attachmentContentValidator.truncatedMessageBodyForInlining(
                MessageBody(text: $0, ranges: bodyRanges),
                tx: tx,
            )
        }

        let validatedContactShare: ValidatedContactShareProto?
        if let contactShareProto = dataMessage.contact.first {
            let contactShareManager = DependenciesBridge.shared.contactShareManager
            validatedContactShare = contactShareManager.validateAndBuild(for: contactShareProto)
        } else {
            validatedContactShare = nil
        }

        let validatedLinkPreview: ValidatedLinkPreviewProto?
        if let linkPreviewProto = dataMessage.preview.first {
            do {
                let linkPreviewManager = DependenciesBridge.shared.linkPreviewManager
                validatedLinkPreview = try linkPreviewManager.validateAndBuildLinkPreview(
                    from: linkPreviewProto,
                    dataMessage: dataMessage,
                )
            } catch LinkPreviewError.invalidPreview {
                // Just drop the link preview, but keep the message
                Logger.warn("Dropping invalid link preview; keeping message")
                validatedLinkPreview = nil
            } catch {
                owsFailDebug("Unexpected error for incoming synced link preview proto! \(error)")
                return nil
            }
        } else {
            validatedLinkPreview = nil
        }

        let validatedMessageSticker: ValidatedMessageStickerProto?
        if let stickerProto = dataMessage.sticker {
            let messageStickerManager = DependenciesBridge.shared.messageStickerManager
            do {
                validatedMessageSticker = try messageStickerManager.buildValidatedMessageSticker(from: stickerProto)
            } catch {
                owsFailDebug("Unexpected error for incoming message sticker! \(error)")
                return nil
            }
        } else {
            validatedMessageSticker = nil
        }

        let giftBadge = OWSGiftBadge.maybeBuild(from: dataMessage)
        if giftBadge != nil, target.thread.isGroupThread {
            owsFailDebug("Ignoring gift sent to group")
            return nil
        }

        let validatedQuotedReply: ValidatedQuotedReply?
        if let quoteProto = dataMessage.quote {
            let quotedReplyManager = DependenciesBridge.shared.quotedReplyManager
            do {
                validatedQuotedReply = try quotedReplyManager.validateAndBuildQuotedReply(
                    from: quoteProto,
                    threadUniqueId: target.thread.uniqueId,
                    tx: tx,
                )
            } catch {
                owsFailDebug("Unexpected error for incoming quote reply! \(error)")
                return nil
            }
        } else {
            validatedQuotedReply = nil
        }

        let validatedPollCreate: ValidatedIncomingPollCreate?
        if let pollCreateProto = dataMessage.pollCreate {
            let pollMessageManager = DependenciesBridge.shared.pollMessageManager
            do {
                validatedPollCreate = try pollMessageManager.validateIncomingPollCreate(
                    pollCreateProto: pollCreateProto,
                    tx: tx,
                )
            } catch {
                owsFailDebug("Unexpected error for incoming poll create! \(error)")
                return nil
            }

            body = validatedPollCreate!.messageBody
        } else {
            validatedPollCreate = nil
        }

        let storyTimestamp: UInt64?
        let storyAuthorAci: Aci?
        if
            let storyContext = dataMessage.storyContext,
            storyContext.hasSentTimestamp,
            storyContext.hasAuthorAci || storyContext.hasAuthorAciBinary
        {
            storyTimestamp = storyContext.sentTimestamp
            storyAuthorAci = Aci.parseFrom(serviceIdBinary: storyContext.authorAciBinary, serviceIdString: storyContext.authorAci)
            guard storyAuthorAci != nil else {
                owsFailDebug("Couldn't parse story author")
                return nil
            }
        } else {
            storyTimestamp = nil
            storyAuthorAci = nil
        }

        return SentMessageTranscriptType.Message(
            target: target,
            body: body,
            attachmentPointerProtos: dataMessage.attachments,
            validatedContactShare: validatedContactShare,
            validatedQuotedReply: validatedQuotedReply,
            validatedLinkPreview: validatedLinkPreview,
            validatedMessageSticker: validatedMessageSticker,
            validatedPollCreate: validatedPollCreate,
            giftBadge: giftBadge,
            isViewOnceMessage: isViewOnceMessage,
            expirationStartedAt: sentProto.expirationStartTimestamp,
            expirationDurationSeconds: dataMessage.expireTimer,
            expireTimerVersion: dataMessage.expireTimerVersion,
            storyTimestamp: storyTimestamp,
            storyAuthorAci: storyAuthorAci,
        )
    }

    private static func getTarget(
        recipientAddress: SignalServiceAddress?,
        groupId: GroupIdentifier?,
        dataMessage: SSKProtoDataMessage,
        tx: DBWriteTransaction,
    ) -> SentMessageTranscriptTarget? {
        if let groupId {
            guard let groupThread = TSGroupThread.fetch(forGroupId: groupId, tx: tx) else {
                owsFailDebug("Missing thread for group.")
                return nil
            }

            if let groupContextV2 = dataMessage.groupV2 {
                guard groupThread.isGroupV2Thread else {
                    owsFailDebug("Invalid thread for v2 group.")
                    return nil
                }
                guard groupContextV2.hasRevision else {
                    owsFailDebug("Missing revision.")
                    return nil
                }
                let revision = groupContextV2.revision
                guard
                    let groupModel = groupThread.groupModel as? TSGroupModelV2,
                    revision <= groupModel.revision
                else {
                    owsFailDebug("Unexpected revision.")
                    return nil
                }
            } else {
                owsFailDebug("Missing group context.")
                return nil
            }
            return .group(groupThread)
        } else if let recipientAddress {
            let thread = TSContactThread.getOrCreateThread(
                withContactAddress: recipientAddress,
                transaction: tx,
            )
            return .contact(
                thread,
                .token(
                    forProtoExpireTimerSeconds: dataMessage.expireTimer,
                    version: dataMessage.expireTimerVersion,
                ),
            )
        } else {
            return nil
        }
    }

    private init(
        type: SentMessageTranscriptType,
        requiredProtocolVersion: UInt32? = nil,
        timestamp: UInt64,
        recipientStates: [SignalServiceAddress: TSOutgoingMessageRecipientState],
    ) {
        self.type = type
        self.requiredProtocolVersion = requiredProtocolVersion
        self.timestamp = timestamp
        self.recipientStates = recipientStates
    }
}
