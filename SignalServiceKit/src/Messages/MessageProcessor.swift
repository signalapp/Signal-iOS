//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient
import SignalCoreKit

public class MessageProcessor: NSObject {
    public static let messageProcessorDidDrainQueue = Notification.Name("messageProcessorDidDrainQueue")

    private var hasPendingEnvelopes: Bool {
        !pendingEnvelopes.isEmpty
    }

    /// When calling `processingCompletePromise` while message processing is suspended,
    /// there is a problem. We may have pending messages waiting to be processed once the suspension
    /// is lifted. But what's more, we may have started processing messages, then suspended, then called
    /// `processingCompletePromise` before that initial processing finished. Suspending does not
    /// interrupt processing if it already started.
    ///
    /// So there are 4 cases to worry about:
    /// 1. Message processing isn't suspended
    /// 2. Suspended with no pending messages
    /// 3. Suspended with pending messages and no active processing underway
    /// 4. Suspended but still processing from before the suspension took effect
    ///
    /// Cases 1 and 2 are easy and behave the same in all cases.
    ///
    /// Case 3 differs in behavior; sometimes we want to wait for suspension to be lifted and
    /// those pending messages to be processed, other times we don't want to wait to unsuspend.
    ///
    /// Case 4 is once again the same in all cases; processing has started and can't be stopped, so
    /// we should always wait until it finishes.
    public enum SuspensionBehavior {
        /// Default value. (Legacy behavior)
        /// If suspended with pending messages and no processing underway, wait for suspension
        /// to be lifted and those messages to be processed.
        case alwaysWait
        /// If suspended with pending messages, only wait if processing has already started. If it
        /// hasn't started, don't wait for it to start, so that the promise can resolve before suspension
        /// is lifted.
        case onlyWaitIfAlreadyInProgress
    }

    /// - parameter suspensionBehavior: What the promise should wait for if message processing
    /// is suspended; see `SuspensionBehavior` documentation for details.
    public func processingCompletePromise(
        suspensionBehavior: SuspensionBehavior = .alwaysWait
    ) -> Promise<Void> {
        guard CurrentAppContext().shouldProcessIncomingMessages else {
            return Promise.value(())
        }

        var shouldWaitForMessageProcessing = self.hasPendingEnvelopes
        var shouldWaitForGV2MessageProcessing = self.databaseStorage.read {
            Self.groupsV2MessageProcessor.hasPendingJobs(transaction: $0)
        }
        // Check if processing is suspended; if so we need to fork behavior.
        if self.messagePipelineSupervisor.isMessageProcessingPermitted.negated {
            switch suspensionBehavior {
            case .alwaysWait:
                break
            case .onlyWaitIfAlreadyInProgress:
                // Check if we are already processing, if so wait for that to finish.
                // If not don't wait even if we have pending messages; those won't process
                // until we unsuspend.
                shouldWaitForMessageProcessing = self.isDrainingPendingEnvelopes.get()
                shouldWaitForGV2MessageProcessing = self.groupsV2MessageProcessor.isActivelyProcessing()
            }
        }

        if shouldWaitForMessageProcessing {
            if DebugFlags.internalLogging {
                Logger.info("hasPendingEnvelopes, queuedContentCount: \(self.queuedContentCount)")
            }

            return NotificationCenter.default.observe(
                once: Self.messageProcessorDidDrainQueue
            ).then { _ in
                // Recur, in case we've enqueued messages handled in another block.
                self.processingCompletePromise(suspensionBehavior: suspensionBehavior)
            }.asVoid()
        } else if shouldWaitForGV2MessageProcessing {
            if DebugFlags.internalLogging {
                let pendingJobCount = databaseStorage.read {
                    Self.groupsV2MessageProcessor.pendingJobCount(transaction: $0)
                }

                Logger.info("groupsV2MessageProcessor.hasPendingJobs, pendingJobCount: \(pendingJobCount)")
            }

            return NotificationCenter.default.observe(
                once: GroupsV2MessageProcessor.didFlushGroupsV2MessageQueue
            ).then { _ in
                // Recur, in case we've enqueued messages handled in another block.
                self.processingCompletePromise(suspensionBehavior: suspensionBehavior)
            }.asVoid()
        } else {
            return Promise.value(())
        }
    }

    /// Suspends message processing, but before doing so processes any messages
    /// received so far.
    /// This suppression will persist until the suspension is explicitly lifted.
    /// For this reason calling this method is highly dangerous, please use with care.
    public func waitForProcessingCompleteAndThenSuspend(
        for suspension: MessagePipelineSupervisor.Suspension
    ) -> Guarantee<Void> {
        // We need to:
        // 1. wait to process
        // 2. suspend
        // 3. wait to process again
        // This is because steps 1 and 2 are not transactional, and in between a message
        // may get queued up for processing. After 2, nothing new can come in, so we only
        // need to wait the once.
        // In most cases nothing sneaks in between 1 and 2, so 3 resolves instantly.
        return processingCompletePromise(suspensionBehavior: .onlyWaitIfAlreadyInProgress).then(on: DispatchQueue.main) {
            self.messagePipelineSupervisor.suspendMessageProcessingWithoutHandle(for: suspension)
            return self.processingCompletePromise(suspensionBehavior: .onlyWaitIfAlreadyInProgress)
        }.recover(on: SyncScheduler()) { _ in return () }
    }

    public func fetchingAndProcessingCompletePromise(
        suspensionBehavior: SuspensionBehavior = .alwaysWait
    ) -> Promise<Void> {
        return firstly { () -> Promise<Void> in
            if DebugFlags.internalLogging { Logger.info("[Scroll Perf Debug] fetchingCompletePromise") }
            return Self.messageFetcherJob.fetchingCompletePromise()
        }.then { () -> Promise<Void> in
            if DebugFlags.internalLogging { Logger.info("[Scroll Perf Debug] processingCompletePromise") }
            return self.processingCompletePromise(suspensionBehavior: suspensionBehavior)
        }
    }

    public override init() {
        super.init()

        SwiftSingletons.register(self)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(registrationStateDidChange),
            name: .registrationStateDidChange,
            object: nil
        )

        AppReadiness.runNowOrWhenAppDidBecomeReadySync {
            Self.messagePipelineSupervisor.register(pipelineStage: self)

            SDSDatabaseStorage.shared.read { transaction in
                // We may have legacy process jobs queued. We want to schedule them for
                // processing immediately when we launch, so that we can drain the old queue.
                let legacyProcessingJobRecords = LegacyMessageJobFinder().allJobs(transaction: transaction)
                for jobRecord in legacyProcessingJobRecords {
                    let completion: (Error?) -> Void = { _ in
                        SDSDatabaseStorage.shared.write { jobRecord.anyRemove(transaction: $0) }
                    }
                    do {
                        let envelope = try SSKProtoEnvelope(serializedData: jobRecord.envelopeData)
                        self.processReceivedEnvelope(
                            ReceivedEnvelope(
                                envelope: envelope,
                                encryptionStatus: .decrypted(plaintextData: jobRecord.plaintextData, wasReceivedByUD: jobRecord.wasReceivedByUD),
                                serverDeliveryTimestamp: jobRecord.serverDeliveryTimestamp,
                                completion: completion
                            ),
                            envelopeSource: .unknown
                        )
                    } catch {
                        completion(error)
                    }
                }

                // We may have legacy decrypt jobs queued. We want to schedule them for
                // processing immediately when we launch, so that we can drain the old queue.
                let legacyDecryptJobRecords: [LegacyMessageDecryptJobRecord]
                do {
                    legacyDecryptJobRecords = try JobRecordFinderImpl<LegacyMessageDecryptJobRecord>().allRecords(
                        label: LegacyMessageDecryptJobRecord.defaultLabel,
                        status: .ready,
                        transaction: transaction.asV2Read
                    )
                } catch {
                    legacyDecryptJobRecords = []
                    Logger.error("Couldn't fetch legacy job records: \(error)")
                }
                for jobRecord in legacyDecryptJobRecords {
                    let completion: (Error?) -> Void = { _ in
                        SDSDatabaseStorage.shared.write { jobRecord.anyRemove(transaction: $0) }
                    }
                    do {
                        guard let envelopeData = jobRecord.envelopeData else {
                            throw OWSAssertionError("Skipping job with no envelope data")
                        }
                        self.processReceivedEnvelopeData(
                            envelopeData,
                            serverDeliveryTimestamp: jobRecord.serverDeliveryTimestamp,
                            envelopeSource: .unknown,
                            completion: completion
                        )
                    } catch {
                        completion(error)
                    }
                }
            }
        }
    }

    public func processReceivedEnvelopeData(
        _ envelopeData: Data,
        serverDeliveryTimestamp: UInt64,
        envelopeSource: EnvelopeSource,
        completion: @escaping (Error?) -> Void
    ) {
        guard !envelopeData.isEmpty else {
            completion(OWSAssertionError("Empty envelope, envelopeSource: \(envelopeSource)."))
            return
        }

        // Drop any too-large messages on the floor. Well behaving clients should never send them.
        guard envelopeData.count <= Self.maxEnvelopeByteCount else {
            completion(OWSAssertionError("Oversize envelope, envelopeSource: \(envelopeSource)."))
            return
        }

        // Take note of any messages larger than we expect, but still process them.
        // This likely indicates a misbehaving sending client.
        if envelopeData.count > Self.largeEnvelopeWarningByteCount {
            Logger.verbose("encryptedEnvelopeData: \(envelopeData.count) > : \(Self.largeEnvelopeWarningByteCount)")
            owsFailDebug("Unexpectedly large envelope, envelopeSource: \(envelopeSource).")
        }

        let protoEnvelope: SSKProtoEnvelope
        do {
            protoEnvelope = try SSKProtoEnvelope(serializedData: envelopeData)
        } catch {
            owsFailDebug("Failed to parse encrypted envelope \(error), envelopeSource: \(envelopeSource)")
            completion(error)
            return
        }

        processReceivedEnvelope(
            ReceivedEnvelope(
                envelope: protoEnvelope,
                encryptionStatus: .encrypted,
                serverDeliveryTimestamp: serverDeliveryTimestamp,
                completion: completion
            ),
            envelopeSource: envelopeSource
        )
    }

    public func processReceivedEnvelope(
        _ envelopeProto: SSKProtoEnvelope,
        serverDeliveryTimestamp: UInt64,
        envelopeSource: EnvelopeSource,
        completion: @escaping (Error?) -> Void
    ) {
        processReceivedEnvelope(
            ReceivedEnvelope(
                envelope: envelopeProto,
                encryptionStatus: .encrypted,
                serverDeliveryTimestamp: serverDeliveryTimestamp,
                completion: completion
            ),
            envelopeSource: envelopeSource
        )
    }

    private func processReceivedEnvelope(_ receivedEnvelope: ReceivedEnvelope, envelopeSource: EnvelopeSource) {
        let result = pendingEnvelopes.enqueue(receivedEnvelope)
        switch result {
        case .duplicate:
            let envelope = receivedEnvelope.envelope
            Logger.warn("Duplicate envelope \(envelope.timestamp). Server timestamp: \(envelope.serverTimestamp), serverGuid: \(envelope.serverGuid ?? "nil"), EnvelopeSource: \(envelopeSource).")
            receivedEnvelope.completion(MessageProcessingError.duplicatePendingEnvelope)
        case .enqueued:
            drainPendingEnvelopes()
        }
    }

    public var queuedContentCount: Int {
        pendingEnvelopes.count
    }

    private static let maxEnvelopeByteCount = 250 * 1024
    public static let largeEnvelopeWarningByteCount = 25 * 1024
    private let serialQueue = DispatchQueue(
        label: "org.signal.message-processor",
        autoreleaseFrequency: .workItem
    )

    private var pendingEnvelopes = PendingEnvelopes()

    private let isDrainingPendingEnvelopes = AtomicBool(false, lock: .init())

    private func drainPendingEnvelopes() {
        guard CurrentAppContext().shouldProcessIncomingMessages else { return }
        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else { return }

        guard Self.messagePipelineSupervisor.isMessageProcessingPermitted else { return }

        serialQueue.async {
            self.isDrainingPendingEnvelopes.set(true)
            while autoreleasepool(invoking: { self.drainNextBatch() }) {}
            self.isDrainingPendingEnvelopes.set(false)
            if self.pendingEnvelopes.isEmpty {
                NotificationCenter.default.postNotificationNameAsync(Self.messageProcessorDidDrainQueue, object: nil)
            }
        }
    }

    /// Returns whether or not to continue draining the queue.
    private func drainNextBatch() -> Bool {
        assertOnQueue(serialQueue)

        guard messagePipelineSupervisor.isMessageProcessingPermitted else {
            return false
        }

        // We want a value that is just high enough to yield perf benefits.
        let kIncomingMessageBatchSize = 16
        // If the app is in the background, use batch size of 1.
        // This reduces the risk of us never being able to drain any
        // messages from the queue. We should fine tune this number
        // to yield the best perf we can get.
        let batchSize = CurrentAppContext().isInBackground() ? 1 : kIncomingMessageBatchSize
        let batch = pendingEnvelopes.nextBatch(batchSize: batchSize)
        let batchEnvelopes = batch.batchEnvelopes
        let pendingEnvelopesCount = batch.pendingEnvelopesCount

        guard !batchEnvelopes.isEmpty else {
            return false
        }

        let startTime = CACurrentMediaTime()
        Logger.info("Processing batch of \(batchEnvelopes.count)/\(pendingEnvelopesCount) received envelope(s). (memoryUsage: \(LocalDevice.memoryUsageString)")

        var processedEnvelopesCount = 0
        databaseStorage.write { tx in
            // This is only called via `drainPendingEnvelopes`, and that confirms that
            // we're registered. If we're registered, we must have `LocalIdentifiers`,
            // so this (generally) shouldn't fail.
            guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read) else {
                return
            }
            let localDeviceId = DependenciesBridge.shared.tsAccountManager.storedDeviceId(tx: tx.asV2Read)

            var remainingEnvelopes = batchEnvelopes
            while !remainingEnvelopes.isEmpty {
                guard messagePipelineSupervisor.isMessageProcessingPermitted else {
                    break
                }
                autoreleasepool {
                    // If we build a request, we must handle it to ensure it's not lost if we
                    // stop processing envelopes.
                    let combinedRequest = buildNextCombinedRequest(
                        envelopes: &remainingEnvelopes,
                        localIdentifiers: localIdentifiers,
                        localDeviceId: localDeviceId,
                        tx: tx
                    )
                    handle(combinedRequest: combinedRequest, transaction: tx)
                }
            }
            processedEnvelopesCount += batchEnvelopes.count - remainingEnvelopes.count
        }
        pendingEnvelopes.removeProcessedEnvelopes(processedEnvelopesCount)
        let duration = CACurrentMediaTime() - startTime
        Logger.info(String(format: "Processed %.0d envelopes in %0.2fms -> %.2f envelopes per second", batchEnvelopes.count, duration * 1000, duration > 0 ? Double(batchEnvelopes.count) / duration : 0))
        return true
    }

    // If envelopes is not empty, this will emit a single request for a non-delivery receipt or one or more requests
    // all for delivery receipts.
    private func buildNextCombinedRequest(
        envelopes: inout [ReceivedEnvelope],
        localIdentifiers: LocalIdentifiers,
        localDeviceId: UInt32,
        tx: SDSAnyWriteTransaction
    ) -> RelatedProcessingRequests {
        let result = RelatedProcessingRequests()
        while let envelope = envelopes.first {
            envelopes.removeFirst()
            let request = processingRequest(
                for: envelope,
                localIdentifiers: localIdentifiers,
                localDeviceId: localDeviceId,
                tx: tx
            )
            result.add(request)
            if request.deliveryReceiptMessageTimestamps == nil {
                // If we hit a non-delivery receipt envelope, handle it immediately to avoid
                // keeping potentially large decrypted envelopes in memory.
                break
            }
        }
        return result
    }

    private func handle(combinedRequest: RelatedProcessingRequests, transaction: SDSAnyWriteTransaction) {
        // Efficiently handle delivery receipts for the same message by fetching the sent message only
        // once and only using one updateWith... to update the message with new recipient state.
        BatchingDeliveryReceiptContext.withDeferredUpdates(transaction: transaction) { context in
            for request in combinedRequest.processingRequests {
                handleProcessingRequest(request, context: context, tx: transaction)
            }
        }
    }

    private func reallyHandleProcessingRequest(
        _ request: ProcessingRequest,
        context: DeliveryReceiptContext,
        transaction: SDSAnyWriteTransaction
    ) -> Error? {
        switch request.state {
        case .completed(error: let error):
            Logger.info("Envelope completed early with error \(String(describing: error))")
            return error
        case .enqueueForGroup(let decryptedEnvelope, let envelopeData):
            Self.groupsV2MessageProcessor.enqueue(
                envelopeData: envelopeData,
                plaintextData: decryptedEnvelope.plaintextData,
                wasReceivedByUD: decryptedEnvelope.wasReceivedByUD,
                serverDeliveryTimestamp: request.receivedEnvelope.serverDeliveryTimestamp,
                transaction: transaction
            )
            return nil
        case .messageReceiverRequest(let messageReceiverRequest):
            messageReceiver.handleRequest(messageReceiverRequest, context: context, tx: transaction)
            messageReceiver.finishProcessingEnvelope(messageReceiverRequest.decryptedEnvelope, tx: transaction)
            return nil
        case .clearPlaceholdersOnly(let decryptedEnvelope):
            messageReceiver.finishProcessingEnvelope(decryptedEnvelope, tx: transaction)
            return nil
        case .serverReceipt(let serverReceiptEnvelope):
            messageReceiver.handleDeliveryReceipt(envelope: serverReceiptEnvelope, context: context, tx: transaction)
            return nil
        }
    }

    private func handleProcessingRequest(
        _ request: ProcessingRequest,
        context: DeliveryReceiptContext,
        tx: SDSAnyWriteTransaction
    ) {
        let error = reallyHandleProcessingRequest(request, context: context, transaction: tx)
        tx.addAsyncCompletionOffMain { request.receivedEnvelope.completion(error) }
    }

    @objc
    private func registrationStateDidChange() {
        AppReadiness.runNowOrWhenAppDidBecomeReadySync {
            self.drainPendingEnvelopes()
        }
    }

    public enum MessageAckBehavior {
        case shouldAck
        case shouldNotAck(error: Error)
    }

    public static func handleMessageProcessingOutcome(error: Error?) -> MessageAckBehavior {
        guard let error = error else {
            // Success.
            return .shouldAck
        }
        if case MessageProcessingError.duplicatePendingEnvelope = error {
            // _DO NOT_ ACK if de-duplicated before decryption.
            return .shouldNotAck(error: error)
        } else if case MessageProcessingError.blockedSender = error {
            return .shouldAck
        } else if let owsError = error as? OWSError,
                  owsError.errorCode == OWSErrorCode.failedToDecryptDuplicateMessage.rawValue {
            // _DO_ ACK if de-duplicated during decryption.
            return .shouldAck
        } else {
            Logger.warn("Failed to process message: \(error)")
            // This should only happen for malformed envelopes. We may eventually
            // want to show an error in this case.
            return .shouldAck
        }
    }
}

private struct ProcessingRequest {
    enum State {
        case completed(error: Error?)
        case enqueueForGroup(decryptedEnvelope: DecryptedIncomingEnvelope, envelopeData: Data)
        case messageReceiverRequest(MessageReceiverRequest)
        case serverReceipt(ServerReceiptEnvelope)
        // Message decrypted but had an invalid protobuf.
        case clearPlaceholdersOnly(DecryptedIncomingEnvelope)
    }

    let receivedEnvelope: ReceivedEnvelope
    let state: State

    // If this request is for a delivery receipt, return the timestamps for the sent-messages it
    // corresponds to.
    var deliveryReceiptMessageTimestamps: [UInt64]? {
        switch state {
        case .completed, .enqueueForGroup, .clearPlaceholdersOnly:
            return nil
        case .serverReceipt(let envelope):
            return [envelope.validatedEnvelope.timestamp]
        case .messageReceiverRequest(let request):
            guard
                case .receiptMessage = request.messageType,
                let receiptMessage = request.protoContent.receiptMessage,
                receiptMessage.type == .delivery
            else {
                return nil
            }
            return receiptMessage.timestamp
        }
    }

    init(_ receivedEnvelope: ReceivedEnvelope, state: State) {
        self.receivedEnvelope = receivedEnvelope
        self.state = state
    }
}

private class RelatedProcessingRequests {
    private(set) var processingRequests = [ProcessingRequest]()

    func add(_ processingRequest: ProcessingRequest) {
        processingRequests.append(processingRequest)
    }
}

private struct ProcessingRequestBuilder {
    let receivedEnvelope: ReceivedEnvelope
    let blockingManager: BlockingManager
    let localDeviceId: UInt32
    let localIdentifiers: LocalIdentifiers
    let messageDecrypter: OWSMessageDecrypter
    let messageReceiver: MessageReceiver

    init(
        _ receivedEnvelope: ReceivedEnvelope,
        blockingManager: BlockingManager,
        localDeviceId: UInt32,
        localIdentifiers: LocalIdentifiers,
        messageDecrypter: OWSMessageDecrypter,
        messageReceiver: MessageReceiver
    ) {
        self.receivedEnvelope = receivedEnvelope
        self.blockingManager = blockingManager
        self.localDeviceId = localDeviceId
        self.localIdentifiers = localIdentifiers
        self.messageDecrypter = messageDecrypter
        self.messageReceiver = messageReceiver
    }

    func build(tx: SDSAnyWriteTransaction) -> ProcessingRequest.State {
        do {
            let decryptionResult = try receivedEnvelope.decryptIfNeeded(
                messageDecrypter: messageDecrypter,
                localIdentifiers: localIdentifiers,
                localDeviceId: localDeviceId,
                tx: tx
            )
            switch decryptionResult {
            case .serverReceipt(let receiptEnvelope):
                return .serverReceipt(receiptEnvelope)
            case .decryptedMessage(let decryptedEnvelope):
                return processingRequest(for: decryptedEnvelope, tx: tx)
            }
        } catch {
            return .completed(error: error)
        }
    }

    private enum ProcessingStep {
        case discard
        case enqueueForGroupProcessing
        case processNow(shouldDiscardVisibleMessages: Bool)
    }

    private func processingStep(
        for decryptedEnvelope: DecryptedIncomingEnvelope,
        tx: SDSAnyWriteTransaction
    ) -> ProcessingStep {
        guard
            let contentProto = decryptedEnvelope.content,
            let groupContextV2 = GroupsV2MessageProcessor.groupContextV2(from: contentProto)
        else {
            // Non-v2-group messages can be processed immediately.
            return .processNow(shouldDiscardVisibleMessages: false)
        }

        guard GroupsV2MessageProcessor.canContextBeProcessedImmediately(
            groupContext: groupContextV2,
            transaction: tx
        ) else {
            // Some v2 group messages required group state to be
            // updated before they can be processed.
            return .enqueueForGroupProcessing
        }
        let discardMode = GroupsMessageProcessor.discardMode(
            forMessageFrom: SignalServiceAddress(decryptedEnvelope.sourceAci),
            groupContext: groupContextV2,
            transaction: tx
        )
        switch discardMode {
        case .discard:
            // Some v2 group messages should be discarded and not processed.
            return .discard
        case .doNotDiscard:
            return .processNow(shouldDiscardVisibleMessages: false)
        case .discardVisibleMessages:
            // Some v2 group messages should be processed, but discarding any "visible"
            // messages, e.g. text messages or calls.
            return .processNow(shouldDiscardVisibleMessages: true)
        }
    }

    private func processingRequest(
        for decryptedEnvelope: DecryptedIncomingEnvelope,
        tx: SDSAnyWriteTransaction
    ) -> ProcessingRequest.State {
        owsAssert(CurrentAppContext().shouldProcessIncomingMessages)

        // NOTE: We use the envelope from the decrypt result, not the pending envelope,
        // since the envelope may be altered by the decryption process in the UD case.
        Logger.info("Decrypted envelope \(OWSMessageHandler.description(for: decryptedEnvelope.envelope))")

        // Pre-processing has to happen during the same transaction that performed
        // decryption.
        messageReceiver.preprocessEnvelope(decryptedEnvelope, tx: tx)

        // If the sender is in the block list, we can skip scheduling any additional processing.
        let sourceAddress = SignalServiceAddress(decryptedEnvelope.sourceAci)
        if blockingManager.isAddressBlocked(sourceAddress, transaction: tx) {
            Logger.info("Skipping processing for blocked envelope from \(decryptedEnvelope.sourceAci)")
            return .completed(error: MessageProcessingError.blockedSender)
        }

        if decryptedEnvelope.localIdentity == .pni {
            let identityManager = DependenciesBridge.shared.identityManager
            identityManager.setShouldSharePhoneNumber(with: decryptedEnvelope.sourceAci, tx: tx.asV2Write)
        }

        switch processingStep(for: decryptedEnvelope, tx: tx) {
        case .discard:
            // Do nothing.
            return .completed(error: nil)

        case .enqueueForGroupProcessing:
            // If we can't process the message immediately, we enqueue it for
            // for processing in the same transaction within which it was decrypted
            // to prevent data loss.
            let envelopeData: Data
            do {
                envelopeData = try decryptedEnvelope.envelope.serializedData()
            } catch {
                owsFailDebug("failed to reserialize envelope: \(error)")
                return .completed(error: error)
            }
            return .enqueueForGroup(decryptedEnvelope: decryptedEnvelope, envelopeData: envelopeData)

        case .processNow(let shouldDiscardVisibleMessages):
            // Envelopes can be processed immediately if they're:
            // 1. Not a GV2 message.
            // 2. A GV2 message that doesn't require updating the group.
            //
            // The advantage to processing the message immediately is that we can full
            // process the message in the same transaction that we used to decrypt it.
            // This results in a significant perf benefit verse queueing the message
            // and waiting for that queue to open new transactions and process
            // messages. The downside is that if we *fail* to process this message
            // (e.g. the app crashed or was killed), we'll have to re-decrypt again
            // before we process. This is safe since the decrypt operation would also
            // be rolled back (since the transaction didn't commit) and should be rare.
            messageReceiver.checkForUnknownLinkedDevice(in: decryptedEnvelope, tx: tx)

            let buildResult = MessageReceiverRequest.buildRequest(
                for: decryptedEnvelope,
                serverDeliveryTimestamp: receivedEnvelope.serverDeliveryTimestamp,
                shouldDiscardVisibleMessages: shouldDiscardVisibleMessages,
                tx: tx
            )

            switch buildResult {
            case .discard:
                return .completed(error: nil)
            case .noContent:
                return .clearPlaceholdersOnly(decryptedEnvelope)
            case .request(let messageReceiverRequest):
                return .messageReceiverRequest(messageReceiverRequest)
            }
        }
    }
}

private extension MessageProcessor {
    func processingRequest(
        for envelope: ReceivedEnvelope,
        localIdentifiers: LocalIdentifiers,
        localDeviceId: UInt32,
        tx: SDSAnyWriteTransaction
    ) -> ProcessingRequest {
        assertOnQueue(serialQueue)
        let builder = ProcessingRequestBuilder(
            envelope,
            blockingManager: Self.blockingManager,
            localDeviceId: localDeviceId,
            localIdentifiers: localIdentifiers,
            messageDecrypter: Self.messageDecrypter,
            messageReceiver: Self.messageReceiver
        )
        return ProcessingRequest(envelope, state: builder.build(tx: tx))
    }
}

// MARK: -

extension MessageProcessor: MessageProcessingPipelineStage {
    public func supervisorDidResumeMessageProcessing(_ supervisor: MessagePipelineSupervisor) {
        drainPendingEnvelopes()
    }
}

// MARK: -

private struct ReceivedEnvelope {
    enum EncryptionStatus {
        case encrypted
        /// Kept for historical purposes -- unused by new clients.
        case decrypted(plaintextData: Data?, wasReceivedByUD: Bool)
    }

    let envelope: SSKProtoEnvelope
    let encryptionStatus: EncryptionStatus
    let serverDeliveryTimestamp: UInt64
    let completion: (Error?) -> Void

    enum DecryptionResult {
        case serverReceipt(ServerReceiptEnvelope)
        case decryptedMessage(DecryptedIncomingEnvelope)
    }

    func decryptIfNeeded(
        messageDecrypter: OWSMessageDecrypter,
        localIdentifiers: LocalIdentifiers,
        localDeviceId: UInt32,
        tx: SDSAnyWriteTransaction
    ) throws -> DecryptionResult {
        Logger.info("Processing envelope: \(OWSMessageDecrypter.description(for: envelope))")

        // Figure out what type of envelope we're dealing with.
        let validatedEnvelope = try ValidatedIncomingEnvelope(envelope, localIdentifiers: localIdentifiers)

        switch encryptionStatus {
        case .encrypted:
            switch validatedEnvelope.kind {
            case .serverReceipt:
                return .serverReceipt(try ServerReceiptEnvelope(validatedEnvelope))
            case .identifiedSender(let cipherType):
                return .decryptedMessage(
                    try messageDecrypter.decryptIdentifiedEnvelope(
                        validatedEnvelope, cipherType: cipherType, localIdentifiers: localIdentifiers, tx: tx
                    )
                )
            case .unidentifiedSender:
                return .decryptedMessage(
                    try messageDecrypter.decryptUnidentifiedSenderEnvelope(
                        validatedEnvelope, localIdentifiers: localIdentifiers, localDeviceId: localDeviceId, tx: tx
                    )
                )
            }

        case .decrypted(let plaintextData, let wasReceivedByUD):
            switch validatedEnvelope.kind {
            case .serverReceipt:
                return .serverReceipt(try ServerReceiptEnvelope(validatedEnvelope))
            case .identifiedSender, .unidentifiedSender:
                // In this flow, we've already decrypted the sender and added them to our
                // local copy of the envelope. So we can grab the source from the envelope
                // in both cases.
                let (sourceAci, sourceDeviceId) = try validatedEnvelope.validateSource(Aci.self)
                guard let plaintextData else {
                    throw OWSAssertionError("Missing plaintextData for previously-encrypted message.")
                }
                return .decryptedMessage(DecryptedIncomingEnvelope(
                    validatedEnvelope: validatedEnvelope,
                    updatedEnvelope: envelope,
                    sourceAci: sourceAci,
                    sourceDeviceId: sourceDeviceId,
                    wasReceivedByUD: wasReceivedByUD,
                    plaintextData: plaintextData
                ))
            }
        }
    }

    func isDuplicateOf(_ other: ReceivedEnvelope) -> Bool {
        guard let serverGuid = self.envelope.serverGuid else {
            owsFailDebug("Missing serverGuid.")
            return false
        }
        guard let otherServerGuid = other.envelope.serverGuid else {
            owsFailDebug("Missing other.serverGuid.")
            return false
        }
        return serverGuid == otherServerGuid
    }
}

// MARK: -

public enum EnvelopeSource {
    case unknown
    case websocketIdentified
    case websocketUnidentified
    case rest
    // We re-decrypt incoming messages after accepting a safety number change.
    case identityChangeError
    case debugUI
    case tests
}

// MARK: -

private class PendingEnvelopes {
    private let unfairLock = UnfairLock()
    private var pendingEnvelopes = [ReceivedEnvelope]()

    var isEmpty: Bool {
        unfairLock.withLock { pendingEnvelopes.isEmpty }
    }

    var count: Int {
        unfairLock.withLock { pendingEnvelopes.count }
    }

    struct Batch {
        let batchEnvelopes: [ReceivedEnvelope]
        let pendingEnvelopesCount: Int
    }

    func nextBatch(batchSize: Int) -> Batch {
        unfairLock.withLock {
            Batch(
                batchEnvelopes: Array(pendingEnvelopes.prefix(batchSize)),
                pendingEnvelopesCount: pendingEnvelopes.count
            )
        }
    }

    func removeProcessedEnvelopes(_ processedEnvelopesCount: Int) {
        unfairLock.withLock {
            let oldCount = pendingEnvelopes.count
            pendingEnvelopes.removeFirst(processedEnvelopesCount)
            let newCount = pendingEnvelopes.count
            if DebugFlags.internalLogging {
                Logger.info("\(oldCount) -> \(newCount)")
            }
        }
    }

    enum EnqueueResult {
        case duplicate
        case enqueued
    }

    func enqueue(_ receivedEnvelope: ReceivedEnvelope) -> EnqueueResult {
        unfairLock.withLock {
            let oldCount = pendingEnvelopes.count

            for pendingEnvelope in pendingEnvelopes {
                if pendingEnvelope.isDuplicateOf(receivedEnvelope) {
                    return .duplicate
                }
            }
            pendingEnvelopes.append(receivedEnvelope)

            let newCount = pendingEnvelopes.count
            if DebugFlags.internalLogging {
                Logger.info("\(oldCount) -> \(newCount)")
            }
            return .enqueued
        }
    }
}

// MARK: -

public enum MessageProcessingError: Error {
    case wrongDestinationUuid
    case invalidMessageTypeForDestinationUuid
    case duplicatePendingEnvelope
    case blockedSender
}
