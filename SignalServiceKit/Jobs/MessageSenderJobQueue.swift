//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

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
public class MessageSenderJobQueue: NSObject, JobQueue {

    @objc
    public override init() {
        super.init()

        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            self.setup()
        }
    }

    // MARK: 

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

    private var jobFutures = AtomicDictionary<String, Future<Void>>(lock: .sharedGlobal)
    private func add(
        message: PreparedOutgoingMessage,
        exclusiveToCurrentProcessIdentifier: Bool,
        isHighPriority: Bool,
        future: Future<Void>?,
        transaction: SDSAnyWriteTransaction
    ) {
        assert(AppReadiness.isAppReady || CurrentAppContext().isRunningTests)
        let messageRecord = message.dequeueForSending(tx: transaction)
        do {
            let jobRecord: MessageSenderJobRecord
            switch messageRecord {
            case .persisted(let persisted):
                jobRecord = try .init(persistedMessage: persisted, isHighPriority: isHighPriority, transaction: transaction)
            case .editMessage(let edit):
                jobRecord = try .init(editMessage: edit, isHighPriority: isHighPriority, transaction: transaction)
            case .contactSync:
                throw OWSAssertionError("Cannot create a job record for contact syncs; they can't be persisted!")
            case .story(let story):
                jobRecord = .init(storyMessage: story, isHighPriority: isHighPriority)
            case .transient(let message):
                jobRecord = .init(transientMessage: message, isHighPriority: isHighPriority)
            }
            if exclusiveToCurrentProcessIdentifier {
                jobRecord.flagAsExclusiveForCurrentProcessIdentifier()
            }
            self.add(jobRecord: jobRecord, transaction: transaction)
            if let future = future {
                jobFutures[jobRecord.uniqueId] = future
            }
        } catch {
            let messageToUpdate: TSOutgoingMessage? = {
                switch messageRecord {
                case .persisted(let persisted):
                    return persisted.message
                case .editMessage(let edit):
                    return edit.editedMessage
                case .contactSync(let message):
                    return message
                case .story(let story):
                    return story.message
                case .transient(let message):
                    return message
                }
            }()
            messageToUpdate?.update(sendingError: error, transaction: transaction)
        }
    }

    // MARK: JobQueue

    public typealias DurableOperationType = MessageSenderOperation
    public let requiresInternet: Bool = true
    public var isEnabled: Bool { true }
    public var runningOperations = AtomicArray<MessageSenderOperation>(lock: .sharedGlobal)

    @objc
    public func setup() {
        defaultSetup()
    }

    public let isSetup = AtomicBool(false, lock: .sharedGlobal)

    public func didMarkAsReady(
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

    public func buildOperation(jobRecord: MessageSenderJobRecord,
                               transaction: SDSAnyReadTransaction) throws -> MessageSenderOperation {
        let message: TSOutgoingMessage
        switch jobRecord.messageType {
        case .transient(let outgoingMessage):
            message = outgoingMessage
        case .editMessage(_, let messageForSending, _):
            message = messageForSending
        case .persisted(let messageId, _):
            if
                let fetchedMessage = TSOutgoingMessage.anyFetch(
                    uniqueId: messageId,
                    transaction: transaction
                ) as? TSOutgoingMessage
            {
                message = fetchedMessage
            } else {
                fallthrough
            }
        case .none:
            throw JobError.obsolete(description: "message no longer exists")
        }

        let operation = MessageSenderOperation(
            message: message,
            jobRecord: jobRecord,
            future: jobFutures.pop(jobRecord.uniqueId)
        )
        operation.queuePriority = jobRecord.isHighPriority ? .high : MessageSender.sendingQueuePriority(for: message, tx: transaction)

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

    var senderQueues: [String: OperationQueue] = [:]
    var mediaSenderQueues: [String: OperationQueue] = [:]
    let defaultQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "MessageSenderJobQueue-Default"
        operationQueue.maxConcurrentOperationCount = 1

        return operationQueue
    }()

    // We use a per-thread serial OperationQueue to ensure messages are delivered to the
    // service in the order the user sent them.
    public func operationQueue(jobRecord: MessageSenderJobRecord) -> OperationQueue {
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
}

public class MessageSenderOperation: OWSOperation, DurableOperation {

    // MARK: DurableOperation

    public let jobRecord: MessageSenderJobRecord
    weak public var durableOperationDelegate: MessageSenderJobQueue?

    public var operation: OWSOperation { return self }

    /// 110 retries corresponds to approximately ~24hr of retry when using
    /// ``OWSOperation/retryIntervalForExponentialBackoff(failureCount:maxBackoff:)``.
    public let maxRetries: UInt = 110

    // MARK: Init

    let message: TSOutgoingMessage
    private var future: Future<Void>?

    init(message: TSOutgoingMessage, jobRecord: MessageSenderJobRecord, future: Future<Void>?) {
        self.message = message
        self.jobRecord = jobRecord
        self.future = future

        super.init()
    }

    // MARK: OWSOperation

    override public func run() {
        Task {
            do {
                try await self.messageSender.sendMessage(message.asPreparer)
                DispatchQueue.global().async { self.reportSuccess() }
            } catch {
                DispatchQueue.global().async { self.reportError(withUndefinedRetry: error) }
            }
        }
    }

    override public func didSucceed() {
        databaseStorage.write { tx in
            self.durableOperationDelegate?.durableOperationDidSucceed(self, transaction: tx)
        }
        future?.resolve()
    }

    override public func didReportError(_ error: Error) {
        databaseStorage.write { transaction in
            self.durableOperationDelegate?.durableOperation(self, didReportError: error,
                                                            transaction: transaction)
        }
    }

    override public func retryInterval() -> TimeInterval {
        return OWSOperation.retryIntervalForExponentialBackoff(failureCount: jobRecord.failureCount)
    }

    override public func didFail(error: Error) {
        databaseStorage.write { tx in
            self.durableOperationDelegate?.durableOperation(self, didFailWithError: error, transaction: tx)

            self.message.update(sendingError: error, transaction: tx)
        }
        future?.reject(error)
    }
}
