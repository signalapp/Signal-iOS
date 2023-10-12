//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

// Every time we add a new property to TSOutgoingMessage, we should:
//
// * Add that property here.
// * Handle that property for received sync transcripts.
// * Handle that property in the test factories.
@objc
public class TSOutgoingMessageBuilder: TSMessageBuilder {
    @objc
    public var isVoiceMessage = false
    @objc
    public var groupMetaMessage: TSGroupMetaMessage = .unspecified
    @objc
    public var changeActionsProtoData: Data?
    @objc
    public var additionalRecipients: [SignalServiceAddress]?
    @objc
    public var skippedRecipients: Set<SignalServiceAddress>?

    public required init(thread: TSThread,
                         timestamp: UInt64? = nil,
                         messageBody: String? = nil,
                         bodyRanges: MessageBodyRanges? = nil,
                         attachmentIds: [String]? = nil,
                         editState: TSEditState = .none,
                         expiresInSeconds: UInt32 = 0,
                         expireStartedAt: UInt64 = 0,
                         isVoiceMessage: Bool = false,
                         groupMetaMessage: TSGroupMetaMessage = .unspecified,
                         quotedMessage: TSQuotedMessage? = nil,
                         contactShare: OWSContact? = nil,
                         linkPreview: OWSLinkPreview? = nil,
                         messageSticker: MessageSticker? = nil,
                         isViewOnceMessage: Bool = false,
                         changeActionsProtoData: Data? = nil,
                         additionalRecipients: [SignalServiceAddress]? = nil,
                         skippedRecipients: Set<SignalServiceAddress>? = nil,
                         storyAuthorAci: Aci? = nil,
                         storyTimestamp: UInt64? = nil,
                         storyReactionEmoji: String? = nil,
                         giftBadge: OWSGiftBadge? = nil
    ) {

        super.init(thread: thread,
                   timestamp: timestamp,
                   messageBody: messageBody,
                   bodyRanges: bodyRanges,
                   attachmentIds: attachmentIds,
                   editState: editState,
                   expiresInSeconds: expiresInSeconds,
                   expireStartedAt: expireStartedAt,
                   quotedMessage: quotedMessage,
                   contactShare: contactShare,
                   linkPreview: linkPreview,
                   messageSticker: messageSticker,
                   isViewOnceMessage: isViewOnceMessage,
                   storyAuthorAci: storyAuthorAci.map { AciObjC($0) },
                   storyTimestamp: storyTimestamp,
                   storyReactionEmoji: storyReactionEmoji,
                   giftBadge: giftBadge)

        self.isVoiceMessage = isVoiceMessage
        self.groupMetaMessage = groupMetaMessage
        self.changeActionsProtoData = changeActionsProtoData
        self.additionalRecipients = additionalRecipients
        self.skippedRecipients = skippedRecipients
    }

    @objc
    public class func outgoingMessageBuilder(thread: TSThread) -> TSOutgoingMessageBuilder {
        return TSOutgoingMessageBuilder(thread: thread)
    }

    @objc
    public class func outgoingMessageBuilder(thread: TSThread,
                                             messageBody: String?) -> TSOutgoingMessageBuilder {
        return TSOutgoingMessageBuilder(thread: thread,
                                        messageBody: messageBody)
    }

    // This factory method can be used at call sites that want
    // to specify every property; usage will fail to compile if
    // if any property is missing.
    @objc
    public class func builder(thread: TSThread,
                              timestamp: UInt64,
                              messageBody: String?,
                              bodyRanges: MessageBodyRanges?,
                              attachmentIds: [String]?,
                              expiresInSeconds: UInt32,
                              expireStartedAt: UInt64,
                              isVoiceMessage: Bool,
                              groupMetaMessage: TSGroupMetaMessage,
                              quotedMessage: TSQuotedMessage?,
                              contactShare: OWSContact?,
                              linkPreview: OWSLinkPreview?,
                              messageSticker: MessageSticker?,
                              isViewOnceMessage: Bool,
                              changeActionsProtoData: Data?,
                              additionalRecipients: [SignalServiceAddress]?,
                              skippedRecipients: Set<SignalServiceAddress>?,
                              storyAuthorAci: AciObjC?,
                              storyTimestamp: NSNumber?,
                              storyReactionEmoji: String?,
                              giftBadge: OWSGiftBadge?) -> TSOutgoingMessageBuilder {
        return TSOutgoingMessageBuilder(thread: thread,
                                        timestamp: timestamp,
                                        messageBody: messageBody,
                                        bodyRanges: bodyRanges,
                                        attachmentIds: attachmentIds,
                                        expiresInSeconds: expiresInSeconds,
                                        expireStartedAt: expireStartedAt,
                                        isVoiceMessage: isVoiceMessage,
                                        groupMetaMessage: groupMetaMessage,
                                        quotedMessage: quotedMessage,
                                        contactShare: contactShare,
                                        linkPreview: linkPreview,
                                        messageSticker: messageSticker,
                                        isViewOnceMessage: isViewOnceMessage,
                                        changeActionsProtoData: changeActionsProtoData,
                                        additionalRecipients: additionalRecipients,
                                        skippedRecipients: skippedRecipients,
                                        storyAuthorAci: storyAuthorAci?.wrappedAciValue,
                                        storyTimestamp: storyTimestamp?.uint64Value,
                                        storyReactionEmoji: storyReactionEmoji,
                                        giftBadge: giftBadge)
    }

    private var hasBuilt = false

    @objc
    public func build(transaction: SDSAnyReadTransaction) -> TSOutgoingMessage {
        if hasBuilt {
            owsFailDebug("Don't build more than once.")
        }
        hasBuilt = true
        return TSOutgoingMessage(outgoingMessageWithBuilder: self, transaction: transaction)
    }

    @objc
    public func buildWithSneakyTransaction() -> TSOutgoingMessage {
        databaseStorage.read { build(transaction: $0) }
    }
}

public extension TSOutgoingMessage {
    @objc
    var isStorySend: Bool { isGroupStoryReply }

    @objc
    func failedRecipientAddresses(errorCode: Int) -> [SignalServiceAddress] {
        guard let states = recipientAddressStates else { return [] }

        return states.filter { _, state in
            return state.state == .failed && state.errorCode?.intValue == errorCode
        }.map { $0.key }
    }

    @objc
    var canSendWithSenderKey: Bool {
        // Sometimes we can fail to send a SenderKey message for an unknown reason. For example,
        // the server may reject the message because one of our recipients has an invalid access
        // token, but we don't know which recipient is the culprit. If we ever hit any of these
        // non-transient failures, we should not send this message with sender key.
        //
        // By sending the message with traditional fanout, this *should* put things in order so
        // that our next SenderKey message will send successfully.
        guard let states = recipientAddressStates else { return true }
        return states
            .compactMap { $0.value.errorCode?.intValue }
            .allSatisfy { $0 != SenderKeyUnavailableError.errorCode }
    }

    @objc(buildPniSignatureMessageIfNeededWithTransaction:)
    func buildPniSignatureMessageIfNeeded(transaction tx: SDSAnyReadTransaction) -> SSKProtoPniSignatureMessage? {
        guard recipientAddressStates?.count == 1 else {
            // This is probably a group message, nothing to be alarmed about.
            return nil
        }
        guard let recipientServiceId = recipientAddressStates!.keys.first!.serviceId else {
            return nil
        }
        let identityManager = DependenciesBridge.shared.identityManager
        guard identityManager.shouldSharePhoneNumber(with: recipientServiceId, tx: tx.asV2Read) else {
            // No PNI signature needed.
            return nil
        }
        guard let pni = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.pni else {
            owsFailDebug("missing PNI")
            return nil
        }
        guard let pniIdentityKeyPair = identityManager.identityKeyPair(for: .pni, tx: tx.asV2Read) else {
            owsFailDebug("missing PNI identity key")
            return nil
        }
        guard let aciIdentityKeyPair = identityManager.identityKeyPair(for: .aci, tx: tx.asV2Read) else {
            owsFailDebug("missing ACI identity key")
            return nil
        }

        let signature = pniIdentityKeyPair.identityKeyPair.signAlternateIdentity(
            aciIdentityKeyPair.identityKeyPair.identityKey)

        let builder = SSKProtoPniSignatureMessage.builder()
        builder.setPni(pni.rawUUID.data)
        builder.setSignature(Data(signature))
        return builder.buildInfallibly()
    }

    fileprivate func maybeClearShouldSharePhoneNumber(
        for recipientAddress: SignalServiceAddress,
        recipientDeviceId deviceId: UInt32,
        transaction: SDSAnyWriteTransaction
    ) {
        guard let aci = recipientAddress.serviceId as? Aci else {
            // We can't be sharing our phone number b/c there's no ACI.
            return
        }

        guard recipientAddressStates?[recipientAddress]?.wasSentByUD == true else {
            // Can't be sure the message was actually decrypted by the recipient,
            // because the server sends delivery receipts for non-sealed-sender messages.
            return
        }

        let identityManager = DependenciesBridge.shared.identityManager
        guard identityManager.shouldSharePhoneNumber(with: aci, tx: transaction.asV2Read) else {
            // Not currently sharing anyway!
            return
        }

        let messageSendLog = SSKEnvironment.shared.messageSendLogRef
        let messagePayload = messageSendLog.fetchPayload(
            recipientAci: aci,
            recipientDeviceId: deviceId,
            timestamp: timestamp,
            tx: transaction
        )
        guard let messagePayload, let payloadId = messagePayload.payloadId else {
            // Can't check whether this message included a PNI signature.
            return
        }

        let deviceIdsPendingDelivery = messageSendLog.deviceIdsPendingDelivery(
            for: payloadId,
            recipientAci: aci,
            tx: transaction
        )
        guard let deviceIdsPendingDelivery, deviceIdsPendingDelivery == [deviceId] else {
            // Other devices still need the PniSignature.
            return
        }

        guard let content = try? SSKProtoContent(serializedData: messagePayload.plaintextContent),
              let messagePniData = content.pniSignatureMessage?.pni else {
            // No PNI signature in the message.
            return
        }

        guard let currentPni = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)?.pni else {
            owsFailDebug("missing local PNI")
            return
        }

        if messagePniData == currentPni.rawUUID.data {
            identityManager.clearShouldSharePhoneNumber(with: aci, tx: transaction.asV2Write)
        }
    }
}

// MARK: - Receipts

extension TSOutgoingMessage {
    public func update(
        withDeliveredRecipient recipientAddress: SignalServiceAddress,
        deviceId: UInt32,
        deliveryTimestamp timestamp: UInt64,
        context: DeliveryReceiptContext,
        tx: SDSAnyWriteTransaction
    ) {
        handleReceipt(
            from: recipientAddress,
            deviceId: deviceId,
            type: \.deliveryTimestamp,
            timestamp: timestamp,
            tryToClearPhoneNumberSharing: true,
            tx: tx
        )
    }

    public func update(
        withReadRecipient recipientAddress: SignalServiceAddress,
        deviceId: UInt32,
        readTimestamp timestamp: UInt64,
        tx: SDSAnyWriteTransaction
    ) {
        handleReceipt(from: recipientAddress, deviceId: deviceId, type: \.readTimestamp, timestamp: timestamp, tx: tx)
    }

    public func update(
        withViewedRecipient recipientAddress: SignalServiceAddress,
        deviceId: UInt32,
        viewedTimestamp timestamp: UInt64,
        tx: SDSAnyWriteTransaction
    ) {
        handleReceipt(from: recipientAddress, deviceId: deviceId, type: \.viewedTimestamp, timestamp: timestamp, tx: tx)
    }

    private func handleReceipt(
        from recipientAddress: SignalServiceAddress,
        deviceId: UInt32,
        type timestampProperty: ReferenceWritableKeyPath<TSOutgoingMessageRecipientState, NSNumber?>,
        timestamp: UInt64,
        tryToClearPhoneNumberSharing: Bool = false,
        tx: SDSAnyWriteTransaction
    ) {
        owsAssertDebug(recipientAddress.isValid)

        // Ignore receipts for messages that have been deleted. They are no longer
        // relevant to this message.
        if wasRemotelyDeleted {
            return
        }

        // Note that this relies on the Message Send Log, so we have to execute it first.
        if tryToClearPhoneNumberSharing {
            maybeClearShouldSharePhoneNumber(for: recipientAddress, recipientDeviceId: deviceId, transaction: tx)
        }

        // This is only necessary for delivery receipts, but while we're here with
        // an open write transaction, we check it for other receipts as well.
        clearMessageSendLogEntry(forRecipient: recipientAddress, deviceId: deviceId, tx: tx)

        anyUpdateOutgoingMessage(transaction: tx) { message in
            guard let recipientState = message.recipientAddressStates?[recipientAddress] else {
                owsFailDebug("Missing recipient state for \(recipientAddress)")
                return
            }
            recipientState.state = .sent
            recipientState[keyPath: timestampProperty] = NSNumber(value: timestamp)
            recipientState.errorCode = nil
        }
    }
}

// MARK: - Sender Key + Message Send Log

extension TSOutgoingMessage {

    /// A collection of message unique IDs related to the outgoing message
    ///
    /// Used to help prune the Message Send Log. For example, a properly annotated outgoing reaction
    /// message will automatically be deleted from the Message Send Log when the reacted message is
    /// deleted.
    ///
    /// Subclasses should override to include any interactionIds their specific subclass relates to. Subclasses
    /// *probably* want to return a union with the results of their parent class' implementation
    @objc
    var relatedUniqueIds: Set<String> {
        Set([self.uniqueId])
    }

    /// Returns a content hint appropriate for representing this content
    ///
    /// If a message is sent with sealed sender, this will be included inside the envelope. A recipient who's
    /// able to decrypt the envelope, but unable to decrypt the inner content can use this to infer how to
    /// handle recovery based on the user-visibility of the content and likelihood of recovery.
    ///
    /// See: SealedSenderContentHint
    @objc
    var contentHint: SealedSenderContentHint {
        .resendable
    }

    /// Returns a groupId relevant to the message. This is included in the envelope, outside the content encryption.
    ///
    /// Usually, this will be the groupId of the target thread. However, there's a special case here where message resend
    /// responses will inherit the groupId of the original message. This probably shouldn't be overridden by anything except
    /// OWSOutgoingMessageResendResponse
    @objc
    func envelopeGroupIdWithTransaction(_ transaction: SDSAnyReadTransaction) -> Data? {
        (thread(tx: transaction) as? TSGroupThread)?.groupId
    }

    /// Indicates whether or not this message's proto should be saved into the MessageSendLog
    ///
    /// Anything high volume or time-dependent (typing indicators, calls, etc.) should set this false.
    /// A non-resendable content hint does not necessarily mean this should be false set false (though
    /// it is a good indicator)
    @objc
    var shouldRecordSendLog: Bool { true }

    /// Used in MessageSender to signal how a message should be encrypted before sending
    /// Currently only overridden by OWSOutgoingResendRequest (this is asserted in the MessageSender implementation)
    @objc
    var encryptionStyle: EncryptionStyle { .whisper }

    @objc
    func clearMessageSendLogEntry(forRecipient address: SignalServiceAddress, deviceId: UInt32, tx: SDSAnyWriteTransaction) {
        // MSL entries will only exist for addresses with ACIs
        guard let aci = address.serviceId as? Aci else {
            return
        }
        let messageSendLog = SSKEnvironment.shared.messageSendLogRef
        messageSendLog.recordSuccessfulDelivery(
            message: self,
            recipientAci: aci,
            recipientDeviceId: deviceId,
            tx: tx
        )
    }

    @objc
    func markMessageSendLogEntryCompleteIfNeeded(tx: SDSAnyWriteTransaction) {
        guard sendingRecipientAddresses().isEmpty else {
            return
        }
        let messageSendLog = SSKEnvironment.shared.messageSendLogRef
        messageSendLog.sendComplete(message: self, tx: tx)
    }
}

// MARK: - Transcripts

public extension TSOutgoingMessage {
    func sendSyncTranscript() async throws {
        let messageSend = try await databaseStorage.awaitableWrite { tx in
            guard let localThread = TSContactThread.getOrCreateLocalThread(transaction: tx) else {
                throw OWSAssertionError("Missing local thread")
            }

            guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read) else {
                throw OWSAssertionError("Missing localIdentifiers.")
            }

            guard let transcript = self.buildTranscriptSyncMessage(localThread: localThread, transaction: tx) else {
                throw OWSAssertionError("Failed to build transcript")
            }

            guard let serializedMessage = self.messageSender.buildAndRecordMessage(transcript, in: localThread, tx: tx) else {
                throw OWSAssertionError("Couldn't serialize message.")
            }

            return OWSMessageSend(
                message: transcript,
                plaintextContent: serializedMessage.plaintextData,
                plaintextPayloadId: serializedMessage.payloadId,
                thread: localThread,
                serviceId: localIdentifiers.aci,
                udSendingAccess: nil,
                localIdentifiers: localIdentifiers,
                sendErrorBlock: nil
            )
        }
        return try await messageSender.performMessageSendAttempt(messageSend).awaitable()
    }
}
