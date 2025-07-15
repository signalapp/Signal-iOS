//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient

public class MessageProcessor {
    public static let messageProcessorDidDrainQueue = Notification.Name("messageProcessorDidDrainQueue")

    private var hasPendingEnvelopes: Bool {
        !pendingEnvelopes.isEmpty
    }

    public struct Stages: OptionSet {
        public var rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public static let messageFetcher = Stages(rawValue: 1 << 0)
        public static let messageProcessor = Stages(rawValue: 1 << 1)
        public static let groupMessageProcessor = Stages(rawValue: 1 << 2)
    }

    public func waitForFetchingAndProcessing(stages: Stages = [.messageFetcher, .messageProcessor, .groupMessageProcessor]) async throws(CancellationError) {
        guard CurrentAppContext().shouldProcessIncomingMessages else {
            return
        }

        var preconditions = [any Precondition]()
        if stages.contains(.messageFetcher) {
            preconditions.append(SSKEnvironment.shared.messageFetcherJobRef.preconditionForFetchingComplete())
        }
        if stages.contains(.messageProcessor) {
            preconditions.append(NotificationPrecondition(
                notificationName: Self.messageProcessorDidDrainQueue,
                isSatisfied: { !self.hasPendingEnvelopes }
            ))
        }
        if stages.contains(.groupMessageProcessor) {
            preconditions.append(NotificationPrecondition(
                notificationName: GroupMessageProcessorManager.didFlushGroupsV2MessageQueue,
                isSatisfied: { !SSKEnvironment.shared.groupMessageProcessorManagerRef.isProcessing() }
            ))
        }
        try await Preconditions(preconditions).waitUntilSatisfied()
    }

    private let appReadiness: AppReadiness

    public init(appReadiness: AppReadiness) {
        self.appReadiness = appReadiness

        SwiftSingletons.register(self)

        appReadiness.runNowOrWhenAppDidBecomeReadySync {
            SSKEnvironment.shared.messagePipelineSupervisorRef.register(pipelineStage: self)

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.registrationStateDidChange),
                name: .registrationStateDidChange,
                object: nil
            )
        }
    }

    public func processReceivedEnvelopeData(
        _ envelopeData: Data,
        serverDeliveryTimestamp: UInt64,
        envelopeSource: EnvelopeSource,
        completion: @escaping () -> Void
    ) {
        guard !envelopeData.isEmpty else {
            owsFailDebug("Empty envelope, envelopeSource: \(envelopeSource).")
            completion()
            return
        }

        let protoEnvelope: SSKProtoEnvelope
        do {
            protoEnvelope = try SSKProtoEnvelope(serializedData: envelopeData)
        } catch {
            owsFailDebug("Failed to parse encrypted envelope \(error), envelopeSource: \(envelopeSource)")
            completion()
            return
        }

        // Drop any too-large messages on the floor. Well behaving clients should never send them.
        guard (protoEnvelope.content ?? Data()).count <= Self.maxEnvelopeByteCount else {
            owsFailDebug("Oversize envelope, envelopeSource: \(envelopeSource).")
            completion()
            return
        }

        processReceivedEnvelope(
            ReceivedEnvelope(
                envelope: protoEnvelope,
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
        completion: @escaping () -> Void
    ) {
        processReceivedEnvelope(
            ReceivedEnvelope(
                envelope: envelopeProto,
                serverDeliveryTimestamp: serverDeliveryTimestamp,
                completion: completion
            ),
            envelopeSource: envelopeSource
        )
    }

    private func processReceivedEnvelope(_ receivedEnvelope: ReceivedEnvelope, envelopeSource: EnvelopeSource) {
        pendingEnvelopes.enqueue(receivedEnvelope)
        drainPendingEnvelopes()
    }

    private static let maxEnvelopeByteCount = 256 * 1024
    private let serialQueue = DispatchQueue(
        label: "org.signal.message-processor",
        autoreleaseFrequency: .workItem
    )

    #if TESTABLE_BUILD
    var serialQueueForTests: DispatchQueue { serialQueue }
    #endif

    private var pendingEnvelopes = PendingEnvelopes()

    private let isDrainingPendingEnvelopes = AtomicBool(false, lock: .init())

    private func drainPendingEnvelopes() {
        guard CurrentAppContext().shouldProcessIncomingMessages else { return }
        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else { return }

        guard SSKEnvironment.shared.messagePipelineSupervisorRef.isMessageProcessingPermitted else { return }

        serialQueue.async {
            self.isDrainingPendingEnvelopes.set(true)
            while autoreleasepool(invoking: { self.drainNextBatch() }) {}
            self.isDrainingPendingEnvelopes.set(false)
            if self.pendingEnvelopes.isEmpty {
                NotificationCenter.default.postOnMainThread(name: Self.messageProcessorDidDrainQueue, object: nil)
            }
        }
    }

    private var recentlyProcessedGuids = SetDeque<String>()
    /// Should ideally match `MESSAGE_SENDER_MAX_CONCURRENCY`.
    private var recentlyProcessedGuidLimit = 256

    /// Returns whether or not to continue draining the queue.
    private func drainNextBatch() -> Bool {
        assertOnQueue(serialQueue)

        guard SSKEnvironment.shared.messagePipelineSupervisorRef.isMessageProcessingPermitted else {
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

        if pendingEnvelopesCount > self.recentlyProcessedGuidLimit {
            self.recentlyProcessedGuidLimit = pendingEnvelopesCount
        }

        guard !batchEnvelopes.isEmpty else {
            return false
        }

        var startTime: CFTimeInterval = 0

        var processedEnvelopesCount = 0
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            // Start the timer once we acquire a write transaction.
            startTime = CACurrentMediaTime()

            // This is only called via `drainPendingEnvelopes`, and that confirms that
            // we're registered. If we're registered, we must have `LocalIdentifiers`,
            // so this (generally) shouldn't fail.
            guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx) else {
                return
            }
            let localDeviceId = DependenciesBridge.shared.tsAccountManager.storedDeviceId(tx: tx)

            var remainingEnvelopes = batchEnvelopes[...]
            while !remainingEnvelopes.isEmpty {
                guard SSKEnvironment.shared.messagePipelineSupervisorRef.isMessageProcessingPermitted else {
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
                    handle(
                        combinedRequest: combinedRequest,
                        localIdentifiers: localIdentifiers,
                        transaction: tx
                    )
                }
            }
            processedEnvelopesCount += batchEnvelopes.count - remainingEnvelopes.count
        }
        for processedEnvelope in batchEnvelopes.prefix(processedEnvelopesCount) {
            guard let serverGuid = processedEnvelope.envelope.serverGuid else {
                continue
            }
            recentlyProcessedGuids.pushBack(serverGuid)
        }
        while recentlyProcessedGuids.count > recentlyProcessedGuidLimit {
            _ = recentlyProcessedGuids.popFront()
        }
        // The groups processing logic relies on `removeProcessedEnvelopes` being
        // called after the `write`'s `addSyncCompletion` blocks.
        pendingEnvelopes.removeProcessedEnvelopes(processedEnvelopesCount)
        let endTime = CACurrentMediaTime()
        let formattedDuration = String(format: "%.1f", (endTime - startTime) * 1000)
        Logger.info("Processed \(processedEnvelopesCount) envelopes (of \(pendingEnvelopesCount) total) in \(formattedDuration)ms")
        return true
    }

    // If envelopes is not empty, this will emit a single request for a non-delivery receipt or one or more requests
    // all for delivery receipts.
    private func buildNextCombinedRequest(
        envelopes: inout ArraySlice<ReceivedEnvelope>,
        localIdentifiers: LocalIdentifiers,
        localDeviceId: LocalDeviceId,
        tx: DBWriteTransaction
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

    private func handle(combinedRequest: RelatedProcessingRequests, localIdentifiers: LocalIdentifiers, transaction: DBWriteTransaction) {
        // Efficiently handle delivery receipts for the same message by fetching the sent message only
        // once and only using one updateWith... to update the message with new recipient state.
        BatchingDeliveryReceiptContext.withDeferredUpdates(transaction: transaction) { context in
            for request in combinedRequest.processingRequests {
                handleProcessingRequest(request, context: context, localIdentifiers: localIdentifiers, tx: transaction)
            }
        }
    }

    private func reallyHandleProcessingRequest(
        _ request: ProcessingRequest,
        context: DeliveryReceiptContext,
        localIdentifiers: LocalIdentifiers,
        transaction: DBWriteTransaction
    ) {
        switch request.state {
        case .completed(error: let error):
            Logger.info("Envelope completed early with error \(String(describing: error))")
        case .enqueueForGroup(let decryptedEnvelope, let envelopeData):
            SSKEnvironment.shared.groupMessageProcessorManagerRef.enqueue(
                envelope: decryptedEnvelope,
                envelopeData: envelopeData,
                serverDeliveryTimestamp: request.receivedEnvelope.serverDeliveryTimestamp,
                tx: transaction
            )
            SSKEnvironment.shared.messageReceiverRef.finishProcessingEnvelope(decryptedEnvelope, tx: transaction)
        case .messageReceiverRequest(let messageReceiverRequest):
            SSKEnvironment.shared.messageReceiverRef.handleRequest(messageReceiverRequest, context: context, localIdentifiers: localIdentifiers, tx: transaction)
            SSKEnvironment.shared.messageReceiverRef.finishProcessingEnvelope(messageReceiverRequest.decryptedEnvelope, tx: transaction)
        case .clearPlaceholdersOnly(let decryptedEnvelope):
            SSKEnvironment.shared.messageReceiverRef.finishProcessingEnvelope(decryptedEnvelope, tx: transaction)
        case .serverReceipt(let serverReceiptEnvelope):
            SSKEnvironment.shared.messageReceiverRef.handleDeliveryReceipt(envelope: serverReceiptEnvelope, context: context, tx: transaction)
        }
    }

    private func handleProcessingRequest(
        _ request: ProcessingRequest,
        context: DeliveryReceiptContext,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction
    ) {
        reallyHandleProcessingRequest(request, context: context, localIdentifiers: localIdentifiers, transaction: tx)
        tx.addSyncCompletion { request.receivedEnvelope.completion() }
    }

    @objc
    private func registrationStateDidChange() {
        self.drainPendingEnvelopes()
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
    let localDeviceId: LocalDeviceId
    let localIdentifiers: LocalIdentifiers
    let messageDecrypter: OWSMessageDecrypter
    let messageReceiver: MessageReceiver

    init(
        _ receivedEnvelope: ReceivedEnvelope,
        blockingManager: BlockingManager,
        localDeviceId: LocalDeviceId,
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

    func build(tx: DBWriteTransaction) -> ProcessingRequest.State {
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
        tx: DBWriteTransaction
    ) -> ProcessingStep {
        guard
            let contentProto = decryptedEnvelope.content,
            let groupContextV2 = GroupMessageProcessorManager.groupContextV2(from: contentProto)
        else {
            // Non-v2-group messages can be processed immediately.
            return .processNow(shouldDiscardVisibleMessages: false)
        }

        guard GroupMessageProcessorManager.canContextBeProcessedImmediately(
            groupContext: groupContextV2,
            tx: tx
        ) else {
            // Some v2 group messages required group state to be
            // updated before they can be processed.
            return .enqueueForGroupProcessing
        }
        let discardMode = SpecificGroupMessageProcessor.discardMode(
            forMessageFrom: decryptedEnvelope.sourceAci,
            groupContext: groupContextV2,
            tx: tx
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
        tx: DBWriteTransaction
    ) -> ProcessingRequest.State {
        owsPrecondition(CurrentAppContext().shouldProcessIncomingMessages)

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
            identityManager.setShouldSharePhoneNumber(with: decryptedEnvelope.sourceAci, tx: tx)
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
        localDeviceId: LocalDeviceId,
        tx: DBWriteTransaction
    ) -> ProcessingRequest {
        assertOnQueue(serialQueue)
        if let serverGuid = envelope.envelope.serverGuid, recentlyProcessedGuids.contains(serverGuid) {
            return ProcessingRequest(envelope, state: .completed(error: OWSGenericError("Skipping because it was recently processed.")))
        }
        let builder = ProcessingRequestBuilder(
            envelope,
            blockingManager: SSKEnvironment.shared.blockingManagerRef,
            localDeviceId: localDeviceId,
            localIdentifiers: localIdentifiers,
            messageDecrypter: SSKEnvironment.shared.messageDecrypterRef,
            messageReceiver: SSKEnvironment.shared.messageReceiverRef
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
    let envelope: SSKProtoEnvelope
    let serverDeliveryTimestamp: UInt64
    let completion: () -> Void

    enum DecryptionResult {
        case serverReceipt(ServerReceiptEnvelope)
        case decryptedMessage(DecryptedIncomingEnvelope)
    }

    func decryptIfNeeded(
        messageDecrypter: OWSMessageDecrypter,
        localIdentifiers: LocalIdentifiers,
        localDeviceId: LocalDeviceId,
        tx: DBWriteTransaction
    ) throws -> DecryptionResult {
        // Figure out what type of envelope we're dealing with.
        let validatedEnvelope = try ValidatedIncomingEnvelope(envelope, localIdentifiers: localIdentifiers)

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
    }
}

// MARK: -

public enum EnvelopeSource {
    case unknown
    case websocketIdentified
    case websocketUnidentified
    case rest
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
            pendingEnvelopes.removeFirst(processedEnvelopesCount)
        }
    }

    func enqueue(_ receivedEnvelope: ReceivedEnvelope) {
        unfairLock.withLock {
            pendingEnvelopes.append(receivedEnvelope)
        }
    }
}

// MARK: -

public enum MessageProcessingError: Error {
    case wrongDestinationUuid
    case invalidMessageTypeForDestinationUuid
    case blockedSender
}
