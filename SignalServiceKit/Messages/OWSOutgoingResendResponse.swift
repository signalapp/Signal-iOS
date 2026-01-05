//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

@objc(OWSOutgoingResendResponse)
final class OWSOutgoingResendResponse: TSOutgoingMessage {
    required init?(coder: NSCoder) {
        self.derivedContentHint = (coder.decodeObject(of: NSNumber.self, forKey: "derivedContentHint")?.intValue).flatMap(SealedSenderContentHint.init(rawValue:)) ?? .default
        self.didAppendSKDM = coder.decodeObject(of: NSNumber.self, forKey: "didAppendSKDM")?.boolValue ?? false
        self.originalGroupId = coder.decodeObject(of: NSData.self, forKey: "originalGroupId") as Data?
        self.originalMessagePlaintext = coder.decodeObject(of: NSData.self, forKey: "originalMessagePlaintext") as Data?
        self.originalThreadId = coder.decodeObject(of: NSString.self, forKey: "originalThreadId") as String?
        super.init(coder: coder)
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(NSNumber(value: self.derivedContentHint.rawValue), forKey: "derivedContentHint")
        coder.encode(NSNumber(value: self.didAppendSKDM), forKey: "didAppendSKDM")
        if let originalGroupId {
            coder.encode(originalGroupId, forKey: "originalGroupId")
        }
        if let originalMessagePlaintext {
            coder.encode(originalMessagePlaintext, forKey: "originalMessagePlaintext")
        }
        if let originalThreadId {
            coder.encode(originalThreadId, forKey: "originalThreadId")
        }
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(derivedContentHint)
        hasher.combine(didAppendSKDM)
        hasher.combine(originalGroupId)
        hasher.combine(originalMessagePlaintext)
        hasher.combine(originalThreadId)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.derivedContentHint == object.derivedContentHint else { return false }
        guard self.didAppendSKDM == object.didAppendSKDM else { return false }
        guard self.originalGroupId == object.originalGroupId else { return false }
        guard self.originalMessagePlaintext == object.originalMessagePlaintext else { return false }
        guard self.originalThreadId == object.originalThreadId else { return false }
        return true
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        let result = super.copy(with: zone) as! Self
        result.derivedContentHint = self.derivedContentHint
        result.didAppendSKDM = self.didAppendSKDM
        result.originalGroupId = self.originalGroupId
        result.originalMessagePlaintext = self.originalMessagePlaintext
        result.originalThreadId = self.originalThreadId
        return result
    }

    private(set) var originalMessagePlaintext: Data?
    private(set) var originalThreadId: String?
    private(set) var originalGroupId: Data?
    private var derivedContentHint: SealedSenderContentHint
    private(set) var didAppendSKDM: Bool = false

    private init(
        outgoingMessageBuilder: TSOutgoingMessageBuilder,
        originalMessagePlaintext: Data?,
        originalThreadId: String?,
        originalGroupId: Data?,
        derivedContentHint: SealedSenderContentHint,
        tx: DBWriteTransaction,
    ) {
        self.derivedContentHint = derivedContentHint
        super.init(
            outgoingMessageWith: outgoingMessageBuilder,
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: tx,
        )
        self.originalMessagePlaintext = originalMessagePlaintext
        self.originalThreadId = originalThreadId
        self.originalGroupId = originalGroupId
    }

    convenience init?(
        aci: Aci,
        deviceId: DeviceId,
        failedTimestamp: UInt64,
        didResetSession: Bool,
        tx: DBWriteTransaction,
    ) {
        let targetThread = TSContactThread.getOrCreateThread(withContactAddress: SignalServiceAddress(aci), transaction: tx)
        let builder: TSOutgoingMessageBuilder = .withDefaultValues(thread: targetThread)

        let messageSendLog = SSKEnvironment.shared.messageSendLogRef
        if
            let payloadRecord = messageSendLog.fetchPayload(
                recipientAci: aci,
                recipientDeviceId: deviceId,
                timestamp: failedTimestamp,
                tx: tx,
            )
        {
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
                tx: tx,
            )
        } else if didResetSession {
            Logger.info("Failed to find MSL record for resend request: \(failedTimestamp). Will reply with Null message")
            self.init(
                outgoingMessageBuilder: builder,
                originalMessagePlaintext: nil,
                originalThreadId: nil,
                originalGroupId: nil,
                derivedContentHint: .implicit,
                tx: tx,
            )
        } else {
            Logger.warn("Failed to find MSL record for resend request: \(failedTimestamp). Declining to respond.")
            return nil
        }
    }

    override var shouldRecordSendLog: Bool { false }

    override func shouldSyncTranscript() -> Bool { false }

    override var shouldBeSaved: Bool { false }

    override var contentHint: SealedSenderContentHint { self.derivedContentHint }

    override func envelopeGroupIdWithTransaction(_ transaction: DBReadTransaction) -> Data? { self.originalGroupId }

    override func buildPlainTextData(_ thread: TSThread, transaction tx: DBWriteTransaction) -> Data? {
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

    func didPerformMessageSend(_ sentMessages: [SentDeviceMessage], to serviceId: ServiceId, tx: DBWriteTransaction) {
        if
            self.didAppendSKDM,
            let originalThreadId,
            let originalThread = TSThread.anyFetch(uniqueId: originalThreadId, transaction: tx),
            originalThread.usesSenderKey
        {
            do {
                try SSKEnvironment.shared.senderKeyStoreRef.recordSentSenderKeys(
                    [SentSenderKey(recipient: serviceId, messages: sentMessages)],
                    for: originalThread,
                    writeTx: tx,
                )
            } catch {
                owsFailDebug("Couldn't update sender key after resend: \(error)")
            }
        }
    }
}
