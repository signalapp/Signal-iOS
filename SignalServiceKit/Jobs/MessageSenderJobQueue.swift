//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

private enum JobError: Error {
    case permanentFailure(description: String)
    case obsolete(description: String)
}

private struct MessageSenderJob {
    let record: MessageSenderJobRecord
    let isInMemoryOnly: Bool
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
        owsAssertDebug(jobRecord.status == .ready)
        if exclusiveToCurrentProcessIdentifier {
            // Nothing to do. Just don't insert it into the database.
        } else {
            jobRecord.anyInsert(transaction: transaction)
        }

        self.state.update {
            $0.pendingJobs.append(MessageSenderJob(record: jobRecord, isInMemoryOnly: exclusiveToCurrentProcessIdentifier))
            if let future {
                $0.jobFutures[jobRecord.uniqueId] = future
            }
        }

        transaction.addTransactionFinalizationBlock(forKey: "\(#fileID):\(#line)") { _ in
            self.startPendingJobRecordsIfPossible()
        }
    }

    // MARK: JobQueue

    private struct State {
        var isLoaded = false
        var runningOperations = [MessageSenderOperation]()
        var pendingJobs = [MessageSenderJob]()
        var jobFutures = [String: Future<Void>]()
    }
    private let state = AtomicValue<State>(State(), lock: .init())

    private func didMarkAsReady(oldJobRecord: MessageSenderJobRecord, transaction: SDSAnyWriteTransaction) {
        // TODO: Remove this method and status swapping logic entirely.
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
        job: MessageSenderJob,
        transaction: SDSAnyReadTransaction
    ) -> MessageSenderOperation? {
        guard let message = PreparedOutgoingMessage.restore(from: job.record, tx: transaction) else {
            return nil
        }

        let operation = MessageSenderOperation(
            message: message,
            job: job,
            future: self.state.update { $0.jobFutures.removeValue(forKey: job.record.uniqueId) }
        )
        operation.queuePriority = job.record.isHighPriority ? .high : message.sendingQueuePriority(tx: transaction)

        // Media messages run on their own queue to not block future non-media sends,
        // but should not start sending until all previous operations have executed.
        // We can guarantee this by adding another operation to the send queue that
        // we depend upon.
        //
        // For example, if you send text messages A, B and then media message C
        // message C should never send before A and B. However, if you send text
        // messages A, B, then media message C, followed by text message D, D cannot
        // send before A and B, but CAN send before C.
        switch job.record.messageType {
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

    private let pendingJobQueue = DispatchQueue(label: "MessageSenderJobQueue.pendingJobRecords")

    private func startPendingJobRecordsIfPossible() {
        pendingJobQueue.async {
            let pendingJobs = self.state.update {
                if $0.isLoaded {
                    let result = $0.pendingJobs
                    $0.pendingJobs = []
                    return result
                }
                return []
            }
            if !pendingJobs.isEmpty {
                SSKEnvironment.shared.databaseStorageRef.write { tx in
                    for pendingJob in pendingJobs {
                        self.startJob(pendingJob, tx: tx)
                    }
                }
            }
        }
    }

    private func startJob(_ job: MessageSenderJob, tx transaction: SDSAnyWriteTransaction) {
        let operationQueue = operationQueue(jobRecord: job.record)
        guard let durableOperation = buildOperation(job: job, transaction: transaction) else {
            Logger.warn("Dropping obsolete job record.")
            job.record.anyRemove(transaction: transaction)
            return
        }

        durableOperation.durableOperationDelegate = self
        owsAssertDebug(durableOperation.durableOperationDelegate != nil)

        transaction.addSyncCompletion {
            self.state.update { $0.runningOperations.append(durableOperation) }
            operationQueue.addOperation(durableOperation)
        }
    }

    public func setUp() {
        let jobRecordFinder = JobRecordFinderImpl<MessageSenderJobRecord>(db: DependenciesBridge.shared.db)
        Task {
            if CurrentAppContext().isMainApp {
                do {
                    let jobRecords = try await jobRecordFinder.loadRunnableJobs(updateRunnableJobRecord: { jobRecord, tx in
                        self.didMarkAsReady(oldJobRecord: jobRecord, transaction: SDSDB.shimOnlyBridge(tx))
                    })
                    let jobRecordUniqueIds = Set(jobRecords.lazy.map(\.uniqueId))
                    self.state.update {
                        var newlyPendingJobs = $0.pendingJobs
                        newlyPendingJobs.removeAll(where: { jobRecordUniqueIds.contains($0.record.uniqueId) })
                        $0.pendingJobs = jobRecords.map { MessageSenderJob(record: $0, isInMemoryOnly: false) }
                        $0.pendingJobs.append(contentsOf: newlyPendingJobs)
                    }
                } catch {
                    owsFailDebug("Couldn't load existing message send jobs: \(error)")
                }
            }

            // FIXME: The returned observer token is never unregistered.
            // In practice all our JobQueues live forever, so this isn't a problem.
            // We use "unowned" so that don't silently fail (or leak) when this changes.
            NotificationCenter.default.addObserver(
                forName: SSKReachability.owsReachabilityDidChange,
                object: nil,
                queue: nil
            ) { [unowned self] _ in
                if SSKEnvironment.shared.reachabilityManagerRef.isReachable {
                    self.becameReachable()
                }
            }

            // No matter what, mark it as loaded. This keeps things semi-functional.
            self.state.update { $0.isLoaded = true }
            startPendingJobRecordsIfPossible()
        }
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

    fileprivate func durableOperationDidComplete(_ operation: MessageSenderOperation) {
        self.state.update { $0.runningOperations.removeAll(where: { $0 == operation }) }
    }
}

private class MessageSenderOperation: OWSOperation {

    // MARK: DurableOperation

    private let job: MessageSenderJob
    weak public var durableOperationDelegate: MessageSenderJobQueue?

    /// 110 retries corresponds to approximately ~24hr of retry when using
    /// ``OWSOperation/retryIntervalForExponentialBackoff(failureCount:maxBackoff:)``.
    let maxRetries: Int = 110

    // MARK: Init

    let message: PreparedOutgoingMessage
    private var future: Future<Void>?

    init(message: PreparedOutgoingMessage, job: MessageSenderJob, future: Future<Void>?) {
        self.message = message
        self.job = job
        self.future = future

        super.init()

        self.remainingRetries = UInt(max(0, self.maxRetries - Int(job.record.failureCount)))
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
        self.durableOperationDelegate?.durableOperationDidComplete(self)
        if self.job.isInMemoryOnly {
            // Nothing to clean up
        } else {
            SSKEnvironment.shared.databaseStorageRef.write { tx in
                self.job.record.anyRemove(transaction: tx)
            }
        }
        future?.resolve()
    }

    override func didReportError(_ error: Error) {
        if self.job.isInMemoryOnly {
            self.job.record.addInMemoryFailure()
        } else {
            SSKEnvironment.shared.databaseStorageRef.write { transaction in
                self.job.record.addFailure(tx: transaction)
            }
        }
    }

    override var retryInterval: TimeInterval {
        OWSOperation.retryIntervalForExponentialBackoff(failureCount: self.job.record.failureCount)
    }

    override func didFail(error: Error) {
        self.durableOperationDelegate?.durableOperationDidComplete(self)
        if self.job.isInMemoryOnly {
            // Nothing to clean up
        } else {
            SSKEnvironment.shared.databaseStorageRef.write { tx in
                self.job.record.anyRemove(transaction: tx)
                self.message.updateWithAllSendingRecipientsMarkedAsFailed(error: error, tx: tx)
            }
        }
        future?.reject(error)
    }
}
