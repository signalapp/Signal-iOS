//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Manages durable jobs for deleting all ``CallRecord``s.
///
/// This is a special action distinct from deleting a single ``CallRecord``, or
/// even multiple discrete ``CallRecord``s, which is handled by the
/// ``CallRecordDeleteManager``. This type is specifically for "delete them all,
/// in bulk".
///
/// - SeeAlso ``CallRecordDeleteManager``
public class CallRecordDeleteAllJobQueue {
    private let jobRunnerFactory: CallRecordDeleteAllJobRunnerFactory
    private let jobQueueRunner: JobQueueRunner<
        JobRecordFinderImpl<CallRecordDeleteAllJobRecord>,
        CallRecordDeleteAllJobRunnerFactory
    >

    public init(
        callRecordDeleteManager: CallRecordDeleteManager,
        callRecordQuerier: CallRecordQuerier,
        db: DB,
        messageSenderJobQueue: MessageSenderJobQueue
    ) {
        self.jobRunnerFactory = CallRecordDeleteAllJobRunnerFactory(
            callRecordDeleteManager: callRecordDeleteManager,
            callRecordQuerier: callRecordQuerier,
            db: db,
            messageSenderJobQueue: messageSenderJobQueue
        )
        self.jobQueueRunner = JobQueueRunner(
            canExecuteJobsConcurrently: false,
            db: db,
            jobFinder: JobRecordFinderImpl(db: db),
            jobRunnerFactory: self.jobRunnerFactory
        )
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
        deleteAllBeforeTimestamp: UInt64,
        tx: SDSAnyWriteTransaction
    ) {
        let jobRecord = CallRecordDeleteAllJobRecord(
            sendDeleteAllSyncMessage: sendDeleteAllSyncMessage,
            deleteAllBeforeTimestamp: deleteAllBeforeTimestamp
        )
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
    private let db: DB
    private let messageSenderJobQueue: MessageSenderJobQueue

    init(
        callRecordDeleteManager: CallRecordDeleteManager,
        callRecordQuerier: CallRecordQuerier,
        db: DB,
        messageSenderJobQueue: MessageSenderJobQueue
    ) {
        self.callRecordDeleteManager = callRecordDeleteManager
        self.callRecordQuerier = callRecordQuerier
        self.db = db
        self.messageSenderJobQueue = messageSenderJobQueue
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
        logger.info("Attempting to delete all call records before \(jobRecord.deleteAllBeforeTimestamp).")

        let deletedCount = await TimeGatedBatch.processAllAsync(db: db) { tx in
            return self.deleteSomeCallRecords(
                beforeTimestamp: jobRecord.deleteAllBeforeTimestamp,
                tx: tx
            )
        }

        logger.info("Deleted \(deletedCount) calls.")

        await db.awaitableWrite { tx in
            let sdsTx: SDSAnyWriteTransaction = SDSDB.shimOnlyBridge(tx)

            if jobRecord.sendDeleteAllSyncMessage {
                self.logger.info("Sending delete-all-calls sync message.")

                self.sendClearCallLogSyncMessage(
                    beforeTimestamp: jobRecord.deleteAllBeforeTimestamp,
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
        beforeTimestamp: UInt64,
        tx: SDSAnyWriteTransaction
    ) {
        guard let localThread = TSContactThread.getOrCreateLocalThread(
            transaction: tx
        ) else { return }

        let outgoingCallLogEventSyncMessage = OutgoingCallLogEventSyncMessage(
            callLogEvent: OutgoingCallLogEventSyncMessage.CallLogEvent(
                eventType: .cleared,
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
    private let db: DB
    private let messageSenderJobQueue: MessageSenderJobQueue

    init(
        callRecordDeleteManager: CallRecordDeleteManager,
        callRecordQuerier: CallRecordQuerier,
        db: DB,
        messageSenderJobQueue: MessageSenderJobQueue
    ) {
        self.callRecordDeleteManager = callRecordDeleteManager
        self.callRecordQuerier = callRecordQuerier
        self.db = db
        self.messageSenderJobQueue = messageSenderJobQueue
    }

    func buildRunner() -> CallRecordDeleteAllJobRunner {
        return CallRecordDeleteAllJobRunner(
            callRecordDeleteManager: callRecordDeleteManager,
            callRecordQuerier: callRecordQuerier,
            db: db,
            messageSenderJobQueue: messageSenderJobQueue
        )
    }
}
