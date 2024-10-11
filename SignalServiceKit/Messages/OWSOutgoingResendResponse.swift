//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

@objc(OWSOutgoingResendResponse) // for Mantle
final class OWSOutgoingResendResponse: TSOutgoingMessage {
    @objc // for Mantle
    private(set) var originalMessagePlaintext: Data?

    @objc // for Mantle
    private(set) var originalThreadId: String?

    @objc // for Mantle
    private(set) var originalGroupId: Data?

    @objc // for Mantle
    private var derivedContentHint: SealedSenderContentHint = .default

    @objc // for Mantle
    private(set) var didAppendSKDM: Bool = false

    private init(
        outgoingMessageBuilder: TSOutgoingMessageBuilder,
        originalMessagePlaintext: Data?,
        originalThreadId: String?,
        originalGroupId: Data?,
        derivedContentHint: SealedSenderContentHint,
        tx: SDSAnyWriteTransaction
    ) {
        super.init(
            outgoingMessageWith: outgoingMessageBuilder,
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: tx
        )
        self.originalMessagePlaintext = originalMessagePlaintext
        self.originalThreadId = originalThreadId
        self.originalGroupId = originalGroupId
        self.derivedContentHint = derivedContentHint
    }

    convenience init?(
        aci: Aci,
        deviceId: UInt32,
        failedTimestamp: UInt64,
        didResetSession: Bool,
        tx: SDSAnyWriteTransaction
    ) {
        let targetThread = TSContactThread.getOrCreateThread(withContactAddress: SignalServiceAddress(aci), transaction: tx)
        let builder: TSOutgoingMessageBuilder = .withDefaultValues(thread: targetThread)

        let messageSendLog = SSKEnvironment.shared.messageSendLogRef
        if let payloadRecord = messageSendLog.fetchPayload(
            recipientAci: aci,
            recipientDeviceId: deviceId,
            timestamp: failedTimestamp,
            tx: tx
        ) {
            let originalThread = TSThread.anyFetch(uniqueId: payloadRecord.uniqueThreadId, transaction: tx)

            // We should inherit the timestamp of the failed message. This allows the
            // recipient of this message to correlate the resend response with the
            // original failed message.
            builder.timestamp = payloadRecord.sentTimestamp

            // We also want to reset the delivery record for the failing address if
            // this was a sender key group. This will be re-marked as delivered on
            // success if we included an SKDM in the resend response
            if let originalThread, originalThread.isGroupThread {
                SSKEnvironment.shared.senderKeyStoreRef.resetSenderKeyDeliveryRecord(for: originalThread, serviceId: aci, writeTx: tx)
            }

            self.init(
                outgoingMessageBuilder: builder,
                originalMessagePlaintext: payloadRecord.plaintextContent,
                originalThreadId: payloadRecord.uniqueThreadId,
                originalGroupId: (originalThread as? TSGroupThread)?.groupId,
                derivedContentHint: payloadRecord.contentHint,
                tx: tx
            )
        } else if didResetSession {
            Logger.info("Failed to find MSL record for resend request: \(failedTimestamp). Will reply with Null message")
            self.init(
                outgoingMessageBuilder: builder,
                originalMessagePlaintext: nil,
                originalThreadId: nil,
                originalGroupId: nil,
                derivedContentHint: .implicit,
                tx: tx
            )
        } else {
            Logger.warn("Failed to find MSL record for resend request: \(failedTimestamp). Declining to respond.")
            return nil
        }
    }

    required init!(coder: NSCoder) {
        super.init(coder: coder)
        // Discard invalid SealedSenderContentHint values.
        self.derivedContentHint = SealedSenderContentHint(rawValue: self.derivedContentHint.rawValue) ?? .default
    }

    required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    override var shouldRecordSendLog: Bool { false }

    override func shouldSyncTranscript() -> Bool { false }

    override var shouldBeSaved: Bool { false }

    override var contentHint: SealedSenderContentHint { self.derivedContentHint }

    override func envelopeGroupIdWithTransaction(_ transaction: SDSAnyReadTransaction) -> Data? { self.originalGroupId }

    override func buildPlainTextData(_ thread: TSThread, transaction tx: SDSAnyWriteTransaction) -> Data? {
        owsAssertDebug(self.recipientAddresses().count == 1)

        let contentBuilder: SSKProtoContentBuilder = {
            if let originalMessagePlaintext {
                do {
                    return try resentProtoBuilder(from: originalMessagePlaintext)
                } catch {
                    owsFailDebug("Failed to build resent content: \(error)")
                    // fallthrough
                }
            }
            return nullMessageProtoBuilder()
        }()

        if
            let originalThreadId,
            let originalThread = TSThread.anyFetch(uniqueId: originalThreadId, transaction: tx),
            originalThread.usesSenderKey,
            let recipientAddress = self.recipientAddresses().first,
            originalThread.recipientAddresses(with: tx).contains(recipientAddress)
        {
            let skdmData = SSKEnvironment.shared.senderKeyStoreRef.skdmBytesForThread(originalThread, tx: tx)
            if let skdmData {
                contentBuilder.setSenderKeyDistributionMessage(skdmData)
            }
            self.didAppendSKDM = skdmData != nil
        }

        do {
            return try contentBuilder.buildSerializedData()
        } catch {
            owsFailDebug("Failed to build plaintext message: \(error)")
            return nil
        }
    }

    private func resentProtoBuilder(from plaintextData: Data) throws -> SSKProtoContentBuilder {
        return try SSKProtoContent(serializedData: plaintextData).asBuilder()
    }

    private func nullMessageProtoBuilder() -> SSKProtoContentBuilder {
        let contentBuilder = SSKProtoContent.builder()
        contentBuilder.setNullMessage(SSKProtoNullMessage.builder().buildInfallibly())
        return contentBuilder
    }

    func didPerformMessageSend(_ sentMessages: [SentDeviceMessage], to serviceId: ServiceId, tx: SDSAnyWriteTransaction) {
        if
            self.didAppendSKDM,
            let originalThreadId,
            let originalThread = TSThread.anyFetch(uniqueId: originalThreadId, transaction: tx),
            originalThread.usesSenderKey
        {
            do {
                try SSKEnvironment.shared.senderKeyStoreRef.recordSentSenderKeys(
                    [SentSenderKey(recipient: serviceId, timestamp: self.timestamp, messages: sentMessages)],
                    for: originalThread,
                    writeTx: tx
                )
            } catch {
                owsFailDebug("Couldn't update sender key after resend: \(error)")
            }
        }
    }
}
