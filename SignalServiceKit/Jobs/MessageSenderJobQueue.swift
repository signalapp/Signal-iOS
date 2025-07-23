//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Durably enqueues outgoing messages.
///
/// Calls `MessageSender` to send messages.
///
/// # Retries
///
/// Both `MessageSenderJobQueue` and `MessageSender` implement retry
/// handling.
///
/// The latter (`MessageSender`) retries only specific errors that the
/// server indicates are immediately retryable (e.g., "you are missing a
/// device for the destination; add it and try again"). These retries aren't
/// "configurable", nor do they have any backoff. They are expected when the
/// system is operating normally, and they are part of the expected flow for
/// sending a message.
///
/// The former (`MessageSenderJobQueue`) retries generic/unknown failures
/// (e.g., "the server gave us a 5xx error; try after a few seconds", "there
/// isn't any Internet; try when we reconnect"). These retries are
/// "configurable", meaning we can decide how many occur and how often they
/// occur. These only happen when something is operating abnormally (e.g.,
/// "the server is down", "the user isn't connected to the network").
///
/// Both respect `IsRetryableProvider` and only retry retryable errors.
public class MessageSenderJobQueue {
    private var jobSerializer = CompletionSerializer()

    public init(appReadiness: AppReadiness) {
        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            self.setUp()
        }
    }

    public func add(
        message: PreparedOutgoingMessage,
        limitToCurrentProcessLifetime: Bool = false,
        isHighPriority: Bool = false,
        transaction: DBWriteTransaction
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
        transaction: DBWriteTransaction
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
        transaction: DBWriteTransaction
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
            $0.pendingJobs.append(Job(record: jobRecord, isInMemoryOnly: exclusiveToCurrentProcessIdentifier))
            if let future {
                $0.jobFutures[jobRecord.uniqueId] = future
            }
        }

        transaction.addSyncCompletion {
            self.startPendingJobRecordsIfPossible()
        }
    }

    // MARK: JobQueue

    /// A job that needs to be executed.
    private struct Job {
        let record: MessageSenderJobRecord
        let isInMemoryOnly: Bool
    }

    /// A job that's been queued but hasn't started yet.
    private struct QueuedOperationState {
        let job: Job
        let message: PreparedOutgoingMessage
        let future: Future<Void>?
    }

    /// A job that's actively executing; it may be suspended due to errors.
    private struct ActiveOperationState {
        let job: Job
        let message: PreparedOutgoingMessage
        let future: Future<Void>?
        let externalRetryTriggerState = AtomicValue(ExternalRetryTriggerState(), lock: .init())

        init(queuedOperation: QueuedOperationState) {
            self.job = queuedOperation.job
            self.message = queuedOperation.message
            self.future = queuedOperation.future
        }

        /// "Consume" any triggers that have already fired.
        ///
        /// Callers should do this before performing any retryable action that might
        /// fail due to one of the triggers. For example, if a message might fail to
        /// send because there's no Internet, this should be called before
        /// attempting to send the message.
        ///
        /// This pattern ensures no triggers are missed due to concurrently
        /// executing operations & triggers. For example, if Internet isn't
        /// available, you start sending a message, Internet becomes available, and
        /// then the message fails to send with a "network failure" error, we want
        /// to immediately retry. If we don't retry, we'd be stuck until something
        /// *else* triggers a retry (e.g., losing & gaining Internet again).
        func clearExternalRetryTriggers() {
            self.externalRetryTriggerState.update {
                $0.reportedExternalRetryTriggers = []
            }
        }

        /// Trigger any jobs that failed because of `failureReason`.
        ///
        /// This also triggers any in-progress jobs (after they fail) that fail
        /// because of `failureReason`. This avoids race conditions (see above).
        func reportExternalRetryTrigger(_ externalRetryTrigger: ExternalRetryTriggers) {
            self.externalRetryTriggerState.update {
                $0.reportedExternalRetryTriggers.formUnion(externalRetryTrigger)
                notifyIfPossible(mutableState: &$0)
            }
        }

        /// Waits until any of `failureReasons` has been triggered.
        func waitForAnyExternalRetryTrigger(fromExternalRetryTriggers externalRetryTriggers: ExternalRetryTriggers) async throws {
            let waitingContinuation = CancellableContinuation<Void>()
            self.externalRetryTriggerState.update {
                $0.waitingState = (waitingContinuation, externalRetryTriggers)
                notifyIfPossible(mutableState: &$0)
            }
            return try await waitingContinuation.wait()
        }

        private func notifyIfPossible(mutableState: inout ExternalRetryTriggerState) {
            guard let waitingState = mutableState.waitingState else {
                return
            }
            if mutableState.reportedExternalRetryTriggers.isDisjoint(with: waitingState.externalRetryTriggers) {
                return
            }
            waitingState.continuation.resume(with: .success(()))
        }
    }

    /// Tracks information about failures with external retry triggers.
    private struct ExternalRetryTriggerState {
        var reportedExternalRetryTriggers: ExternalRetryTriggers = []
        var waitingState: (continuation: CancellableContinuation<Void>, externalRetryTriggers: ExternalRetryTriggers)?
    }

    /// Tracks failure types with external retry triggers.
    ///
    /// For example, a "network failure" error can be triggered before its
    /// timer-based retry interval if Internet suddenly becomes available.
    /// Conversely, 5xx errors are transient but can only be retried when their
    /// timer-based retry fires, so they're not included here.
    private struct ExternalRetryTriggers: OptionSet {
        let rawValue: Int

        static let networkBecameReachable = ExternalRetryTriggers(rawValue: 1 << 0)
        static let chatConnectionOpened = ExternalRetryTriggers(rawValue: 1 << 1)
    }

    private enum JobPriority: Hashable {
        case high
        case renderableContent
        case low
    }

    private struct State {
        var isLoaded = false
        var pendingJobs = [Job]()
        var isTransferringPendingJobs = false
        var queueStates = [QueueKey: QueueState]()
        var jobFutures = [String: Future<Void>]()

        /// Resumed when `isDone` is true.
        var onDone = [NSObject: Monitor.Continuation]()
        var isDone: Bool {
            return isLoaded && pendingJobs.isEmpty && !isTransferringPendingJobs && queueStates.isEmpty
        }
    }

    private struct QueueKey: Hashable {
        let threadId: String?
        let priority: JobPriority
    }

    private struct QueueState {
        var activeOperations = [ActiveOperationState]()
        var queuedOperations = [QueuedOperationState]()

        var isEmpty: Bool {
            return activeOperations.isEmpty && queuedOperations.isEmpty
        }

        var hasExactlyOneActiveOperationThatUsesTheMediaQueue: Bool {
            return activeOperations.count == 1 && activeOperations[0].job.record.useMediaQueue
        }
    }

    private let state = AtomicValue<State>(State(), lock: .init())

    private func didMarkAsReady(oldJobRecord: MessageSenderJobRecord, transaction: DBWriteTransaction) {
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

    private let pendingJobQueue = DispatchQueue(label: "MessageSenderJobQueue.pendingJobRecords")

    private func startPendingJobRecordsIfPossible() {
        // Use a queue to ensure "pendingJobs" get passed to queueJob in the correct order.
        pendingJobQueue.async {
            let pendingJobs = self.state.update {
                if $0.isLoaded {
                    let result = $0.pendingJobs
                    $0.pendingJobs = []
                    return result
                }
                $0.isTransferringPendingJobs = true
                return []
            }
            defer {
                self.updateStateAndNotify {
                    $0.isTransferringPendingJobs = false
                }
            }
            if !pendingJobs.isEmpty {
                SSKEnvironment.shared.databaseStorageRef.write { tx in
                    for pendingJob in pendingJobs {
                        self.queueJob(pendingJob, tx: tx)
                    }
                }
            }
        }
    }

    private func queueJob(_ job: Job, tx transaction: DBWriteTransaction) {
        let future = self.state.update { $0.jobFutures.removeValue(forKey: job.record.uniqueId) }

        guard let message = PreparedOutgoingMessage.restore(from: job.record, tx: transaction) else {
            if !job.isInMemoryOnly {
                job.record.anyRemove(transaction: transaction)
            }
            future?.reject(OWSAssertionError("Can't start job that can't be prepared."))
            return
        }

        let sendPriority: JobPriority
        if job.record.isHighPriority {
            sendPriority = .high
        } else if message.hasRenderableContent(tx: transaction) {
            sendPriority = .renderableContent
        } else {
            sendPriority = .low
        }

        let operation = QueuedOperationState(
            job: job,
            message: message,
            future: future
        )

        let queueKey = QueueKey(threadId: job.record.threadId, priority: sendPriority)
        self.jobSerializer.addOrderedSyncCompletion(tx: transaction) {
            self.state.update {
                $0.queueStates[queueKey, default: QueueState()].queuedOperations.append(operation)
            }
            self.startNextJobIfNeeded(queueKey: queueKey)
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
                        $0.pendingJobs = jobRecords.map { Job(record: $0, isInMemoryOnly: false) }
                        $0.pendingJobs.append(contentsOf: newlyPendingJobs)
                    }
                } catch {
                    owsFailDebug("Couldn't load existing message send jobs: \(error)")
                }
            }

            // FIXME: The returned observer token is never unregistered.
            // In practice all our JobQueues live forever, so this isn't a problem.

            // We use "unowned" so that don't silently fail (or leak) when this changes.
            let becameReachableBlock = { [unowned self] in
                self.becameReachable()
            }
            NotificationCenter.default.addObserver(
                forName: SSKReachability.owsReachabilityDidChange,
                object: nil,
                queue: nil
            ) { _ in
                if SSKEnvironment.shared.reachabilityManagerRef.isReachable {
                    becameReachableBlock()
                }
            }
            let chatConnectionOpenedBlock = { [unowned self] in
                self.reportExternalRetryTrigger(.chatConnectionOpened)
            }
            NotificationCenter.default.addObserver(
                forName: OWSChatConnection.chatConnectionStateDidChange,
                object: nil,
                queue: nil,
                using: { note in
                    let connectionState = note.userInfo![OWSChatConnection.chatConnectionStateKey]! as! OWSChatConnectionState
                    if connectionState == .open {
                        chatConnectionOpenedBlock()
                    }
                },
            )

            // No matter what, mark it as loaded. This keeps things semi-functional.
            self.updateStateAndNotify { $0.isLoaded = true }
            startPendingJobRecordsIfPossible()
        }
    }

    func becameReachable() {
        self.reportExternalRetryTrigger(.networkBecameReachable)
    }

    private func reportExternalRetryTrigger(_ externalRetryTrigger: ExternalRetryTriggers) {
        self.state.update {
            for (_, queueState) in $0.queueStates {
                for activeOperation in queueState.activeOperations {
                    activeOperation.reportExternalRetryTrigger(externalRetryTrigger)
                }
            }
        }
    }

    private func startNextJobIfNeeded(queueKey: QueueKey) {
        self.updateStateAndNotify {
            var queueState = $0.queueStates[queueKey, default: QueueState()]

            // If nothing is running, start *any* operation that needs to be started.
            if queueState.activeOperations.isEmpty {
                if let nextIndex = queueState.queuedOperations.indices.first {
                    startNextJob(atQueuedIndex: nextIndex, forQueueKey: queueKey, in: &queueState)
                }
            }

            // Non-media messages get an extra slot to run so that they don't get stuck
            // behind media messages. If the first slot got filled by a media message,
            // this one can be filled by a non-media message. If the first slot is
            // filled by a non-media message, we can't schedule anything else.

            // For example, if you send A, B, C, and D, where C is media and everything
            // else is a text message, then only orderings ABCD and ABDC are allowed.
            // This block exists to start sending "D" concurrently with "C".
            if queueState.hasExactlyOneActiveOperationThatUsesTheMediaQueue {
                if let nextIndex = queueState.queuedOperations.firstIndex(where: { !$0.job.record.useMediaQueue }) {
                    startNextJob(atQueuedIndex: nextIndex, forQueueKey: queueKey, in: &queueState)
                }
            }

            $0.queueStates[queueKey] = queueState.isEmpty ? nil : queueState
        }
    }

    private func startNextJob(atQueuedIndex index: Int, forQueueKey queueKey: QueueKey, in queueState: inout QueueState) {
        let queuedOperation = queueState.queuedOperations.remove(at: index)
        let activeOperation = ActiveOperationState(queuedOperation: queuedOperation)
        queueState.activeOperations.append(activeOperation)
        Task(priority: Self.taskPriority(forJobPriority: queueKey.priority)) {
            await self.runOperation(activeOperation)
            self.state.update {
                $0.queueStates[queueKey]!.activeOperations.removeAll(where: { $0.job.record.uniqueId == activeOperation.job.record.uniqueId })
            }
            startNextJobIfNeeded(queueKey: queueKey)
        }
    }

    private static func taskPriority(forJobPriority jobPriority: JobPriority) -> TaskPriority {
        switch jobPriority {
        case .high, .renderableContent:
            return .userInitiated
        case .low:
            return .medium
        }
    }

    /// Runs a job to send a particular message.
    ///
    /// This method returns after the operation reaches a terminal result and
    /// the job record has been deleted.
    private func runOperation(_ operation: ActiveOperationState) async {
        let result = await Result { try await self._runOperation(operation) }
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            if !operation.job.isInMemoryOnly {
                operation.job.record.anyRemove(transaction: tx)
            }
            if case .failure(let error) = result {
                operation.message.updateWithAllSendingRecipientsMarkedAsFailed(error: error, tx: tx)
            }
        }
        switch result {
        case .success(()):
            operation.future?.resolve()
        case .failure(let error):
            operation.future?.reject(error)
        }
    }

    /// Runs a job to send a particular message.
    ///
    /// This methods returns after the operation has reached a terminal result
    /// but before that result has been processed.
    private func _runOperation(_ operation: ActiveOperationState) async throws {
        var attemptCount = Int(operation.job.record.failureCount)
        let maxRetries = 110
        while true {
            assert(!Task.isCancelled, "Cancellation isn't supported.")
            do {
                operation.clearExternalRetryTriggers()
                try await SSKEnvironment.shared.messageSenderRef.sendMessage(operation.message)
                return
            } catch where error.isRetryable && !error.isFatalError && attemptCount < maxRetries {
                attemptCount += 1
                if !operation.job.isInMemoryOnly {
                    await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                        operation.job.record.addFailure(tx: tx)
                    }
                }
                var externalRetryTriggers: ExternalRetryTriggers = []
                // If there's a network failure, this is an external error, so we want to
                // retry as soon as we reconnect.
                if error.isNetworkFailure {
                    externalRetryTriggers.insert(.chatConnectionOpened)
                    // TODO: Remove this after REST is gone -- it'll no longer be relevant.
                    externalRetryTriggers.insert(.networkBecameReachable)
                }
                // If there's a timeout, we interrupted the request ourselves, and sending
                // the same request again on a new connection will typically result in the
                // same outcome, so we want to perform exponential backoff before retrying.
                // However, if Reachability indicates that something has changed, we might
                // be on a better network, and it may be worth retrying immediately.
                if error.isTimeout {
                    externalRetryTriggers.insert(.networkBecameReachable)
                }
                try? await withCooperativeTimeout(
                    seconds: OWSOperation.retryIntervalForExponentialBackoff(failureCount: attemptCount, maxAverageBackoff: 14.1 * .minute),
                    operation: { try await operation.waitForAnyExternalRetryTrigger(fromExternalRetryTriggers: externalRetryTriggers) }
                )
            }
        }
    }

    // MARK: - Notifications

    private let doneCondition = Monitor.Condition<State>(
        isSatisfied: \.isDone,
        waiters: \.onDone,
    )

    private func updateStateAndNotify<T>(_ block: (inout State) -> T) -> T {
        return Monitor.updateAndNotify(
            in: state,
            block: block,
            conditions: doneCondition,
        )
    }

    public func waitUntilDone() async throws(CancellationError) {
        return try await Monitor.waitForCondition(doneCondition, in: state)
    }
}
