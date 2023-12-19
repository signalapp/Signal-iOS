//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class OWSIncomingSentMessageTranscript: Dependencies, SentMessageTranscript {

    public let type: SentMessageTranscriptType

    public var requiredProtocolVersion: UInt32?

    public let timestamp: UInt64

    public let recipientStates: [SignalServiceAddress: TSOutgoingMessageRecipientState]

    public static func from(
        sentProto: SSKProtoSyncMessageSent,
        serverTimestamp: UInt64,
        tx: DBWriteTransaction
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
        let groupId: Data?
        if let groupContextV2 = dataMessage.groupV2 {
            guard let masterKey = groupContextV2.masterKey, masterKey.count >= 1 else {
                owsFailDebug("Missing masterKey.")
                return nil
            }

            guard let contextInfo = try? Self.groupsV2.groupV2ContextInfo(forMasterKeyData: masterKey) else {
                owsFailDebug("Couldn't parse contextInfo.")
                return nil
            }

            groupId = contextInfo.groupId
            recipientAddress = nil
            guard
                let groupId,
                groupId.count >= 1,
                GroupManager.isValidGroupId(groupId, groupsVersion: .V2)
            else {
                owsFailDebug("Invalid groupId.")
                return nil
            }
        } else if
            sentProto.destinationServiceID != nil
            || sentProto.destinationE164 != nil
        {
            let destinationAddress = SignalServiceAddress(
                serviceIdString: sentProto.destinationServiceID,
                phoneNumber: sentProto.destinationE164
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

        if let groupId {
            TSGroupThread.ensureGroupIdMapping(forGroupId: groupId, transaction: SDSDB.shimOnlyBridge(tx))
        }

        var isExpirationTimerUpdate = false
        var isEndSessionMessage = false
        if dataMessage.hasFlags {
            let flags = Int32(dataMessage.flags)
            isExpirationTimerUpdate = (flags & SSKProtoDataMessageFlags.expirationTimerUpdate.rawValue) != 0
            isEndSessionMessage = (flags & SSKProtoDataMessageFlags.endSession.rawValue) != 0
        }

        let type: SentMessageTranscriptType
        if sentProto.isRecipientUpdate && !isEdit {
            guard
                let groupId,
                let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: SDSDB.shimOnlyBridge(tx))
            else {
                owsFailDebug("We should never receive a 'recipient update' for messages in contact threads.")
                return nil
            }
            type = .recipientUpdate(groupThread)
        } else if isExpirationTimerUpdate {
            guard let target = getTarget(
                recipientAddress: recipientAddress,
                groupId: groupId,
                dataMessage: dataMessage,
                tx: tx
            ) else {
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
            guard let target = getTarget(
                recipientAddress: recipientAddress,
                groupId: groupId,
                dataMessage: dataMessage,
                tx: tx
            ) else {
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
                notification: paymentModels.notification
            )
            type = .paymentNotification(paymentNotification)
        } else {
            guard let target = getTarget(
                recipientAddress: recipientAddress,
                groupId: groupId,
                dataMessage: dataMessage,
                tx: tx
            ) else {
                return nil
            }
            guard let messageParams = self.parseMessageParams(
                sentProto: sentProto,
                serverTimestamp: serverTimestamp,
                dataMessage: dataMessage,
                target: target,
                tx: tx
            ) else {
                return nil
            }
            type = .message(messageParams)
        }

        var recipientStates = [SignalServiceAddress: TSOutgoingMessageRecipientState]()
        for statusProto in sentProto.unidentifiedStatus {
            guard
                let serviceIdString = statusProto.destinationServiceID,
                let serviceId = try? ServiceId.parseFrom(serviceIdString: serviceIdString),
                statusProto.hasUnidentified
            else {
                owsFailDebug("Delivery status proto is missing value.")
                continue
            }

            var recipientState: TSOutgoingMessageRecipientState = TSOutgoingMessageRecipientState()
            recipientState.state = .sent
            recipientState.wasSentByUD = statusProto.unidentified
            recipientStates[.init(serviceId: serviceId, e164: nil)] = recipientState
        }

        guard validateTimestampsMatch(type: type, sentProto: sentProto, dataMessage: dataMessage) else {
            return nil
        }

        return .init(
            type: type,
            timestamp: sentProto.timestamp,
            recipientStates: recipientStates
        )
    }

    private static func validateTimestampsMatch(
        type: SentMessageTranscriptType,
        sentProto: SSKProtoSyncMessageSent,
        dataMessage: SSKProtoDataMessage
    ) -> Bool {
        switch type {
        case .message, .expirationTimerUpdate, .paymentNotification:
            // We only validate these types
            break
        case .recipientUpdate, .endSessionUpdate:
            // Don't validate these types, as was done historically.
            return true
        }
        guard sentProto.timestamp == dataMessage.timestamp else {
            Logger.verbose("Transcript timestamps do not match: \(sentProto.timestamp) != \(dataMessage.timestamp)")
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
        tx: DBWriteTransaction
    ) -> SentMessageTranscriptType.Message? {
        let isViewOnceMessage = dataMessage.hasIsViewOnce && dataMessage.isViewOnce

        let requiredProtocolVersion = dataMessage.requiredProtocolVersion == 0 ? nil : dataMessage.requiredProtocolVersion

        let body = dataMessage.body

        let bodyRanges: MessageBodyRanges?
        if dataMessage.bodyRanges.isEmpty.negated {
            bodyRanges = MessageBodyRanges(protos: dataMessage.bodyRanges)
        } else {
            bodyRanges = nil
        }

        let contact = OWSContact.contact(for: dataMessage, transaction: SDSDB.shimOnlyBridge(tx))

        let linkPreview: OWSLinkPreview?
        do {
            linkPreview = try OWSLinkPreview.buildValidatedLinkPreview(
                dataMessage: dataMessage,
                body: body,
                transaction: SDSDB.shimOnlyBridge(tx)
            )
        } catch {
            Logger.error("linkPreviewError: \(error)")
            linkPreview = nil
        }

        let giftBadge = OWSGiftBadge.maybeBuild(from: dataMessage)
        if giftBadge != nil, target.thread.isGroupThread {
            owsFailDebug("Ignoring gift sent to group")
            return nil
        }

        let messageSticker: MessageSticker?
        do {
            messageSticker = try MessageSticker.buildValidatedMessageSticker(
                dataMessage: dataMessage,
                transaction: SDSDB.shimOnlyBridge(tx)
            )
        } catch {
            if !MessageSticker.isNoStickerError(error) {
                owsFailDebug("stickerError: \(error)")
            }
            messageSticker = nil
        }

        let quotedMessage = TSQuotedMessage(for: dataMessage, thread: target.thread, transaction: SDSDB.shimOnlyBridge(tx))

        let storyTimestamp: UInt64?
        let storyAuthorAci: Aci?
        if
            let storyContext = dataMessage.storyContext,
            storyContext.hasSentTimestamp,
            let authorAci = storyContext.authorAci
        {
            storyTimestamp = storyContext.sentTimestamp
            storyAuthorAci = try? Aci.parseFrom(serviceIdString: authorAci)

            if storyAuthorAci == nil {
                owsFailDebug("Discarding story reply transcript with invalid aci")
                return nil
            }
        } else {
            storyTimestamp = nil
            storyAuthorAci = nil
        }

        return .init(
            target: target,
            body: body,
            bodyRanges: bodyRanges,
            attachmentPointerProtos: dataMessage.attachments,
            quotedMessage: quotedMessage,
            contact: contact,
            linkPreview: linkPreview,
            giftBadge: giftBadge,
            messageSticker: messageSticker,
            isViewOnceMessage: isViewOnceMessage,
            expirationStartedAt: sentProto.expirationStartTimestamp,
            expirationDuration: dataMessage.expireTimer,
            storyTimestamp: storyTimestamp,
            storyAuthorAci: storyAuthorAci
        )
    }

    private static func getTarget(
        recipientAddress: SignalServiceAddress?,
        groupId: Data?,
        dataMessage: SSKProtoDataMessage,
        tx: DBWriteTransaction
    ) -> SentMessageTranscriptTarget? {
        if let groupId {
            guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: SDSDB.shimOnlyBridge(tx)) else {
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
                transaction: SDSDB.shimOnlyBridge(tx)
            )
            return .contact(thread, DisappearingMessageToken.token(forProtoExpireTimer: dataMessage.expireTimer))
        } else {
            return nil
        }
    }

    private init(
        type: SentMessageTranscriptType,
        requiredProtocolVersion: UInt32? = nil,
        timestamp: UInt64,
        recipientStates: [SignalServiceAddress: TSOutgoingMessageRecipientState]
    ) {
        self.type = type
        self.requiredProtocolVersion = requiredProtocolVersion
        self.timestamp = timestamp
        self.recipientStates = recipientStates
    }
}
