//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

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

    private let callRecordConversationIdAdapter: CallRecordSyncMessageConversationIdAdapter

    public init(
        callRecordConversationIdAdapter: CallRecordSyncMessageConversationIdAdapter,
        callRecordQuerier: CallRecordQuerier,
        db: any DB,
        interactionDeleteManager: InteractionDeleteManager,
        messageSenderJobQueue: MessageSenderJobQueue
    ) {
        self.jobRunnerFactory = CallRecordDeleteAllJobRunnerFactory(
            callRecordConversationIdAdapter: callRecordConversationIdAdapter,
            callRecordQuerier: callRecordQuerier,
            db: db,
            interactionDeleteManager: interactionDeleteManager,
            messageSenderJobQueue: messageSenderJobQueue
        )
        self.jobQueueRunner = JobQueueRunner(
            canExecuteJobsConcurrently: false,
            db: db,
            jobFinder: JobRecordFinderImpl(db: db),
            jobRunnerFactory: self.jobRunnerFactory
        )

        self.callRecordConversationIdAdapter = callRecordConversationIdAdapter
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
            let conversationId: Data
            do {
                conversationId = try callRecordConversationIdAdapter.getConversationId(callRecord: callRecord, tx: tx.asV2Read)
            } catch {
                owsFailDebug("\(error)")
                return
            }

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
        static let deletionBatchSize: Int = 500
    }

    private var logger: CallRecordLogger { .shared }

    private let callRecordConversationIdAdapter: CallRecordSyncMessageConversationIdAdapter
    private let callRecordQuerier: CallRecordQuerier
    private let db: any DB
    private let interactionDeleteManager: InteractionDeleteManager
    private let messageSenderJobQueue: MessageSenderJobQueue

    init(
        callRecordConversationIdAdapter: CallRecordSyncMessageConversationIdAdapter,
        callRecordQuerier: CallRecordQuerier,
        db: any DB,
        interactionDeleteManager: InteractionDeleteManager,
        messageSenderJobQueue: MessageSenderJobQueue
    ) {
        self.callRecordConversationIdAdapter = callRecordConversationIdAdapter
        self.callRecordQuerier = callRecordQuerier
        self.db = db
        self.interactionDeleteManager = interactionDeleteManager
        self.messageSenderJobQueue = messageSenderJobQueue
    }

    // MARK: -

    func runJobAttempt(
        _ jobRecord: CallRecordDeleteAllJobRecord
    ) async -> JobAttemptResult {
        return await JobAttemptResult.executeBlockWithDefaultErrorHandler(
            jobRecord: jobRecord,
            retryLimit: Constants.maxRetries,
            db: db,
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
                    do {
                        return try callRecordConversationIdAdapter.hydrate(
                            conversationId: conversationId,
                            callId: callId,
                            tx: tx
                        )
                    } catch {
                        owsFailDebug("\(error)")
                        return nil
                    }
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
                /// Delete the call records and their associated interactions.
                /// Disable sending a sync message here, since we're instead
                /// going to send a different sync message when we're done
                /// deleting all the records.
                interactionDeleteManager.delete(
                    alongsideAssociatedCallRecords: callRecordsToDelete,
                    sideEffects: .custom(associatedCallDelete: .localDeleteOnly),
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
        conversationId: Data?,
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
        let preparedMessage = PreparedOutgoingMessage.preprepared(
            transientMessageWithoutAttachments: outgoingCallLogEventSyncMessage
        )
        messageSenderJobQueue.add(
            message: preparedMessage,
            transaction: tx
        )
    }
}

// MARK: -

private class CallRecordDeleteAllJobRunnerFactory: JobRunnerFactory {
    typealias JobRunnerType = CallRecordDeleteAllJobRunner

    private let callRecordConversationIdAdapter: CallRecordSyncMessageConversationIdAdapter
    private let callRecordQuerier: CallRecordQuerier
    private let db: any DB
    private let interactionDeleteManager: InteractionDeleteManager
    private let messageSenderJobQueue: MessageSenderJobQueue

    init(
        callRecordConversationIdAdapter: CallRecordSyncMessageConversationIdAdapter,
        callRecordQuerier: CallRecordQuerier,
        db: any DB,
        interactionDeleteManager: InteractionDeleteManager,
        messageSenderJobQueue: MessageSenderJobQueue
    ) {
        self.callRecordConversationIdAdapter = callRecordConversationIdAdapter
        self.callRecordQuerier = callRecordQuerier
        self.db = db
        self.interactionDeleteManager = interactionDeleteManager
        self.messageSenderJobQueue = messageSenderJobQueue
    }

    func buildRunner() -> CallRecordDeleteAllJobRunner {
        return CallRecordDeleteAllJobRunner(
            callRecordConversationIdAdapter: callRecordConversationIdAdapter,
            callRecordQuerier: callRecordQuerier,
            db: db,
            interactionDeleteManager: interactionDeleteManager,
            messageSenderJobQueue: messageSenderJobQueue
        )
    }
}
