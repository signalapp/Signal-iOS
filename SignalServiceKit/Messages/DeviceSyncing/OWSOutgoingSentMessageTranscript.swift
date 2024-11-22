//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
extension OWSOutgoingSentMessageTranscript {

    @objc(prepareDataSyncMessageContentWithSentBuilder:tx:)
    func prepareDataSyncMessageContent(
        with sentBuilder: SSKProtoSyncMessageSentBuilder,
        tx: SDSAnyReadTransaction
    ) -> Bool {

        let dataMessage: SSKProtoDataMessage
        if message.isViewOnceMessage {
            let dataBuilder = SSKProtoDataMessage.builder()
            dataBuilder.setTimestamp(message.timestamp)
            dataBuilder.setExpireTimer(message.expiresInSeconds)
            dataBuilder.setExpireTimerVersion(message.expireTimerVersion?.uint32Value ?? 0)
            dataBuilder.setIsViewOnce(true)
            dataBuilder.setRequiredProtocolVersion(UInt32(SSKProtoDataMessageProtocolVersion.viewOnceVideo.rawValue))

            if let groupThread = messageThread as? TSGroupThread {
                switch groupThread.groupModel.groupsVersion {
                case .V1:
                    Logger.error("[GV1] Failed to build sync message contents for V1 groups message!")
                    return false
                case .V2:
                    guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
                        return false
                    }
                    do {
                        let groupContextV2 = try GroupsV2Protos.buildGroupContextProto(
                            groupModel: groupModel,
                            groupChangeProtoData: nil
                        )
                        dataBuilder.setGroupV2(groupContextV2)
                    } catch {
                        owsFailDebug("Error \(error)")
                        return false
                    }
                }
            }
            do {
                dataMessage = try dataBuilder.build()
            } catch {
                owsFailDebug("Could not build protobuf: \(error)")
                return false
            }

        } else {
            guard let newDataMessage = message.buildDataMessage(messageThread, transaction: tx) else {
                owsFailDebug("Could not build protobuf")
                return false
            }
            dataMessage = newDataMessage
        }

        sentBuilder.setMessage(dataMessage)
        sentBuilder.setExpirationStartTimestamp(message.timestamp)
        return true
    }

    @objc(prepareUnidentifiedStatusSyncMessageContentWithSentBuilder:tx:)
    func prepareUnidentifiedStatusSyncMessageContent(
        with sentBuilder: SSKProtoSyncMessageSentBuilder,
        tx: SDSAnyReadTransaction
    ) {
        for recipientAddress in message.sentRecipientAddresses() {
            guard let recipientState = message.recipientState(for: recipientAddress) else {
                owsFailDebug("Unexpectedly missing recipient state for address?")
                continue
            }
            guard let recipientServiceId = recipientAddress.serviceId else {
                owsFailDebug("Missing service ID for sent recipient!")
                continue
            }

            let statusBuilder = SSKProtoSyncMessageSentUnidentifiedDeliveryStatus.builder()
            statusBuilder.setDestinationServiceID(recipientServiceId.serviceIdString)
            statusBuilder.setUnidentified(recipientState.wasSentByUD)

            sentBuilder.addUnidentifiedStatus(statusBuilder.buildInfallibly())
        }
    }
}
