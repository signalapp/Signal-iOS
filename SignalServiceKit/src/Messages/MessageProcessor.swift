//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import SignalCoreKit

@objc
public class MessageProcessor: NSObject {
    @objc
    public static let messageProcessorDidDrainQueue = Notification.Name("messageProcessorDidDrainQueue")

    @objc
    public var hasPendingEnvelopes: Bool {
        !pendingEnvelopes.isEmpty
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func processingCompletePromise() -> AnyPromise {
        return AnyPromise(processingCompletePromise())
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

    @objc
    @available(swift, obsoleted: 1.0)
    public func fetchingAndProcessingCompletePromise() -> AnyPromise {
        return AnyPromise(fetchingAndProcessingCompletePromise())
    }

    public func fetchingAndProcessingCompletePromise() -> Promise<Void> {
        return firstly { () -> Promise<Void> in
            Self.messageFetcherJob.fetchingCompletePromise()
        }.then { () -> Promise<Void> in
            self.processingCompletePromise()
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
                let legacyProcessingJobRecords = AnyMessageContentJobFinder().allJobs(transaction: transaction)
                for jobRecord in legacyProcessingJobRecords {
                    let completion: (Error?) -> Void = { _ in
                        SDSDatabaseStorage.shared.write { jobRecord.anyRemove(transaction: $0) }
                    }
                    do {
                        let envelope = try SSKProtoEnvelope(serializedData: jobRecord.envelopeData)
                        let validatedEnvelope = try ValidatedIncomingEnvelope(envelope)
                        let identifiedEnvelope = try IdentifiedIncomingEnvelope(validatedEnvelope: validatedEnvelope)
                        self.processDecryptedEnvelope(
                            identifiedEnvelope,
                            plaintextData: jobRecord.plaintextData,
                            serverDeliveryTimestamp: jobRecord.serverDeliveryTimestamp,
                            wasReceivedByUD: jobRecord.wasReceivedByUD,
                            identity: .aci,
                            completion: completion
                        )
                    } catch {
                        completion(error)
                    }
                }

                // We may have legacy decrypt jobs queued. We want to schedule them for
                // processing immediately when we launch, so that we can drain the old queue.
                do {
                    let legacyDecryptJobRecords = try AnyJobRecordFinder<LegacyMessageDecryptJobRecord>().allRecords(
                        label: "SSKMessageDecrypt",
                        status: .ready,
                        transaction: transaction
                    )
                    for jobRecord in legacyDecryptJobRecords {
                        guard let envelopeData = jobRecord.envelopeData else {
                            owsFailDebug("Skipping job with no envelope data")
                            continue
                        }
                        self.processEncryptedEnvelopeData(
                            envelopeData,
                            serverDeliveryTimestamp: jobRecord.serverDeliveryTimestamp,
                            envelopeSource: .unknown,
                            completion: { _ in
                                SDSDatabaseStorage.shared.write { jobRecord.anyRemove(transaction: $0) }
                            }
                        )
                    }
                } catch {
                    Logger.error("Couldn't fetch legacy job records: \(error)")
                }
            }
        }
    }

    public func processEncryptedEnvelopeData(
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

        processEncryptedEnvelope(EncryptedEnvelope(encryptedEnvelopeData: envelopeData,
                                                   encryptedEnvelope: protoEnvelope,
                                                   serverDeliveryTimestamp: serverDeliveryTimestamp,
                                                   completion: completion),
                                 envelopeSource: envelopeSource)
    }

    public func processEncryptedEnvelope(
        _ encryptedEnvelopeProto: SSKProtoEnvelope,
        serverDeliveryTimestamp: UInt64,
        envelopeSource: EnvelopeSource,
        completion: @escaping (Error?) -> Void
    ) {
        processEncryptedEnvelope(EncryptedEnvelope(encryptedEnvelopeData: nil,
                                                   encryptedEnvelope: encryptedEnvelopeProto,
                                                   serverDeliveryTimestamp: serverDeliveryTimestamp,
                                                   completion: completion),
                                 envelopeSource: envelopeSource)
    }

    private func processEncryptedEnvelope(_ encryptedEnvelope: EncryptedEnvelope, envelopeSource: EnvelopeSource) {
        let result = pendingEnvelopes.enqueue(encryptedEnvelope: encryptedEnvelope)
        switch result {
        case .duplicate:
            Logger.warn("Duplicate envelope \(encryptedEnvelope.encryptedEnvelope.timestamp). Server timestamp: \(encryptedEnvelope.serverTimestamp), serverGuid: \(encryptedEnvelope.serverGuidFormatted), EnvelopeSource: \(envelopeSource).")
            encryptedEnvelope.completion(MessageProcessingError.duplicatePendingEnvelope)
        case .enqueued:
            drainPendingEnvelopes()
        }
    }

#if DEBUG
    public func processFakeDecryptedEnvelope(_ envelope: SSKProtoEnvelope, plaintextData: Data) {
        processDecryptedEnvelope(
            try! IdentifiedIncomingEnvelope(validatedEnvelope: ValidatedIncomingEnvelope(envelope)),
            plaintextData: plaintextData,
            serverDeliveryTimestamp: 0,
            wasReceivedByUD: false,
            identity: .aci,
            completion: { error in
                switch error {
                case MessageProcessingError.duplicatePendingEnvelope?:
                    Logger.warn("duplicatePendingEnvelope.")
                case let otherError?:
                    owsFailDebug("Error: \(otherError)")
                case nil:
                    break
                }
            }
        )
    }
#endif

    func processDecryptedEnvelope(
        _ identifiedEnvelope: IdentifiedIncomingEnvelope,
        plaintextData: Data?,
        serverDeliveryTimestamp: UInt64,
        wasReceivedByUD: Bool,
        identity: OWSIdentity,
        completion: @escaping (Error?) -> Void
    ) {
        let decryptedEnvelope = DecryptedEnvelope(
            identifiedEnvelope: identifiedEnvelope,
            envelopeData: nil,
            plaintextData: plaintextData,
            serverDeliveryTimestamp: serverDeliveryTimestamp,
            wasReceivedByUD: wasReceivedByUD,
            identity: identity,
            completion: completion
        )
        pendingEnvelopes.enqueue(decryptedEnvelope: decryptedEnvelope)
        drainPendingEnvelopes()
    }

    public var queuedContentCount: Int {
        pendingEnvelopes.count
    }

    private static let maxEnvelopeByteCount = 250 * 1024
    public static let largeEnvelopeWarningByteCount = 25 * 1024
    private let serialQueue = DispatchQueue(label: "org.signal.message-processor",
                                            autoreleaseFrequency: .workItem)

    private var pendingEnvelopes = PendingEnvelopes()

    private var isDrainingPendingEnvelopes = AtomicBool(false, lock: .init())

    private func drainPendingEnvelopes() {
        guard CurrentAppContext().shouldProcessIncomingMessages else { return }
        guard tsAccountManager.isRegisteredAndReady else { return }

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
            var remainingEnvelopes = batchEnvelopes
            while !remainingEnvelopes.isEmpty {
                guard messagePipelineSupervisor.isMessageProcessingPermitted else {
                    break
                }
                autoreleasepool {
                    // If we build a request, we must handle it to ensure it's not lost if we
                    // stop processing envelopes.
                    let combinedRequest = buildNextCombinedRequest(envelopes: &remainingEnvelopes, transaction: tx)
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
    private func buildNextCombinedRequest(envelopes: inout [PendingEnvelope],
                                          transaction: SDSAnyWriteTransaction) -> RelatedProcessingRequests {
        let result = RelatedProcessingRequests()
        while let envelope = envelopes.first {
            envelopes.removeFirst()
            let request = processingRequest(for: envelope,
                                            messageManager: Self.messageManager,
                                            blockingManager: Self.blockingManager,
                                            transaction: transaction)
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
        Logger.info("Process \(combinedRequest.processingRequests.count) related requests")
        // Efficiently handle delivery receipts for the same message by fetching the sent message only
        // once and only using one transaction to update the message with new recipient state.
        // If `relation` doesn't contain a bunch of delivery receipts, handle the envelopes individually.
        BatchingDeliveryReceiptContext.withDeferredUpdates(transaction: transaction) { context in
            for request in combinedRequest.processingRequests {
                guard handleProcessingRequest(request, context: context, transaction: transaction) else {
                    continue
                }
                if let envelope = request.identifiedEnvelope {
                    messageManager.finishProcessingEnvelope(envelope, tx: transaction)
                }
            }
        }
    }

    private func reallyHandleProcessingRequest(
        _ request: ProcessingRequest,
        context: DeliveryReceiptContext,
        transaction: SDSAnyWriteTransaction
    ) -> (Bool, Error?) {
        switch request.state {
        case .completed(error: let error):
            Logger.info("Envelope completed early with error \(String(describing: error))")
            return (false, error)
        case .enqueueForGroup(decryptedEnvelope: let decryptedEnvelope, envelopeData: let envelopeData):
            Logger.info("Enqueue group envelope")
            Self.groupsV2MessageProcessor.enqueue(
                envelopeData: envelopeData,
                // All GV2 messages have plaintext data (because that's where the group context lives)
                plaintextData: decryptedEnvelope.plaintextData!,
                wasReceivedByUD: decryptedEnvelope.wasReceivedByUD,
                serverDeliveryTimestamp: decryptedEnvelope.serverDeliveryTimestamp,
                transaction: transaction
            )
            return (false, nil)
        case .messageManagerRequest(let messageManagerRequest):
            Logger.info("Pass envelope to message manager")
            messageManager.handle(messageManagerRequest, context: context, transaction: transaction)
            return (true, nil)
        case .plaintextReceipt(let identifiedEnvelope):
            Logger.info("Handle server-generated receipt")
            messageManager.handleDeliveryReceipt(identifiedEnvelope, context: context, transaction: transaction)
            return (true, nil)
        case .clearPlaceholdersOnly:
            return (true, nil)
        }
    }

    private func handleProcessingRequest(_ request: ProcessingRequest,
                                         context: DeliveryReceiptContext,
                                         transaction: SDSAnyWriteTransaction) -> Bool {
        let (shouldFinishProcessing, maybeError) = reallyHandleProcessingRequest(request,
                                                                                 context: context,
                                                                                 transaction: transaction)
        transaction.addAsyncCompletionOffMain {
            request.pendingEnvelope.completion(maybeError)
        }
        return shouldFinishProcessing
    }

    @objc
    func registrationStateDidChange() {
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

struct ProcessingRequest {
    enum State {
        case completed(error: Error?)
        case enqueueForGroup(decryptedEnvelope: DecryptedEnvelope, envelopeData: Data)
        case messageManagerRequest(MessageManagerRequest)
        case plaintextReceipt(IdentifiedIncomingEnvelope)
        // Message decrypted but had an invalid protobuf.
        case clearPlaceholdersOnly(IdentifiedIncomingEnvelope)
    }

    let state: State
    let pendingEnvelope: PendingEnvelope

    var identifiedEnvelope: IdentifiedIncomingEnvelope? {
        switch state {
        case .completed, .enqueueForGroup:
            return nil
        case .messageManagerRequest(let messageManagerRequest):
            return messageManagerRequest.identifiedEnvelope
        case .plaintextReceipt(let identifiedEnvelope), .clearPlaceholdersOnly(let identifiedEnvelope):
            return identifiedEnvelope
        }
    }

    // If this request is for a delivery receipt, return the timestamps for the sent-messages it
    // corresponds to.
    var deliveryReceiptMessageTimestamps: [UInt64]? {
        switch state {
        case .completed, .enqueueForGroup, .clearPlaceholdersOnly:
            return nil
        case .plaintextReceipt(let identifiedEnvelope):
            return [identifiedEnvelope.timestamp]
        case .messageManagerRequest(let request):
            switch request.messageType {
            case .receiptMessage:
                guard let receiptMessage = request.protoContent?.receiptMessage,
                      receiptMessage.unwrappedType == .delivery else {
                    return nil
                }
                return receiptMessage.timestamp
            case .syncMessage, .dataMessage, .callMessage, .typingMessage, .nullMessage,
                    .decryptionErrorMessage, .storyMessage, .hasSenderKeyDistributionMessage,
                    .editMessage, .unknown:
                return nil
            }
        }
    }
    init(_ pendingEnvelope: PendingEnvelope,
         state: State) {
        self.pendingEnvelope = pendingEnvelope
        self.state = state
    }
}

class RelatedProcessingRequests {
    private(set) var processingRequests = [ProcessingRequest]()

    func add(_ processingRequest: ProcessingRequest) {
        processingRequests.append(processingRequest)
    }
}

struct ProcessingRequestBuilder {
    let pendingEnvelope: PendingEnvelope
    let messageManager: OWSMessageManager
    let blockingManager: BlockingManager

    init(_ pendingEnvelope: PendingEnvelope,
         messageManager: OWSMessageManager,
         blockingManager: BlockingManager) {
        self.pendingEnvelope = pendingEnvelope
        self.messageManager = messageManager
        self.blockingManager = blockingManager
    }

    func build(transaction: SDSAnyWriteTransaction) -> ProcessingRequest {
        switch pendingEnvelope.decrypt(transaction: transaction) {
        case .success(let result):
            return decryptionSucceeded(result, transaction: transaction)
        case .failure(let error):
            return decryptionFailed(error)
        }
    }

    private enum ProcessingStep {
        case discard
        case enqueueForGroupProcessing
        case processNow(shouldDiscardVisibleMessages: Bool)
    }

    private func processingStep(
        _ result: DecryptedEnvelope,
        sourceServiceId: ServiceId,
        transaction: SDSAnyWriteTransaction
    ) -> ProcessingStep {
        guard let plaintextData = result.plaintextData,
              let groupContextV2 =
                GroupsV2MessageProcessor.groupContextV2(fromPlaintextData: plaintextData) else {
            // Non-v2-group messages can be processed immediately.
            return .processNow(shouldDiscardVisibleMessages: false)
        }

        guard GroupsV2MessageProcessor.canContextBeProcessedImmediately(
            groupContext: groupContextV2,
            transaction: transaction
        ) else {
            // Some v2 group messages required group state to be
            // updated before they can be processed.
            return .enqueueForGroupProcessing
        }
        let discardMode = GroupsMessageProcessor.discardMode(
            forMessageFrom: SignalServiceAddress(sourceServiceId),
            groupContext: groupContextV2,
            transaction: transaction
        )
        if discardMode == .discard {
            // Some v2 group messages should be discarded and not processed.
            Logger.verbose("Discarding job.")
            return .discard
        }
        // Some v2 group messages should be processed, but
        // discarding any "visible" messages, e.g. text messages
        // or calls.
        return .processNow(shouldDiscardVisibleMessages: discardMode == .discardVisibleMessages)
    }

    private func decryptionSucceeded(
        _ result: DecryptedEnvelope,
        transaction: SDSAnyWriteTransaction
    ) -> ProcessingRequest {
        // NOTE: We use the envelope from the decrypt result, not the pending envelope,
        // since the envelope may be altered by the decryption process in the UD case.
        owsAssert(CurrentAppContext().shouldProcessIncomingMessages)

        let identifiedEnvelope = result.identifiedEnvelope
        Logger.info("Decrypted envelope \(OWSMessageHandler.description(for: identifiedEnvelope.envelope))")

        // Pre-processing has to happen during the same transaction that performed decryption
        messageManager.preprocessEnvelope(
            identifiedEnvelope,
            plaintext: result.plaintextData,
            transaction: transaction
        )

        // If the sender is in the block list, we can skip scheduling any additional processing.
        let sourceAddress = SignalServiceAddress(identifiedEnvelope.sourceServiceId)
        if blockingManager.isAddressBlocked(sourceAddress, transaction: transaction) {
            Logger.info("Skipping processing for blocked envelope from \(identifiedEnvelope.sourceServiceId)")
            return ProcessingRequest(pendingEnvelope, state: .completed(error: MessageProcessingError.blockedSender))
        }

        if result.identity == .pni {
            NSObject.identityManager.setShouldSharePhoneNumber(with: sourceAddress, transaction: transaction)
        }

        switch processingStep(result, sourceServiceId: identifiedEnvelope.sourceServiceId, transaction: transaction) {
        case .discard:
            // Do nothing.
            Logger.verbose("Discarding job.")
            return ProcessingRequest(pendingEnvelope, state: .completed(error: nil))
        case .enqueueForGroupProcessing:
            // If we can't process the message immediately, we enqueue it for
            // for processing in the same transaction within which it was decrypted
            // to prevent data loss.
            let envelopeData: Data
            if let existingEnvelopeData = result.envelopeData {
                envelopeData = existingEnvelopeData
            } else {
                do {
                    envelopeData = try identifiedEnvelope.envelope.serializedData()
                } catch {
                    owsFailDebug("failed to reserialize envelope: \(error)")
                    return ProcessingRequest(pendingEnvelope, state: .completed(error: error))
                }
            }
            return ProcessingRequest(
                pendingEnvelope,
                state: .enqueueForGroup(decryptedEnvelope: result, envelopeData: envelopeData)
            )
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
            messageManager.checkForUnknownLinkedDevice(in: identifiedEnvelope.envelope, transaction: transaction)
            switch identifiedEnvelope.envelopeType {
            case .ciphertext, .prekeyBundle, .unidentifiedSender, .senderkeyMessage, .plaintextContent:
                if result.plaintextData == nil {
                    owsFailDebug("Missing plaintextData")
                }
                guard
                    let plaintextData = result.plaintextData,
                    let messageManagerRequest = MessageManagerRequest(
                        identifiedEnvelope: identifiedEnvelope,
                        plaintextData: plaintextData,
                        wasReceivedByUD: result.wasReceivedByUD,
                        serverDeliveryTimestamp: result.serverDeliveryTimestamp,
                        shouldDiscardVisibleMessages: shouldDiscardVisibleMessages,
                        transaction: transaction
                    )
                else {
                    return ProcessingRequest(pendingEnvelope, state: .completed(error: nil))
                }
                if messageManagerRequest.protoContent == nil {
                    messageManager.logUnactionablePayload(identifiedEnvelope.envelope)
                    return ProcessingRequest(pendingEnvelope, state: .clearPlaceholdersOnly(identifiedEnvelope))
                }
                return ProcessingRequest(pendingEnvelope, state: .messageManagerRequest(messageManagerRequest))
            case .receipt:
                return ProcessingRequest(pendingEnvelope, state: .plaintextReceipt(identifiedEnvelope))
            case .keyExchange:
                Logger.warn("Received Key Exchange Message, not supported")
                return ProcessingRequest(pendingEnvelope, state: .completed(error: nil))
            case .unknown:
                Logger.warn("Received an unknown message type")
                return ProcessingRequest(pendingEnvelope, state: .completed(error: nil))
            default:
                Logger.warn("Received unhandled envelope type: \(identifiedEnvelope.envelopeType)")
                return ProcessingRequest(pendingEnvelope, state: .completed(error: nil))
            }
        }
    }

    private func decryptionFailed(_ error: Error) -> ProcessingRequest {
        return ProcessingRequest(pendingEnvelope,
                                 state: .completed(error: error))
    }
}

extension MessageProcessor {
    func processingRequest(for envelope: PendingEnvelope,
                           messageManager: OWSMessageManager,
                           blockingManager: BlockingManager,
                           transaction: SDSAnyWriteTransaction) -> ProcessingRequest {
        assertOnQueue(serialQueue)
        let builder = ProcessingRequestBuilder(envelope,
                                               messageManager: messageManager,
                                               blockingManager: blockingManager)
        return builder.build(transaction: transaction)
    }
}

// MARK: -

extension MessageProcessor: MessageProcessingPipelineStage {
    public func supervisorDidResumeMessageProcessing(_ supervisor: MessagePipelineSupervisor) {
        drainPendingEnvelopes()
    }
}

// MARK: -

protocol PendingEnvelope {
    var completion: (Error?) -> Void { get }
    var wasReceivedByUD: Bool { get }
    func decrypt(transaction: SDSAnyWriteTransaction) -> Swift.Result<DecryptedEnvelope, Error>
    func isDuplicateOf(_ other: PendingEnvelope) -> Bool
}

// MARK: -

private struct EncryptedEnvelope: PendingEnvelope, Dependencies {
    let encryptedEnvelopeData: Data?
    let encryptedEnvelope: SSKProtoEnvelope
    let serverDeliveryTimestamp: UInt64
    let completion: (Error?) -> Void

    public var serverGuid: String? {
        encryptedEnvelope.serverGuid
    }
    public var serverGuidFormatted: String {
        String(describing: serverGuid)
    }
    public var serverTimestamp: UInt64 {
        encryptedEnvelope.serverTimestamp
    }

    var wasReceivedByUD: Bool {
        let hasSenderSource: Bool
        if encryptedEnvelope.hasValidSource {
            hasSenderSource = true
        } else {
            hasSenderSource = false
        }
        return encryptedEnvelope.type == .unidentifiedSender && !hasSenderSource
    }

    func decrypt(transaction: SDSAnyWriteTransaction) -> Swift.Result<DecryptedEnvelope, Error> {
        return Result {
            let result = try Self.messageDecrypter.decryptEnvelope(
                encryptedEnvelope,
                envelopeData: encryptedEnvelopeData,
                transaction: transaction
            )
            return DecryptedEnvelope(
                identifiedEnvelope: result.identifiedEnvelope,
                envelopeData: result.envelopeData,
                plaintextData: result.plaintextData,
                serverDeliveryTimestamp: serverDeliveryTimestamp,
                wasReceivedByUD: wasReceivedByUD,
                identity: result.localIdentity,
                completion: completion
            )
        }
    }

    func isDuplicateOf(_ other: PendingEnvelope) -> Bool {
        guard let other = other as? EncryptedEnvelope else {
            return false
        }
        guard let serverGuid = self.serverGuid else {
            owsFailDebug("Missing serverGuid.")
            return false
        }
        guard let otherServerGuid = other.serverGuid else {
            owsFailDebug("Missing other.serverGuid.")
            return false
        }
        return serverGuid == otherServerGuid
    }
}

// MARK: -

struct DecryptedEnvelope: PendingEnvelope {
    let identifiedEnvelope: IdentifiedIncomingEnvelope
    let envelopeData: Data?
    let plaintextData: Data?
    let serverDeliveryTimestamp: UInt64
    let wasReceivedByUD: Bool
    let identity: OWSIdentity
    let completion: (Error?) -> Void

    func decrypt(transaction: SDSAnyWriteTransaction) -> Swift.Result<DecryptedEnvelope, Error> {
        return .success(self)
    }

    func isDuplicateOf(_ other: PendingEnvelope) -> Bool {
        // This envelope is only used for legacy envelopes.
        // We don't need to de-duplicate.
        false
    }
}

// MARK: -

@objc
public enum EnvelopeSource: UInt, CustomStringConvertible {
    case unknown
    case websocketIdentified
    case websocketUnidentified
    case rest
    // We re-decrypt incoming messages after accepting a safety number change.
    case identityChangeError
    case debugUI
    case tests

    // MARK: - CustomStringConvertible

    public var description: String {
        switch self {
        case .unknown:
            return "unknown"
        case .websocketIdentified:
            return "websocketIdentified"
        case .websocketUnidentified:
            return "websocketUnidentified"
        case .rest:
            return "rest"
        case .identityChangeError:
            return "identityChangeError"
        case .debugUI:
            return "debugUI"
        case .tests:
            return "tests"
        }
    }
}

// MARK: -

private class PendingEnvelopes {
    private let unfairLock = UnfairLock()
    private var pendingEnvelopes = [PendingEnvelope]()

    var isEmpty: Bool {
        unfairLock.withLock { pendingEnvelopes.isEmpty }
    }

    var count: Int {
        unfairLock.withLock { pendingEnvelopes.count }
    }

    struct Batch {
        let batchEnvelopes: [PendingEnvelope]
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

    func enqueue(decryptedEnvelope: DecryptedEnvelope) {
        unfairLock.withLock {
            let oldCount = pendingEnvelopes.count
            pendingEnvelopes.append(decryptedEnvelope)
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

    func enqueue(encryptedEnvelope: EncryptedEnvelope) -> EnqueueResult {
        unfairLock.withLock {
            let oldCount = pendingEnvelopes.count

            for pendingEnvelope in pendingEnvelopes {
                if pendingEnvelope.isDuplicateOf(encryptedEnvelope) {
                    return .duplicate
                }
            }
            pendingEnvelopes.append(encryptedEnvelope)

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
