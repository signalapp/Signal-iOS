//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

// MARK: - Get recipients

extension TSOutgoingMessage {
    @objc
    open func recipientState(for address: SignalServiceAddress) -> TSOutgoingMessageRecipientState? {
        return recipientAddressStates?[address]
    }

    /// All recipients of this message.
    @objc
    public func recipientAddresses() -> [SignalServiceAddress] {
        return filterRecipientAddresses { _ in
            return true
        }
    }

    /// All recipients of this message to whom we are currently trying to send.
    @objc
    public func sendingRecipientAddresses() -> [SignalServiceAddress] {
        return filterRecipientAddresses { state in
            switch state.status {
            case .sending, .pending: return true
            case .skipped, .failed, .sent, .delivered, .read, .viewed: return false
            }
        }
    }

    /// All recipients of this message to whom it has been sent, including those
    /// for whom it has been delivered, read, or viewed.
    ///
    /// - Note: we only learn "read" status if read receipts are enabled.
    @objc
    public func sentRecipientAddresses() -> [SignalServiceAddress] {
        return filterRecipientAddresses { state in
            switch state.status {
            case .sent, .delivered, .read, .viewed: return true
            case .skipped, .sending, .pending, .failed: return false
            }
        }
    }

    /// All recipients of this message to whom it has been sent and delivered,
    /// including those for whom it has been read or viewed.
    ///
    /// - Note: we only learn "read" status if read receipts are enabled.
    @objc
    public func deliveredRecipientAddresses() -> [SignalServiceAddress] {
        return filterRecipientAddresses { state in
            switch state.status {
            case .delivered, .read, .viewed: return true
            case .skipped, .sending, .sent, .pending, .failed: return false
            }
        }
    }

    /// All recipients of this message to whom it has been sent, delivered, and
    /// read, including those for whom it has been viewed.
    ///
    /// - Note: we only learn "read" status if read receipts are enabled.
    @objc
    open func readRecipientAddresses() -> [SignalServiceAddress] {
        return filterRecipientAddresses { state in
            switch state.status {
            case .read, .viewed: return true
            case .skipped, .sending, .sent, .delivered, .pending, .failed: return false
            }
        }
    }

    /// All recipients of this message to whom it has been sent, delivered, and
    /// viewed.
    @objc
    public func viewedRecipientAddresses() -> [SignalServiceAddress] {
        return filterRecipientAddresses { state in
            switch state.status {
            case .viewed: return true
            case .skipped, .sending, .sent, .delivered, .read, .pending, .failed: return false
            }
        }
    }

    @objc
    public func failedRecipientAddresses(errorCode: Int) -> [SignalServiceAddress] {
        return filterRecipientAddresses { state in
            return state.status == .failed && state.errorCode == errorCode
        }
    }

    private func filterRecipientAddresses(
        predicate: (TSOutgoingMessageRecipientState) -> Bool
    ) -> [SignalServiceAddress] {
        guard let recipientAddressStates else { return [] }

        return recipientAddressStates.filter { _, state in
            predicate(state)
        }.map { $0.key }
    }
}

// MARK: - Update recipients

public extension TSOutgoingMessage {
    @objc
    func updateWithRecipientAddressStates(
        _ recipientAddressStates: [SignalServiceAddress: TSOutgoingMessageRecipientState]?,
        tx: SDSAnyWriteTransaction
    ) {
        anyUpdateOutgoingMessage(transaction: tx) { outgoingMessage in
            outgoingMessage.recipientAddressStates = recipientAddressStates
        }
    }

    /// Records a successful send to a one recipient.
    func updateWithSentRecipient(
        _ serviceId: ServiceId,
        wasSentByUD: Bool,
        transaction tx: SDSAnyWriteTransaction
    ) {
        let address = SignalServiceAddress(serviceId)

        anyUpdateOutgoingMessage(transaction: tx) { outgoingMessage in
            guard let recipientState = outgoingMessage.recipientAddressStates?[address] else {
                owsFailDebug("Missing recipient state for recipient: \(address)!")
                return
            }

            recipientState.updateStatus(.sent)
            recipientState.wasSentByUD = wasSentByUD
            recipientState.errorCode = nil
        }
    }

    /// Records a skipped send to one recipient.
    func updateWithSkippedRecipient(
        _ address: SignalServiceAddress,
        transaction tx: SDSAnyWriteTransaction
    ) {
        anyUpdateOutgoingMessage(transaction: tx) { outgoingMessage in
            guard let recipientState = outgoingMessage.recipientAddressStates?[address] else {
                owsFailDebug("Missing recipient state for recipient: \(address)!")
                return
            }

            recipientState.updateStatus(.skipped)
        }
    }

    /// Updates recipients based on information from a linked device outgoing
    /// message transcript.
    ///
    /// - Parameter isSentUpdate:
    /// If false, treats this as message creation, overwriting all existing
    /// recipient state. Otherwise, treats this as a sent update, only adding or
    /// updating recipients but never removing.
    func updateRecipientsFromNonLocalDevice(
        _ nonLocalRecipientStates: [SignalServiceAddress: TSOutgoingMessageRecipientState],
        isSentUpdate: Bool,
        transaction tx: SDSAnyWriteTransaction
    ) {
        anyUpdateOutgoingMessage(transaction: tx) { outgoingMessage in
            let localRecipientStates = outgoingMessage.recipientAddressStates ?? [:]

            if nonLocalRecipientStates.count > 0 {
                /// If we have specific recipient info from the transcript,
                /// build new recipient states wholesale.
                if isSentUpdate {
                    /// If this is a "sent update", make sure that:
                    ///
                    /// 1) We never remove any recipients. We end up with the
                    /// union of the existing and new recipients.
                    ///
                    /// 2) We never downgrade the recipient state for any
                    /// recipients. Prefer existing recipient state; "sent
                    /// updates" only add new recipients in the "sent" state.
                    var nonLocalRecipientStates = nonLocalRecipientStates
                    for (recipientAddress, recipientState) in localRecipientStates {
                        nonLocalRecipientStates[recipientAddress] = recipientState
                    }

                    outgoingMessage.recipientAddressStates = nonLocalRecipientStates
                } else {
                    outgoingMessage.recipientAddressStates = nonLocalRecipientStates
                }
            } else {
                /// Otherwise, mark any "sending" recipients as "sent".
                for recipientState in localRecipientStates.values {
                    guard recipientState.status == .sending else {
                        continue
                    }

                    recipientState.updateStatus(.sent)
                }
            }

            if !isSentUpdate {
                outgoingMessage.wasNotCreatedLocally = true
            }
        }
    }

    /// Records failed sends to the given recipients.
    func updateWithFailedRecipients(
        _ recipientErrors: some Collection<(serviceId: ServiceId, error: Error)>,
        tx: SDSAnyWriteTransaction
    ) {
        let fatalErrors = recipientErrors.lazy.filter { !$0.error.isRetryable }
        let retryableErrors = recipientErrors.lazy.filter { $0.error.isRetryable }

        if fatalErrors.isEmpty {
            Logger.warn("Couldn't send \(self.timestamp), but all errors are retryable: \(Array(retryableErrors))")
        } else {
            Logger.warn("Couldn't send \(self.timestamp): \(Array(fatalErrors)); retryable errors: \(Array(retryableErrors))")
        }

        self.anyUpdateOutgoingMessage(transaction: tx) {
            for (serviceId, error) in recipientErrors {
                guard let recipientState = $0.recipientAddressStates?[SignalServiceAddress(serviceId)] else {
                    owsFailDebug("Missing recipient state for \(serviceId)")
                    continue
                }
                if error.isRetryable, recipientState.status == .sending {
                    // For retryable errors, we can just set the error code and leave the
                    // state set as Sending
                } else if error is SpamChallengeRequiredError || error is SpamChallengeResolvedError {
                    recipientState.updateStatus(.pending)
                } else {
                    recipientState.updateStatus(.failed)
                }

                recipientState.errorCode = (error as NSError).code
            }
        }
    }

    /// Mark all "sending" recipients as "failed".
    ///
    /// This should be called on app launch.
    @objc
    func updateWithAllSendingRecipientsMarkedAsFailed(
        error: (any Error)? = nil,
        transaction tx: SDSAnyWriteTransaction
    ) {
        anyUpdateOutgoingMessage(transaction: tx) { outgoingMessage in
            if let error {
                outgoingMessage.mostRecentFailureText = error.userErrorDescription
            }

            guard let recipientAddressStates = outgoingMessage.recipientAddressStates else {
                return
            }

            for recipientState in recipientAddressStates.values {
                if recipientState.status == .sending {
                    recipientState.updateStatus(.failed)
                }
            }
        }
    }

    /// Mark all "failed" recipients as "sending".
    ///
    /// This should be called when we start a message send.
    func updateAllUnsentRecipientsAsSending(
        transaction tx: SDSAnyWriteTransaction
    ) {
        anyUpdateOutgoingMessage(transaction: tx) { outgoingMessage in
            guard let recipientAddressStates = outgoingMessage.recipientAddressStates else {
                return
            }

            for recipientState in recipientAddressStates.values {
                if recipientState.status == .failed {
                    recipientState.updateStatus(.sending)
                }
            }
        }
    }
}

#if TESTABLE_BUILD
public extension TSOutgoingMessage {
    func updateWithFakeMessageState(
        _ messageState: TSOutgoingMessageState,
        tx: SDSAnyWriteTransaction
    ) {
        anyUpdateOutgoingMessage(transaction: tx) { outgoingMessage in
            guard let recipientAddressStates = outgoingMessage.recipientAddressStates else {
                return
            }

            for recipientState in recipientAddressStates.values {
                switch messageState {
                case .sending:
                    recipientState.updateStatus(.sending)
                case .failed:
                    recipientState.updateStatus(.failed)
                case .sent:
                    recipientState.updateStatus(.sent)
                case .pending:
                    recipientState.updateStatus(.pending)
                case .sent_OBSOLETE, .delivered_OBSOLETE:
                    break
                }
            }
        }
    }
}
#endif

// MARK: -

public extension TSOutgoingMessage {
    @objc
    static func messageStateForRecipientStates(
        _ recipientStates: [TSOutgoingMessageRecipientState]
    ) -> TSOutgoingMessageState {
        var hasFailedRecipient: Bool = false

        for recipientState in recipientStates {
            switch recipientState.status {
            case .sending:
                return .sending
            case .pending:
                return .pending
            case .failed:
                hasFailedRecipient = true
            case .skipped, .sent, .delivered, .read, .viewed:
                break
            }
        }

        if hasFailedRecipient {
            return .failed
        } else {
            return .sent
        }
    }

    @objc
    static func isEligibleToStartExpireTimer(recipientStates: [TSOutgoingMessageRecipientState]) -> Bool {
        let messageState = Self.messageStateForRecipientStates(recipientStates)
        return isEligibleToStartExpireTimer(messageState: messageState)
    }

    // This method will be called after every insert and update, so it needs
    // to be cheap.
    @objc
    static func isEligibleToStartExpireTimer(messageState: TSOutgoingMessageState) -> Bool {
        switch messageState {
        case .sent, .sent_OBSOLETE, .delivered_OBSOLETE:
            // If _all_ recipients have been sent (not necessarily received or viewed)
            // we should start the expire timer.
            return true
        case .pending, .sending, .failed:
            // If _any_ recipient is pending or failed, don't start the timer.
            return false
        }
    }

    @objc
    var isStorySend: Bool { isGroupStoryReply }

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

    @objc
    func addGroupsV2ToDataMessageBuilder(
        _ builder: SSKProtoDataMessageBuilder,
        groupThread: TSGroupThread,
        tx: SDSAnyReadTransaction
    ) -> OutgoingGroupProtoResult {
        guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
            owsFailDebug("Invalid group model.")
            return .error
        }

        do {
            let groupContextV2 = try GroupsV2Protos.buildGroupContextProto(
                groupModel: groupModel,
                groupChangeProtoData: self.changeActionsProtoData
            )
            builder.setGroupV2(groupContextV2)
            return .addedWithoutGroupAvatar
        } catch {
            owsFailDebug("Error: \(error)")
            return .error
        }
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

// MARK: - Attachments

extension TSOutgoingMessage {

    @objc
    func buildProtosForBodyAttachments(tx: SDSAnyReadTransaction) throws -> [SSKProtoAttachmentPointer] {
        let attachments = sqliteRowId.map { sqliteRowId in
            return DependenciesBridge.shared.attachmentStore.fetchReferencedAttachments(
                owners: [
                    .messageOversizeText(messageRowId: sqliteRowId),
                    .messageBodyAttachment(messageRowId: sqliteRowId)
                ],
                tx: tx.asV2Read
            )
        } ?? []
        return attachments.compactMap { attachment in
            guard let pointer = attachment.attachment.asTransitTierPointer() else {
                owsFailDebug("Generating proto for non-uploaded attachment!")
                return nil
            }
            return DependenciesBridge.shared.attachmentManager.buildProtoForSending(
                from: attachment.reference,
                pointer: pointer
            )
        }
    }

    @objc
    func buildLinkPreviewProto(
        linkPreview: OWSLinkPreview,
        tx: SDSAnyReadTransaction
    ) throws -> SSKProtoPreview {
        return try DependenciesBridge.shared.linkPreviewManager.buildProtoForSending(
            linkPreview,
            parentMessage: self,
            tx: tx.asV2Read
        )
    }

    @objc
    func buildContactShareProto(
        _ contact: OWSContact,
        tx: SDSAnyReadTransaction
    ) throws -> SSKProtoDataMessageContact {
        return try DependenciesBridge.shared.contactShareManager.buildProtoForSending(
            from: contact,
            parentMessage: self,
            tx: tx.asV2Read
        )
    }

    @objc
    func buildStickerProto(
        sticker: MessageSticker,
        tx: SDSAnyReadTransaction
    ) throws -> SSKProtoDataMessageSticker {
        return try DependenciesBridge.shared.messageStickerManager.buildProtoForSending(
            sticker,
            parentMessage: self,
            tx: tx.asV2Read
        )
    }

    @objc
    func buildQuoteProto(
        quote: TSQuotedMessage,
        tx: SDSAnyReadTransaction
    ) throws -> SSKProtoDataMessageQuote {
        return try DependenciesBridge.shared.quotedReplyManager.buildProtoForSending(
            quote,
            parentMessage: self,
            tx: tx.asV2Read
        )
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
            receiptType: .delivered,
            receiptTimestamp: timestamp,
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
        handleReceipt(
            from: recipientAddress,
            deviceId: deviceId,
            receiptType: .read,
            receiptTimestamp: timestamp,
            tx: tx
        )
    }

    public func update(
        withViewedRecipient recipientAddress: SignalServiceAddress,
        deviceId: UInt32,
        viewedTimestamp timestamp: UInt64,
        tx: SDSAnyWriteTransaction
    ) {
        handleReceipt(
            from: recipientAddress,
            deviceId: deviceId,
            receiptType: .viewed,
            receiptTimestamp: timestamp,
            tx: tx
        )
    }

    private enum IncomingReceiptType {
        case delivered
        case read
        case viewed

        var asRecipientStatus: OWSOutgoingMessageRecipientStatus {
            switch self {
            case .delivered: return .delivered
            case .read: return .read
            case .viewed: return .viewed
            }
        }
    }

    private func handleReceipt(
        from recipientAddress: SignalServiceAddress,
        deviceId: UInt32,
        receiptType: IncomingReceiptType,
        receiptTimestamp: UInt64,
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

        let recipientStateMerger = RecipientStateMerger(
            recipientDatabaseTable: DependenciesBridge.shared.recipientDatabaseTable,
            signalServiceAddressCache: SSKEnvironment.shared.signalServiceAddressCacheRef
        )
        anyUpdateOutgoingMessage(transaction: tx) { message in
            guard let recipientState: TSOutgoingMessageRecipientState = {
                if let existingMatch = message.recipientAddressStates?[recipientAddress] {
                    return existingMatch
                }
                if let normalizedAddress = recipientStateMerger.normalizedAddressIfNeeded(for: recipientAddress, tx: tx.asV2Read) {
                    // If we get a receipt from a PNI, then normalizing PNIs -> ACIs won't fix
                    // it, but normalizing the address from a PNI to an ACI might fix it.
                    return message.recipientAddressStates?[normalizedAddress]
                } else {
                    // If we get a receipt from an ACI, then we might have the PNI stored, and
                    // we need to migrate it to the ACI before we'll be able to find it.
                    recipientStateMerger.normalize(&message.recipientAddressStates, tx: tx.asV2Read)
                    return message.recipientAddressStates?[recipientAddress]
                }
            }() else {
                owsFailDebug("Missing recipient state for \(recipientAddress)")
                return
            }

            /// We want to avoid "downgrading" the recipient status; for
            /// example, if we receive a delivery receipt after a read receipt,
            /// we want to preserve the `.read` status.
            ///
            /// We do, however, support overwriting the recipient status'
            /// timestamp when receiving a receipt matching the existing
            /// recipient status (e.g., receiving a `.read` receipt when the
            /// recipient status is already `.read`).
            let shouldUpdateRecipientStatus: Bool = {
                switch (recipientState.status, receiptType) {
                case (.failed, _), (.sending, _), (.sent, _), (.skipped, _), (.pending, _):
                    return true
                case
                        (.delivered, .delivered),
                        (.delivered, .read),
                        (.delivered, .viewed),
                        (.read, .read),
                        (.read, .viewed),
                        (.viewed, .viewed):
                    return true
                case
                        (.read, .delivered),
                        (.viewed, .delivered),
                        (.viewed, .read):
                    return false
                }
            }()

            if shouldUpdateRecipientStatus {
                recipientState.updateStatus(
                    receiptType.asRecipientStatus,
                    statusTimestamp: receiptTimestamp
                )
                recipientState.errorCode = nil
            }
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
        let messageSend = try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            guard let localThread = TSContactThread.getOrCreateLocalThread(transaction: tx) else {
                throw OWSAssertionError("Missing local thread")
            }

            guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read) else {
                throw OWSAssertionError("Missing localIdentifiers.")
            }

            guard let transcript = self.buildTranscriptSyncMessage(localThread: localThread, transaction: tx) else {
                throw OWSAssertionError("Failed to build transcript")
            }

            guard let serializedMessage = SSKEnvironment.shared.messageSenderRef.buildAndRecordMessage(transcript, in: localThread, tx: tx) else {
                throw OWSAssertionError("Couldn't serialize message.")
            }

            return OWSMessageSend(
                message: transcript,
                plaintextContent: serializedMessage.plaintextData,
                plaintextPayloadId: serializedMessage.payloadId,
                thread: localThread,
                serviceId: localIdentifiers.aci,
                localIdentifiers: localIdentifiers
            )
        }
        try await SSKEnvironment.shared.messageSenderRef.performMessageSend(messageSend, sealedSenderParameters: nil)
    }
}
