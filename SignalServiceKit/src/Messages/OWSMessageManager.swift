//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalCoreKit

/// An ObjC wrapper around UnidentifiedSenderMessageContent.ContentHint
@objc
public enum SealedSenderContentHint: Int, Codable, CustomStringConvertible {
    /// Indicates that the content of a message requires rendering user-visible errors immediately
    /// upon decryption failure. It is not expected that it will be resent, and we make no attempt
    /// to preserve ordering if it is.
    /// Insert a placeholder: No
    /// Show error to user: Yes, immediately
    case `default` = 0
    /// Indicates that the content of a message requires rendering user-visible errors upon
    /// decryption failure, but errors will be delayed in case the message is resent before
    /// the user attempts to view it. In order to facilitate insertion of resent messages in situ, a
    /// placeholder is inserted into the interaction table to reserve its positioning.
    /// Insert a placeholder: Yes
    /// Show error to user: Yes, after some deferral period
    case resendable
    /// Indicates that the content of a message does not require rendering any user-visible
    /// errors upon decryption failure. These messages may be resent, but we don't insert
    /// a placeholder for them so their ordering is not preserved.
    /// Insert a placeholder: No
    /// Show error to user: No
    case implicit

    init(_ signalClientHint: UnidentifiedSenderMessageContent.ContentHint) {
        switch signalClientHint {
        case .default: self = .default
        case .resendable: self = .resendable
        case .implicit: self = .implicit
        default:
            owsFailDebug("Unspecified case \(signalClientHint)")
            self = .default
        }
    }

    public var signalClientHint: UnidentifiedSenderMessageContent.ContentHint {
        switch self {
        case .default: return .default
        case .resendable: return .resendable
        case .implicit: return .implicit
        }
    }

    public var description: String {
        switch self {
        case .default: return "default"
        case .resendable: return "resendable"
        case .implicit: return "implicit"
        }
    }
}

// MARK: -

extension OWSMessageManager {

    private static let pendingTasks = PendingTasks(label: "messageManager")

    public static func pendingTasksPromise() -> Promise<Void> {
        // This promise blocks on all pending tasks already in flight,
        // but will not block on new tasks enqueued after this promise
        // is created. That's intentional to ensure that NotificationService
        // instances complete in a timely way.
        pendingTasks.pendingTasksPromise()
    }

    @objc
    public static func buildPendingTask(label: String) -> PendingTask {
        Self.pendingTasks.buildPendingTask(label: label)
    }

    /// Performs a limited amount of time sensitive processing before scheduling
    /// the remainder of message processing
    ///
    /// Currently, the preprocess step only parses sender key distribution
    /// messages to update the sender key store. It's important the sender key
    /// store is updated *before* the write transaction completes since we don't
    /// know if the next message to be decrypted will depend on the sender key
    /// store being up to date.
    ///
    /// Some other things worth noting:
    ///
    /// - We should preprocess *all* envelopes, even those where the sender is
    /// blocked. This is important because it protects us from a case where the
    /// recipient blocks and then unblocks a user. If the sender they blocked
    /// sent an SKDM while the user was blocked, their understanding of the
    /// world is that we have saved the SKDM. After unblock, if we don't have
    /// the SKDM we'll fail to decrypt.
    ///
    /// - This *needs* to happen in the very same write transaction where the
    /// message was decrypted. It's important to keep in mind that the NSE could
    /// race with the main app when processing messages. The write transaction
    /// is used to protect us from any races.
    func preprocessEnvelope(
        _ decryptedEnvelope: DecryptedIncomingEnvelope,
        tx: SDSAnyWriteTransaction
    ) {
        // Currently, this function is only used for SKDM processing. Since this is
        // idempotent, we don't need to check for a duplicate envelope.
        //
        // SKDM processing is also not user-visible, so we don't want to skip if
        // the sender is blocked. This ensures that we retain session info to
        // decrypt future messages from a blocked sender if they're ever unblocked.

        if let skdmBytes = decryptedEnvelope.content?.senderKeyDistributionMessage {
            handleIncomingEnvelope(decryptedEnvelope, withSenderKeyDistributionMessage: skdmBytes, transaction: tx)
        }
    }

    public func processEnvelope(
        _ envelope: SSKProtoEnvelope,
        plaintextData: Data?,
        wasReceivedByUD: Bool,
        serverDeliveryTimestamp: UInt64,
        shouldDiscardVisibleMessages: Bool,
        localIdentifiers: LocalIdentifiers,
        tx: SDSAnyWriteTransaction
    ) {
        do {
            let validatedEnvelope = try ValidatedIncomingEnvelope(envelope, localIdentifiers: localIdentifiers)
            switch validatedEnvelope.kind {
            case .unidentifiedSender, .identifiedSender:
                // At this point, unidentifiedSender envelopes have already been updated
                // with the sourceAci, so we should be able to parse it from the envelope.
                let (sourceAci, sourceDeviceId) = try validatedEnvelope.validateSource(Aci.self)
                if blockingManager.isAddressBlocked(SignalServiceAddress(sourceAci), transaction: tx) {
                    return
                }
                guard let plaintextData else {
                    throw OWSAssertionError("Missing plaintextData.")
                }
                let decryptedEnvelope = DecryptedIncomingEnvelope(
                    validatedEnvelope: validatedEnvelope,
                    updatedEnvelope: validatedEnvelope.envelope,
                    sourceAci: sourceAci,
                    sourceDeviceId: sourceDeviceId,
                    wasReceivedByUD: wasReceivedByUD,
                    plaintextData: plaintextData
                )
                checkForUnknownLinkedDevice(in: decryptedEnvelope, tx: tx)
                let buildResult = MessageManagerRequest.buildRequest(
                    for: decryptedEnvelope,
                    serverDeliveryTimestamp: serverDeliveryTimestamp,
                    shouldDiscardVisibleMessages: shouldDiscardVisibleMessages,
                    tx: tx
                )
                switch buildResult {
                case .discard:
                    break
                case .request(let messageManagerRequest):
                    handle(messageManagerRequest, context: PassthroughDeliveryReceiptContext(), transaction: tx)
                    fallthrough
                case .noContent:
                    finishProcessingEnvelope(decryptedEnvelope, tx: tx)
                }
            case .serverReceipt:
                owsAssertDebug(plaintextData == nil)
                let envelope = try ServerReceiptEnvelope(validatedEnvelope)
                handleDeliveryReceipt(envelope, context: PassthroughDeliveryReceiptContext(), transaction: tx)
            }
        } catch {
            Logger.warn("Dropping invalid envelope \(error)")
        }
    }

    /// Called when we've finished processing an envelope.
    ///
    /// If we call this method, we tried to process an envelope. However, the
    /// contents of that envelope may or may not be valid.
    ///
    /// Cases where we won't call this method:
    /// - The envelope is missing a sender (or a device ID)
    /// - The envelope has a sender but they're blocked
    /// - The envelope is missing a timestamp
    /// - The user isn't registered
    ///
    /// Cases where we will call this method:
    /// - The envelope contains a fully valid message
    /// - The envelope contains a message with an invalid reaction
    /// - The envelope contains a link preview but the URL isn't in the message
    /// - & so on, for many "errors" that are handled elsewhere
    func finishProcessingEnvelope(_ decryptedEnvelope: DecryptedIncomingEnvelope, tx: SDSAnyWriteTransaction) {
        saveSpamReportingToken(for: decryptedEnvelope, tx: tx)
        clearLeftoverPlaceholders(for: decryptedEnvelope, tx: tx)
    }

    private func saveSpamReportingToken(for decryptedEnvelope: DecryptedIncomingEnvelope, tx: SDSAnyWriteTransaction) {
        guard
            let rawSpamReportingToken = decryptedEnvelope.envelope.spamReportingToken,
            let spamReportingToken = SpamReportingToken(data: rawSpamReportingToken)
        else {
            Logger.debug("Received an envelope without a spam reporting token. Doing nothing")
            return
        }

        Logger.info("Saving spam reporting token. Envelope timestamp: \(decryptedEnvelope.timestamp)")
        do {
            try SpamReportingTokenRecord(
                sourceAci: decryptedEnvelope.sourceAci,
                spamReportingToken: spamReportingToken
            ).upsert(tx.unwrapGrdbWrite.database)
        } catch {
            owsFailBeta(
                "Couldn't save spam reporting token record. Continuing on, to avoid interrupting message processing. Error: \(error)"
            )
        }
    }

    /// Clear any remaining placeholders for a fully-processed message.
    ///
    /// We need to check to make sure that we clear any placeholders that may
    /// have been inserted for this message. This would happen if:
    ///
    /// - This is a resend of a message that we had previously failed to decrypt
    ///
    /// - The message does not result in an inserted TSIncomingMessage or
    /// TSOutgoingMessage. For example, a read receipt. In that case, we should
    /// just clear the placeholder.
    private func clearLeftoverPlaceholders(for envelope: DecryptedIncomingEnvelope, tx: SDSAnyWriteTransaction) {
        do {
            let placeholders = try InteractionFinder.interactions(
                withTimestamp: envelope.timestamp,
                filter: { ($0 as? OWSRecoverableDecryptionPlaceholder)?.sender?.serviceId == envelope.sourceAci },
                transaction: tx
            )
            owsAssertDebug(placeholders.count <= 1)
            for placeholder in placeholders {
                placeholder.anyRemove(transaction: tx)
            }
        } catch {
            owsFailDebug("Failed to fetch placeholders: \(error)")
        }
    }

    @objc(groupIdForDataMessage:)
    func groupId(for dataMessage: SSKProtoDataMessage) -> Data? {
        guard let groupContext = dataMessage.groupV2 else {
            return nil
        }
        guard let masterKey = groupContext.masterKey else {
            owsFailDebug("Missing masterKey.")
            return nil
        }
        do {
            return try groupsV2.groupV2ContextInfo(forMasterKeyData: masterKey).groupId
        } catch {
            owsFailDebug("Invalid group context.")
            return nil
        }
    }

    @objc
    func handleIncomingEnvelope(
        _ decryptedEnvelope: DecryptedIncomingEnvelope,
        syncMessage: SSKProtoSyncMessage,
        plaintextData: Data,
        wasReceivedByUD: Bool,
        serverDeliveryTimestamp: UInt64,
        tx: SDSAnyWriteTransaction
    ) {
        guard decryptedEnvelope.sourceAci == tsAccountManager.localIdentifiers(transaction: tx)?.aci else {
            // Sync messages should only come from linked devices.
            owsFailDebug("Received sync message from another user.")
            return
        }

        let envelope = decryptedEnvelope.envelope
        if let sent = syncMessage.sent {
            guard SDS.fitsInInt64(sent.timestamp) else {
                owsFailDebug("Invalid timestamp.")
                return
            }

            if let dataMessage = sent.message {
                let groupId = groupId(for: dataMessage)
                if let groupId {
                    TSGroupThread.ensureGroupIdMapping(forGroupId: groupId, transaction: tx)
                }

                guard SDS.fitsInInt64(sent.expirationStartTimestamp) else {
                    owsFailDebug("Invalid expirationStartTimestamp.")
                    return
                }

                guard let transcript = OWSIncomingSentMessageTranscript(
                    proto: sent, serverTimestamp: decryptedEnvelope.serverTimestamp, transaction: tx
                ) else {
                    owsFailDebug("Couldn't parse transcript.")
                    return
                }

                if dataMessage.hasProfileKey {
                    if let groupId {
                        profileManager.addGroupId(
                            toProfileWhitelist: groupId, userProfileWriter: .localUser, transaction: tx
                        )
                    } else {
                        // If we observe a linked device sending our profile key to another user,
                        // we can infer that that user belongs in our profile whitelist.
                        let destinationAddress = SignalServiceAddress(
                            serviceIdString: sent.destinationServiceID,
                            phoneNumber: sent.destinationE164
                        )
                        if destinationAddress.isValid {
                            profileManager.addUser(
                                toProfileWhitelist: destinationAddress, userProfileWriter: .localUser, transaction: tx
                            )
                        }
                    }
                }

                if let reaction = dataMessage.reaction {
                    guard let thread = transcript.thread else {
                        owsFailDebug("Could not process reaction from sync transcript.")
                        return
                    }
                    let result = ReactionManager.processIncomingReaction(
                        reaction,
                        thread: thread,
                        reactor: decryptedEnvelope.sourceAciObjC,
                        timestamp: sent.timestamp,
                        serverTimestamp: decryptedEnvelope.serverTimestamp,
                        expiresInSeconds: dataMessage.expireTimer,
                        sentTranscript: transcript,
                        transaction: tx
                    )
                    switch result {
                    case .success, .invalidReaction:
                        break
                    case .associatedMessageMissing:
                        let messageAuthor = Aci.parseFrom(aciString: reaction.targetAuthorAci)
                        earlyMessageManager.recordEarlyEnvelope(
                            envelope,
                            plainTextData: plaintextData,
                            wasReceivedByUD: wasReceivedByUD,
                            serverDeliveryTimestamp: serverDeliveryTimestamp,
                            associatedMessageTimestamp: reaction.timestamp,
                            associatedMessageAuthor: messageAuthor.map { AciObjC($0) },
                            transaction: tx
                        )
                    }
                } else if let delete = dataMessage.delete {
                    let result = TSMessage.tryToRemotelyDeleteMessage(
                        fromAuthor: decryptedEnvelope.sourceAciObjC,
                        sentAtTimestamp: delete.targetSentTimestamp,
                        threadUniqueId: transcript.thread?.uniqueId,
                        serverTimestamp: decryptedEnvelope.serverTimestamp,
                        transaction: tx
                    )
                    switch result {
                    case .success:
                        break
                    case .invalidDelete:
                        Logger.error("Failed to remotely delete message \(delete.targetSentTimestamp)")
                    case .deletedMessageMissing:
                        earlyMessageManager.recordEarlyEnvelope(
                            envelope,
                            plainTextData: plaintextData,
                            wasReceivedByUD: wasReceivedByUD,
                            serverDeliveryTimestamp: serverDeliveryTimestamp,
                            associatedMessageTimestamp: delete.targetSentTimestamp,
                            associatedMessageAuthor: decryptedEnvelope.sourceAciObjC,
                            transaction: tx
                        )
                    }
                } else if let groupCallUpdate = dataMessage.groupCallUpdate {
                    if let groupId, let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: tx) {
                        let pendingTask = OWSMessageManager.buildPendingTask(label: "GroupCallUpdate")
                        callMessageHandler?.receivedGroupCallUpdateMessage(
                            groupCallUpdate,
                            for: groupThread,
                            serverReceivedTimestamp: decryptedEnvelope.timestamp,
                            completion: { pendingTask.complete() }
                        )
                    } else {
                        Logger.warn("Received GroupCallUpdate for unknown groupId")
                    }
                } else {
                    OWSRecordTranscriptJob.processIncomingSentMessageTranscript(transcript, transaction: tx)
                }
            } else if sent.isStoryTranscript {
                do {
                    try StoryManager.processStoryMessageTranscript(sent, transaction: tx)
                } catch {
                    owsFailDebug("Failed to process story message transcript \(error)")
                }
            } else if let editMessage = sent.editMessage {
                let result = handleIncomingEnvelope(
                    decryptedEnvelope, sentMessage: sent, editMessage: editMessage, transaction: tx
                )
                switch result {
                case .success, .invalidEdit:
                    break
                case .editedMessageMissing:
                    earlyMessageManager.recordEarlyEnvelope(
                        envelope,
                        plainTextData: plaintextData,
                        wasReceivedByUD: wasReceivedByUD,
                        serverDeliveryTimestamp: serverDeliveryTimestamp,
                        associatedMessageTimestamp: editMessage.targetSentTimestamp,
                        associatedMessageAuthor: decryptedEnvelope.sourceAciObjC,
                        transaction: tx
                    )
                }
            }
        } else if let request = syncMessage.request {
            handleIncomingSyncRequest(request, tx: tx)
        } else if let blocked = syncMessage.blocked {
            Logger.info("Received blocked sync message.")
            handleSyncedBlocklist(blocked, tx: tx)
        } else if !syncMessage.read.isEmpty {
            Logger.info("Received \(syncMessage.read.count) read receipt(s) in sync message")
            let earlyReceipts = receiptManager.processReadReceiptsFromLinkedDevice(
                syncMessage.read, readTimestamp: decryptedEnvelope.timestamp, tx: tx
            )
            for readReceiptProto in earlyReceipts {
                let messageAuthor = Aci.parseFrom(aciString: readReceiptProto.senderAci)
                earlyMessageManager.recordEarlyReadReceiptFromLinkedDevice(
                    timestamp: decryptedEnvelope.timestamp,
                    associatedMessageTimestamp: readReceiptProto.timestamp,
                    associatedMessageAuthor: messageAuthor.map { AciObjC($0) },
                    transaction: tx
                )
            }
        } else if !syncMessage.viewed.isEmpty {
            Logger.info("Received \(syncMessage.viewed.count) viewed receipt(s) in sync message")
            let earlyReceipts = receiptManager.processViewedReceiptsFromLinkedDevice(
                syncMessage.viewed, viewedTimestamp: decryptedEnvelope.timestamp, tx: tx
            )
            for viewedReceiptProto in earlyReceipts {
                let messageAuthor = Aci.parseFrom(aciString: viewedReceiptProto.senderAci)
                earlyMessageManager.recordEarlyViewedReceiptFromLinkedDevice(
                    timestamp: decryptedEnvelope.timestamp,
                    associatedMessageTimestamp: viewedReceiptProto.timestamp,
                    associatedMessageAuthor: messageAuthor.map { AciObjC($0) },
                    transaction: tx
                )
            }
        } else if let verified = syncMessage.verified {
            do {
                try identityManager.processIncomingVerifiedProto(verified, transaction: tx)
                identityManager.fireIdentityStateChangeNotification(after: tx)
            } catch {
                Logger.warn("Couldn't process verification state \(error)")
            }
        } else if !syncMessage.stickerPackOperation.isEmpty {
            Logger.info("Received sticker pack operation(s): \(syncMessage.stickerPackOperation.count)")
            for packOperationProto in syncMessage.stickerPackOperation {
                StickerManager.processIncomingStickerPackOperation(packOperationProto, transaction: tx)
            }
        } else if let viewOnceOpen = syncMessage.viewOnceOpen {
            Logger.info("Received view-once read receipt sync message")
            let result = ViewOnceMessages.processIncomingSyncMessage(viewOnceOpen, envelope: envelope, transaction: tx)
            switch result {
            case .success, .invalidSyncMessage:
                break
            case .associatedMessageMissing(let senderAci, let associatedMessageTimestamp):
                earlyMessageManager.recordEarlyEnvelope(
                    envelope,
                    plainTextData: plaintextData,
                    wasReceivedByUD: wasReceivedByUD,
                    serverDeliveryTimestamp: serverDeliveryTimestamp,
                    associatedMessageTimestamp: associatedMessageTimestamp,
                    associatedMessageAuthor: AciObjC(senderAci),
                    transaction: tx
                )
            }
        } else if let configuration = syncMessage.configuration {
            syncManager.processIncomingConfigurationSyncMessage(configuration, transaction: tx)
        } else if let contacts = syncMessage.contacts {
            syncManager.processIncomingContactsSyncMessage(contacts, transaction: tx)
        } else if let fetchLatest = syncMessage.fetchLatest {
            syncManager.processIncomingFetchLatestSyncMessage(fetchLatest, transaction: tx)
        } else if let keys = syncMessage.keys {
            syncManager.processIncomingKeysSyncMessage(keys, transaction: tx)
        } else if let messageRequestResponse = syncMessage.messageRequestResponse {
            syncManager.processIncomingMessageRequestResponseSyncMessage(messageRequestResponse, transaction: tx)
        } else if let outgoingPayment = syncMessage.outgoingPayment {
            // An "incoming" sync message notifies us of an "outgoing" payment.
            paymentsHelper.processIncomingPaymentSyncMessage(
                outgoingPayment, messageTimestamp: serverDeliveryTimestamp, transaction: tx
            )
        } else if let callEvent = syncMessage.callEvent {
            Logger.info("Received call event sync message.")
            CallRecord.createOrUpdateForSyncMessage(
                callEvent, messageTimestamp: decryptedEnvelope.timestamp, transaction: tx
            )
        } else if let pniChangeNumber = syncMessage.pniChangeNumber {
            identityManager.processIncomingPniChangePhoneNumber(
                proto: pniChangeNumber, updatedPni: envelope.updatedPni, transaction: tx
            )
        } else {
            Logger.warn("Ignoring unsupported sync message.")
        }
    }

    private func handleIncomingSyncRequest(_ request: SSKProtoSyncMessageRequest, tx: SDSAnyWriteTransaction) {
        guard tsAccountManager.isRegisteredPrimaryDevice else {
            // Don't respond to sync requests from a linked device.
            return
        }
        switch request.type {
        case .contacts:
            // We respond asynchronously because populating the sync message will
            // create transactions and it's not practical (due to locking in the
            // OWSIdentityManager) to plumb our transaction through.
            //
            // In rare cases this means we won't respond to the sync request, but
            // that's acceptable.
            let pendingTask = Self.buildPendingTask(label: "syncAllContacts")
            DispatchQueue.global().async {
                self.syncManager.syncAllContacts().ensure(on: DispatchQueue.global()) {
                    pendingTask.complete()
                }.catch(on: DispatchQueue.global()) { error in
                    Logger.error("Error: \(error)")
                }
            }

        case .blocked:
            Logger.info("Received request for block list")
            let pendingTask = Self.buildPendingTask(label: "syncBlockList")
            blockingManager.syncBlockList { pendingTask.complete() }

        case .configuration:
            // We send _two_ responses to the "configuration request".
            syncManager.sendConfigurationSyncMessage()
            StickerManager.syncAllInstalledPacks(transaction: tx)

        case .keys:
            syncManager.sendKeysSyncMessage()

        case .unknown, .none:
            owsFailDebug("Ignoring sync request with unexpected type")
        }
    }

    private func handleSyncedBlocklist(_ blocked: SSKProtoSyncMessageBlocked, tx: SDSAnyWriteTransaction) {
        var blockedAcis = Set<Aci>()
        for aciString in blocked.acis {
            guard let aci = Aci.parseFrom(aciString: aciString) else {
                owsFailDebug("Blocked ACI was nil.")
                continue
            }
            blockedAcis.insert(aci)
        }
        blockingManager.processIncomingSync(
            blockedPhoneNumbers: Set(blocked.numbers),
            blockedAcis: blockedAcis,
            blockedGroupIds: Set(blocked.groupIds),
            tx: tx
        )
    }

    private func handleIncomingEnvelope(
        _ decryptedEnvelope: DecryptedIncomingEnvelope,
        withSenderKeyDistributionMessage skdmData: Data,
        transaction writeTx: SDSAnyWriteTransaction
    ) {
        do {
            let skdm = try SenderKeyDistributionMessage(bytes: skdmData.map { $0 })
            let sourceAci = decryptedEnvelope.sourceAci
            let sourceDeviceId = decryptedEnvelope.sourceDeviceId
            let protocolAddress = ProtocolAddress(sourceAci, deviceId: sourceDeviceId)
            try processSenderKeyDistributionMessage(skdm, from: protocolAddress, store: senderKeyStore, context: writeTx)

            Logger.info("Processed incoming sender key distribution message from \(sourceAci).\(sourceDeviceId)")

        } catch {
            owsFailDebug("Failed to process incoming sender key \(error)")
        }
    }

    @objc
    func handleIncomingEnvelope(
        _ decryptedEnvelope: DecryptedIncomingEnvelope,
        withDecryptionErrorMessage bytes: Data,
        transaction writeTx: SDSAnyWriteTransaction
    ) {
        let sourceAci = decryptedEnvelope.sourceAci
        let sourceDeviceId = decryptedEnvelope.sourceDeviceId

        do {
            let errorMessage = try DecryptionErrorMessage(bytes: bytes)
            guard errorMessage.deviceId == tsAccountManager.storedDeviceId(transaction: writeTx) else {
                Logger.info("Received a DecryptionError message targeting a linked device. Ignoring.")
                return
            }
            let protocolAddress = ProtocolAddress(sourceAci, deviceId: sourceDeviceId)

            let didPerformSessionReset: Bool

            if let ratchetKey = errorMessage.ratchetKey {
                // If a ratchet key is included, this was a 1:1 session message
                // Archive the session if the current key matches.
                // PNI TODO: We should never get a DEM for our PNI, but we should check that anyway.
                let sessionStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore
                let sessionRecord = try sessionStore.loadSession(for: protocolAddress, context: writeTx)
                if try sessionRecord?.currentRatchetKeyMatches(ratchetKey) == true {
                    Logger.info("Decryption error included ratchet key. Archiving...")
                    sessionStore.archiveSession(
                        for: SignalServiceAddress(sourceAci),
                        deviceId: Int32(sourceDeviceId),
                        tx: writeTx.asV2Write
                    )
                    didPerformSessionReset = true
                } else {
                    Logger.info("Ratchet key mismatch. Leaving session as-is.")
                    didPerformSessionReset = false
                }
            } else {
                // If we don't have a ratchet key, this was a sender key session message.
                // Let's log any info about SKDMs that we had sent to the address requesting resend
                senderKeyStore.logSKDMInfo(for: SignalServiceAddress(sourceAci), transaction: writeTx)
                didPerformSessionReset = false
            }

            Logger.warn("Performing message resend of timestamp \(errorMessage.timestamp)")
            let resendResponse = OWSOutgoingResendResponse(
                aci: sourceAci,
                deviceId: sourceDeviceId,
                failedTimestamp: errorMessage.timestamp,
                didResetSession: didPerformSessionReset,
                tx: writeTx
            )

            let sendBlock = { (transaction: SDSAnyWriteTransaction) in
                if let resendResponse = resendResponse {
                    Self.sskJobQueues.messageSenderJobQueue.add(message: resendResponse.asPreparer, transaction: transaction)
                }
            }

            if DebugFlags.delayedMessageResend.get() {
                DispatchQueue.sharedUtility.asyncAfter(deadline: .now() + 10) {
                    Self.databaseStorage.asyncWrite { writeTx in
                        sendBlock(writeTx)
                    }
                }
            } else {
                sendBlock(writeTx)
            }

        } catch {
            owsFailDebug("Failed to process decryption error message \(error)")
        }
    }

    @objc
    func handleIncomingEnvelope(
        _ decryptedEnvelope: DecryptedIncomingEnvelope,
        withStoryMessage storyMessage: SSKProtoStoryMessage,
        tx: SDSAnyWriteTransaction
    ) {
        do {
            try StoryManager.processIncomingStoryMessage(
                storyMessage,
                timestamp: decryptedEnvelope.timestamp,
                author: decryptedEnvelope.sourceAci,
                transaction: tx
            )
        } catch {
            Logger.warn("Failed to insert story message with error \(error.localizedDescription)")
        }
    }

    @objc(OWSEditProcessingResult)
    enum EditProcessingResult: Int, Error {
        case editedMessageMissing
        case invalidEdit
        case success
    }

    private func handleIncomingEnvelope(
        _ decryptedEnvelope: DecryptedIncomingEnvelope,
        sentMessage: SSKProtoSyncMessageSent,
        editMessage: SSKProtoEditMessage,
        transaction tx: SDSAnyWriteTransaction
    ) -> EditProcessingResult {

        guard let transcript = OWSIncomingSentMessageTranscript(
            proto: sentMessage,
            serverTimestamp: decryptedEnvelope.serverTimestamp,
            transaction: tx
        ) else {
            Logger.warn("Missing edit transcript.")
            return .invalidEdit
        }

        guard let thread = transcript.thread else {
            Logger.warn("Missing edit message thread.")
            return .invalidEdit
        }

        // Find the target message to edit. If missing,
        // return and enqueue the message to be handled as early delivery
        guard
            let targetMessage = EditMessageFinder.editTarget(
                timestamp: editMessage.targetSentTimestamp,
                authorAci: nil,
                transaction: tx
            )
        else {
            Logger.warn("Edit cannot find the target message")
            return .editedMessageMissing
        }

        guard let message = handleMessageEdit(
            envelope: decryptedEnvelope,
            thread: thread,
            editTarget: targetMessage,
            editMessage: editMessage,
            transaction: tx
        ) else {
            Logger.info("Failed to insert edit sync message")
            return .invalidEdit
        }

        if let msg = message as? TSOutgoingMessage {
            msg.updateWithWasSentFromLinkedDevice(
                withUDRecipients: transcript.udRecipients,
                nonUdRecipients: transcript.nonUdRecipients,
                isSentUpdate: false,
                transaction: tx
            )
        }

        return .success
    }

    @objc
    func handleIncomingEnvelope(
        _ decryptedEnvelope: DecryptedIncomingEnvelope,
        withEditMessage editMessage: SSKProtoEditMessage,
        wasReceivedByUD: Bool,
        transaction tx: SDSAnyWriteTransaction
    ) -> EditProcessingResult {

        guard let dataMessage = editMessage.dataMessage else {
            Logger.warn("Missing edit message data.")
            return .invalidEdit
        }

        guard let thread = preprocessDataMessage(
            dataMessage,
            envelope: decryptedEnvelope.envelope,
            transaction: tx
        ) else {
            Logger.warn("Missing edit message thread.")
            return .invalidEdit
        }

        // Find the target message to edit. If missing,
        // return and enqueue the message to be handled as early delivery
        guard let targetMessage = EditMessageFinder.editTarget(
            timestamp: editMessage.targetSentTimestamp,
            authorAci: decryptedEnvelope.sourceAci,
            transaction: tx
        ) else {
            Logger.warn("Edit cannot find the target message")
            return .editedMessageMissing
        }

        guard let message = handleMessageEdit(
            envelope: decryptedEnvelope,
            thread: thread,
            editTarget: targetMessage,
            editMessage: editMessage,
            transaction: tx
        ) else {
            Logger.info("Failed to insert edit message")
            return .invalidEdit
        }

        if wasReceivedByUD {
            self.outgoingReceiptManager.enqueueDeliveryReceipt(
                for: decryptedEnvelope.envelope,
                messageUniqueId: message.uniqueId,
                transaction: tx
            )

            if
                case let .incomingMessage(incoming) = targetMessage,
                let message = message as? TSIncomingMessage
            {
                // Only update notifications for unread/unedited message targets
                let targetEditState = incoming.message.editState
                if targetEditState == .latestRevisionUnread || targetEditState == .none {
                    self.notificationsManager.notifyUser(
                        forIncomingMessage: message,
                        editTarget: incoming.message,
                        thread: thread,
                        transaction: tx
                    )
                }
            }
        }

        return .success
    }

    private func handleMessageEdit(
        envelope: DecryptedIncomingEnvelope,
        thread: TSThread,
        editTarget: EditMessageTarget,
        editMessage: SSKProtoEditMessage,
        transaction tx: SDSAnyWriteTransaction
    ) -> TSMessage? {

        guard let dataMessage = editMessage.dataMessage else {
            owsFailDebug("Missing dataMessage in edit")
            return nil
        }

        let message = DependenciesBridge.shared.editManager.processIncomingEditMessage(
            dataMessage,
            thread: thread,
            editTarget: editTarget,
            serverTimestamp: envelope.serverTimestamp,
            tx: tx.asV2Write
        )

        guard let message else {
            return nil
        }

        // Start downloading any new attachments
        self.attachmentDownloads.enqueueDownloadOfAttachmentsForNewMessage(
            message,
            transaction: tx
        )

        DispatchQueue.main.async {
            self.typingIndicatorsImpl.didReceiveIncomingMessage(
                inThread: thread,
                address: SignalServiceAddress(envelope.sourceAci),
                deviceId: UInt(envelope.sourceDeviceId)
            )
        }

        return message
    }

    @objc
    public static func descriptionForDataMessageContents(_ dataMessage: SSKProtoDataMessage) -> String {
        var splits = [String]()
        if !dataMessage.attachments.isEmpty {
            splits.append("attachments: \(dataMessage.attachments.count)")
        }
        if dataMessage.groupV2 != nil {
            splits.append("groupV2")
        }
        if dataMessage.quote != nil {
            splits.append("quote")
        }
        if !dataMessage.contact.isEmpty {
            splits.append("contacts: \(dataMessage.contact.count)")
        }
        if !dataMessage.preview.isEmpty {
            splits.append("previews: \(dataMessage.preview.count)")
        }
        if dataMessage.sticker != nil {
            splits.append("sticker")
        }
        if dataMessage.reaction != nil {
            splits.append("reaction")
        }
        if dataMessage.delete != nil {
            splits.append("delete")
        }
        if !dataMessage.bodyRanges.isEmpty {
            splits.append("bodyRanges: \(dataMessage.bodyRanges.count)")
        }
        if dataMessage.groupCallUpdate != nil {
            splits.append("groupCallUpdate")
        }
        if dataMessage.payment != nil {
            splits.append("payment")
        }
        if dataMessage.body?.nilIfEmpty != nil {
            splits.append("body")
        }
        if dataMessage.expireTimer > 0 {
            splits.append("expireTimer")
        }
        if dataMessage.profileKey != nil {
            splits.append("profileKey")
        }
        if dataMessage.isViewOnce {
            splits.append("isViewOnce")
        }
        if dataMessage.flags > 0 {
            splits.append("flags: \(dataMessage.flags)")
        }
        return "[" + splits.joined(separator: ", ") + "]"
    }

    @objc
    func checkForUnknownLinkedDevice(in envelope: DecryptedIncomingEnvelope, tx: SDSAnyWriteTransaction) {
        let aci = envelope.sourceAci
        let deviceId = envelope.sourceDeviceId

        guard aci == tsAccountManager.localIdentifiers(transaction: tx)?.aci else {
            return
        }

        // Check if the SignalRecipient (used for sending messages) knows about
        // this device.
        let recipient = DependenciesBridge.shared.recipientFetcher.fetchOrCreate(serviceId: aci, tx: tx.asV2Write)
        if !recipient.deviceIds.contains(deviceId) {
            Logger.info("Message received from unknown linked device; adding to local SignalRecipient: \(deviceId).")
            recipient.modifyAndSave(deviceIdsToAdd: [deviceId], deviceIdsToRemove: [], tx: tx)
        }

        // Check if OWSDevice (ie the "Linked Devices" UI) knows about this device.
        let hasDevice = OWSDevice.anyFetchAll(transaction: tx).contains(where: { $0.deviceId == deviceId })
        if !hasDevice {
            Logger.info("Message received from unknown linked device; refreshing device list: \(deviceId).")
            OWSDevicesService.refreshDevices()
            profileManager.fetchLocalUsersProfile(authedAccount: .implicit())
        }
    }

    @objc
    func archiveSessions(for address: SignalServiceAddress?, transaction: SDSAnyWriteTransaction) {
        guard let address else { return }

        // PNI TODO: this should end the PNI session if it was sent to our PNI.
        let sessionStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore
        sessionStore.archiveAllSessions(for: address, tx: transaction.asV2Write)
    }
}

// MARK: -

extension SSKProtoEnvelope {
    @objc
    var formattedAddress: String {
        return "\(String(describing: sourceServiceID)).\(sourceDevice)"
    }
}

extension SSKProtoContent {
    @objc
    var contentDescription: String {
        var message = String()
        if let syncMessage = self.syncMessage {
            message.append("<SyncMessage: \(syncMessage.contentDescription) />")
        } else if let dataMessage = self.dataMessage {
            message.append("<DataMessage: \(dataMessage.contentDescription) />")
        } else if let callMessage = self.callMessage {
            message.append("<CallMessage \(callMessage.contentDescription) />")
        } else if let nullMessage = self.nullMessage {
            message.append("<NullMessage: \(nullMessage) />")
        } else if let receiptMessage = self.receiptMessage {
            message.append("<ReceiptMessage: \(receiptMessage) />")
        } else if let typingMessage = self.typingMessage {
            message.append("<TypingMessage: \(typingMessage) />")
        } else if let decryptionErrorMessage = self.decryptionErrorMessage {
            message.append("<DecryptionErrorMessage: \(decryptionErrorMessage) />")
        } else if let storyMessage = self.storyMessage {
            message.append("<StoryMessage: \(storyMessage) />")
        } else if let editMessage = self.editMessage {
            message.append("<EditMessage: \(editMessage) />")
        }

         // SKDM's are not mutually exclusive with other content types
         if hasSenderKeyDistributionMessage {
             if !message.isEmpty {
                 message.append(" + ")
             }
             message.append("SenderKeyDistributionMessage")
         }

        if message.isEmpty {
            // Don't fire an analytics event; if we ever add a new content type, we'd generate a ton of
            // analytics traffic.
            owsFailDebug("Unknown content type.")
            return "UnknownContent"

        }
        return message
    }
}

extension SSKProtoCallMessage {
    @objc
    var contentDescription: String {
        let messageType: String
        let callId: UInt64

        if let offer = self.offer {
            messageType = "Offer"
            callId = offer.id
        } else if let busy = self.busy {
            messageType = "Busy"
            callId = busy.id
        } else if let answer = self.answer {
            messageType = "Answer"
            callId = answer.id
        } else if let legacyHangup = self.legacyHangup {
            messageType = "legacyHangup"
            callId = legacyHangup.id
        } else if let hangup = self.hangup {
            messageType = "Hangup"
            callId = hangup.id
        } else if let firstICEUpdate = iceUpdate.first {
            messageType = "Ice Updates \(iceUpdate.count)"
            callId = firstICEUpdate.id
        } else if let opaque = self.opaque {
            if opaque.hasUrgency {
                messageType = "Opaque (\(opaque.unwrappedUrgency.contentDescription))"
            } else {
                messageType = "Opaque"
            }
            callId = 0
        } else {
            owsFailDebug("failure: unexpected call message type: \(self)")
            messageType = "Unknown"
            callId = 0
        }

        return "type: \(messageType), id: \(callId)"
    }
}

extension SSKProtoCallMessageOpaqueUrgency {
    var contentDescription: String {
        switch self {
        case .droppable:
            return "Droppable"
        case .handleImmediately:
            return "HandleImmediately"
        default:
            return "Unknown"
        }
    }
}

extension SSKProtoDataMessage {
    @objc
    var contentDescription: String {
        var parts = [String]()
        if Int64(flags) & Int64(SSKProtoDataMessageFlags.endSession.rawValue) != 0 {
            parts.append("EndSession")
        } else if Int64(flags) & Int64(SSKProtoDataMessageFlags.expirationTimerUpdate.rawValue) != 0 {
            parts.append("ExpirationTimerUpdate")
        } else if Int64(flags) & Int64(SSKProtoDataMessageFlags.profileKeyUpdate.rawValue) != 0 {
            parts.append("ProfileKey")
        } else if attachments.count > 0 {
            parts.append("MessageWithAttachment")
        } else {
            parts.append("Plain")
        }
        return "<\(parts.joined(separator: " ")) />"
    }
}

extension SSKProtoSyncMessage {
    @objc
    var contentDescription: String {
        if sent != nil {
            return "SentTranscript"
        }
        if contacts != nil {
            return "Contacts"
        }
        if let request = self.request {
            if !request.hasType {
                return "Unknown sync request."
            }
            switch request.unwrappedType {
            case .contacts:
                return "ContactRequest"
            case .blocked:
                return "BlockedRequest"
            case .configuration:
                return "ConfigurationRequest"
            case .keys:
                return "KeysRequest"
            default:
                owsFailDebug("Unknown sync message request type: \(request.unwrappedType)")
                return "UnknownRequest"
            }
        }
        if !read.isEmpty {
            return "ReadReceipt"
        }
        if blocked != nil {
            return "Blocked"
        }
        if verified != nil {
            return "Verification"
        }
        if configuration != nil {
            return "Configuration"
        }
        if !stickerPackOperation.isEmpty {
            var operationTypes = [String]()
            for packOperationProto in stickerPackOperation {
                if !packOperationProto.hasType {
                    operationTypes.append("unknown")
                    continue
                }
                switch packOperationProto.unwrappedType {
                case .install:
                    operationTypes.append("install")
                case .remove:
                    operationTypes.append("remove")
                default:
                    operationTypes.append("unknown")
                }
            }
            return "StickerPackOperation: \(operationTypes.joined(separator: ", "))"
        }
        if viewOnceOpen != nil {
            return "ViewOnceOpen"
        }
        if let fetchLatest = fetchLatest {
            switch fetchLatest.unwrappedType {
            case .unknown:
                return "FetchLatest_Unknown"
            case .localProfile:
                return "FetchLatest_LocalProfile"
            case .storageManifest:
                return "FetchLatest_StorageManifest"
            case .subscriptionStatus:
                return "FetchLatest_SubscriptionStatus"
            }
        }
        if keys != nil {
            return "Keys"
        }
        if messageRequestResponse != nil {
            return "MessageRequestResponse"
        }
        if outgoingPayment != nil {
            return "OutgoingPayment"
        }
        if !viewed.isEmpty {
            return "ViewedReceipt"
        }
        if callEvent != nil {
            return "CallDispositionEvent"
        }
        if pniChangeNumber != nil {
            return "PniChangeNumber"
        }
        owsFailDebug("Unknown sync message type")
        return "Unknown"

    }
}

@objc
class MessageManagerRequest: NSObject {
    @objc
    let decryptedEnvelope: DecryptedIncomingEnvelope

    @objc
    let envelope: SSKProtoEnvelope

    @objc
    let plaintextData: Data

    @objc
    let wasReceivedByUD: Bool

    @objc
    let serverDeliveryTimestamp: UInt64

    @objc
    let shouldDiscardVisibleMessages: Bool

    @objc
    let protoContent: SSKProtoContent

    @objc
    var messageType: OWSMessageManagerMessageType {
        if protoContent.syncMessage != nil {
            return .syncMessage
        }
        if protoContent.dataMessage != nil {
            return .dataMessage
        }
        if protoContent.callMessage != nil {
            return .callMessage
        }
        if protoContent.typingMessage != nil {
            return .typingMessage
        }
        if protoContent.nullMessage != nil {
            return .nullMessage
        }
        if protoContent.receiptMessage != nil {
            return .receiptMessage
        }
        if protoContent.decryptionErrorMessage != nil {
            return .decryptionErrorMessage
        }
        if protoContent.storyMessage != nil {
            return .storyMessage
        }
        if protoContent.hasSenderKeyDistributionMessage {
            return .hasSenderKeyDistributionMessage
        }
        if protoContent.editMessage != nil {
            return .editMessage
        }
        return .unknown
    }

    enum BuildResult {
        case discard
        case noContent
        case request(MessageManagerRequest)
    }

    static func buildRequest(
        for decryptedEnvelope: DecryptedIncomingEnvelope,
        serverDeliveryTimestamp: UInt64,
        shouldDiscardVisibleMessages: Bool,
        tx: SDSAnyWriteTransaction
    ) -> BuildResult {
        if Self.isDuplicate(decryptedEnvelope, tx: tx) {
            Logger.info("Ignoring previously received envelope from \(decryptedEnvelope.sourceAci) with timestamp: \(decryptedEnvelope.timestamp)")
            return .discard
        }

        guard let contentProto = decryptedEnvelope.content else {
            return .noContent
        }

        Logger.info("handling content: <Content: \(contentProto.contentDescription)>")
        if contentProto.callMessage != nil && shouldDiscardVisibleMessages {
            Logger.info("Discarding message with timestamp \(decryptedEnvelope.timestamp)")
            return .discard
        }

        if decryptedEnvelope.envelope.story && contentProto.dataMessage?.delete == nil {
            guard StoryManager.areStoriesEnabled(transaction: tx) else {
                Logger.info("Discarding story message received while stories are disabled")
                return .discard
            }
            guard
                contentProto.senderKeyDistributionMessage != nil ||
                contentProto.storyMessage != nil ||
                (contentProto.dataMessage?.storyContext != nil && contentProto.dataMessage?.groupV2 != nil)
            else {
                owsFailDebug("Discarding story message with invalid content.")
                return .discard
            }
        }

        return .request(MessageManagerRequest(
            decryptedEnvelope: decryptedEnvelope,
            protoContent: contentProto,
            serverDeliveryTimestamp: serverDeliveryTimestamp,
            shouldDiscardVisibleMessages: shouldDiscardVisibleMessages
        ))
    }

    private static func isDuplicate(_ decryptedEnvelope: DecryptedIncomingEnvelope, tx: SDSAnyReadTransaction) -> Bool {
        return InteractionFinder.existsIncomingMessage(
            timestamp: decryptedEnvelope.timestamp,
            sourceAci: decryptedEnvelope.sourceAci,
            sourceDeviceId: decryptedEnvelope.sourceDeviceId,
            transaction: tx
        )
    }

    private init(
        decryptedEnvelope: DecryptedIncomingEnvelope,
        protoContent: SSKProtoContent,
        serverDeliveryTimestamp: UInt64,
        shouldDiscardVisibleMessages: Bool
    ) {
        self.decryptedEnvelope = decryptedEnvelope
        self.envelope = decryptedEnvelope.envelope
        self.plaintextData = decryptedEnvelope.plaintextData
        self.wasReceivedByUD = decryptedEnvelope.wasReceivedByUD
        self.protoContent = protoContent
        self.serverDeliveryTimestamp = serverDeliveryTimestamp
        self.shouldDiscardVisibleMessages = shouldDiscardVisibleMessages
    }
}
