//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Notifies your other registered devices (if you have any) that you've
/// sent a message. This way the message you just sent can appear on all
/// your devices.
class OutgoingSentMessageTranscript: OWSOutgoingSyncMessage {
    private(set) var message: TSOutgoingMessage!
    private(set) var messageThread: TSThread!
    private(set) var isRecipientUpdate: Bool = false

    // sentRecipientAddress is the recipient of message, for contact thread messages.
    // It is used to identify the thread/conversation to desktop.
    private(set) var sentRecipientAddress: SignalServiceAddress?

    init(
        localThread: TSContactThread,
        messageThread: TSThread,
        message: TSOutgoingMessage,
        isRecipientUpdate: Bool,
        tx: DBReadTransaction,
    ) {
        self.message = message
        self.messageThread = messageThread
        self.isRecipientUpdate = isRecipientUpdate
        self.sentRecipientAddress = (messageThread as? TSContactThread)?.contactAddress

        // The sync message's timestamp must match the original outgoing message's timestamp.
        super.init(timestamp: message.timestamp, localThread: localThread, transaction: tx)
    }

    override func encode(with coder: NSCoder) {
        owsFail("Doesn't support serialization.")
    }

    required init?(coder: NSCoder) {
        // Doesn't support serialization.
        return nil
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(self.isRecipientUpdate)
        hasher.combine(self.message)
        hasher.combine(self.messageThread)
        hasher.combine(self.sentRecipientAddress)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.isRecipientUpdate == object.isRecipientUpdate else { return false }
        guard self.message == object.message else { return false }
        guard self.messageThread == object.messageThread else { return false }
        guard self.sentRecipientAddress == object.sentRecipientAddress else { return false }
        return true
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        let result = super.copy(with: zone) as! Self
        result.isRecipientUpdate = self.isRecipientUpdate
        result.message = self.message
        result.messageThread = self.messageThread
        result.sentRecipientAddress = self.sentRecipientAddress
        return result
    }

    override var isUrgent: Bool { false }

    override func syncMessageBuilder(transaction: DBReadTransaction) -> SSKProtoSyncMessageBuilder? {
        let sentBuilder = SSKProtoSyncMessageSent.builder()
        sentBuilder.setTimestamp(self.timestamp)
        if let phoneNumber = self.sentRecipientAddress?.phoneNumber {
            sentBuilder.setDestinationE164(phoneNumber)
        }
        if let serviceId = self.sentRecipientAddress?.serviceId {
            if BuildFlags.serviceIdStrings {
                sentBuilder.setDestinationServiceID(serviceId.serviceIdString)
            }
            if BuildFlags.serviceIdBinaryConstantOverhead {
                sentBuilder.setDestinationServiceIDBinary(serviceId.serviceIdBinary)
            }
        }
        sentBuilder.setIsRecipientUpdate(self.isRecipientUpdate)

        guard prepareDataSyncMessageContent(with: sentBuilder, tx: transaction) else {
            return nil
        }

        prepareUnidentifiedStatusSyncMessageContent(with: sentBuilder, tx: transaction)

        do {
            let syncMessageBuilder = SSKProtoSyncMessage.builder()
            syncMessageBuilder.setSent(try sentBuilder.build())
            return syncMessageBuilder
        } catch {
            owsFailDebug("couldn't serialize sent transcript: \(error)")
            return nil
        }
    }

    override var relatedUniqueIds: Set<String> {
        return super.relatedUniqueIds.union([self.message.uniqueId])
    }

    func prepareDataSyncMessageContent(
        with sentBuilder: SSKProtoSyncMessageSentBuilder,
        tx: DBReadTransaction,
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
                            groupChangeProtoData: nil,
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

    private func prepareUnidentifiedStatusSyncMessageContent(
        with sentBuilder: SSKProtoSyncMessageSentBuilder,
        tx: DBReadTransaction,
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
            if BuildFlags.serviceIdStrings {
                statusBuilder.setDestinationServiceID(recipientServiceId.serviceIdString)
            }
            if BuildFlags.serviceIdBinaryVariableOverhead {
                statusBuilder.setDestinationServiceIDBinary(recipientServiceId.serviceIdBinary)
            }
            statusBuilder.setUnidentified(recipientState.wasSentByUD)

            sentBuilder.addUnidentifiedStatus(statusBuilder.buildInfallibly())
        }
    }
}
