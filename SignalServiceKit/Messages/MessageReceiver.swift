//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient
import SignalRingRTC

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

public final class MessageReceiver {
    private let callMessageHandler: any CallMessageHandler
    private let deleteForMeSyncMessageReceiver: any DeleteForMeSyncMessageReceiver

    init(
        callMessageHandler: any CallMessageHandler,
        deleteForMeSyncMessageReceiver: any DeleteForMeSyncMessageReceiver
    ) {
        self.callMessageHandler = callMessageHandler
        self.deleteForMeSyncMessageReceiver = deleteForMeSyncMessageReceiver
    }

    private static let pendingTasks = PendingTasks(label: "messageReceiver")

    public static func pendingTasksPromise() -> Promise<Void> {
        // This promise blocks on all pending tasks already in flight,
        // but will not block on new tasks enqueued after this promise
        // is created. That's intentional to ensure that NotificationService
        // instances complete in a timely way.
        pendingTasks.pendingTasksPromise()
    }

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
                if SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(SignalServiceAddress(sourceAci), transaction: tx) {
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
                let buildResult = MessageReceiverRequest.buildRequest(
                    for: decryptedEnvelope,
                    serverDeliveryTimestamp: serverDeliveryTimestamp,
                    shouldDiscardVisibleMessages: shouldDiscardVisibleMessages,
                    tx: tx
                )
                switch buildResult {
                case .discard:
                    break
                case .request(let messageReceiverRequest):
                    handleRequest(
                        messageReceiverRequest,
                        context: PassthroughDeliveryReceiptContext(),
                        localIdentifiers: localIdentifiers,
                        tx: tx
                    )
                    fallthrough
                case .noContent:
                    finishProcessingEnvelope(decryptedEnvelope, tx: tx)
                }
            case .serverReceipt:
                owsAssertDebug(plaintextData == nil)
                let envelope = try ServerReceiptEnvelope(validatedEnvelope)
                handleDeliveryReceipt(envelope: envelope, context: PassthroughDeliveryReceiptContext(), tx: tx)
            }
        } catch {
            Logger.warn("Dropping invalid envelope \(error)")
        }
    }

    func handleRequest(
        _ request: MessageReceiverRequest,
        context: DeliveryReceiptContext,
        localIdentifiers: LocalIdentifiers,
        tx: SDSAnyWriteTransaction
    ) {
        let protoContent = request.protoContent
        Logger.info("Received \(request.decryptedEnvelope.timestamp) w/\(protoContent.contentDescription) from \(request.decryptedEnvelope.sourceAci)")

        switch request.messageType {
        case .syncMessage(let syncMessage):
            handleIncomingEnvelope(request: request, syncMessage: syncMessage, localIdentifiers: localIdentifiers, tx: tx)
            DependenciesBridge.shared.deviceManager.setHasReceivedSyncMessage(transaction: tx.asV2Write)
        case .dataMessage(let dataMessage):
            handleIncomingEnvelope(request: request, dataMessage: dataMessage, localIdentifiers: localIdentifiers, tx: tx)
        case .callMessage(let callMessage):
            owsAssertDebug(!request.shouldDiscardVisibleMessages)
            handleIncomingEnvelope(request: request, callMessage: callMessage, localIdentifiers: localIdentifiers, tx: tx)
        case .typingMessage(let typingMessage):
            handleIncomingEnvelope(request: request, typingMessage: typingMessage, tx: tx)
        case .nullMessage:
            Logger.info("Received null message.")
        case .receiptMessage(let receiptMessage):
            handleIncomingEnvelope(request: request, receiptMessage: receiptMessage, context: context, tx: tx)
        case .decryptionErrorMessage(let decryptionErrorMessage):
            handleIncomingEnvelope(request: request, decryptionErrorMessage: decryptionErrorMessage, tx: tx)
        case .storyMessage(let storyMessage):
            handleIncomingEnvelope(request: request, storyMessage: storyMessage, localIdentifiers: localIdentifiers, tx: tx)
        case .editMessage(let editMessage):
            let result = handleIncomingEnvelope(request: request, editMessage: editMessage, tx: tx)
            switch result {
            case .success, .invalidEdit:
                break
            case .editedMessageMissing:
                SSKEnvironment.shared.earlyMessageManagerRef.recordEarlyEnvelope(
                    request.envelope,
                    plainTextData: request.plaintextData,
                    wasReceivedByUD: request.wasReceivedByUD,
                    serverDeliveryTimestamp: request.serverDeliveryTimestamp,
                    associatedMessageTimestamp: editMessage.targetSentTimestamp,
                    associatedMessageAuthor: request.decryptedEnvelope.sourceAci,
                    transaction: tx
                )
            }
        case .handledElsewhere:
            break
        case .none:
            Logger.warn("Ignoring envelope with unknown type.")
        }
    }

    /// This code path is for server-generated receipts only.
    func handleDeliveryReceipt(
        envelope: ServerReceiptEnvelope,
        context: DeliveryReceiptContext,
        tx: SDSAnyWriteTransaction
    ) {
        // Server-generated delivery receipts don't include a "delivery timestamp".
        // The envelope's timestamp gives the timestamp of the message this receipt
        // is for. Unlike UD receipts, it is not meant to be the time the message
        // was delivered. We use the current time as a good-enough guess. We could
        // also use the envelope's serverTimestamp.
        let deliveryTimestamp = NSDate.ows_millisecondTimeStamp()
        guard SDS.fitsInInt64(deliveryTimestamp) else {
            owsFailDebug("Invalid timestamp.")
            return
        }

        let earlyReceiptTimestamps = SSKEnvironment.shared.receiptManagerRef.processDeliveryReceipts(
            from: envelope.sourceServiceId,
            recipientDeviceId: envelope.sourceDeviceId,
            sentTimestamps: [envelope.validatedEnvelope.timestamp],
            deliveryTimestamp: deliveryTimestamp,
            context: context,
            tx: tx
        )

        recordEarlyReceipts(
            receiptType: .delivery,
            senderServiceId: envelope.sourceServiceId,
            senderDeviceId: envelope.sourceDeviceId,
            associatedMessageTimestamps: earlyReceiptTimestamps,
            actionTimestamp: deliveryTimestamp,
            tx: tx
        )
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
            return
        }

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
                DependenciesBridge.shared.interactionDeleteManager
                    .delete(placeholder, sideEffects: .default(), tx: tx.asV2Write)
            }
        } catch {
            owsFailDebug("Failed to fetch placeholders: \(error)")
        }
    }

    private func groupId(for dataMessage: SSKProtoDataMessage) -> Data? {
        guard let groupContext = dataMessage.groupV2 else {
            return nil
        }
        guard let masterKey = groupContext.masterKey else {
            owsFailDebug("Missing masterKey.")
            return nil
        }
        do {
            return try GroupV2ContextInfo.deriveFrom(masterKeyData: masterKey).groupId
        } catch {
            owsFailDebug("Invalid group context.")
            return nil
        }
    }

    private func handleIncomingEnvelope(
        request: MessageReceiverRequest,
        syncMessage: SSKProtoSyncMessage,
        localIdentifiers: LocalIdentifiers,
        tx: SDSAnyWriteTransaction
    ) {
        let decryptedEnvelope = request.decryptedEnvelope

        guard decryptedEnvelope.sourceAci == localIdentifiers.aci else {
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
                let groupId: Data? = groupId(for: dataMessage)

                guard SDS.fitsInInt64(sent.expirationStartTimestamp) else {
                    owsFailDebug("Invalid expirationStartTimestamp.")
                    return
                }

                guard let transcript = OWSIncomingSentMessageTranscript.from(
                    sentProto: sent,
                    serverTimestamp: decryptedEnvelope.serverTimestamp,
                    tx: tx.asV2Write
                ) else {
                    owsFailDebug("Couldn't parse transcript.")
                    return
                }

                if dataMessage.hasProfileKey {
                    if let groupId {
                        SSKEnvironment.shared.profileManagerRef.addGroupId(
                            toProfileWhitelist: groupId, userProfileWriter: .localUser, transaction: tx
                        )
                    } else {
                        // If we observe a linked device sending our profile key to another user,
                        // we can infer that that user belongs in our profile whitelist.
                        let destinationAddress = SignalServiceAddress.legacyAddress(
                            serviceIdString: sent.destinationServiceID,
                            phoneNumber: sent.destinationE164?.nilIfEmpty
                        )
                        if destinationAddress.isValid {
                            SSKEnvironment.shared.profileManagerRef.addUser(
                                toProfileWhitelist: destinationAddress, userProfileWriter: .localUser, transaction: tx
                            )
                        }
                    }
                }

                if let reaction = dataMessage.reaction {
                    guard let thread = transcript.threadForDataMessage else {
                        owsFailDebug("Could not process reaction from sync transcript.")
                        return
                    }
                    let result = ReactionManager.processIncomingReaction(
                        reaction,
                        thread: thread,
                        reactor: decryptedEnvelope.sourceAci,
                        timestamp: sent.timestamp,
                        serverTimestamp: decryptedEnvelope.serverTimestamp,
                        expiresInSeconds: dataMessage.expireTimer,
                        expireTimerVersion: dataMessage.expireTimerVersion,
                        sentTranscript: transcript,
                        transaction: tx
                    )
                    switch result {
                    case .success, .invalidReaction:
                        break
                    case .associatedMessageMissing:
                        let messageAuthor = Aci.parseFrom(aciString: reaction.targetAuthorAci)
                        SSKEnvironment.shared.earlyMessageManagerRef.recordEarlyEnvelope(
                            envelope,
                            plainTextData: request.plaintextData,
                            wasReceivedByUD: request.wasReceivedByUD,
                            serverDeliveryTimestamp: request.serverDeliveryTimestamp,
                            associatedMessageTimestamp: reaction.timestamp,
                            associatedMessageAuthor: messageAuthor,
                            transaction: tx
                        )
                    }
                } else if let delete = dataMessage.delete {
                    let result = TSMessage.tryToRemotelyDeleteMessage(
                        fromAuthor: decryptedEnvelope.sourceAci,
                        sentAtTimestamp: delete.targetSentTimestamp,
                        threadUniqueId: transcript.threadForDataMessage?.uniqueId,
                        serverTimestamp: decryptedEnvelope.serverTimestamp,
                        transaction: tx
                    )
                    switch result {
                    case .success:
                        break
                    case .invalidDelete:
                        Logger.error("Failed to remotely delete message \(delete.targetSentTimestamp)")
                    case .deletedMessageMissing:
                        SSKEnvironment.shared.earlyMessageManagerRef.recordEarlyEnvelope(
                            envelope,
                            plainTextData: request.plaintextData,
                            wasReceivedByUD: request.wasReceivedByUD,
                            serverDeliveryTimestamp: request.serverDeliveryTimestamp,
                            associatedMessageTimestamp: delete.targetSentTimestamp,
                            associatedMessageAuthor: decryptedEnvelope.sourceAci,
                            transaction: tx
                        )
                    }
                } else if let groupCallUpdate = dataMessage.groupCallUpdate {
                    if let groupId = try? GroupIdentifier(contents: [UInt8](groupId ?? Data())) {
                        let pendingTask = MessageReceiver.buildPendingTask(label: "GroupCallUpdate")
                        Task { [callMessageHandler] in
                            defer { pendingTask.complete() }
                            await callMessageHandler.receivedGroupCallUpdateMessage(
                                groupCallUpdate,
                                forGroupId: groupId,
                                serverReceivedTimestamp: decryptedEnvelope.timestamp
                            )
                        }
                    } else {
                        Logger.warn("Received GroupCallUpdate for invalid groupId")
                    }
                } else {
                    guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read) else {
                        owsFailDebug("Missing local identifiers!")
                        return
                    }
                    DependenciesBridge.shared.sentMessageTranscriptReceiver.process(
                        transcript,
                        localIdentifiers: localIdentifiers,
                        tx: tx.asV2Write
                    )
                }
            } else if sent.isStoryTranscript {
                do {
                    try StoryManager.processStoryMessageTranscript(sent, transaction: tx)
                } catch {
                    owsFailDebug("Failed to process story message transcript \(error)")
                }
            } else if let editMessage = sent.editMessage {
                let result = handleIncomingEnvelope(
                    decryptedEnvelope,
                    sentMessage: sent,
                    editMessage: editMessage,
                    serverDeliveryTimestamp: request.serverDeliveryTimestamp,
                    transaction: tx
                )
                switch result {
                case .success, .invalidEdit:
                    break
                case .editedMessageMissing:
                    SSKEnvironment.shared.earlyMessageManagerRef.recordEarlyEnvelope(
                        envelope,
                        plainTextData: request.plaintextData,
                        wasReceivedByUD: request.wasReceivedByUD,
                        serverDeliveryTimestamp: request.serverDeliveryTimestamp,
                        associatedMessageTimestamp: editMessage.targetSentTimestamp,
                        associatedMessageAuthor: decryptedEnvelope.sourceAci,
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
            let earlyReceipts = SSKEnvironment.shared.receiptManagerRef.processReadReceiptsFromLinkedDevice(
                syncMessage.read, readTimestamp: decryptedEnvelope.timestamp, tx: tx
            )
            for readReceiptProto in earlyReceipts {
                let messageAuthor = Aci.parseFrom(aciString: readReceiptProto.senderAci)
                SSKEnvironment.shared.earlyMessageManagerRef.recordEarlyReadReceiptFromLinkedDevice(
                    timestamp: decryptedEnvelope.timestamp,
                    associatedMessageTimestamp: readReceiptProto.timestamp,
                    associatedMessageAuthor: messageAuthor.map { AciObjC($0) },
                    transaction: tx
                )
            }
        } else if !syncMessage.viewed.isEmpty {
            let earlyReceipts = SSKEnvironment.shared.receiptManagerRef.processViewedReceiptsFromLinkedDevice(
                syncMessage.viewed, viewedTimestamp: decryptedEnvelope.timestamp, tx: tx
            )
            for viewedReceiptProto in earlyReceipts {
                let messageAuthor = Aci.parseFrom(aciString: viewedReceiptProto.senderAci)
                SSKEnvironment.shared.earlyMessageManagerRef.recordEarlyViewedReceiptFromLinkedDevice(
                    timestamp: decryptedEnvelope.timestamp,
                    associatedMessageTimestamp: viewedReceiptProto.timestamp,
                    associatedMessageAuthor: messageAuthor.map { AciObjC($0) },
                    transaction: tx
                )
            }
        } else if let verified = syncMessage.verified {
            do {
                let identityManager = DependenciesBridge.shared.identityManager
                try identityManager.processIncomingVerifiedProto(verified, tx: tx.asV2Write)
                identityManager.fireIdentityStateChangeNotification(after: tx.asV2Write)
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
                SSKEnvironment.shared.earlyMessageManagerRef.recordEarlyEnvelope(
                    envelope,
                    plainTextData: request.plaintextData,
                    wasReceivedByUD: request.wasReceivedByUD,
                    serverDeliveryTimestamp: request.serverDeliveryTimestamp,
                    associatedMessageTimestamp: associatedMessageTimestamp,
                    associatedMessageAuthor: senderAci,
                    transaction: tx
                )
            }
        } else if let configuration = syncMessage.configuration {
            SSKEnvironment.shared.syncManagerRef.processIncomingConfigurationSyncMessage(configuration, transaction: tx)
        } else if let contacts = syncMessage.contacts {
            SSKEnvironment.shared.syncManagerRef.processIncomingContactsSyncMessage(contacts, transaction: tx)
        } else if let fetchLatest = syncMessage.fetchLatest {
            SSKEnvironment.shared.syncManagerRef.processIncomingFetchLatestSyncMessage(fetchLatest, transaction: tx)
        } else if let keys = syncMessage.keys {
            SSKEnvironment.shared.syncManagerRef.processIncomingKeysSyncMessage(keys, transaction: tx)
        } else if let messageRequestResponse = syncMessage.messageRequestResponse {
            SSKEnvironment.shared.syncManagerRef.processIncomingMessageRequestResponseSyncMessage(messageRequestResponse, transaction: tx)
        } else if let outgoingPayment = syncMessage.outgoingPayment {
            // An "incoming" sync message notifies us of an "outgoing" payment.
            SSKEnvironment.shared.paymentsHelperRef.processIncomingPaymentSyncMessage(
                outgoingPayment, messageTimestamp: request.serverDeliveryTimestamp, transaction: tx
            )
        } else if let pniChangeNumber = syncMessage.pniChangeNumber {
            let pniProcessor = DependenciesBridge.shared.incomingPniChangeNumberProcessor
            pniProcessor.processIncomingPniChangePhoneNumber(
                proto: pniChangeNumber,
                updatedPni: envelope.updatedPni,
                tx: tx.asV2Write
            )
        } else if let callEvent = syncMessage.callEvent {
            let incomingCallEvent: IncomingCallEventSyncMessageParams
            do {
                incomingCallEvent = try IncomingCallEventSyncMessageParams.parse(callEventProto: callEvent)
            } catch {
                CallRecordLogger.shared.warn("Failed to parse incoming call event protobuf: \(error)")
                return
            }

            DependenciesBridge.shared.incomingCallEventSyncMessageManager
                .createOrUpdateRecordForIncomingSyncMessage(
                    incomingSyncMessage: incomingCallEvent,
                    syncMessageTimestamp: decryptedEnvelope.timestamp,
                    tx: tx.asV2Write
                )
        } else if let callLinkUpdate = syncMessage.callLinkUpdate {
            switch callLinkUpdate.type {
            case nil:
                Logger.warn("Ignoring CallLinkUpdate with unexpected type.")
            case .update:
                self.handleCallLinkUpdate(callLinkUpdate, tx: tx)
            }
        } else if let callLogEvent = syncMessage.callLogEvent {
            let incomingCallLogEvent: IncomingCallLogEventSyncMessageParams
            do {
                incomingCallLogEvent = try IncomingCallLogEventSyncMessageParams.parse(callLogEvent: callLogEvent)
            } catch {
                CallRecordLogger.shared.warn("Failed to parse incoming call log event protobuf: \(error)")
                return
            }

            DependenciesBridge.shared.incomingCallLogEventSyncMessageManager
                .handleIncomingSyncMessage(
                    incomingSyncMessage: incomingCallLogEvent,
                    tx: tx.asV2Write
                )
        } else if let deleteForMe = syncMessage.deleteForMe {
            deleteForMeSyncMessageReceiver.handleDeleteForMeProto(
                deleteForMeProto: deleteForMe,
                tx: tx.asV2Write
            )
        } else if syncMessage.deviceNameChange != nil {
            Task {
                let deviceService = DependenciesBridge.shared.deviceService

                /// Opportunistically try and refresh our device list. If this
                /// fails that's ok – there are other places we'll do this
                /// refresh as well.
                try await Retry.performWithBackoff(maxAttempts: 4) {
                    _ = try await deviceService.refreshDevices()
                }
            }
        } else {
            Logger.warn("Ignoring unsupported sync message.")
        }
    }

    private func handleIncomingSyncRequest(_ request: SSKProtoSyncMessageRequest, tx: SDSAnyWriteTransaction) {
        guard DependenciesBridge.shared.tsAccountManager.registrationState(tx: tx.asV2Read).isRegisteredPrimaryDevice else {
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
                SSKEnvironment.shared.syncManagerRef.syncAllContacts().ensure(on: DispatchQueue.global()) {
                    pendingTask.complete()
                }.catch(on: DispatchQueue.global()) { error in
                    Logger.warn("Error: \(error)")
                }
            }

        case .blocked:
            let pendingTask = Self.buildPendingTask(label: "syncBlockList")
            SSKEnvironment.shared.blockingManagerRef.syncBlockList { pendingTask.complete() }

        case .configuration:
            // We send _two_ responses to the "configuration request".
            SSKEnvironment.shared.syncManagerRef.sendConfigurationSyncMessage()
            StickerManager.syncAllInstalledPacks(transaction: tx)

        case .keys:
            SSKEnvironment.shared.syncManagerRef.sendKeysSyncMessage()

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
        SSKEnvironment.shared.blockingManagerRef.processIncomingSync(
            blockedPhoneNumbers: Set(blocked.numbers),
            blockedAcis: blockedAcis,
            blockedGroupIds: Set(blocked.groupIds),
            tx: tx
        )
    }

    private func handleCallLinkUpdate(_ callLinkUpdate: SSKProtoSyncMessageCallLinkUpdate, tx: SDSAnyWriteTransaction) {
        let callLinkStore = DependenciesBridge.shared.callLinkStore
        do {
            let rootKey = try CallLinkRootKey(callLinkUpdate.rootKey ?? Data())
            var (callLink, _) = try callLinkStore.fetchOrInsert(rootKey: rootKey, tx: tx.asV2Write)
            callLink.adminPasskey = callLink.adminPasskey ?? callLinkUpdate.adminPasskey
            callLink.setNeedsFetch()
            try callLinkStore.update(callLink, tx: tx.asV2Write)
        } catch {
            Logger.warn("Ignoring CallLinkUpdate: \(error)")
        }
    }

    private func handleIncomingEnvelope(
        request: MessageReceiverRequest,
        dataMessage: SSKProtoDataMessage,
        localIdentifiers: LocalIdentifiers,
        tx: SDSAnyWriteTransaction
    ) {
        let envelope = request.decryptedEnvelope

        if let groupId = self.groupId(for: dataMessage) {
            if SSKEnvironment.shared.blockingManagerRef.isGroupIdBlocked(groupId, transaction: tx) {
                Logger.warn("Ignoring blocked message from \(envelope.sourceAci) in group \(groupId)")
                return
            }
        }

        // This prevents replay attacks by the service.
        guard !dataMessage.hasTimestamp || dataMessage.timestamp == envelope.timestamp else {
            owsFailDebug("Ignoring message with non-matching data message timestamp from \(envelope.sourceAci)")
            return
        }

        if let profileKey = dataMessage.profileKey {
            setProfileKeyIfValid(profileKey, for: envelope.sourceAci, localIdentifiers: localIdentifiers, tx: tx)
        }

        // Pre-process the data message. For v1 and v2 group messages this involves
        // checking group state, possibly creating the group thread, possibly
        // responding to group info requests, etc.
        //
        // If we can and should try to "process" (e.g. generate user-visible
        // interactions) for the data message, preprocessDataMessage will return a
        // thread. If not, we should abort immediately.
        guard let thread = preprocessDataMessage(dataMessage, envelope: envelope, tx: tx) else {
            return
        }

        var message: TSIncomingMessage?
        if dataMessage.flags & UInt32(SSKProtoDataMessageFlags.endSession.rawValue) != 0 {
            handleIncomingEndSessionEnvelope(envelope, withDataMessage: dataMessage, tx: tx)
        } else if dataMessage.flags & UInt32(SSKProtoDataMessageFlags.expirationTimerUpdate.rawValue) != 0 {
            updateDisappearingMessageConfiguration(envelope: envelope, dataMessage: dataMessage, thread: thread, tx: tx)
        } else if dataMessage.flags & UInt32(SSKProtoDataMessageFlags.profileKeyUpdate.rawValue) != 0 {
            // Do nothing, we handle profile keys on all incoming messages above.
        } else {
            message = processFlaglessDataMessage(dataMessage, request: request, thread: thread, tx: tx)
        }

        // Send delivery receipts for "valid data" messages received via UD.
        if request.wasReceivedByUD {
            let receiptSender = SSKEnvironment.shared.receiptSenderRef
            receiptSender.enqueueDeliveryReceipt(for: envelope, messageUniqueId: message?.uniqueId, tx: tx)
        }
    }

    private func setProfileKeyIfValid(
        _ profileKey: Data,
        for aci: Aci,
        localIdentifiers: LocalIdentifiers,
        tx: SDSAnyWriteTransaction
    ) {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        if aci == localIdentifiers.aci, tsAccountManager.registrationState(tx: tx.asV2Read).isPrimaryDevice != false {
            return
        }
        SSKEnvironment.shared.profileManagerRef.setProfileKeyData(
            profileKey,
            for: aci,
            onlyFillInIfMissing: false,
            shouldFetchProfile: true,
            userProfileWriter: .localUser,
            localIdentifiers: localIdentifiers,
            authedAccount: .implicit(),
            tx: tx.asV2Write
        )
    }

    /// Returns a thread reference if message processing should proceed.
    ///
    /// Message processing involves generating user-visible interactions, and we
    /// don't do that if there's an invalid group context, or if there's a valid
    /// group context but the sender/local user aren't in the group.
    private func preprocessDataMessage(
        _ dataMessage: SSKProtoDataMessage,
        envelope: DecryptedIncomingEnvelope,
        tx: SDSAnyWriteTransaction
    ) -> TSThread? {
        guard let groupContext = dataMessage.groupV2 else {
            let contactAddress = SignalServiceAddress(envelope.sourceAci)
            return TSContactThread.getOrCreateThread(withContactAddress: contactAddress, transaction: tx)
        }
        guard let masterKey = groupContext.masterKey else {
            owsFailDebug("Missing masterKey.")
            return nil
        }
        let groupContextInfo: GroupV2ContextInfo
        do {
            groupContextInfo = try GroupV2ContextInfo.deriveFrom(masterKeyData: masterKey)
        } catch {
            owsFailDebug("Invalid group context.")
            return nil
        }
        guard let groupThread = TSGroupThread.fetch(groupId: groupContextInfo.groupId, transaction: tx) else {
            owsFailDebug("Unknown v2 group.")
            return nil
        }
        guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
            owsFailDebug("invalid group model.")
            return nil
        }
        guard groupContext.hasRevision, groupModel.revision >= groupContext.revision else {
            owsFailDebug("Group v2 revision larger than \(groupModel.revision) in \(groupContextInfo.groupId)")
            return nil
        }
        guard groupThread.isLocalUserFullMember else {
            // We don't want to process user-visible messages for groups in which we
            // are a pending member.
            Logger.info("Ignoring messages for invited group or left group.")
            return nil
        }
        guard groupModel.groupMembership.isFullMember(envelope.sourceAci) else {
            // We don't want to process group messages for non-members.
            Logger.info("Ignoring message from not in group user \(envelope.sourceAci)")
            return nil
        }
        return groupThread
    }

    private func processFlaglessDataMessage(
        _ dataMessage: SSKProtoDataMessage,
        request: MessageReceiverRequest,
        thread: TSThread,
        tx: SDSAnyWriteTransaction
    ) -> TSIncomingMessage? {
        let envelope = request.decryptedEnvelope

        guard !dataMessage.hasRequiredProtocolVersion || dataMessage.requiredProtocolVersion <= SSKProtos.currentProtocolVersion else {
            owsFailDebug("Unknown protocol version: \(dataMessage.requiredProtocolVersion)")
            OWSUnknownProtocolVersionMessage(
                thread: thread,
                timestamp: MessageTimestampGenerator.sharedInstance.generateTimestamp(),
                sender: SignalServiceAddress(envelope.sourceAci),
                protocolVersion: UInt(dataMessage.requiredProtocolVersion)
            ).anyInsert(transaction: tx)
            return nil
        }

        let deviceAddress = "\(envelope.sourceAci).\(envelope.sourceDeviceId)"
        let messageDescription: String
        if let groupThread = thread as? TSGroupThread {
            messageDescription = "Incoming message from \(deviceAddress) in group \(groupThread.groupModel.groupId) w/ts \(envelope.timestamp), serverTimestamp: \(envelope.serverTimestamp)"
        } else {
            messageDescription = "Incoming message from \(deviceAddress) w/ts \(envelope.timestamp), serverTimestamp: \(envelope.serverTimestamp)"
        }

        if let reaction = dataMessage.reaction {
            let result = ReactionManager.processIncomingReaction(
                reaction,
                thread: thread,
                reactor: envelope.sourceAci,
                timestamp: envelope.timestamp,
                serverTimestamp: envelope.serverTimestamp,
                expiresInSeconds: dataMessage.expireTimer,
                expireTimerVersion: dataMessage.expireTimerVersion,
                sentTranscript: nil,
                transaction: tx
            )
            switch result {
            case .success, .invalidReaction:
                break
            case .associatedMessageMissing:
                SSKEnvironment.shared.earlyMessageManagerRef.recordEarlyEnvelope(
                    envelope.envelope,
                    plainTextData: request.plaintextData,
                    wasReceivedByUD: request.wasReceivedByUD,
                    serverDeliveryTimestamp: request.serverDeliveryTimestamp,
                    associatedMessageTimestamp: reaction.timestamp,
                    associatedMessageAuthor: Aci.parseFrom(aciString: reaction.targetAuthorAci),
                    transaction: tx
                )
            }
            return nil
        }

        if let delete = dataMessage.delete {
            let result = TSMessage.tryToRemotelyDeleteMessage(
                fromAuthor: envelope.sourceAci,
                sentAtTimestamp: delete.targetSentTimestamp,
                threadUniqueId: thread.uniqueId,
                serverTimestamp: envelope.serverTimestamp,
                transaction: tx
            )
            switch result {
            case .success:
                break
            case .invalidDelete:
                Logger.warn("Couldn't process invalid remote delete w/ts \(delete.targetSentTimestamp)")
            case .deletedMessageMissing:
                SSKEnvironment.shared.earlyMessageManagerRef.recordEarlyEnvelope(
                    envelope.envelope,
                    plainTextData: request.plaintextData,
                    wasReceivedByUD: request.wasReceivedByUD,
                    serverDeliveryTimestamp: request.serverDeliveryTimestamp,
                    associatedMessageTimestamp: delete.targetSentTimestamp,
                    associatedMessageAuthor: envelope.sourceAci,
                    transaction: tx
                )
            }
            return nil
        }

        if request.shouldDiscardVisibleMessages {
            // Now that "reactions" and "delete for everyone" have been processed, the
            // only possible outcome of further processing is a visible message or
            // group call update, both of which should be discarded.
            Logger.info("Discarding message w/ts \(envelope.timestamp)")
            return nil
        }

        if let groupCallUpdate = dataMessage.groupCallUpdate {
            guard let groupId = try? (thread as? TSGroupThread)?.groupIdentifier else {
                Logger.warn("Ignoring group call update invalid group thread.")
                return nil
            }
            let pendingTask = Self.buildPendingTask(label: "GroupCallUpdate")
            Task { [callMessageHandler] in
                defer { pendingTask.complete() }
                await callMessageHandler.receivedGroupCallUpdateMessage(
                    groupCallUpdate,
                    forGroupId: groupId,
                    serverReceivedTimestamp: envelope.timestamp
                )
            }
            return nil
        }

        // TODO: change this back to kOversizeTextMessageSizeThreshold
        guard dataMessage.body?.utf8.count ?? 0 <= 6000 else {
            Logger.error("Dropping message with too large body: \(dataMessage.body?.utf8.count ?? 0)")
            return nil
        }

        let body = dataMessage.body
        let bodyRanges = dataMessage.bodyRanges.isEmpty ? nil : MessageBodyRanges(protos: dataMessage.bodyRanges)
        let serverGuid = envelope.envelope.serverGuid.flatMap { UUID(uuidString: $0) }
        let quotedMessageBuilder = DependenciesBridge.shared.quotedReplyManager.quotedMessage(
            for: dataMessage,
            thread: thread,
            tx: tx.asV2Write
        )
        let contactBuilder: OwnedAttachmentBuilder<OWSContact>?
        if let contactProto = dataMessage.contact.first {
            do {
                contactBuilder = try DependenciesBridge.shared.contactShareManager.validateAndBuild(
                    for: contactProto,
                    tx: tx.asV2Write
                )
            } catch {
                Logger.error("contact share error: \(error)")
                return nil
            }
        } else {
            contactBuilder = nil
        }

        let linkPreviewBuilder: OwnedAttachmentBuilder<OWSLinkPreview>?
        if let linkPreview = dataMessage.preview.first {
            do {
                linkPreviewBuilder = try DependenciesBridge.shared.linkPreviewManager.validateAndBuildLinkPreview(
                    from: linkPreview,
                    dataMessage: dataMessage,
                    tx: tx.asV2Write
                )
            } catch let error as LinkPreviewError {
                switch error {
                case .invalidPreview:
                    // Just drop the link preview, but keep the message
                    Logger.info("Dropping invalid link preview; keeping message")
                    linkPreviewBuilder = nil
                case .noPreview, .fetchFailure, .featureDisabled:
                    owsFailDebug("Invalid link preview error on incoming proto")
                    linkPreviewBuilder = nil
                }
            } catch {
                Logger.error("linkPreviewError: \(error)")
                return nil
            }
        } else {
            linkPreviewBuilder = nil
        }

        var messageStickerBuilder: OwnedAttachmentBuilder<MessageSticker>?
        if let stickerProto = dataMessage.sticker {
            do {
                messageStickerBuilder = try DependenciesBridge.shared.messageStickerManager.buildValidatedMessageSticker(
                    from: stickerProto,
                    tx: tx.asV2Write
                )
            } catch {
                Logger.error("stickerError: \(error)")
                return nil
            }
        } else {
            messageStickerBuilder = nil
        }

        let giftBadge = OWSGiftBadge.maybeBuild(from: dataMessage)
        let isViewOnceMessage = dataMessage.hasIsViewOnce && dataMessage.isViewOnce
        let paymentModels = TSPaymentModels.parsePaymentProtos(dataMessage: dataMessage, thread: thread)

        if let paymentModels {
            SSKEnvironment.shared.paymentsHelperRef.processIncomingPaymentNotification(
                thread: thread,
                paymentNotification: paymentModels.notification,
                senderAci: envelope.sourceAci,
                transaction: tx
            )
        } else if let payment = dataMessage.payment, let activation = payment.activation {
            switch activation.type {
            case .none, .request:
                SSKEnvironment.shared.paymentsHelperRef.processIncomingPaymentsActivationRequest(thread: thread, senderAci: envelope.sourceAci, transaction: tx)
            case .activated:
                SSKEnvironment.shared.paymentsHelperRef.processIncomingPaymentsActivatedMessage(thread: thread, senderAci: envelope.sourceAci, transaction: tx)
            }
            return nil
        }

        updateDisappearingMessageConfiguration(envelope: envelope, dataMessage: dataMessage, thread: thread, tx: tx)

        var storyTimestamp: UInt64?
        var storyAuthorAci: Aci?
        if let storyContext = dataMessage.storyContext, storyContext.hasSentTimestamp, storyContext.hasAuthorAci {
            storyTimestamp = storyContext.sentTimestamp
            storyAuthorAci = Aci.parseFrom(aciString: storyContext.authorAci)
            Logger.info("Processing storyContext for message w/ts \(envelope.timestamp), storyTimestamp: \(String(describing: storyTimestamp)), authorAci: \(String(describing: storyAuthorAci))")
            guard let storyAuthorAci else {
                owsFailDebug("Discarding story reply with invalid ACI")
                return nil
            }

            if thread.isGroupThread {
                // Drop group story replies if we can't find the story message
                guard StoryFinder.story(
                    timestamp: storyContext.sentTimestamp,
                    author: storyAuthorAci,
                    transaction: tx
                ) != nil else {
                    Logger.warn("Couldn't find story message; discarding group story reply")
                    return nil
                }
            }
        }

        // Legit usage of senderTimestamp when creating an incoming group message
        // record.
        let messageBuilder = TSIncomingMessageBuilder(
            thread: thread,
            timestamp: envelope.timestamp,
            receivedAtTimestamp: nil,
            authorAci: envelope.sourceAci,
            authorE164: nil,
            messageBody: body,
            bodyRanges: bodyRanges,
            editState: .none,
            expiresInSeconds: dataMessage.expireTimer,
            expireTimerVersion: dataMessage.expireTimerVersion,
            expireStartedAt: 0,
            read: false,
            serverTimestamp: envelope.serverTimestamp,
            serverDeliveryTimestamp: request.serverDeliveryTimestamp,
            serverGuid: serverGuid?.uuidString.lowercased(),
            wasReceivedByUD: request.wasReceivedByUD,
            isSmsMessageRestoredFromBackup: false,
            isViewOnceMessage: isViewOnceMessage,
            isViewOnceComplete: false,
            wasRemotelyDeleted: false,
            storyAuthorAci: storyAuthorAci,
            storyTimestamp: storyTimestamp,
            storyReactionEmoji: nil,
            quotedMessage: quotedMessageBuilder?.info,
            contactShare: contactBuilder?.info,
            linkPreview: linkPreviewBuilder?.info,
            messageSticker: messageStickerBuilder?.info,
            giftBadge: giftBadge,
            paymentNotification: paymentModels?.notification
        )
        let message = messageBuilder.build()

        guard message.shouldBeSaved else {
            owsFailDebug("We should be able to save all incoming messages.")
            return nil
        }

        let hasRenderableContent = messageBuilder.hasRenderableContent(
            hasBodyAttachments: !dataMessage.attachments.isEmpty,
            hasLinkPreview: linkPreviewBuilder != nil,
            hasQuotedReply: quotedMessageBuilder != nil,
            hasContactShare: contactBuilder != nil,
            hasSticker: messageStickerBuilder != nil,
            hasPayment: paymentModels != nil
        )
        guard hasRenderableContent else {
            Logger.warn("Ignoring empty: \(messageDescription)")
            return nil
        }

        if message.giftBadge != nil, thread.isGroupThread {
            owsFailDebug("Ignoring gift sent to group.")
            return nil
        }

        // Check for any placeholders inserted because of a previously
        // undecryptable message. The sender may have resent the message. If so, we
        // should swap it in place of the placeholder.
        message.insertOrReplacePlaceholder(from: SignalServiceAddress(envelope.sourceAci), transaction: tx)

        // Inserting the message may have modified the thread on disk, so reload
        // it. For example, we may have marked the thread as visible.
        let updatedThread = TSThread.anyFetch(uniqueId: thread.uniqueId, transaction: tx) ?? thread

        do {
            try DependenciesBridge.shared.attachmentManager.createAttachmentPointers(
                from: dataMessage.attachments.map { proto in
                    return .init(
                        proto: proto,
                        owner: .messageBodyAttachment(.init(
                            messageRowId: message.sqliteRowId!,
                            receivedAtTimestamp: message.receivedAtTimestamp,
                            threadRowId: thread.sqliteRowId!,
                            isViewOnce: message.isViewOnceMessage,
                            isPastEditRevision: message.isPastEditRevision()
                        ))
                    )
                },
                tx: tx.asV2Write
            )

            try quotedMessageBuilder?.finalize(
                owner: .quotedReplyAttachment(.init(
                    messageRowId: message.sqliteRowId!,
                    receivedAtTimestamp: message.receivedAtTimestamp,
                    threadRowId: thread.sqliteRowId!,
                    isPastEditRevision: message.isPastEditRevision()
                )),
                tx: tx.asV2Write
            )
            try linkPreviewBuilder?.finalize(
                owner: .messageLinkPreview(.init(
                    messageRowId: message.sqliteRowId!,
                    receivedAtTimestamp: message.receivedAtTimestamp,
                    threadRowId: thread.sqliteRowId!,
                    isPastEditRevision: message.isPastEditRevision()
                )),
                tx: tx.asV2Write
            )
            try messageStickerBuilder.map {
                try $0.finalize(
                    owner: .messageSticker(.init(
                        messageRowId: message.sqliteRowId!,
                        receivedAtTimestamp: message.receivedAtTimestamp,
                        threadRowId: thread.sqliteRowId!,
                        isPastEditRevision: message.isPastEditRevision(),
                        stickerPackId: $0.info.packId,
                        stickerId: $0.info.stickerId
                    )),
                    tx: tx.asV2Write
                )
            }
            try contactBuilder?.finalize(
                owner: .messageContactAvatar(.init(
                    messageRowId: message.sqliteRowId!,
                    receivedAtTimestamp: message.receivedAtTimestamp,
                    threadRowId: thread.sqliteRowId!,
                    isPastEditRevision: message.isPastEditRevision()
                )),
                tx: tx.asV2Write
            )
        } catch {
            owsFailDebug("Could not build attachments!")
            DependenciesBridge.shared.interactionDeleteManager
                .delete(message, sideEffects: .default(), tx: tx.asV2Write)
            return nil
        }

        owsAssertDebug(message.insertedMessageHasRenderableContent(rowId: message.sqliteRowId!, tx: tx))

        guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read) else {
            owsFailDebug("Can't process messages when not registered.")
            return nil
        }

        SSKEnvironment.shared.earlyMessageManagerRef.applyPendingMessages(for: message, localIdentifiers: localIdentifiers, transaction: tx)

        // Any messages sent from the current user - from this device or another -
        // should be automatically marked as read.
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        if envelope.sourceAci == tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aci {
            let hasPendingMessageRequest = updatedThread.hasPendingMessageRequest(transaction: tx)
            owsFailDebug("Incoming messages from yourself aren't supported.")
            // Don't send a read receipt for messages sent by ourselves.
            message.markAsRead(
                atTimestamp: envelope.timestamp,
                thread: updatedThread,
                circumstance: hasPendingMessageRequest ? .onLinkedDeviceWhilePendingMessageRequest : .onLinkedDevice,
                shouldClearNotifications: false, // not required, since no notifications if sent by local
                transaction: tx
            )
        }

        DependenciesBridge.shared.attachmentDownloadManager.enqueueDownloadOfAttachmentsForMessage(message, tx: tx.asV2Write)
        SSKEnvironment.shared.notificationPresenterRef.notifyUser(forIncomingMessage: message, thread: thread, transaction: tx)

        if CurrentAppContext().isMainApp {
            DispatchQueue.main.async {
                SSKEnvironment.shared.typingIndicatorsRef.didReceiveIncomingMessage(
                    inThread: updatedThread,
                    senderAci: envelope.sourceAci,
                    deviceId: envelope.sourceDeviceId
                )
            }
        }

        return nil
    }

    private func updateDisappearingMessageConfiguration(
        envelope: DecryptedIncomingEnvelope,
        dataMessage: SSKProtoDataMessage,
        thread: TSThread,
        tx: SDSAnyWriteTransaction
    ) {
        guard let contactThread = thread as? TSContactThread else {
            return
        }
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx.asV2Read) else {
            owsFailDebug("Not registered.")
            return
        }
        GroupManager.remoteUpdateDisappearingMessages(
            contactThread: contactThread,
            disappearingMessageToken: .token(
                forProtoExpireTimerSeconds: dataMessage.expireTimer,
                version: dataMessage.expireTimerVersion
            ),
            changeAuthor: envelope.sourceAci,
            localIdentifiers: localIdentifiers,
            transaction: tx
        )
    }

    private func handleIncomingEnvelope(
        request: MessageReceiverRequest,
        callMessage: SSKProtoCallMessage,
        localIdentifiers: LocalIdentifiers,
        tx: SDSAnyWriteTransaction
    ) {
        let envelope = request.decryptedEnvelope

        // If destinationDevice is defined, ignore messages not addressed to this device.
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        let localDeviceId = tsAccountManager.storedDeviceId(tx: tx.asV2Read)
        if callMessage.hasDestinationDeviceID, callMessage.destinationDeviceID != localDeviceId {
            Logger.info("Ignoring call message for other device #\(callMessage.destinationDeviceID)")
            return
        }

        if let profileKey = callMessage.profileKey {
            setProfileKeyIfValid(profileKey, for: envelope.sourceAci, localIdentifiers: localIdentifiers, tx: tx)
        }

        let callEnvelope: CallEnvelopeType

        if let offer = callMessage.offer {
            callEnvelope = .offer(offer)
        } else if let answer = callMessage.answer {
            callEnvelope = .answer(answer)
        } else if !callMessage.iceUpdate.isEmpty {
            callEnvelope = .iceUpdate(callMessage.iceUpdate)
        } else if let hangup = callMessage.hangup {
            callEnvelope = .hangup(hangup)
        } else if let busy = callMessage.busy {
            callEnvelope = .busy(busy)
        } else if let opaque = callMessage.opaque {
            callEnvelope = .opaque(opaque)
        } else {
            Logger.warn("Dropping call message with no actionable payload.")
            return
        }
        callMessageHandler.receivedEnvelope(
            envelope.envelope,
            callEnvelope: callEnvelope,
            from: (envelope.sourceAci, envelope.sourceDeviceId),
            toLocalIdentity: envelope.localIdentity,
            plaintextData: envelope.plaintextData,
            wasReceivedByUD: envelope.wasReceivedByUD,
            sentAtTimestamp: envelope.timestamp,
            serverReceivedTimestamp: envelope.serverTimestamp,
            serverDeliveryTimestamp: request.serverDeliveryTimestamp,
            tx: tx
        )
    }

    private func handleIncomingEnvelope(
        _ decryptedEnvelope: DecryptedIncomingEnvelope,
        withSenderKeyDistributionMessage skdmData: Data,
        transaction tx: SDSAnyWriteTransaction
    ) {
        do {
            let skdm = try SenderKeyDistributionMessage(bytes: skdmData.map { $0 })
            let sourceAci = decryptedEnvelope.sourceAci
            let sourceDeviceId = decryptedEnvelope.sourceDeviceId
            let protocolAddress = ProtocolAddress(sourceAci, deviceId: sourceDeviceId)
            try processSenderKeyDistributionMessage(skdm, from: protocolAddress, store: SSKEnvironment.shared.senderKeyStoreRef, context: tx)

            Logger.info("Processed incoming sender key distribution message from \(sourceAci).\(sourceDeviceId)")

        } catch {
            owsFailDebug("Failed to process incoming sender key \(error)")
        }
    }

    private func handleIncomingEnvelope(
        request: MessageReceiverRequest,
        typingMessage: SSKProtoTypingMessage,
        tx: SDSAnyWriteTransaction
    ) {
        let envelope = request.decryptedEnvelope

        guard typingMessage.timestamp == envelope.timestamp else {
            owsFailDebug("typingMessage has invalid timestamp")
            return
        }
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        if envelope.sourceAci == tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aci {
            return
        }
        let thread: TSThread
        if let groupId = typingMessage.groupID {
            if SSKEnvironment.shared.blockingManagerRef.isGroupIdBlocked(groupId, transaction: tx) {
                Logger.warn("Ignoring blocked message from \(envelope.sourceAci) in \(groupId)")
                return
            }
            guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: tx) else {
                // This isn't necessarily an error. We might not yet know about the thread,
                // in which case we don't need to display the typing indicators.
                Logger.warn("Ignoring typingMessage for non-existent thread")
                return
            }
            guard groupThread.isLocalUserFullOrInvitedMember else {
                Logger.info("Ignoring message for left group")
                return
            }
            if let groupModel = groupThread.groupModel as? TSGroupModelV2, groupModel.isAnnouncementsOnly {
                guard groupModel.groupMembership.isFullMemberAndAdministrator(envelope.sourceAci) else {
                    return
                }
            }
            thread = groupThread
        } else {
            let sourceAddress = SignalServiceAddress(envelope.sourceAci)
            guard let contactThread = TSContactThread.getWithContactAddress(sourceAddress, transaction: tx) else {
                // This isn't necessarily an error. We might not yet know about the thread,
                // in which case we don't need to display the typing indicators.
                Logger.warn("Ignoring typingMessage for non-existent thread")
                return
            }
            thread = contactThread
        }
        DispatchQueue.main.async {
            switch typingMessage.action {
            case .started:
                SSKEnvironment.shared.typingIndicatorsRef.didReceiveTypingStartedMessage(
                    inThread: thread,
                    senderAci: envelope.sourceAci,
                    deviceId: envelope.sourceDeviceId
                )
            case .stopped:
                SSKEnvironment.shared.typingIndicatorsRef.didReceiveTypingStoppedMessage(
                    inThread: thread,
                    senderAci: envelope.sourceAci,
                    deviceId: envelope.sourceDeviceId
                )
            case .none:
                owsFailDebug("typingMessage has unexpected action")
            }
        }
    }

    /// This code path is for UD receipts.
    private func handleIncomingEnvelope(
        request: MessageReceiverRequest,
        receiptMessage: SSKProtoReceiptMessage,
        context: DeliveryReceiptContext,
        tx: SDSAnyWriteTransaction
    ) {
        let envelope = request.decryptedEnvelope

        guard let receiptType = receiptMessage.type else {
            owsFailDebug("Missing type for receipt message.")
            return
        }

        let sentTimestamps = receiptMessage.timestamp
        for sentTimestamp in sentTimestamps {
            guard SDS.fitsInInt64(sentTimestamp) else {
                owsFailDebug("Invalid timestamp.")
                return
            }
        }

        let earlyTimestamps: [UInt64]
        switch receiptType {
        case .delivery:
            earlyTimestamps = SSKEnvironment.shared.receiptManagerRef.processDeliveryReceipts(
                from: envelope.sourceAci,
                recipientDeviceId: envelope.sourceDeviceId,
                sentTimestamps: sentTimestamps,
                deliveryTimestamp: envelope.timestamp,
                context: context,
                tx: tx
            )
        case .read:
            earlyTimestamps = SSKEnvironment.shared.receiptManagerRef.processReadReceipts(
                from: envelope.sourceAci,
                recipientDeviceId: envelope.sourceDeviceId,
                sentTimestamps: sentTimestamps,
                readTimestamp: envelope.timestamp,
                tx: tx
            )
        case .viewed:
            earlyTimestamps = SSKEnvironment.shared.receiptManagerRef.processViewedReceipts(
                from: envelope.sourceAci,
                recipientDeviceId: envelope.sourceDeviceId,
                sentTimestamps: sentTimestamps,
                viewedTimestamp: envelope.timestamp,
                tx: tx
            )
        }

        recordEarlyReceipts(
            receiptType: receiptType,
            senderServiceId: envelope.sourceAci,
            senderDeviceId: envelope.sourceDeviceId,
            associatedMessageTimestamps: earlyTimestamps,
            actionTimestamp: envelope.timestamp,
            tx: tx
        )
    }

    /// Records early receipts for a set of message timestamps.
    ///
    /// - Parameter associatedMessageTimestamps: A list of message timestamps
    /// that may need to be marked viewed/read/delivered after they are
    /// received.
    ///
    /// - Parameter actionTimestamp: The timestamp when the other user
    /// viewed/read/received the message.
    private func recordEarlyReceipts(
        receiptType: SSKProtoReceiptMessageType,
        senderServiceId: ServiceId,
        senderDeviceId: UInt32,
        associatedMessageTimestamps: [UInt64],
        actionTimestamp: UInt64,
        tx: SDSAnyWriteTransaction
    ) {
        for associatedMessageTimestamp in associatedMessageTimestamps {
            SSKEnvironment.shared.earlyMessageManagerRef.recordEarlyReceiptForOutgoingMessage(
                type: receiptType,
                senderServiceId: senderServiceId,
                senderDeviceId: senderDeviceId,
                timestamp: actionTimestamp,
                associatedMessageTimestamp: associatedMessageTimestamp,
                tx: tx
            )
        }
    }

    private func handleIncomingEnvelope(
        request: MessageReceiverRequest,
        decryptionErrorMessage: Data,
        tx: SDSAnyWriteTransaction
    ) {
        let envelope = request.decryptedEnvelope
        let sourceAci = envelope.sourceAci
        let sourceDeviceId = envelope.sourceDeviceId

        do {
            guard envelope.localIdentity == .aci else {
                throw OWSGenericError("Can't receive DEMs at our PNI.")
            }
            let errorMessage = try DecryptionErrorMessage(bytes: decryptionErrorMessage)
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            guard errorMessage.deviceId == tsAccountManager.storedDeviceId(tx: tx.asV2Read) else {
                Logger.info("Received a DecryptionError message targeting a linked device. Ignoring.")
                return
            }
            let protocolAddress = ProtocolAddress(sourceAci, deviceId: sourceDeviceId)

            let didPerformSessionReset: Bool

            if let ratchetKey = errorMessage.ratchetKey {
                // If a ratchet key is included, this was a 1:1 session message
                // Archive the session if the current key matches.
                let sessionStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore
                let sessionRecord = try sessionStore.loadSession(for: protocolAddress, context: tx)
                if try sessionRecord?.currentRatchetKeyMatches(ratchetKey) == true {
                    Logger.info("Decryption error included ratchet key. Archiving...")
                    sessionStore.archiveSession(for: sourceAci, deviceId: sourceDeviceId, tx: tx.asV2Write)
                    didPerformSessionReset = true
                } else {
                    didPerformSessionReset = false
                }
            } else {
                // If we don't have a ratchet key, this was a sender key session message.
                // Let's log any info about SKDMs that we had sent to the address requesting resend
                SSKEnvironment.shared.senderKeyStoreRef.logSKDMInfo(for: SignalServiceAddress(sourceAci), transaction: tx)
                didPerformSessionReset = false
            }

            Logger.warn("Performing message resend of timestamp \(errorMessage.timestamp)")
            let resendResponse = OWSOutgoingResendResponse(
                aci: sourceAci,
                deviceId: sourceDeviceId,
                failedTimestamp: errorMessage.timestamp,
                didResetSession: didPerformSessionReset,
                tx: tx
            )

            let sendBlock = { (transaction: SDSAnyWriteTransaction) in
                if let resendResponse = resendResponse {
                    let preparedMessage = PreparedOutgoingMessage.preprepared(
                        transientMessageWithoutAttachments: resendResponse
                    )
                    SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: transaction)
                }
            }

            if DebugFlags.delayedMessageResend.get() {
                DispatchQueue.sharedUtility.asyncAfter(deadline: .now() + 10) {
                    SSKEnvironment.shared.databaseStorageRef.asyncWrite { tx in
                        sendBlock(tx)
                    }
                }
            } else {
                sendBlock(tx)
            }

        } catch {
            owsFailDebug("Failed to process decryption error message \(error)")
        }
    }

    private func handleIncomingEnvelope(
        request: MessageReceiverRequest,
        storyMessage: SSKProtoStoryMessage,
        localIdentifiers: LocalIdentifiers,
        tx: SDSAnyWriteTransaction
    ) {
        do {
            try StoryManager.processIncomingStoryMessage(
                storyMessage,
                timestamp: request.decryptedEnvelope.timestamp,
                author: request.decryptedEnvelope.sourceAci,
                localIdentifiers: localIdentifiers,
                transaction: tx
            )
        } catch {
            Logger.warn("Failed to insert story message with error \(error.localizedDescription)")
        }
    }

    private enum EditProcessingResult: Int, Error {
        case editedMessageMissing
        case invalidEdit
        case success
    }

    private func handleIncomingEnvelope(
        _ decryptedEnvelope: DecryptedIncomingEnvelope,
        sentMessage: SSKProtoSyncMessageSent,
        editMessage: SSKProtoEditMessage,
        serverDeliveryTimestamp: UInt64,
        transaction tx: SDSAnyWriteTransaction
    ) -> EditProcessingResult {

        guard SDS.fitsInInt64(editMessage.targetSentTimestamp) else {
            Logger.error("Edit message target was invalid timestamp!")
            return .invalidEdit
        }

        guard let transcript = OWSIncomingSentMessageTranscript.from(
            sentProto: sentMessage,
            serverTimestamp: decryptedEnvelope.serverTimestamp,
            tx: tx.asV2Write
        ) else {
            Logger.warn("Missing edit transcript.")
            return .invalidEdit
        }

        guard let thread = transcript.threadForDataMessage else {
            Logger.warn("Missing edit message thread.")
            return .invalidEdit
        }

        // Find the target message to edit. If missing,
        // return and enqueue the message to be handled as early delivery
        guard
            let targetMessage = DependenciesBridge.shared.editMessageStore.editTarget(
                timestamp: editMessage.targetSentTimestamp,
                authorAci: nil,
                tx: tx.asV2Read
            )
        else {
            Logger.warn("Edit cannot find the target message")
            return .editedMessageMissing
        }

        guard let message = try? handleMessageEdit(
            envelope: decryptedEnvelope,
            serverDeliveryTimestamp: serverDeliveryTimestamp,
            thread: thread,
            editTarget: targetMessage,
            editMessage: editMessage,
            transaction: tx
        ) else {
            Logger.info("Failed to insert edit sync message")
            return .invalidEdit
        }

        if let msg = message as? TSOutgoingMessage {
            msg.updateRecipientsFromNonLocalDevice(
                transcript.recipientStates,
                isSentUpdate: false,
                transaction: tx
            )
        }

        return .success
    }

    private func handleIncomingEnvelope(
        request: MessageReceiverRequest,
        editMessage: SSKProtoEditMessage,
        tx: SDSAnyWriteTransaction
    ) -> EditProcessingResult {
        guard SDS.fitsInInt64(editMessage.targetSentTimestamp) else {
            Logger.error("Edit message target was invalid timestamp!")
            return .invalidEdit
        }

        guard let dataMessage = editMessage.dataMessage else {
            Logger.warn("Missing edit message data.")
            return .invalidEdit
        }

        let decryptedEnvelope = request.decryptedEnvelope

        guard let thread = preprocessDataMessage(dataMessage, envelope: decryptedEnvelope, tx: tx) else {
            Logger.warn("Missing edit message thread.")
            return .invalidEdit
        }

        // Find the target message to edit. If missing,
        // return and enqueue the message to be handled as early delivery
        guard let targetMessage = DependenciesBridge.shared.editMessageStore.editTarget(
            timestamp: editMessage.targetSentTimestamp,
            authorAci: decryptedEnvelope.sourceAci,
            tx: tx.asV2Read
        ) else {
            Logger.warn("Edit cannot find the target message")
            return .editedMessageMissing
        }

        guard let message = try? handleMessageEdit(
            envelope: decryptedEnvelope,
            serverDeliveryTimestamp: request.serverDeliveryTimestamp,
            thread: thread,
            editTarget: targetMessage,
            editMessage: editMessage,
            transaction: tx
        ) else {
            Logger.info("Failed to insert edit message")
            return .invalidEdit
        }

        if request.wasReceivedByUD {
            let receiptSender = SSKEnvironment.shared.receiptSenderRef
            receiptSender.enqueueDeliveryReceipt(for: decryptedEnvelope, messageUniqueId: message.uniqueId, tx: tx)
        }

        if
            case let .incomingMessage(incoming) = targetMessage,
            let message = message as? TSIncomingMessage
        {
            // Only update notifications for unread/unedited message targets
            let targetEditState = incoming.message.editState
            if targetEditState == .latestRevisionUnread || targetEditState == .none {
                SSKEnvironment.shared.notificationPresenterRef.notifyUser(
                    forIncomingMessage: message,
                    editTarget: incoming.message,
                    thread: thread,
                    transaction: tx
                )
            }
        }

        return .success
    }

    private func handleMessageEdit(
        envelope: DecryptedIncomingEnvelope,
        serverDeliveryTimestamp: UInt64,
        thread: TSThread,
        editTarget: EditMessageTarget,
        editMessage: SSKProtoEditMessage,
        transaction tx: SDSAnyWriteTransaction
    ) throws -> TSMessage {

        guard let dataMessage = editMessage.dataMessage else {
            throw OWSAssertionError("Missing dataMessage in edit")
        }

        let message = try DependenciesBridge.shared.editManager.processIncomingEditMessage(
            dataMessage,
            serverTimestamp: envelope.serverTimestamp,
            serverGuid: envelope.envelope.serverGuid,
            serverDeliveryTimestamp: serverDeliveryTimestamp,
            thread: thread,
            editTarget: editTarget,
            tx: tx.asV2Write
        )

        // Start downloading any new attachments
        DependenciesBridge.shared.attachmentDownloadManager.enqueueDownloadOfAttachmentsForMessage(
            message,
            tx: tx.asV2Write
        )

        DispatchQueue.main.async {
            SSKEnvironment.shared.typingIndicatorsRef.didReceiveIncomingMessage(
                inThread: thread,
                senderAci: envelope.sourceAci,
                deviceId: envelope.sourceDeviceId
            )
        }

        return message
    }

    func checkForUnknownLinkedDevice(in envelope: DecryptedIncomingEnvelope, tx: SDSAnyWriteTransaction) {
        let aci = envelope.sourceAci
        let deviceId = envelope.sourceDeviceId

        guard aci == DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aci else {
            return
        }

        // Check if the SignalRecipient (used for sending messages) knows about
        // this device.
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher
        let recipient = recipientFetcher.fetchOrCreate(serviceId: aci, tx: tx.asV2Write)
        if !recipient.deviceIds.contains(deviceId) {
            let recipientManager = DependenciesBridge.shared.recipientManager
            Logger.info("Message received from unknown linked device; adding to local SignalRecipient: \(deviceId).")
            recipientManager.markAsRegisteredAndSave(recipient, deviceId: deviceId, shouldUpdateStorageService: true, tx: tx.asV2Write)
        }
    }

    private func handleIncomingEndSessionEnvelope(
        _ decryptedEnvelope: DecryptedIncomingEnvelope,
        withDataMessage dataMessage: SSKProtoDataMessage,
        tx: SDSAnyWriteTransaction
    ) {
        guard decryptedEnvelope.localIdentity == .aci else {
            owsFailDebug("Can't receive end session messages to our PNI.")
            return
        }

        let thread = TSContactThread.getOrCreateThread(
            withContactAddress: SignalServiceAddress(decryptedEnvelope.sourceAci),
            transaction: tx
        )
        TSInfoMessage(thread: thread, messageType: .typeRemoteUserEndedSession).anyInsert(transaction: tx)

        let sessionStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore
        sessionStore.archiveAllSessions(for: decryptedEnvelope.sourceAci, tx: tx.asV2Write)
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
        var parts = [String]()
        if let dataMessage = self.dataMessage {
            parts.append("data \(dataMessage.contentDescription)")
        }
        if let syncMessage = self.syncMessage {
            parts.append("sync \(syncMessage.contentDescription)")
        }
        if let callMessage = self.callMessage {
            parts.append("call \(callMessage.contentDescription)")
        }
        if nullMessage != nil {
            parts.append("null")
        }
        if receiptMessage != nil {
            parts.append("receipt")
        }
        if typingMessage != nil {
            parts.append("typing")
        }
        if storyMessage != nil {
            parts.append("story")
        }
        if pniSignatureMessage != nil {
            parts.append("pniSignature")
        }
        if editMessage != nil {
            parts.append("edit")
        }
        if senderKeyDistributionMessage != nil {
            parts.append("senderKeyDistribution")
        }
        if decryptionErrorMessage != nil {
            parts.append("decryptionError")
        }
        if hasUnknownFields {
            parts.append("unknown fields")
        }
        return "[\(parts.joined(separator: ", "))]"
    }
}

extension SSKProtoCallMessage {
    @objc
    var contentDescription: String {
        let messageType: String
        let callId: UInt64

        if let offer = self.offer {
            messageType = "offer"
            callId = offer.id
        } else if let busy = self.busy {
            messageType = "busy"
            callId = busy.id
        } else if let answer = self.answer {
            messageType = "answer"
            callId = answer.id
        } else if let hangup = self.hangup {
            messageType = "hangup"
            callId = hangup.id
        } else if let firstICEUpdate = iceUpdate.first {
            messageType = "ice updates \(iceUpdate.count)"
            callId = firstICEUpdate.id
        } else if let opaque = self.opaque {
            if opaque.hasUrgency {
                messageType = "opaque \(opaque.unwrappedUrgency.contentDescription)"
            } else {
                messageType = "opaque"
            }
            callId = 0
        } else {
            owsFailDebug("failure: unexpected call message type: \(self)")
            messageType = "unknown"
            callId = 0
        }

        return "[type: \(messageType), id: \(callId)]"
    }
}

extension SSKProtoCallMessageOpaqueUrgency {
    var contentDescription: String {
        switch self {
        case .droppable:
            return "droppable"
        case .handleImmediately:
            return "handleImmediately"
        default:
            return "unknown"
        }
    }
}

extension SSKProtoDataMessage {
    @objc
    var contentDescription: String {
        var parts = [String]()
        if !attachments.isEmpty {
            parts.append("attachments")
        }
        if groupV2 != nil {
            parts.append("group")
        }
        if quote != nil {
            parts.append("quote")
        }
        if !contact.isEmpty {
            parts.append("contacts")
        }
        if !preview.isEmpty {
            parts.append("linkPreviews")
        }
        if sticker != nil {
            parts.append("stickers")
        }
        if reaction != nil {
            parts.append("reaction")
        }
        if delete != nil {
            parts.append("delete")
        }
        if !bodyRanges.isEmpty {
            parts.append("bodyRanges")
        }
        if groupCallUpdate != nil {
            parts.append("groupCallUpdate")
        }
        if payment != nil {
            parts.append("payment")
        }
        if giftBadge != nil {
            parts.append("giftBadge")
        }
        if body != nil {
            parts.append("body")
        }
        if expireTimer > 0 {
            parts.append("expireTimer")
        }
        if profileKey != nil {
            parts.append("profileKey")
        }
        if isViewOnce {
            parts.append("viewOnce")
        }
        if flags > 0 {
            parts.append("flags \(flags)")
        }
        if hasUnknownFields {
            parts.append("unknown fields")
        }
        return "[\(parts.joined(separator: ", "))]"
    }
}

extension SSKProtoSyncMessage {
    @objc
    var contentDescription: String {
        var parts = [String]()
        if sent != nil {
            parts.append("sentTranscript")
        }
        if contacts != nil {
            parts.append("contacts")
        }
        if let request {
            switch request.type {
            case .contacts:
                parts.append("request: contacts")
            case .blocked:
                parts.append("request: blocked")
            case .configuration:
                parts.append("request: configuration")
            case .keys:
                parts.append("request: keys")
            case .unknown, .none: fallthrough
            @unknown default:
                parts.append("request: unknown")
            }
        }
        if !read.isEmpty {
            parts.append("readReceipts")
        }
        if blocked != nil {
            parts.append("blocked")
        }
        if verified != nil {
            parts.append("verified")
        }
        if configuration != nil {
            parts.append("configuration")
        }
        if !stickerPackOperation.isEmpty {
            for packOperationProto in stickerPackOperation {
                switch packOperationProto.type {
                case .install:
                    parts.append("stickerPack: install")
                case .remove:
                    parts.append("stickerPack: remove")
                case .none: fallthrough
                @unknown default:
                    parts.append("stickerPack: unknown")
                }
            }
        }
        if viewOnceOpen != nil {
            parts.append("viewOnceOpen")
        }
        if let fetchLatest {
            switch fetchLatest.type {
            case .localProfile:
                parts.append("fetchLatest: profile")
            case .storageManifest:
                parts.append("fetchLatest: storageService")
            case .subscriptionStatus:
                parts.append("fetchLatest: subscription")
            case .unknown, .none: fallthrough
            @unknown default:
                parts.append("fetchLatest: unknown")
            }
        }
        if keys != nil {
            parts.append("keys")
        }
        if messageRequestResponse != nil {
            parts.append("messageRequestResponse")
        }
        if outgoingPayment != nil {
            parts.append("outgoingPayment")
        }
        if !viewed.isEmpty {
            parts.append("viewedReceipt")
        }
        if pniChangeNumber != nil {
            parts.append("pniChangeNumber")
        }
        if callEvent != nil {
            parts.append("callEvent")
        }
        if callLinkUpdate != nil {
            parts.append("callLinkUpdate")
        }
        if callLogEvent != nil {
            parts.append("callLogEvent")
        }
        if deleteForMe != nil {
            parts.append("deleteForMe")
        }
        if deviceNameChange != nil {
            parts.append("deviceNameChange")
        }
        if hasUnknownFields {
            parts.append("unknown fields")
        }
        owsAssertDebug(!parts.isEmpty, "unknown sync message type")
        return "[\(parts.joined(separator: ", "))]"
    }
}

// MARK: -

enum MessageReceiverMessageType {
    case syncMessage(SSKProtoSyncMessage)
    case dataMessage(SSKProtoDataMessage)
    case callMessage(SSKProtoCallMessage)
    case typingMessage(SSKProtoTypingMessage)
    case nullMessage
    case receiptMessage(SSKProtoReceiptMessage)
    case decryptionErrorMessage(Data)
    case storyMessage(SSKProtoStoryMessage)
    case editMessage(SSKProtoEditMessage)
    case handledElsewhere
}

class MessageReceiverRequest {
    let decryptedEnvelope: DecryptedIncomingEnvelope
    let envelope: SSKProtoEnvelope
    let plaintextData: Data
    let wasReceivedByUD: Bool
    let serverDeliveryTimestamp: UInt64
    let shouldDiscardVisibleMessages: Bool
    let protoContent: SSKProtoContent
    var messageType: MessageReceiverMessageType? {
        if let syncMessage = protoContent.syncMessage {
            return .syncMessage(syncMessage)
        }
        if let dataMessage = protoContent.dataMessage {
            return .dataMessage(dataMessage)
        }
        if let callMessage = protoContent.callMessage {
            return .callMessage(callMessage)
        }
        if let typingMessage = protoContent.typingMessage {
            return .typingMessage(typingMessage)
        }
        if protoContent.nullMessage != nil {
            return .nullMessage
        }
        if let receiptMessage = protoContent.receiptMessage {
            return .receiptMessage(receiptMessage)
        }
        if let decryptionErrorMessage = protoContent.decryptionErrorMessage {
            return .decryptionErrorMessage(decryptionErrorMessage)
        }
        if let storyMessage = protoContent.storyMessage {
            return .storyMessage(storyMessage)
        }
        if let editMessage = protoContent.editMessage {
            return .editMessage(editMessage)
        }
        // All mutually-exclusive top-level proto content types should be placed
        // above this comment. Below this comment, we return `.handledElsewhere`
        // for cases that *might* be combined with another type or sent alone.
        if protoContent.hasSenderKeyDistributionMessage {
            // Sender key distribution messages are not mutually exclusive. They can be
            // included with any message type. However, they're not processed here.
            // They're processed in the -preprocess phase that occurs post-decryption.
            return .handledElsewhere
        }
        return nil
    }

    enum BuildResult {
        case discard
        case noContent
        case request(MessageReceiverRequest)
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

        return .request(MessageReceiverRequest(
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
