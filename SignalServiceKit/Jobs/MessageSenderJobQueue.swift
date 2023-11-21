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

    @objc(addMessage:transaction:)
    @available(swift, obsoleted: 1.0)
    public func add(message: OutgoingMessagePreparer, transaction: SDSAnyWriteTransaction) {
        self.add(
            message: message,
            removeMessageAfterSending: false,
            exclusiveToCurrentProcessIdentifier: false,
            isHighPriority: false,
            future: nil,
            transaction: transaction
        )
    }

    public func add(
        message: OutgoingMessagePreparer,
        limitToCurrentProcessLifetime: Bool = false,
        isHighPriority: Bool = false,
        transaction: SDSAnyWriteTransaction
    ) {
        self.add(
            message: message,
            removeMessageAfterSending: false,
            exclusiveToCurrentProcessIdentifier: limitToCurrentProcessLifetime,
            isHighPriority: isHighPriority,
            future: nil,
            transaction: transaction
        )
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func addPromise(
        message: OutgoingMessagePreparer,
        removeMessageAfterSending: Bool,
        limitToCurrentProcessLifetime: Bool,
        isHighPriority: Bool,
        transaction: SDSAnyWriteTransaction
    ) -> AnyPromise {
        return AnyPromise(add(
            .promise,
            message: message,
            removeMessageAfterSending: removeMessageAfterSending,
            limitToCurrentProcessLifetime: limitToCurrentProcessLifetime,
            isHighPriority: isHighPriority,
            transaction: transaction
        ))
    }

    public func add(
        _ namespace: PromiseNamespace,
        message: OutgoingMessagePreparer,
        removeMessageAfterSending: Bool = false,
        limitToCurrentProcessLifetime: Bool = false,
        isHighPriority: Bool = false,
        transaction: SDSAnyWriteTransaction
    ) -> Promise<Void> {
        return Promise { future in
            self.add(
                message: message,
                removeMessageAfterSending: false,
                exclusiveToCurrentProcessIdentifier: limitToCurrentProcessLifetime,
                isHighPriority: isHighPriority,
                future: future,
                transaction: transaction
            )
        }
    }

    @objc(addMediaMessage:dataSource:contentType:sourceFilename:caption:albumMessageId:isTemporaryAttachment:)
    public func add(mediaMessage: TSOutgoingMessage,
                    dataSource: DataSource,
                    contentType: String,
                    sourceFilename: String?,
                    caption: String?,
                    albumMessageId: String?,
                    isTemporaryAttachment: Bool) {
        let attachmentInfo = OutgoingAttachmentInfo(dataSource: dataSource,
                                                    contentType: contentType,
                                                    sourceFilename: sourceFilename,
                                                    caption: caption,
                                                    albumMessageId: albumMessageId,
                                                    isBorderless: false,
                                                    isLoopingVideo: false)
        let message = OutgoingMessagePreparer(mediaMessage, unsavedAttachmentInfos: [attachmentInfo])
        add(message: message, isTemporaryAttachment: isTemporaryAttachment)
    }

    @objc(addMessage:isTemporaryAttachment:)
    public func add(message: OutgoingMessagePreparer, isTemporaryAttachment: Bool) {
        databaseStorage.asyncWrite { transaction in
            self.add(
                message: message,
                removeMessageAfterSending: isTemporaryAttachment,
                exclusiveToCurrentProcessIdentifier: false,
                isHighPriority: false,
                future: nil,
                transaction: transaction
            )
        }
    }

    private var jobFutures = AtomicDictionary<String, Future<Void>>()
    private func add(
        message: OutgoingMessagePreparer,
        removeMessageAfterSending: Bool,
        exclusiveToCurrentProcessIdentifier: Bool,
        isHighPriority: Bool,
        future: Future<Void>?,
        transaction: SDSAnyWriteTransaction
    ) {
        assert(AppReadiness.isAppReady || CurrentAppContext().isRunningTests)
        do {
            let messageRecord = try message.prepareMessage(transaction: transaction)
            let jobRecord = try MessageSenderJobRecord(
                message: messageRecord,
                removeMessageAfterSending: removeMessageAfterSending,
                isHighPriority: isHighPriority,
                label: self.jobRecordLabel,
                transaction: transaction
            )
            if exclusiveToCurrentProcessIdentifier {
                jobRecord.flagAsExclusiveForCurrentProcessIdentifier()
            }
            self.add(jobRecord: jobRecord, transaction: transaction)
            if let future = future {
                jobFutures[jobRecord.uniqueId] = future
            }
        } catch {
            message.unpreparedMessage.update(sendingError: error, transaction: transaction)
        }
    }

    // MARK: JobQueue

    public typealias DurableOperationType = MessageSenderOperation
    @objc
    public static let jobRecordLabel: String = "MessageSender"
    public let requiresInternet: Bool = true
    public var isEnabled: Bool { true }
    public var runningOperations = AtomicArray<MessageSenderOperation>()

    public var jobRecordLabel: String {
        return type(of: self).jobRecordLabel
    }

    @objc
    public func setup() {
        defaultSetup()
    }

    public let isSetup = AtomicBool(false)

    public func didMarkAsReady(oldJobRecord: MessageSenderJobRecord,
                               transaction: SDSAnyWriteTransaction) {
        if let messageId = oldJobRecord.messageId,
           let message = TSOutgoingMessage.anyFetch(uniqueId: messageId,
                                                    transaction: transaction) as? TSOutgoingMessage {
            message.updateAllUnsentRecipientsAsSending(transaction: transaction)
        }
    }

    public func buildOperation(jobRecord: MessageSenderJobRecord,
                               transaction: SDSAnyReadTransaction) throws -> MessageSenderOperation {
        let message: TSOutgoingMessage
        if let invisibleMessage = jobRecord.invisibleMessage {
            message = invisibleMessage
        } else if let messageId = jobRecord.messageId,
                  let fetchedMessage = TSOutgoingMessage.anyFetch(uniqueId: messageId,
                                                                  transaction: transaction) as? TSOutgoingMessage {
            message = fetchedMessage
        } else {
            throw JobError.obsolete(description: "message no longer exists")
        }

        let operation = MessageSenderOperation(
            message: message,
            jobRecord: jobRecord,
            future: jobFutures.pop(jobRecord.uniqueId)
        )
        operation.queuePriority = jobRecord.isHighPriority ? .high : MessageSender.queuePriority(for: message)

        // Media messages run on their own queue to not block future non-media sends,
        // but should not start sending until all previous operations have executed.
        // We can guarantee this by adding another operation to the send queue that
        // we depend upon.
        //
        // For example, if you send text messages A, B and then media message C
        // message C should never send before A and B. However, if you send text
        // messages A, B, then media message C, followed by text message D, D cannot
        // send before A and B, but CAN send before C.
        if jobRecord.isMediaMessage, let sendQueue = senderQueues[message.uniqueThreadId] {
            let orderMaintainingOperation = Operation()
            orderMaintainingOperation.queuePriority = operation.queuePriority
            sendQueue.addOperation(orderMaintainingOperation)
            operation.addDependency(orderMaintainingOperation)
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

        if jobRecord.isMediaMessage {
            guard let existingQueue = mediaSenderQueues[threadId] else {
                let operationQueue = OperationQueue()
                operationQueue.name = "MessageSenderJobQueue-Media"
                operationQueue.maxConcurrentOperationCount = 1

                mediaSenderQueues[threadId] = operationQueue

                return operationQueue
            }

            return existingQueue
        } else {
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
        self.messageSender.sendMessage(message.asPreparer,
                                       success: {
                                        self.reportSuccess()
        },
                                       failure: { error in
                                        self.reportError(withUndefinedRetry: error)
        })
    }

    override public func didSucceed() {
        databaseStorage.write { tx in
            self.durableOperationDelegate?.durableOperationDidSucceed(self, transaction: tx)
            if self.jobRecord.removeMessageAfterSending {
                // We only need to delete messages that were saved to the database.
                if let messageUniqueId = self.jobRecord.messageId {
                    TSInteraction.anyFetch(uniqueId: messageUniqueId, transaction: tx)?.anyRemove(transaction: tx)
                }
                // But we might have saved attachments for `invisibleMessage`s.
                self.message.removeTemporaryAttachments(with: tx)
            }
        }
        future?.resolve()
    }

    override public func didReportError(_ error: Error) {
        Logger.debug("remainingRetries: \(self.remainingRetries)")

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

            if self.jobRecord.removeMessageAfterSending {
                // We only need to delete messages that were saved to the database.
                if let messageUniqueId = self.jobRecord.messageId {
                    TSInteraction.anyFetch(uniqueId: messageUniqueId, transaction: tx)?.anyRemove(transaction: tx)
                }
            }
        }
        future?.reject(error)
    }
}
