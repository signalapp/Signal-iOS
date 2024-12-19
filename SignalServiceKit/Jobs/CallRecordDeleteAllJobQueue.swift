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
    private var jobSerializer = CompletionSerializer()

    private let callRecordConversationIdAdapter: CallRecordSyncMessageConversationIdAdapter

    public init(
        callLinkStore: any CallLinkRecordStore,
        callRecordConversationIdAdapter: CallRecordSyncMessageConversationIdAdapter,
        callRecordDeleteManager: any CallRecordDeleteManager,
        callRecordQuerier: CallRecordQuerier,
        db: any DB,
        interactionDeleteManager: InteractionDeleteManager,
        messageSenderJobQueue: MessageSenderJobQueue
    ) {
        self.jobRunnerFactory = CallRecordDeleteAllJobRunnerFactory(
            callLinkStore: callLinkStore,
            callRecordConversationIdAdapter: callRecordConversationIdAdapter,
            callRecordDeleteManager: callRecordDeleteManager,
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

        jobSerializer.addOrderedSyncCompletion(tx: tx.asV2Write) {
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

    private let callLinkStore: any CallLinkRecordStore
    private let callRecordConversationIdAdapter: CallRecordSyncMessageConversationIdAdapter
    private let callRecordDeleteManager: any CallRecordDeleteManager
    private let callRecordQuerier: CallRecordQuerier
    private let db: any DB
    private let interactionDeleteManager: InteractionDeleteManager
    private let messageSenderJobQueue: MessageSenderJobQueue

    init(
        callLinkStore: any CallLinkRecordStore,
        callRecordConversationIdAdapter: CallRecordSyncMessageConversationIdAdapter,
        callRecordDeleteManager: any CallRecordDeleteManager,
        callRecordQuerier: CallRecordQuerier,
        db: any DB,
        interactionDeleteManager: InteractionDeleteManager,
        messageSenderJobQueue: MessageSenderJobQueue
    ) {
        self.callLinkStore = callLinkStore
        self.callRecordConversationIdAdapter = callRecordConversationIdAdapter
        self.callRecordDeleteManager = callRecordDeleteManager
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
        var deleteBeforeTimestamp: UInt64 = {
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
            let (deletedCount, earliestDeletedTimestamp) = self.deleteSomeCallRecords(
                beforeTimestamp: deleteBeforeTimestamp,
                tx: tx
            )
            // We skip any call links for which we're the admin, so update
            // deleteBeforeTimestamp on each iteration to avoid fetching those call
            // links repeatedly.
            if let earliestDeletedTimestamp {
                deleteBeforeTimestamp = earliestDeletedTimestamp
            }
            return deletedCount
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
    ) -> (deletedCount: Int, earliestDeletedTimestamp: UInt64?) {
        /// The passed timestamp will be the timestamp of the most-recent call
        /// when the user initiated the delete-all action. So as to ensure we
        /// delete that most-recent call, we'll shim the timestamp forward.
        let beforeTimestamp = beforeTimestamp + 1

        guard let cursor = callRecordQuerier.fetchCursor(
            ordering: .descendingBefore(timestamp: beforeTimestamp),
            tx: tx
        ) else { return (0, nil) }

        do {
            var earliestTimestamp: UInt64?
            var callRecordsWithInteractions = [CallRecord]()
            var callRecordsWithoutInteractions = [CallRecord]()
            while
                let callRecord = try cursor.next(),
                (callRecordsWithInteractions.count + callRecordsWithoutInteractions.count) < Constants.deletionBatchSize
            {
                earliestTimestamp = callRecord.callBeganTimestamp

                switch callRecord.conversationId {
                case .callLink(let callLinkRowId):
                    let callLinkRecord = try callLinkStore.fetch(rowId: callLinkRowId, tx: tx) ?? {
                        throw OWSAssertionError("Can't fetch CallLink that must exist.")
                    }()
                    if callLinkRecord.adminPasskey != nil {
                        // These are deleted via Storage Service syncs.
                    } else {
                        callRecordsWithoutInteractions.append(callRecord)
                    }
                case .thread:
                    callRecordsWithInteractions.append(callRecord)
                }
            }

            /// Delete the call records and their associated interactions.
            /// Disable sending a sync message here, since we're instead
            /// going to send a different sync message when we're done
            /// deleting all the records.
            interactionDeleteManager.delete(
                alongsideAssociatedCallRecords: callRecordsWithInteractions,
                sideEffects: .custom(associatedCallDelete: .localDeleteOnly),
                tx: tx
            )

            callRecordDeleteManager.deleteCallRecords(
                callRecordsWithoutInteractions,
                sendSyncMessageOnDelete: false,
                tx: tx
            )

            return (callRecordsWithInteractions.count + callRecordsWithoutInteractions.count, earliestTimestamp)
        } catch let error {
            owsFailBeta("Failed to get call records from cursor! \(error)")
        }

        return (0, nil)
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

    private let callLinkStore: any CallLinkRecordStore
    private let callRecordConversationIdAdapter: CallRecordSyncMessageConversationIdAdapter
    private let callRecordDeleteManager: any CallRecordDeleteManager
    private let callRecordQuerier: CallRecordQuerier
    private let db: any DB
    private let interactionDeleteManager: InteractionDeleteManager
    private let messageSenderJobQueue: MessageSenderJobQueue

    init(
        callLinkStore: any CallLinkRecordStore,
        callRecordConversationIdAdapter: CallRecordSyncMessageConversationIdAdapter,
        callRecordDeleteManager: any CallRecordDeleteManager,
        callRecordQuerier: CallRecordQuerier,
        db: any DB,
        interactionDeleteManager: InteractionDeleteManager,
        messageSenderJobQueue: MessageSenderJobQueue
    ) {
        self.callLinkStore = callLinkStore
        self.callRecordConversationIdAdapter = callRecordConversationIdAdapter
        self.callRecordDeleteManager = callRecordDeleteManager
        self.callRecordQuerier = callRecordQuerier
        self.db = db
        self.interactionDeleteManager = interactionDeleteManager
        self.messageSenderJobQueue = messageSenderJobQueue
    }

    func buildRunner() -> CallRecordDeleteAllJobRunner {
        return CallRecordDeleteAllJobRunner(
            callLinkStore: callLinkStore,
            callRecordConversationIdAdapter: callRecordConversationIdAdapter,
            callRecordDeleteManager: callRecordDeleteManager,
            callRecordQuerier: callRecordQuerier,
            db: db,
            interactionDeleteManager: interactionDeleteManager,
            messageSenderJobQueue: messageSenderJobQueue
        )
    }
}
