//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

private enum JobError: Error {
    case permanentFailure(description: String)
    case obsolete(description: String)
}

/// Durably enqueues a message for sending.
///
/// The queue's operations (`MessageSenderOperation`) uses `MessageSender` to send a message.
///
/// ## Retry behavior
///
/// Like all JobQueue's, MessageSenderJobQueue implements retry handling for operation errors.
///
/// `MessageSender` also includes it's own retry logic necessary to encapsulate business logic around
/// a user changing their Registration ID, or adding/removing devices. That is, it is sometimes *normal*
/// for MessageSender to have to resend to a recipient multiple times before it is accepted, and doesn't
/// represent a "failure" from the application standpoint.
///
/// So we have an inner non-durable retry (MessageSender) and an outer durable retry (MessageSenderJobQueue).
///
/// Both respect the `error.isRetryable` convention to be sure we don't keep retrying in some situations
/// (e.g. rate limiting)
public class MessageSenderJobQueue: NSObject {

    public init(appReadiness: AppReadiness) {
        super.init()

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            self.setUp()
        }
    }

    public func add(
        message: PreparedOutgoingMessage,
        limitToCurrentProcessLifetime: Bool = false,
        isHighPriority: Bool = false,
        transaction: SDSAnyWriteTransaction
    ) {
        self.add(
            message: message,
            exclusiveToCurrentProcessIdentifier: limitToCurrentProcessLifetime,
            isHighPriority: isHighPriority,
            future: nil,
            transaction: transaction
        )
    }

    public func add(
        _ namespace: PromiseNamespace,
        message: PreparedOutgoingMessage,
        limitToCurrentProcessLifetime: Bool = false,
        isHighPriority: Bool = false,
        transaction: SDSAnyWriteTransaction
    ) -> Promise<Void> {
        return Promise { future in
            self.add(
                message: message,
                exclusiveToCurrentProcessIdentifier: limitToCurrentProcessLifetime,
                isHighPriority: isHighPriority,
                future: future,
                transaction: transaction
            )
        }
    }

    private func add(
        message: PreparedOutgoingMessage,
        exclusiveToCurrentProcessIdentifier: Bool,
        isHighPriority: Bool,
        future: Future<Void>?,
        transaction: SDSAnyWriteTransaction
    ) {
        // Mark as sending now so the UI updates immediately.
        message.updateAllUnsentRecipientsAsSending(tx: transaction)
        let jobRecord: MessageSenderJobRecord
        do {
            jobRecord = try message.asMessageSenderJobRecord(isHighPriority: isHighPriority, tx: transaction)
        } catch {
            message.updateWithAllSendingRecipientsMarkedAsFailed(error: error, tx: transaction)
            future?.reject(error)
            return
        }
        if exclusiveToCurrentProcessIdentifier {
            jobRecord.flagAsExclusiveForCurrentProcessIdentifier()
        }
        self.add(jobRecord: jobRecord, transaction: transaction)
        if let future {
            self.state.update { $0.jobFutures[jobRecord.uniqueId] = future }
        }
    }

    // MARK: JobQueue

    private struct State {
        var isSetup = false
        var runningOperations = [MessageSenderOperation]()
        var jobFutures = [String: Future<Void>]()
    }
    private let state = AtomicValue<State>(State(), lock: .init())

    private func didMarkAsReady(
        oldJobRecord: MessageSenderJobRecord,
        transaction: SDSAnyWriteTransaction
    ) {
        let uniqueId: String
        switch oldJobRecord.messageType {
        case .persisted(let messageId, _):
            uniqueId = messageId
        case .editMessage(let editedMessageId, _, _):
            uniqueId = editedMessageId
        case .transient, .none:
            return
        }

        TSOutgoingMessage
            .anyFetch(
                uniqueId: uniqueId,
                transaction: transaction
            )
            .flatMap { $0 as? TSOutgoingMessage }?
            .updateAllUnsentRecipientsAsSending(transaction: transaction)
    }

    private func buildOperation(
        jobRecord: MessageSenderJobRecord,
        transaction: SDSAnyReadTransaction
    ) throws -> MessageSenderOperation {
        guard let message = PreparedOutgoingMessage.restore(from: jobRecord, tx: transaction) else {
            throw JobError.obsolete(description: "message no longer exists")
        }

        let operation = MessageSenderOperation(
            message: message,
            jobRecord: jobRecord,
            future: self.state.update { $0.jobFutures.removeValue(forKey: jobRecord.uniqueId) }
        )
        operation.queuePriority = jobRecord.isHighPriority ? .high : message.sendingQueuePriority(tx: transaction)

        // Media messages run on their own queue to not block future non-media sends,
        // but should not start sending until all previous operations have executed.
        // We can guarantee this by adding another operation to the send queue that
        // we depend upon.
        //
        // For example, if you send text messages A, B and then media message C
        // message C should never send before A and B. However, if you send text
        // messages A, B, then media message C, followed by text message D, D cannot
        // send before A and B, but CAN send before C.
        switch jobRecord.messageType {
        case .persisted(_, let useMediaQueue), .editMessage(_, _, let useMediaQueue):
            if useMediaQueue, let sendQueue = senderQueues[message.uniqueThreadId] {
                let orderMaintainingOperation = Operation()
                orderMaintainingOperation.queuePriority = operation.queuePriority
                sendQueue.addOperation(orderMaintainingOperation)
                operation.addDependency(orderMaintainingOperation)
            }
        case .transient, .none:
            break
        }

        return operation
    }

    private var senderQueues: [String: OperationQueue] = [:]
    private var mediaSenderQueues: [String: OperationQueue] = [:]
    private let defaultQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "MessageSenderJobQueue-Default"
        operationQueue.maxConcurrentOperationCount = 1

        return operationQueue
    }()

    // We use a per-thread serial OperationQueue to ensure messages are delivered to the
    // service in the order the user sent them.
    private func operationQueue(jobRecord: MessageSenderJobRecord) -> OperationQueue {
        guard let threadId = jobRecord.threadId else {
            return defaultQueue
        }

        switch jobRecord.messageType {
        case
                .persisted(_, let useMediaQueue) where useMediaQueue,
                .editMessage(_, _, let useMediaQueue) where useMediaQueue:
            guard let existingQueue = mediaSenderQueues[threadId] else {
                let operationQueue = OperationQueue()
                operationQueue.name = "MessageSenderJobQueue-Media"
                operationQueue.maxConcurrentOperationCount = 1

                mediaSenderQueues[threadId] = operationQueue

                return operationQueue
            }

            return existingQueue
        case .persisted, .editMessage, .transient, .none:
            guard let existingQueue = senderQueues[threadId] else {
                let operationQueue = OperationQueue()
                operationQueue.name = "MessageSenderJobQueue-Text"
                operationQueue.maxConcurrentOperationCount = 1

                senderQueues[threadId] = operationQueue

                return operationQueue
            }

            return existingQueue
        }
    }

    // MARK: - Job Queue

    private func add(
        jobRecord: MessageSenderJobRecord,
        transaction: SDSAnyWriteTransaction
    ) {
        owsAssertDebug(jobRecord.status == .ready)

        jobRecord.anyInsert(transaction: transaction)

        transaction.addTransactionFinalizationBlock(
            forKey: "jobQueue.\(MessageSenderJobRecord.jobRecordType.jobRecordLabel).startWorkImmediatelyIfAppIsReady"
        ) { transaction in
            self.startWorkImmediatelyIfPossible(transaction: transaction)
        }
    }

    private func startWorkImmediatelyIfPossible(transaction: SDSAnyWriteTransaction) {
        guard self.state.update(block: { $0.isSetup }) else { return }
        workStep(transaction: transaction)
    }

    private func workStep() {
        guard self.state.update(block: { $0.isSetup }) else { return }
        SSKEnvironment.shared.databaseStorageRef.write { self.workStep(transaction: $0) }
    }

    private func workStep(transaction: SDSAnyWriteTransaction) {
        let nextJob: MessageSenderJobRecord?

        do {
            nextJob = try JobRecordFinderImpl(db: DependenciesBridge.shared.db).getNextReady(transaction: transaction.asV2Write)
        } catch let error {
            Logger.error("Couldn't start next job: \(error)")
            return
        }

        guard let nextJob else {
            return
        }

        do {
            try nextJob.saveReadyAsRunning(transaction: transaction)

            let operationQueue = operationQueue(jobRecord: nextJob)
            let durableOperation = try buildOperation(jobRecord: nextJob, transaction: transaction)

            durableOperation.durableOperationDelegate = self
            owsAssertDebug(durableOperation.durableOperationDelegate != nil)

            let remainingRetries = remainingRetries(durableOperation: durableOperation)
            durableOperation.remainingRetries = remainingRetries

            transaction.addSyncCompletion {
                self.state.update { $0.runningOperations.append(durableOperation) }
                operationQueue.addOperation(durableOperation)
            }
        } catch JobError.permanentFailure(let description) {
            owsFailDebug("permanent failure: \(description)")
            nextJob.saveAsPermanentlyFailed(transaction: transaction)
        } catch JobError.obsolete {
            // TODO is this even worthwhile to have obsolete state? Should we just delete the task outright?
            nextJob.saveAsObsolete(transaction: transaction)
        } catch {
            owsFailDebug("unexpected error")
        }

        transaction.addAsyncCompletionOffMain { self.workStep() }
    }

    private func restartOldJobs() {
        guard CurrentAppContext().isMainApp else { return }

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            let runningRecords: [MessageSenderJobRecord]
            do {
                runningRecords = try JobRecordFinderImpl(db: DependenciesBridge.shared.db).allRecords(
                    status: JobRecord.Status.running,
                    transaction: transaction.asV2Write
                )
            } catch {
                Logger.error("Couldn't restart old jobs: \(error)")
                return
            }
            Logger.info("marking old `running` \(MessageSenderJobRecord.jobRecordType.jobRecordLabel) JobRecords as ready: \(runningRecords.count)")
            for jobRecord in runningRecords {
                do {
                    try jobRecord.saveRunningAsReady(transaction: transaction)
                    self.didMarkAsReady(oldJobRecord: jobRecord, transaction: transaction)
                } catch {
                    owsFailDebug("failed to mark old running records as ready error: \(error)")
                    jobRecord.saveAsPermanentlyFailed(transaction: transaction)
                }
            }
        }
    }

    private func pruneStaleJobs() {
        guard CurrentAppContext().isMainApp else { return }

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            let staleRecords: [MessageSenderJobRecord]
            do {
                staleRecords = try JobRecordFinderImpl(db: DependenciesBridge.shared.db).staleRecords(transaction: transaction.asV2Write)
            } catch {
                Logger.error("Failed to prune stale jobs! \(error)")
                return
            }

            if !staleRecords.isEmpty {
                Logger.info("Pruning stale \(MessageSenderJobRecord.jobRecordType.jobRecordLabel) job records: \(staleRecords.count).")
            }

            for jobRecord in staleRecords {
                jobRecord.anyRemove(transaction: transaction)
            }
        }
    }

    public func setUp() {
        guard !self.state.update(block: { $0.isSetup }) else {
            owsFailDebug("already ready already")
            return
        }

        DispatchQueue.global().async(.promise) {
            self.restartOldJobs()
            self.pruneStaleJobs()
        }.done { [weak self] in
            guard let self = self else {
                return
            }
            // FIXME: The returned observer token is never unregistered.
            // In practice all our JobQueues live forever, so this isn't a problem.
            NotificationCenter.default.addObserver(
                forName: SSKReachability.owsReachabilityDidChange,
                object: nil,
                queue: nil
            ) { _ in
                if SSKEnvironment.shared.reachabilityManagerRef.isReachable {
                    self.becameReachable()
                }
            }

            self.state.update { $0.isSetup = true }
            self.workStep()
        }
    }

    private func remainingRetries(durableOperation: MessageSenderOperation) -> UInt {
        let maxRetries = durableOperation.maxRetries
        let failureCount = durableOperation.jobRecord.failureCount

        guard maxRetries > failureCount else {
            return 0
        }

        return maxRetries - failureCount
    }

    private func becameReachable() {
        _ = self.runAnyQueuedRetry()
    }

    func runAnyQueuedRetry() -> OWSOperation? {
        guard let runningDurableOperation = self.state.update(block: { $0.runningOperations.first }) else {
            return nil
        }
        runningDurableOperation.runAnyQueuedRetry()

        return runningDurableOperation
    }

    // MARK: DurableOperationDelegate

    fileprivate func durableOperationDidSucceed(_ operation: MessageSenderOperation, transaction: SDSAnyWriteTransaction) {
        self.state.update { $0.runningOperations.removeAll(where: { $0 == operation }) }
        operation.jobRecord.anyRemove(transaction: transaction)
    }

    fileprivate func durableOperation(_ operation: MessageSenderOperation, didReportError: Error, transaction: SDSAnyWriteTransaction) {
        do {
            try operation.jobRecord.addFailure(transaction: transaction)
        } catch {
            owsFailDebug("error while addingFailure: \(error)")
            operation.jobRecord.saveAsPermanentlyFailed(transaction: transaction)
        }
    }

    fileprivate func durableOperation(_ operation: MessageSenderOperation, didFailWithError error: Error, transaction: SDSAnyWriteTransaction) {
        self.state.update { $0.runningOperations.removeAll(where: { $0 == operation }) }
        operation.jobRecord.saveAsPermanentlyFailed(transaction: transaction)
    }
}

private class MessageSenderOperation: OWSOperation {

    // MARK: DurableOperation

    let jobRecord: MessageSenderJobRecord
    weak public var durableOperationDelegate: MessageSenderJobQueue?

    /// 110 retries corresponds to approximately ~24hr of retry when using
    /// ``OWSOperation/retryIntervalForExponentialBackoff(failureCount:maxBackoff:)``.
    let maxRetries: UInt = 110

    // MARK: Init

    let message: PreparedOutgoingMessage
    private var future: Future<Void>?

    init(message: PreparedOutgoingMessage, jobRecord: MessageSenderJobRecord, future: Future<Void>?) {
        self.message = message
        self.jobRecord = jobRecord
        self.future = future

        super.init()
    }

    // MARK: OWSOperation

    override func run() {
        Task {
            do {
                try await SSKEnvironment.shared.messageSenderRef.sendMessage(message)
                DispatchQueue.global().async { self.reportSuccess() }
            } catch {
                DispatchQueue.global().async { self.reportError(withUndefinedRetry: error) }
            }
        }
    }

    override func didSucceed() {
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            self.durableOperationDelegate?.durableOperationDidSucceed(self, transaction: tx)
        }
        future?.resolve()
    }

    override func didReportError(_ error: Error) {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            self.durableOperationDelegate?.durableOperation(self, didReportError: error,
                                                            transaction: transaction)
        }
    }

    override var retryInterval: TimeInterval {
        OWSOperation.retryIntervalForExponentialBackoff(failureCount: jobRecord.failureCount)
    }

    override func didFail(error: Error) {
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            self.durableOperationDelegate?.durableOperation(self, didFailWithError: error, transaction: tx)

            self.message.updateWithAllSendingRecipientsMarkedAsFailed(error: error, tx: tx)
        }
        future?.reject(error)
    }
}
