//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public class MessageProcessor: NSObject {
    @objc
    public static let messageProcessorDidFlushQueue = Notification.Name("messageProcessorDidFlushQueue")

    @objc
    public static var shared: MessageProcessor { SSKEnvironment.shared.messageProcessor }

    @objc
    public var hasPendingEnvelopes: Bool {
        pendingEnvelopesLock.withLock { !pendingEnvelopes.isEmpty }
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
            SSKEnvironment.shared.messagePipelineSupervisor.register(pipelineStage: self)
        }
    }

    public func processEncryptedEnvelopes(
        envelopes: [(encryptedEnvelopeData: Data, encryptedEnvelope: SSKProtoEnvelope?, completion: (Error?) -> Void)],
        serverDeliveryTimestamp: UInt64
    ) {
        for envelope in envelopes {
            processEncryptedEnvelopeData(
                envelope.encryptedEnvelopeData,
                encryptedEnvelope: envelope.encryptedEnvelope,
                serverDeliveryTimestamp: serverDeliveryTimestamp,
                completion: envelope.completion
            )
        }
    }

    #if TESTABLE_BUILD
    var shouldProcessDuringTests = false
    #endif

    @objc
    public func processEncryptedEnvelopeData(
        _ encryptedEnvelopeData: Data,
        encryptedEnvelope optionalEncryptedEnvelope: SSKProtoEnvelope? = nil,
        serverDeliveryTimestamp: UInt64,
        completion: @escaping (Error?) -> Void
    ) {
        guard !encryptedEnvelopeData.isEmpty else {
            completion(OWSAssertionError("Empty envelope."))
            return
        }

        // Drop any too-large messages on the floor. Well behaving clients should never send them.
        guard encryptedEnvelopeData.count <= Self.maxEnvelopeByteCount else {
            //        OWSProdError([OWSAnalyticsEvents messageReceiverErrorOversizeMessage]);
            completion(OWSAssertionError("Oversize envelope."))
            return
        }

        // Take note of any messages larger than we expect, but still process them.
        // This likely indicates a misbehaving sending client.
        if encryptedEnvelopeData.count > Self.largeEnvelopeWarningByteCount {
            //        OWSProdError([OWSAnalyticsEvents messageReceiverErrorLargeMessage]);
            owsFailDebug("Unexpectedly large envelope.")
        }

        let encryptedEnvelope: SSKProtoEnvelope
        if let optionalEncryptedEnvelope = optionalEncryptedEnvelope {
            encryptedEnvelope = optionalEncryptedEnvelope
        } else {
            do {
                encryptedEnvelope = try SSKProtoEnvelope(serializedData: encryptedEnvelopeData)
            } catch {
                owsFailDebug("Failed to parse encrypted envelope \(error)")
                completion(error)
                return
            }
        }

        pendingEnvelopesLock.withLock {
            pendingEnvelopes.append(PendingEnvelope(
                encryptedEnvelopeData: encryptedEnvelopeData,
                encryptedEnvelope: encryptedEnvelope,
                serverDeliveryTimestamp: serverDeliveryTimestamp,
                completion: completion
            ))
        }

        drainPendingEnvelopes()
    }

    private static let maxEnvelopeByteCount = 250 * 1024
    private static let largeEnvelopeWarningByteCount = 25 * 1024
    private let serialQueue = DispatchQueue(label: "MessageProcessor.processingQueue")

    private struct PendingEnvelope {
        let encryptedEnvelopeData: Data
        let encryptedEnvelope: SSKProtoEnvelope
        let serverDeliveryTimestamp: UInt64
        let completion: (Error?) -> Void
    }

    private let pendingEnvelopesLock = UnfairLock()
    private var pendingEnvelopes = [PendingEnvelope]()
    private var isDrainingPendingEnvelopes = false {
        didSet { assertOnQueue(serialQueue) }
    }

    private func drainPendingEnvelopes() {
        guard SSKEnvironment.shared.messagePipelineSupervisor.isMessageProcessingPermitted else { return }
        guard TSAccountManager.shared().isRegisteredAndReady else { return }

        guard CurrentAppContext().shouldProcessIncomingMessages else { return }

        serialQueue.async {
            guard !self.isDrainingPendingEnvelopes else { return }
            self.isDrainingPendingEnvelopes = true
            self.drainNextBatch()
        }
    }

    private func drainNextBatch() {
        assertOnQueue(serialQueue)

        #if TESTABLE_BUILD
        guard !CurrentAppContext().isRunningTests || shouldProcessDuringTests else {
            isDrainingPendingEnvelopes = false
            return
        }
        #endif

        // We want a value that is just high enough to yield perf benefits.
        let kIncomingMessageBatchSize = 16
        // If the app is in the background, use batch size of 1.
        // This reduces the risk of us never being able to drain any
        // messages from the queue. We should fine tune this number
        // to yield the best perf we can get.
        let batchSize = CurrentAppContext().isInBackground() ? 1 : kIncomingMessageBatchSize
        let batchEnvelopes = pendingEnvelopesLock.withLock {
            pendingEnvelopes.prefix(batchSize)
        }

        guard !batchEnvelopes.isEmpty else {
            isDrainingPendingEnvelopes = false
            NotificationCenter.default.postNotificationNameAsync(Self.messageProcessorDidFlushQueue, object: nil)
            return
        }

        Logger.info("Processing batch of \(batchEnvelopes.count) received envelope(s).")

        SDSDatabaseStorage.shared.write { transaction in
            batchEnvelopes.forEach { self.processEnvelope($0, transaction: transaction) }
        }

        // Remove the processed envelopes from the pending list.
        pendingEnvelopesLock.withLock {
            guard pendingEnvelopes.count > batchEnvelopes.count else {
                pendingEnvelopes = []
                return
            }
            pendingEnvelopes = Array(pendingEnvelopes.suffix(from: batchEnvelopes.count))
        }

        // Wait a bit in hopes of increasing the batch size.
        // This delay won't affect the first message to arrive when this queue is idle,
        // so by definition we're receiving more than one message and can benefit from
        // batching.
        serialQueue.asyncAfter(deadline: .now() + 0.5) { self.drainNextBatch() }
    }

    private func processEnvelope(_ pendingEnvelope: PendingEnvelope, transaction: SDSAnyWriteTransaction) {
        assertOnQueue(serialQueue)

        Logger.info("Processing envelope with timestamp \(pendingEnvelope.encryptedEnvelope.timestamp)")

        let result = SSKEnvironment.shared.messageDecrypter.decryptEnvelope(
            pendingEnvelope.encryptedEnvelope,
            envelopeData: pendingEnvelope.encryptedEnvelopeData,
            transaction: transaction
        )

        switch result {
        case .success(let result):
            let envelope: SSKProtoEnvelope
            do {
                // NOTE: We use envelopeData from the decrypt result, not the pending envelope,
                // since the envelope may be altered by the decryption process in the UD case.
                envelope = try SSKProtoEnvelope(serializedData: result.envelopeData)
            } catch {
                owsFailDebug("Failed to parse decrypted envelope \(error)")
                transaction.addAsyncCompletionOffMain { pendingEnvelope.completion(error) }
                return
            }

            if let groupContextV2 = GroupsV2MessageProcessor.groupContextV2(
                forEnvelope: envelope,
                plaintextData: result.plaintextData
            ), !GroupsV2MessageProcessor.canContextBeProcessedImmediately(
                groupContext: groupContextV2,
                transaction: transaction
            ) {
                // If we can't process the message immediately, we enqueue it for
                // for processing in the same transaction within which it was decrypted
                // to prevent data loss.
                SSKEnvironment.shared.groupsV2MessageProcessor.enqueue(
                    envelopeData: result.envelopeData,
                    plaintextData: result.plaintextData,
                    envelope: envelope,
                    wasReceivedByUD: wasReceivedByUD(envelope: pendingEnvelope.encryptedEnvelope),
                    serverDeliveryTimestamp: pendingEnvelope.serverDeliveryTimestamp,
                    transaction: transaction
                )
            } else {
                // Envelopes can be processed immediately if they're:
                // 1. Not a GV2 message.
                // 2. A GV2 message that doesn't require updating the group.
                //
                // The advantage to processing the message immediately is that
                // we can full process the message in the same transaction that
                // we used to decrypt it. This results in a significant perf
                // benefit verse queueing the message and waiting for that queue
                // to open new transactions and process messages. The downside is
                // that if we *fail* to process this message (e.g. the app crashed
                // or was killed), we'll have to re-decrypt again before we process.
                // This is safe, since the decrypt operation would also be rolled
                // back (since the transaction didn't finalize) and should be rare.
                SSKEnvironment.shared.messageManager.processEnvelope(
                    envelope,
                    plaintextData: result.plaintextData,
                    wasReceivedByUD: wasReceivedByUD(envelope: pendingEnvelope.encryptedEnvelope),
                    serverDeliveryTimestamp: pendingEnvelope.serverDeliveryTimestamp,
                    transaction: transaction
                )
            }

            transaction.addAsyncCompletionOffMain { pendingEnvelope.completion(nil) }
        case .failure(let error):
            transaction.addAsyncCompletionOffMain {
                pendingEnvelope.completion(error)
            }
        }
    }

    private func wasReceivedByUD(envelope: SSKProtoEnvelope) -> Bool {
        let hasSenderSource: Bool
        if envelope.hasValidSource {
            hasSenderSource = true
        } else {
            hasSenderSource = false
        }
        return envelope.type == .unidentifiedSender && !hasSenderSource
    }

    @objc
    func registrationStateDidChange() {
        AppReadiness.runNowOrWhenAppDidBecomeReadySync {
            self.drainPendingEnvelopes()
        }
    }
}

extension MessageProcessor: MessageProcessingPipelineStage {
    public func supervisorDidResumeMessageProcessing(_ supervisor: MessagePipelineSupervisor) {
        drainPendingEnvelopes()
    }
}
