//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

class OWSOutgoingResendResponse: TSOutgoingMessage {
    var originalPayload: MessageSendLog.Payload?
    var originalThread: TSThread?

    init(address: SignalServiceAddress,
         deviceId: Int64,
         failedTimestamp: Int64,
         transaction: SDSAnyWriteTransaction) {

        originalPayload = MessageSendLog.fetchPayload(
            address: address,
            deviceId: deviceId,
            timestamp: Date(millisecondsSince1970: UInt64(failedTimestamp)),
            transaction: transaction)

        if let originalThreadId = originalPayload?.uniqueThreadId {
            originalThread = TSThread.anyFetch(uniqueId: originalThreadId, transaction: transaction)
        }

        if let groupThread = originalThread as? TSGroupThread {
            // If the failed message was sent to a group thread,
            // let's reset any record of sending an SKDM to the address
            // that failed to decrypt.
            Self.senderKeyStore.resetSenderKeyDeliveryRecord(
                for: groupThread,
                address: address,
                writeTx: transaction)
        }

        let thread = TSContactThread.getOrCreateThread(contactAddress: address)
        let builder = TSOutgoingMessageBuilder(thread: thread)
        if let originalTimestamp = originalPayload?.sentTimestamp {
            builder.timestamp = originalTimestamp.ows_millisecondsSince1970
        }
        super.init(outgoingMessageWithBuilder: builder)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    override var shouldBeSaved: Bool { false }
    override func shouldSyncTranscript() -> Bool { false }

    public override func buildPlainTextData(
        _ thread: TSThread,
        transaction: SDSAnyReadTransaction
    ) -> Data? {

        let originalProto: SSKProtoContent?
        do {
            if let originalPlaintext = originalPayload?.plaintextContent {
               originalProto = try SSKProtoContent(serializedData: originalPlaintext)
            } else {
                originalProto = nil
            }
        } catch {
            owsFailDebug("\(error)")
            originalProto = nil
        }

        let contentBuilder = originalProto?.asBuilder() ?? {
            let contentBuilder = SSKProtoContent.builder()
            let nullMessageBuilder = SSKProtoNullMessage.builder()
            do {
                let nullMessage = try nullMessageBuilder.build()
                contentBuilder.setNullMessage(nullMessage)
            } catch {
                owsFailDebug("\(error)")
            }
            return contentBuilder
        }()

        if recipientAddresses().count == 1,
           let resendTarget = recipientAddresses().first,
           let groupThread = originalThread as? TSGroupThread {

            // Make sure we have a fresh group state. We don't want to send
            // an SKDM to a user that's no longer a group member
            groupThread.anyReload(transaction: transaction)
            if groupThread.recipientAddresses.contains(resendTarget) {
                // SenderKey TODO: To fetch our SKDM bytes, we need a write transaction
                // It's not critical, but eventually we should be tacking on our SKDM to any
                // resend responses
            }
        }

        do {
            return try contentBuilder.buildSerializedData()
        } catch {
            owsFailDebug("\(error)")
            return nil
        }
    }

    override var shouldRecordSendLog: Bool { false }
}
