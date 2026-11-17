//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

@objc(OWSOutgoingResendResponse)
final class OWSOutgoingResendResponse: TransientOutgoingMessage {
    override class var supportsSecureCoding: Bool { true }

    required init?(coder: NSCoder) {
        self.derivedContentHint = (coder.decodeObject(of: NSNumber.self, forKey: "derivedContentHint")?.intValue).flatMap(SealedSenderContentHint.init(rawValue:)) ?? .default
        self.senderKeyId = coder.containsValue(forKey: "senderKeyId") ? SenderKeyRecord.RowId(rawValue: coder.decodeInt64(forKey: "senderKeyId")) : nil
        self.originalGroupId = coder.decodeObject(of: NSData.self, forKey: "originalGroupId") as Data?
        self.originalMessagePlaintext = coder.decodeObject(of: NSData.self, forKey: "originalMessagePlaintext") as Data?
        self.originalThreadId = coder.decodeObject(of: NSString.self, forKey: "originalThreadId") as String?
        super.init(coder: coder)
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(NSNumber(value: self.derivedContentHint.rawValue), forKey: "derivedContentHint")
        if let senderKeyId {
            coder.encode(senderKeyId.rawValue, forKey: "senderKeyId")
        }
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
        hasher.combine(senderKeyId)
        hasher.combine(originalGroupId)
        hasher.combine(originalMessagePlaintext)
        hasher.combine(originalThreadId)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.derivedContentHint == object.derivedContentHint else { return false }
        guard self.senderKeyId == object.senderKeyId else { return false }
        guard self.originalGroupId == object.originalGroupId else { return false }
        guard self.originalMessagePlaintext == object.originalMessagePlaintext else { return false }
        guard self.originalThreadId == object.originalThreadId else { return false }
        return true
    }

    private(set) var originalMessagePlaintext: Data?
    private(set) var originalThreadId: String?
    private(set) var originalGroupId: Data?
    private var derivedContentHint: SealedSenderContentHint
    private(set) var senderKeyId: SenderKeyRecord.RowId?

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
            let originalThread = TSThread.fetchViaCache(uniqueId: payloadRecord.uniqueThreadId, transaction: tx)

            // We should inherit the timestamp of the failed message. This allows the
            // recipient of this message to correlate the resend response with the
            // original failed message.
            builder.timestamp = payloadRecord.sentTimestamp

            // We also want to reset the delivery record for the failing address if
            // this was a sender key group. This will be re-marked as delivered on
            // success if we include an SKDM in the resend response
            let recipientStore = DependenciesBridge.shared.recipientDatabaseTable
            let senderKeySendingManager = DependenciesBridge.shared.senderKeySendingManager
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            if
                let originalThread,
                originalThread.isGroupThread,
                let registeredState = try? tsAccountManager.registeredState(tx: tx),
                let deviceId = tsAccountManager.storedDeviceId(tx: tx).ifValid,
                let senderKeyId = senderKeySendingManager.fetchSenderKeyId(
                    forThreadUniqueId: originalThread.uniqueId,
                    localAci: registeredState.localIdentifiers.aci,
                    localDeviceId: deviceId,
                    tx: tx,
                ),
                let recipient = recipientStore.fetchRecipient(serviceId: aci, transaction: tx)
            {
                senderKeySendingManager.resetDeliveryRecord(senderKeyId: senderKeyId, recipientId: recipient.id, tx: tx)
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

    override var contentHint: SealedSenderContentHint { self.derivedContentHint }

    override func envelopeGroupIdWithTransaction(_ transaction: DBReadTransaction) -> Data? { self.originalGroupId }

    override func buildPlaintextData(inThread thread: TSThread, tx: DBWriteTransaction) throws -> Data {
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

        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        if
            let originalThreadId,
            let originalThread = TSThread.fetchViaCache(uniqueId: originalThreadId, transaction: tx),
            originalThread.usesSenderKey,
            let recipientAddress = self.recipientAddresses().first,
            originalThread.recipientAddresses(with: tx).contains(recipientAddress),
            let registeredState = try? tsAccountManager.registeredState(tx: tx),
            let deviceId = tsAccountManager.storedDeviceId(tx: tx).ifValid
        {
            let senderKeySendingManager = DependenciesBridge.shared.senderKeySendingManager
            do {
                let senderKeyDistributionMessage = try senderKeySendingManager.buildSenderKeyDistributionMessage(
                    forThreadUniqueId: originalThreadId,
                    localAci: registeredState.localIdentifiers.aci,
                    localDeviceId: deviceId,
                    tx: tx,
                )
                contentBuilder.setSenderKeyDistributionMessage(senderKeyDistributionMessage.serialize())
                self.senderKeyId = senderKeySendingManager.fetchSenderKeyId(
                    forThreadUniqueId: originalThreadId,
                    localAci: registeredState.localIdentifiers.aci,
                    localDeviceId: deviceId,
                    tx: tx,
                ).owsFailUnwrap("must be able to fetch sender key we just used")
            } catch {
                owsFailDebug("couldn't append SKDM: \(error)")
            }
        }

        return try contentBuilder.buildSerializedData()
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
            let senderKeyId,
            let originalThreadId,
            let originalThread = TSThread.fetchViaCache(uniqueId: originalThreadId, transaction: tx),
            originalThread.usesSenderKey
        {
            let senderKeySendingManager = DependenciesBridge.shared.senderKeySendingManager
            senderKeySendingManager.recordSentSenderKeys(
                [SentSenderKey(recipient: serviceId, messages: sentMessages)],
                forSenderKeyId: senderKeyId,
                tx: tx,
            )
        }
    }
}
