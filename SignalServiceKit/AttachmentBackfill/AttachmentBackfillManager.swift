//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public class AttachmentBackfillManager {

    /// Wrapper around `MessageSenderJobQueue`, for tests.
    protocol AttachmentBackfillSyncMessageSender {
        func add(
            attachmentBackfillRequestSyncMessage: AttachmentBackfillRequestSyncMessage,
            tx: DBWriteTransaction,
        )

        func add(
            attachmentBackfillResponseSyncMessage: AttachmentBackfillResponseSyncMessage,
            tx: DBWriteTransaction,
        )
    }

    // MARK: -

    private let attachmentStore: AttachmentStore
    private let attachmentUploadManager: AttachmentUploadManager
    private let db: DB
    private let interactionStore: InteractionStore
    private let logger: PrefixedLogger
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let syncMessageSender: AttachmentBackfillSyncMessageSender
    private let taskQueue: SerialTaskQueue
    private let threadStore: ThreadStore

    init(
        attachmentStore: AttachmentStore,
        attachmentUploadManager: AttachmentUploadManager,
        db: DB,
        interactionStore: InteractionStore,
        recipientDatabaseTable: RecipientDatabaseTable,
        syncMessageSender: AttachmentBackfillSyncMessageSender,
        threadStore: ThreadStore,
    ) {
        self.attachmentStore = attachmentStore
        self.attachmentUploadManager = attachmentUploadManager
        self.db = db
        self.interactionStore = interactionStore
        self.logger = PrefixedLogger(prefix: "[Backfill]")
        self.recipientDatabaseTable = recipientDatabaseTable
        self.syncMessageSender = syncMessageSender
        self.taskQueue = SerialTaskQueue()
        self.threadStore = threadStore
    }

    // MARK: - Outbound Requests

    public func sendOutboundRequest(
        message: TSMessage,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction,
    ) {
        guard
            let backfillTarget = assembleBackfillTarget(
                message: message,
                localIdentifiers: localIdentifiers,
                tx: tx,
            )
        else {
            logger.warn("Failed to assemble backfill target for outbound request.")
            return
        }

        guard let localThread = threadStore.getOrCreateLocalThread(tx: tx) else {
            owsFailDebug("Failed to get local thread.", logger: logger)
            return
        }

        let requestProtoBuilder = SSKProtoSyncMessageAttachmentBackfillRequest.builder()
        requestProtoBuilder.setTargetMessage(backfillTarget.addressableMessage.asProto)
        requestProtoBuilder.setTargetConversation(backfillTarget.conversationIdentifier.asProto)

        do {
            let syncMessage = try AttachmentBackfillRequestSyncMessage(
                requestProto: requestProtoBuilder.buildInfallibly(),
                localThread: localThread,
                tx: tx,
            )

            syncMessageSender.add(
                attachmentBackfillRequestSyncMessage: syncMessage,
                tx: tx,
            )
        } catch {
            owsFailDebug("Failed to build backfill request sync message! \(error)")
            return
        }
    }

    // MARK: - Inbound Requests

    /// Returns whether we have an enqueued `AttachmentBackfillInboundRequestRecord`
    /// for the given interaction ID.
    public func hasEnqueuedInboundRequest(interactionRowId: Int64, tx: DBReadTransaction) -> Bool {
        return AttachmentBackfillInboundRequestRecord.fetchRecord(
            interactionId: interactionRowId,
            tx: tx,
        ) != nil
    }

    /// Serially processes already-enqueued `AttachmentBackfillInboundRequestRecord`s,
    /// for example from interrupted previous launches.
    /// - SeeAlso `processInboundRequest(requestRecord:localIdentifiers:)`
    public func processEnqueuedInboundRequests(registeredState: RegisteredState) {
        guard registeredState.isPrimary else {
            return
        }

        let enqueuedRequestRecords: [AttachmentBackfillInboundRequestRecord] = db.read { tx in
            AttachmentBackfillInboundRequestRecord.fetchAllAscending(tx: tx)
        }

        for enqueuedRequestRecord in enqueuedRequestRecords {
            _ = processInboundRequest(
                requestRecordId: enqueuedRequestRecord.id,
                localIdentifiers: registeredState.localIdentifiers,
            )
        }
    }

    /// Enqueues and kicks off an `AttachmentBackfillInboundRequestRecord` for
    /// the given inbound backfill request sync message.
    func enqueueInboundRequest(
        attachmentBackfillRequestProto: SSKProtoSyncMessageAttachmentBackfillRequest,
        registeredState: RegisteredState,
        tx: DBWriteTransaction,
    ) {
        guard BuildFlags.AttachmentBackfill.handleRequests else {
            logger.warn("Dropping backfill request: not yet supported.")
            return
        }

        guard registeredState.isPrimary else {
            logger.warn("Dropping backfill request: not registered primary.")
            return
        }

        guard
            let backfillTarget: AttachmentBackfillTarget = parseBackfillTarget(
                attachmentBackfillRequestProto: attachmentBackfillRequestProto,
                tx: tx,
            )
        else {
            logger.warn("Missing or invalid backfill target!")
            return
        }

        guard
            let backfillTargetMessage: TSMessage = locateBackfillTargetMessage(
                backfillTarget,
                tx: tx,
            )
        else {
            logger.info("Missing message for backfill target.")
            sendTargetNotFoundResponse(
                backfillTarget: backfillTarget,
                localIdentifiers: registeredState.localIdentifiers,
                tx: tx,
            )
            return
        }

        let backfillRecord = AttachmentBackfillInboundRequestRecord.fetchOrInsertRecord(
            interactionId: backfillTargetMessage.sqliteRowId!,
            tx: tx,
        )

        // Touch the target message so we reload it in the ConversationView, to
        // display that it's being backfilled.
        db.touch(interaction: backfillTargetMessage, shouldReindex: false, tx: tx)

        tx.addSyncCompletion { [self] in
            _ = processInboundRequest(
                requestRecordId: backfillRecord.id,
                localIdentifiers: registeredState.localIdentifiers,
            )
        }
    }

    /// Process the given `AttachmentBackfillInboundRequestRecord`, by uploading
    /// its body attachments and enqueuing a response sync message.
    func processInboundRequest(
        requestRecordId: AttachmentBackfillInboundRequestRecord.IDType,
        localIdentifiers: LocalIdentifiers,
    ) -> Task<Void, Error> {
        return taskQueue.enqueue { [self] () async -> Void in
            let requestRecord: AttachmentBackfillInboundRequestRecord?
            let backfillTarget: AttachmentBackfillTarget?
            (
                requestRecord,
                backfillTarget,
            ) = db.read { tx in
                guard
                    let record = failIfThrows(block: {
                        try AttachmentBackfillInboundRequestRecord.fetchOne(
                            tx.database,
                            key: requestRecordId,
                        )
                    }),
                    let message = interactionStore.fetchInteraction(
                        rowId: record.interactionId,
                        tx: tx,
                    ) as? TSMessage,
                    let backfillTarget = assembleBackfillTarget(
                        message: message,
                        localIdentifiers: localIdentifiers,
                        tx: tx,
                    )
                else {
                    return (nil, nil)
                }

                return (record, backfillTarget)
            }

            guard let requestRecord, let backfillTarget else {
                logger.warn("Missing request record or backfill target: no response will be sent.")
                return
            }

            let backfillAttemptResults = await attemptBackfill(
                interactionId: requestRecord.interactionId,
            )

            await db.awaitableWrite { tx in
                self.sendBackfillAttemptResponse(
                    backfillTarget: backfillTarget,
                    backfillAttemptResults: backfillAttemptResults,
                    localIdentifiers: localIdentifiers,
                    tx: tx,
                )

                failIfThrows {
                    try requestRecord.delete(tx.database)
                }

                // Touch the target message so we reload it in the ConversationView,
                // to display that we're done with the backfill.
                if let backfillTargetMessage = locateBackfillTargetMessage(backfillTarget, tx: tx) {
                    db.touch(interaction: backfillTargetMessage, shouldReindex: false, tx: tx)
                }
            }
        }
    }

    private func attemptBackfill(
        interactionId: Int64,
    ) async -> [Result<SSKProtoAttachmentPointer, Error>] {
        let backfillableAttachmentReferences: [AttachmentReference] = db.read { tx in
            let stickerReferences = attachmentStore.fetchReferences(
                owner: .messageSticker(messageRowId: interactionId),
                tx: tx,
            )

            if !stickerReferences.isEmpty {
                return stickerReferences
            }

            return attachmentStore.fetchReferences(
                owner: .messageBodyAttachment(messageRowId: interactionId),
                tx: tx,
            )
        }

        if backfillableAttachmentReferences.isEmpty {
            logger.warn("No attachments for backfill target.")
            return []
        }

        return await withTaskGroup(
            of: (Int, Result<SSKProtoAttachmentPointer, Error>).self,
            returning: [Result<SSKProtoAttachmentPointer, Error>].self,
        ) { taskGroup in
            for (index, attachmentReference) in backfillableAttachmentReferences.enumerated() {
                taskGroup.addTask { [self] in
                    let result = await uploadAttachmentForBackfill(attachmentReference: attachmentReference)
                    return (index, result)
                }
            }

            var indexedResults = [(Int, Result<SSKProtoAttachmentPointer, Error>)]()
            for await indexedResult in taskGroup {
                indexedResults.append(indexedResult)
            }

            return indexedResults
                .sorted(by: { $0.0 < $1.0 })
                .map(\.1)
        }
    }

    private func uploadAttachmentForBackfill(
        attachmentReference: AttachmentReference,
    ) async -> Result<SSKProtoAttachmentPointer, Error> {
        let logger = logger.suffixed(with: "[\(attachmentReference.attachmentRowId)]")

        do {
            try await Retry.performWithBackoff(maxAttempts: 4) { [attachmentUploadManager] in
                // This method will short circuit and return without doing an
                // actual upload if the attachment has recent, reusable transit-
                // tier info.
                try await attachmentUploadManager.uploadTransitTierAttachment(
                    attachmentId: attachmentReference.attachmentRowId,
                    progress: nil,
                )
            }

            guard
                let attachment = db.read(block: { tx in
                    return attachmentStore.fetch(
                        id: attachmentReference.attachmentRowId,
                        tx: tx,
                    )
                }),
                let attachmentProto = ReferencedAttachment(
                    reference: attachmentReference,
                    attachment: attachment,
                ).asProtoForSending()
            else {
                return .failure(OWSAssertionError(
                    "Failed to get proto for sending after successful upload!",
                    logger: logger,
                ))
            }

            return .success(attachmentProto)
        } catch {
            if error.isRetryable {
                logger.warn("Ran out of retries uploading for backfill.")
            } else {
                logger.error("Failed to upload for backfill! \(error)")
            }

            return .failure(error)
        }
    }

    // MARK: - Outbound Responses

    private func sendTargetNotFoundResponse(
        backfillTarget: AttachmentBackfillTarget,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction,
    ) {
        sendBackfillResponse(
            backfillTarget: backfillTarget,
            localIdentifiers: localIdentifiers,
            customizeResponseBlock: { responseBuilder in
                responseBuilder.setError(.messageNotFound)
            },
            tx: tx,
        )
    }

    private func sendBackfillAttemptResponse(
        backfillTarget: AttachmentBackfillTarget,
        backfillAttemptResults: [Result<SSKProtoAttachmentPointer, Error>],
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction,
    ) {
        sendBackfillResponse(
            backfillTarget: backfillTarget,
            localIdentifiers: localIdentifiers,
            customizeResponseBlock: { responseBuilder in
                let attachmentDatas = backfillAttemptResults.map { attemptResult -> SSKProtoSyncMessageAttachmentBackfillResponseAttachmentData in
                    let attachmentDataBuilder = SSKProtoSyncMessageAttachmentBackfillResponseAttachmentData.builder()
                    switch attemptResult {
                    case .success(let attachmentProto):
                        attachmentDataBuilder.setAttachment(attachmentProto)
                    case .failure(let error) where error.isRetryable:
                        attachmentDataBuilder.setStatus(.pending)
                    case .failure:
                        attachmentDataBuilder.setStatus(.terminalError)
                    }
                    return attachmentDataBuilder.buildInfallibly()
                }

                let attachmentDataListBuilder = SSKProtoSyncMessageAttachmentBackfillResponseAttachmentDataList.builder()
                attachmentDataListBuilder.setAttachments(attachmentDatas)
                responseBuilder.setAttachments(attachmentDataListBuilder.buildInfallibly())
            },
            tx: tx,
        )
    }

    private func sendBackfillResponse(
        backfillTarget: AttachmentBackfillTarget,
        localIdentifiers: LocalIdentifiers,
        customizeResponseBlock: (SSKProtoSyncMessageAttachmentBackfillResponseBuilder) -> Void,
        tx: DBWriteTransaction,
    ) {
        guard let localThread = threadStore.getOrCreateLocalThread(tx: tx) else {
            owsFailDebug("Failed to get local thread.", logger: logger)
            return
        }

        let responseProtoBuilder = SSKProtoSyncMessageAttachmentBackfillResponse.builder()
        responseProtoBuilder.setTargetMessage(backfillTarget.addressableMessage.asProto)
        responseProtoBuilder.setTargetConversation(backfillTarget.conversationIdentifier.asProto)
        customizeResponseBlock(responseProtoBuilder)

        do {
            let syncMessage = try AttachmentBackfillResponseSyncMessage(
                responseProto: responseProtoBuilder.buildInfallibly(),
                localThread: localThread,
                tx: tx,
            )

            syncMessageSender.add(
                attachmentBackfillResponseSyncMessage: syncMessage,
                tx: tx,
            )
        } catch {
            owsFailDebug("Failed to build backfill response sync message! \(error)")
            return
        }
    }

    // MARK: - Inbound Responses

    func enqueueInboundResponse(
        attachmentBackfillResponseProto: SSKProtoSyncMessageAttachmentBackfillResponse,
        registeredState: RegisteredState,
        tx: DBWriteTransaction,
    ) {
        // TODO: Enqueue downloads using the attachment pointers in the response.
        logger.warn("AttachmentBackfillResponse not yet supported.")
    }

    // MARK: - Backfill Targets

    private struct AttachmentBackfillTarget {
        let addressableMessage: AddressableMessage
        let conversationIdentifier: ConversationIdentifier
    }

    private func parseBackfillTarget(
        attachmentBackfillRequestProto: SSKProtoSyncMessageAttachmentBackfillRequest,
        tx: DBReadTransaction,
    ) -> AttachmentBackfillTarget? {
        guard
            let addressableMessageProto = attachmentBackfillRequestProto.targetMessage,
            let addressableMessage = AddressableMessage(proto: addressableMessageProto)
        else {
            return nil
        }

        guard
            let conversationIdentifierProto = attachmentBackfillRequestProto.targetConversation,
            let conversationIdentifier = ConversationIdentifier(proto: conversationIdentifierProto)
        else {
            return nil
        }

        return AttachmentBackfillTarget(
            addressableMessage: addressableMessage,
            conversationIdentifier: conversationIdentifier,
        )
    }

    private func locateBackfillTargetMessage(
        _ backfillTarget: AttachmentBackfillTarget,
        tx: DBReadTransaction,
    ) -> TSMessage? {
        let thread: TSThread
        switch backfillTarget.conversationIdentifier {
        case .serviceId(let serviceId):
            guard
                let recipient = recipientDatabaseTable.fetchRecipient(serviceId: serviceId, transaction: tx),
                let contactThread = threadStore.fetchContactThread(recipient: recipient, tx: tx)
            else {
                return nil
            }

            thread = contactThread
        case .e164(let e164):
            guard
                let recipient = recipientDatabaseTable.fetchRecipient(phoneNumber: e164.stringValue, transaction: tx),
                let contactThread = threadStore.fetchContactThread(recipient: recipient, tx: tx)
            else {
                return nil
            }

            thread = contactThread
        case .groupIdentifier(let groupIdentifier):
            guard let groupThread = threadStore.fetchGroupThread(groupId: groupIdentifier, tx: tx) else {
                return nil
            }

            thread = groupThread
        }

        let authorAddress: SignalServiceAddress
        switch backfillTarget.addressableMessage.author {
        case .aci(let aci):
            authorAddress = SignalServiceAddress(aci)
        case .e164(let e164):
            authorAddress = SignalServiceAddress(e164)
        }

        return interactionStore.findMessage(
            withTimestamp: backfillTarget.addressableMessage.sentTimestamp,
            threadId: thread.uniqueId,
            author: authorAddress,
            tx: tx,
        )
    }

    private func assembleBackfillTarget(
        message: TSMessage,
        localIdentifiers: LocalIdentifiers,
        tx: DBReadTransaction,
    ) -> AttachmentBackfillTarget? {
        guard
            let addressableMessage = AddressableMessage(
                message: message,
                localIdentifiers: localIdentifiers,
            )
        else {
            owsFailDebug("Target message missing author info!", logger: logger)
            return nil
        }

        guard let thread = threadStore.fetchThread(uniqueId: message.uniqueThreadId, tx: tx) else {
            owsFailDebug("Missing thread for message!", logger: logger)
            return nil
        }

        let conversationIdentifier: ConversationIdentifier
        if let contactThread = thread as? TSContactThread {
            if let serviceId = ServiceId.parseFrom(serviceIdBinary: nil, serviceIdString: contactThread.contactUUID) {
                conversationIdentifier = .serviceId(serviceId)
            } else if let e164 = E164(contactThread.contactPhoneNumber) {
                conversationIdentifier = .e164(e164)
            } else {
                logger.warn("Contact thread missing identifiers!")
                return nil
            }
        } else if
            let groupThread = thread as? TSGroupThread,
            let groupIdentifier = try? groupThread.groupIdentifier
        {
            conversationIdentifier = .groupIdentifier(groupIdentifier)
        } else {
            owsFailDebug("Target thread is neither contact nor group!", logger: logger)
            return nil
        }

        return AttachmentBackfillTarget(
            addressableMessage: addressableMessage,
            conversationIdentifier: conversationIdentifier,
        )
    }
}

// MARK: - AttachmentBackfillManager.AttachmentBackfillSyncMessageSender

extension MessageSenderJobQueue: AttachmentBackfillManager.AttachmentBackfillSyncMessageSender {
    func add(
        attachmentBackfillRequestSyncMessage: AttachmentBackfillRequestSyncMessage,
        tx: DBWriteTransaction,
    ) {
        add(
            message: .preprepared(transientMessageWithoutAttachments: attachmentBackfillRequestSyncMessage),
            transaction: tx,
        )
    }

    func add(
        attachmentBackfillResponseSyncMessage: AttachmentBackfillResponseSyncMessage,
        tx: DBWriteTransaction,
    ) {
        add(
            message: .preprepared(transientMessageWithoutAttachments: attachmentBackfillResponseSyncMessage),
            transaction: tx,
        )
    }
}
