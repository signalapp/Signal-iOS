//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalCoreKit

/// Manages durable jobs for deleting all ``CallRecord``s.
///
/// This is a special action distinct from deleting a single ``CallRecord``, or
/// even multiple discrete ``CallRecord``s, which is handled by the
/// ``CallRecordDeleteManager``. This type is specifically for "delete them all,
/// in bulk".
///
/// - SeeAlso ``CallRecordDeleteManager``
public class CallRecordDeleteAllJobQueue {
    public enum DeleteAllBeforeOptions {
        case callRecord(CallRecord)
        case timestamp(UInt64)
    }

    private let jobRunnerFactory: CallRecordDeleteAllJobRunnerFactory
    private let jobQueueRunner: JobQueueRunner<
        JobRecordFinderImpl<CallRecordDeleteAllJobRecord>,
        CallRecordDeleteAllJobRunnerFactory
    >

    private let recipientDatabaseTable: RecipientDatabaseTable
    private let threadStore: ThreadStore

    public init(
        callRecordDeleteManager: CallRecordDeleteManager,
        callRecordQuerier: CallRecordQuerier,
        callRecordStore: CallRecordStore,
        db: DB,
        messageSenderJobQueue: MessageSenderJobQueue,
        recipientDatabaseTable: RecipientDatabaseTable,
        threadStore: ThreadStore
    ) {
        self.jobRunnerFactory = CallRecordDeleteAllJobRunnerFactory(
            callRecordDeleteManager: callRecordDeleteManager,
            callRecordQuerier: callRecordQuerier,
            callRecordStore: callRecordStore,
            db: db,
            messageSenderJobQueue: messageSenderJobQueue,
            recipientDatabaseTable: recipientDatabaseTable,
            threadStore: threadStore
        )
        self.jobQueueRunner = JobQueueRunner(
            canExecuteJobsConcurrently: false,
            db: db,
            jobFinder: JobRecordFinderImpl(db: db),
            jobRunnerFactory: self.jobRunnerFactory
        )

        self.recipientDatabaseTable = recipientDatabaseTable
        self.threadStore = threadStore
    }

    func start(appContext: AppContext) {
        jobQueueRunner.start(shouldRestartExistingJobs: appContext.isMainApp)
    }

    /// Add a "delete all call records" job to the queue.
    ///
    /// - Parameter sendDeleteAllSyncMessage
    /// Whether we should send an ``OutgoingCallLogEventSyncMessage`` about this
    /// deletion.
    /// - Parameter deleteAllBeforeTimestamp
    /// The timestamp before which to delete all call records.
    public func addJob(
        sendDeleteAllSyncMessage: Bool,
        deleteAllBefore: DeleteAllBeforeOptions,
        tx: SDSAnyWriteTransaction
    ) {
        let jobRecord: CallRecordDeleteAllJobRecord

        switch deleteAllBefore {
        case .callRecord(let callRecord):
            guard
                let conversationId: CallRecordDeleteAllJobRecord.ConversationId = callRecord
                    .conversationId(
                        threadStore: threadStore,
                        recipientDatabaseTable: recipientDatabaseTable,
                        tx: tx.asV2Read
                    )
            else { return }

            jobRecord = CallRecordDeleteAllJobRecord(
                sendDeleteAllSyncMessage: sendDeleteAllSyncMessage,
                deleteAllBeforeCallId: callRecord.callId,
                deleteAllBeforeConversationId: conversationId,
                deleteAllBeforeTimestamp: callRecord.callBeganTimestamp
            )
        case .timestamp(let timestamp):
            jobRecord = CallRecordDeleteAllJobRecord(
                sendDeleteAllSyncMessage: sendDeleteAllSyncMessage,
                deleteAllBeforeCallId: nil,
                deleteAllBeforeConversationId: nil,
                deleteAllBeforeTimestamp: timestamp
            )
        }

        jobRecord.anyInsert(transaction: tx)

        tx.addSyncCompletion {
            self.jobQueueRunner.addPersistedJob(jobRecord)
        }
    }
}

// MARK: -

private class CallRecordDeleteAllJobRunner: JobRunner {
    typealias JobRecordType = CallRecordDeleteAllJobRecord

    private enum Constants {
        static let maxRetries: UInt = 110
        static let deletionBatchSize: UInt = 500
    }

    private var logger: CallRecordLogger { .shared }

    private let callRecordDeleteManager: CallRecordDeleteManager
    private let callRecordQuerier: CallRecordQuerier
    private let callRecordStore: CallRecordStore
    private let db: DB
    private let messageSenderJobQueue: MessageSenderJobQueue
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let threadStore: ThreadStore

    init(
        callRecordDeleteManager: CallRecordDeleteManager,
        callRecordQuerier: CallRecordQuerier,
        callRecordStore: CallRecordStore,
        db: DB,
        messageSenderJobQueue: MessageSenderJobQueue,
        recipientDatabaseTable: RecipientDatabaseTable,
        threadStore: ThreadStore
    ) {
        self.callRecordDeleteManager = callRecordDeleteManager
        self.callRecordQuerier = callRecordQuerier
        self.callRecordStore = callRecordStore
        self.db = db
        self.messageSenderJobQueue = messageSenderJobQueue
        self.recipientDatabaseTable = recipientDatabaseTable
        self.threadStore = threadStore
    }

    // MARK: -

    func runJobAttempt(
        _ jobRecord: CallRecordDeleteAllJobRecord
    ) async -> JobAttemptResult {
        return await JobAttemptResult.executeBlockWithDefaultErrorHandler(
            jobRecord: jobRecord,
            retryLimit: Constants.maxRetries,
            db: DependenciesBridge.shared.db,
            block: {
                try await _runJobAttempt(jobRecord)
            }
        )
    }

    func didFinishJob(
        _ jobRecordId: JobRecord.RowId,
        result: JobResult
    ) async {
        switch result.ranSuccessfullyOrError {
        case .success:
            break
        case .failure(let failure):
            logger.error("Failed to delete all call records! \(failure)")
        }
    }

    private func _runJobAttempt(
        _ jobRecord: CallRecordDeleteAllJobRecord
    ) async throws {
        let deleteBeforeTimestamp: UInt64 = {
            /// We'll prefer the timestamp on the call record if we have it.
            /// They should be identical in the 99.999% case, but there's a
            /// chance something updated the call's timestamp since this job
            /// record was created; and either way the goal is to use an actual
            /// call as the boundary for the delete-all rather than an arbitrary
            /// timestamp if possible.
            guard
                let callId = jobRecord.deleteAllBeforeCallId,
                let conversationId = jobRecord.deleteAllBeforeConversationId,
                let referencedCallRecord: CallRecord = db.read(block: { tx -> CallRecord? in
                    return .hydrate(
                        callId: callId,
                        conversationId: conversationId,
                        callRecordStore: callRecordStore,
                        recipientDatabaseTable: recipientDatabaseTable,
                        threadStore: threadStore,
                        tx: tx
                    )
                })
            else {
                return jobRecord.deleteAllBeforeTimestamp
            }

            return referencedCallRecord.callBeganTimestamp
        }()

        logger.info("Attempting to delete all call records before \(deleteBeforeTimestamp).")

        let deletedCount = await TimeGatedBatch.processAllAsync(db: db) { tx in
            return self.deleteSomeCallRecords(
                beforeTimestamp: deleteBeforeTimestamp,
                tx: tx
            )
        }

        logger.info("Deleted \(deletedCount) calls.")

        await db.awaitableWrite { tx in
            let sdsTx: SDSAnyWriteTransaction = SDSDB.shimOnlyBridge(tx)

            if jobRecord.sendDeleteAllSyncMessage {
                self.logger.info("Sending delete-all-calls sync message.")

                self.sendClearCallLogSyncMessage(
                    callId: jobRecord.deleteAllBeforeCallId,
                    conversationId: jobRecord.deleteAllBeforeConversationId,
                    beforeTimestamp: deleteBeforeTimestamp,
                    tx: sdsTx
                )
            }

            jobRecord.anyRemove(transaction: sdsTx)
        }
    }

    /// Deletes a batch of call records with timestamps before the given value.
    ///
    /// - Returns
    /// The number of call records deleted. A return value of 0 indicates
    /// deletion has finished, either because there are no more records to
    /// delete or because this method ran into an unexpected, unrecoverable
    /// error.
    private func deleteSomeCallRecords(
        beforeTimestamp: UInt64,
        tx: DBWriteTransaction
    ) -> Int {
        /// The passed timestamp will be the timestamp of the most-recent call
        /// when the user initiated the delete-all action. So as to ensure we
        /// delete that most-recent call, we'll shim the timestamp forward.
        let beforeTimestamp = beforeTimestamp + 1

        guard let cursor = callRecordQuerier.fetchCursor(
            ordering: .descendingBefore(timestamp: beforeTimestamp),
            tx: tx
        ) else { return 0 }

        do {
            let callRecordsToDelete = try cursor.drain(
                maxResults: Constants.deletionBatchSize
            )

            if !callRecordsToDelete.isEmpty {
                /// We disable the sync message here, since we're instead going
                /// to send a different sync message when we're done deleting
                /// all the records.
                let sendSyncMessageOnDelete = false

                callRecordDeleteManager.deleteCallRecordsAndAssociatedInteractions(
                    callRecords: callRecordsToDelete,
                    sendSyncMessageOnDelete: sendSyncMessageOnDelete,
                    tx: tx
                )

                return callRecordsToDelete.count
            }
        } catch let error {
            owsFailBeta("Failed to get call records from cursor! \(error)")
        }

        return 0
    }

    private func sendClearCallLogSyncMessage(
        callId: UInt64?,
        conversationId: CallRecordDeleteAllJobRecord.ConversationId?,
        beforeTimestamp: UInt64,
        tx: SDSAnyWriteTransaction
    ) {
        guard let localThread = TSContactThread.getOrCreateLocalThread(
            transaction: tx
        ) else { return }

        let outgoingCallLogEventSyncMessage = OutgoingCallLogEventSyncMessage(
            callLogEvent: OutgoingCallLogEventSyncMessage.CallLogEvent(
                eventType: .cleared,
                callId: callId,
                conversationId: conversationId,
                timestamp: beforeTimestamp
            ),
            thread: localThread,
            tx: tx
        )

        messageSenderJobQueue.add(
            message: outgoingCallLogEventSyncMessage.asPreparer,
            transaction: tx
        )
    }
}

// MARK: -

private class CallRecordDeleteAllJobRunnerFactory: JobRunnerFactory {
    typealias JobRunnerType = CallRecordDeleteAllJobRunner

    private let callRecordDeleteManager: CallRecordDeleteManager
    private let callRecordQuerier: CallRecordQuerier
    private let callRecordStore: CallRecordStore
    private let db: DB
    private let messageSenderJobQueue: MessageSenderJobQueue
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let threadStore: ThreadStore

    init(
        callRecordDeleteManager: CallRecordDeleteManager,
        callRecordQuerier: CallRecordQuerier,
        callRecordStore: CallRecordStore,
        db: DB,
        messageSenderJobQueue: MessageSenderJobQueue,
        recipientDatabaseTable: RecipientDatabaseTable,
        threadStore: ThreadStore
    ) {
        self.callRecordDeleteManager = callRecordDeleteManager
        self.callRecordQuerier = callRecordQuerier
        self.callRecordStore = callRecordStore
        self.db = db
        self.messageSenderJobQueue = messageSenderJobQueue
        self.recipientDatabaseTable = recipientDatabaseTable
        self.threadStore = threadStore
    }

    func buildRunner() -> CallRecordDeleteAllJobRunner {
        return CallRecordDeleteAllJobRunner(
            callRecordDeleteManager: callRecordDeleteManager,
            callRecordQuerier: callRecordQuerier,
            callRecordStore: callRecordStore,
            db: db,
            messageSenderJobQueue: messageSenderJobQueue,
            recipientDatabaseTable: recipientDatabaseTable,
            threadStore: threadStore
        )
    }
}
