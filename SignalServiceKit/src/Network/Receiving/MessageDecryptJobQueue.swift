//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

/// Durably Decrypt a received signal message enevelope
///
/// The queue's operations (`SSKMessageDecryptOperation`) uses `SSKMessageDecrypt` to decrypt
/// Signal Message envelope data
///
@objc
public class SSKMessageDecryptJobQueue: NSObject, JobQueue {

    @objc
    public override init() {
        super.init()

        AppReadiness.runNowOrWhenAppDidBecomeReadySync {
            self.setup()
        }
    }

    // MARK: 

    @objc(enqueueEnvelopeData:serverDeliveryTimestamp:)
    public func add(envelopeData: Data, serverDeliveryTimestamp: UInt64) {
        databaseStorage.write { transaction in
            self.add(envelopeData: envelopeData, serverDeliveryTimestamp: serverDeliveryTimestamp, transaction: transaction)
        }
    }

    @objc(enqueueEnvelopeData:serverDeliveryTimestamp:transaction:)
    public func add(envelopeData: Data, serverDeliveryTimestamp: UInt64, transaction: SDSAnyWriteTransaction) {
        let jobRecord = SSKMessageDecryptJobRecord(envelopeData: envelopeData, serverDeliveryTimestamp: serverDeliveryTimestamp, label: jobRecordLabel)
        self.add(jobRecord: jobRecord, transaction: transaction)
    }

    // MARK: JobQueue

    public typealias DurableOperationType = SSKMessageDecryptOperation
    @objc
    public static let jobRecordLabel: String = "SSKMessageDecrypt"
    public static let maxRetries: UInt = 1
    public let requiresInternet: Bool = false
    public var runningOperations = AtomicArray<SSKMessageDecryptOperation>()

    public var jobRecordLabel: String {
        return type(of: self).jobRecordLabel
    }

    @objc
    public func setup() {
        guard CurrentAppContext().shouldProcessIncomingMessages else {
            return
        }

        // The pipeline supervisor will post updates when we can process messages
        // Suspend our operation queue if we should pause our work
        pipelineSupervisor.register(pipelineStage: self)
        defaultQueue.isSuspended = !pipelineSupervisor.isMessageProcessingPermitted

        // GRDB TODO: Is it really a concern to run the decrypt queue when we're unregistered?
        // If we want this behavior, we should observe registration state changes, and rerun
        // setup whenever it changes.
        // if !self.tsAccountManager.isRegisteredAndReady {
        //     return;
        // }

        defaultSetup()
    }

    public var isSetup = AtomicBool(false)

    public func didMarkAsReady(oldJobRecord: SSKMessageDecryptJobRecord, transaction: SDSAnyWriteTransaction) {
        // Do nothing.
    }

    public func didFlushQueue(transaction: SDSAnyWriteTransaction) {
        NotificationCenter.default.postNotificationNameAsync(.messageDecryptionDidFlushQueue, object: nil, userInfo: nil)
    }

    public func buildOperation(jobRecord: SSKMessageDecryptJobRecord, transaction: SDSAnyReadTransaction) throws -> SSKMessageDecryptOperation {
        return SSKMessageDecryptOperation(jobRecord: jobRecord)
    }

    let defaultQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "MessageDecryptQueue"
        operationQueue.maxConcurrentOperationCount = 1

        return operationQueue
    }()

    public func operationQueue(jobRecord: SSKMessageDecryptJobRecord) -> OperationQueue {
        return defaultQueue
    }

    @objc
    public func hasPendingJobsObjc(transaction: SDSAnyReadTransaction) -> Bool {
        return hasPendingJobs(transaction: transaction)
    }
}

extension SSKMessageDecryptJobQueue: MessageProcessingPipelineStage {
    private var pipelineSupervisor: MessagePipelineSupervisor {
        return SSKEnvironment.shared.messagePipelineSupervisor
    }

    public func supervisorDidSuspendMessageProcessing(_ supervisor: MessagePipelineSupervisor) {
        defaultQueue.isSuspended = true
    }

    public func supervisorDidResumeMessageProcessing(_ supervisor: MessagePipelineSupervisor) {
        defaultQueue.isSuspended = false
    }
}

enum SSKMessageDecryptOperationError: Error {
    case unspecifiedError
}

extension SSKMessageDecryptOperationError: OperationError {
    var isRetryable: Bool { return false }
}

public class SSKMessageDecryptOperation: OWSOperation, DurableOperation {

    // MARK: DurableOperation

    public let jobRecord: SSKMessageDecryptJobRecord

    weak public var durableOperationDelegate: SSKMessageDecryptJobQueue?

    public var operation: OWSOperation {
        return self
    }

    // MARK: Init

    init(jobRecord: SSKMessageDecryptJobRecord) {
        self.jobRecord = jobRecord
        super.init()
    }

    // MARK: Dependencies

    var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    var messageDecrypter: OWSMessageDecrypter {
        return SSKEnvironment.shared.messageDecrypter
    }

    var batchMessageProcessor: OWSBatchMessageProcessor {
        return SSKEnvironment.shared.batchMessageProcessor
    }

    // MARK: OWSOperation

    override public func run() {
        do {
            guard let envelopeData = jobRecord.envelopeData else {
                reportError(OWSAssertionError("envelopeData was unexpectedly nil"))
                return
            }

            let envelope = try SSKProtoEnvelope(serializedData: envelopeData)

            // It's important to calculate this with the *encrypted* envelope,
            // because after decryption the source will always be filled in.
            let wasReceivedByUD = self.wasReceivedByUD(envelope: envelope)

            messageDecrypter.decryptEnvelope(envelope, envelopeData: envelopeData) { result, transaction in
                self.handleResult(result, wasReceivedByUD: wasReceivedByUD, transaction: transaction)
            } failureBlock: {
                // TODO: failureBlock should propagate specific error.
                self.reportError(SSKMessageDecryptOperationError.unspecifiedError)
            }
        } catch {
            reportError(withUndefinedRetry: error)
        }
    }

    private func handleResult(_ result: OWSMessageDecryptResult, wasReceivedByUD: Bool, transaction: SDSAnyWriteTransaction) {
        owsAssertDebug(!Thread.isMainThread)

        let envelope: SSKProtoEnvelope
        do {
            // NOTE: We use envelopeData from the decrypt result, not job.envelopeData,
            // since the envelope may be altered by the decryption process in the UD case.
            envelope = try SSKProtoEnvelope(serializedData: result.envelopeData)
        } catch {
            owsFailDebug("Failed to parse decrypted envelope \(error)")

            transaction.addAsyncCompletionOffMain {
                self.reportError(error.asUnretryableError)
            }
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
                wasReceivedByUD: wasReceivedByUD,
                serverDeliveryTimestamp: jobRecord.serverDeliveryTimestamp,
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
                wasReceivedByUD: wasReceivedByUD,
                serverDeliveryTimestamp: jobRecord.serverDeliveryTimestamp,
                transaction: transaction
            )
        }

        transaction.addAsyncCompletionOffMain {
            self.reportSuccess()
        }
    }

    override public func didSucceed() {
        databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperationDidSucceed(self, transaction: transaction)
        }
    }

    override public func didReportError(_ error: Error) {
        Logger.debug("remainingRetries: \(self.remainingRetries)")

        databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperation(self, didReportError: error, transaction: transaction)
        }
    }

    override public func didFail(error: Error) {
        databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperation(self, didFailWithError: error, transaction: transaction)
        }
    }

    // MARK: -

    private func wasReceivedByUD(envelope: SSKProtoEnvelope) -> Bool {
        let hasSenderSource: Bool
        if envelope.hasValidSource {
            hasSenderSource = true
        } else {
            hasSenderSource = false
        }
        return envelope.type == .unidentifiedSender && !hasSenderSource
    }
}
