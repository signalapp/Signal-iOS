//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public final class BulkDeleteInteractionJobQueue {
    private let jobRunnerFactory: BulkDeleteInteractionJobRunnerFactory
    private let jobQueueRunner: JobQueueRunner<
        JobRecordFinderImpl<BulkDeleteInteractionJobRecord>,
        BulkDeleteInteractionJobRunnerFactory
    >
    private var jobSerializer = CompletionSerializer()

    init(
        addressableMessageFinder: DeleteForMeAddressableMessageFinder,
        db: any DB,
        interactionDeleteManager: InteractionDeleteManager,
        threadSoftDeleteManager: ThreadSoftDeleteManager,
        threadStore: ThreadStore
    ) {
        self.jobRunnerFactory = BulkDeleteInteractionJobRunnerFactory(
            addressableMessageFinder: addressableMessageFinder,
            db: db,
            interactionDeleteManager: interactionDeleteManager,
            threadSoftDeleteManager: threadSoftDeleteManager,
            threadStore: threadStore
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

    func addJob(
        anchorMessageRowId: Int64,
        isFullThreadDelete: Bool,
        threadUniqueId: String,
        tx: DBWriteTransaction
    ) {
        let jobRecord = BulkDeleteInteractionJobRecord(
            anchorMessageRowId: anchorMessageRowId,
            fullThreadDeletionAnchorMessageRowId: { () -> Int64? in
                if isFullThreadDelete {
                    return InteractionFinder(threadUniqueId: threadUniqueId)
                        .mostRecentRowId(tx: tx)
                }

                return nil
            }(),
            threadUniqueId: threadUniqueId
        )

        jobRecord.anyInsert(transaction: tx)

        jobSerializer.addOrderedSyncCompletion(tx: tx) {
            self.jobQueueRunner.addPersistedJob(jobRecord)
        }
    }
}

// MARK: -

private class BulkDeleteInteractionJobRunner: JobRunner {
    typealias JobRecordType = BulkDeleteInteractionJobRecord

    private enum Constants {
        static let maxRetries: UInt = 110
        static let deletionBatchSize: Int = 500
    }

    private let addressableMessageFinder: DeleteForMeAddressableMessageFinder
    private let db: any DB
    private let interactionDeleteManager: InteractionDeleteManager
    private let threadSoftDeleteManager: ThreadSoftDeleteManager
    private let threadStore: ThreadStore

    private let logger = PrefixedLogger(prefix: "[DeleteForMe]")

    init(
        addressableMessageFinder: DeleteForMeAddressableMessageFinder,
        db: any DB,
        interactionDeleteManager: InteractionDeleteManager,
        threadSoftDeleteManager: ThreadSoftDeleteManager,
        threadStore: ThreadStore
    ) {
        self.addressableMessageFinder = addressableMessageFinder
        self.db = db
        self.interactionDeleteManager = interactionDeleteManager
        self.threadSoftDeleteManager = threadSoftDeleteManager
        self.threadStore = threadStore
    }

    func runJobAttempt(
        _ jobRecord: BulkDeleteInteractionJobRecord
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

    func didFinishJob(_ jobRecordId: JobRecord.RowId, result: JobResult) async {
        switch result.ranSuccessfullyOrError {
        case .success:
            break
        case .failure(let failure):
            logger.error("Failed to perform delete-for-me bulk action! \(failure)")
        }
    }

    private func _runJobAttempt(
        _ jobRecord: BulkDeleteInteractionJobRecord
    ) async throws {
        let anchorMessageRowId = jobRecord.anchorMessageRowId
        let fullThreadDeletionAnchorMessageRowId = jobRecord.fullThreadDeletionAnchorMessageRowId
        let threadUniqueId = jobRecord.threadUniqueId

        logger.info("Attempting to bulk-delete interactions for thread \(threadUniqueId), isFullThreadDelete \(fullThreadDeletionAnchorMessageRowId != nil).")

        let deletedCount = await TimeGatedBatch.processAllAsync(db: db) { tx -> Int in
            return self.deleteSomeInteractions(
                threadUniqueId: threadUniqueId,
                anchorMessageRowId: anchorMessageRowId,
                tx: tx
            )
        }

        logger.info("Deleted \(deletedCount) messages for thread \(threadUniqueId), isFullThreadDelete \(fullThreadDeletionAnchorMessageRowId != nil).")

        await db.awaitableWrite { tx in
            let sdsTx: DBWriteTransaction = SDSDB.shimOnlyBridge(tx)

            jobRecord.anyRemove(transaction: sdsTx)

            guard
                let fullThreadDeletionAnchorMessageRowId,
                let thread = self.threadStore.fetchThread(uniqueId: threadUniqueId, tx: tx)
            else { return }

            /// At this point we've deleted all the messages at or before our
            /// view of the most-recent addressable message. Since we also know
            /// that the user's intent was a "full thread delete", we'll try and
            /// go further and additionally soft-delete the thread.
            ///
            /// This will have a couple desirable side-effects: at the time of
            /// writing, these include deleting associated story messages and
            /// hiding the thread from the chat list. Additionally, if there
            /// were any non-addressable messages that were newer than our
            /// bulk-delete anchor, those will also be deleted.
            ///
            /// Caveats:
            ///
            /// 1. We'll abort the soft-delete if there are any addressable
            ///    messages remaining. This would indicate that the user sent or
            ///    received messages newer than our bulk-delete anchor.
            ///
            /// 2. We'll abort the soft-delete if the most-recent message in the
            ///    thread now is newer than the most-recent message when we
            ///    created the bulk-delete job. This would indicate that while
            ///    all the remaining messages are non-addressable, one of them
            ///    was inserted while the bulk-delete was running.
            if self.addressableMessageFinder.threadContainsAnyAddressableMessages(
                threadUniqueId: threadUniqueId,
                tx: tx
            ) {
                self.logger.warn("Not doing thread soft-delete – thread contains addressable messages after delete.")
            } else if InteractionFinder(threadUniqueId: threadUniqueId)
                .mostRecentRowId(tx: sdsTx) > fullThreadDeletionAnchorMessageRowId
            {
                self.logger.warn("Not doing thread soft-delete – most recent row ID was newer than when we started delete.")
            } else {
                self.threadSoftDeleteManager.softDelete(
                    threads: [thread],
                    sendDeleteForMeSyncMessage: false,
                    tx: tx
                )
            }
        }
    }

    /// Delete a batch of interactions.
    /// - Returns
    /// The number of interactions deleted. A return value of 0 indicates that
    /// there are no more interactions to delete.
    private func deleteSomeInteractions(
        threadUniqueId: String,
        anchorMessageRowId: Int64,
        tx: DBWriteTransaction
    ) -> Int {
        let interactionsToDelete: [TSInteraction]
        do {
            interactionsToDelete = try InteractionFinder(
                threadUniqueId: threadUniqueId
            ).fetchAllInteractions(
                rowIdFilter: .atOrBefore(anchorMessageRowId),
                limit: Constants.deletionBatchSize,
                tx: tx
            )
        } catch {
            owsFailDebug("Failed to get interactions to delete!")
            return 0
        }

        if interactionsToDelete.isEmpty { return 0 }

        for interaction in interactionsToDelete {
            interactionDeleteManager.delete(
                interaction,
                sideEffects: .custom(
                    associatedCallDelete: .localDeleteOnly,
                    updateThreadOnInteractionDelete: .doNotUpdate
                ),
                tx: tx
            )
        }

        /// Above, we're skipping a per-interaction thread update that would
        /// otherwise set various "last visible" properties on the thread. To
        /// compensate, we'll do a single thread update at the end of each
        /// transaction (note that because we're in a `TimeGatedBatch`, we don't
        /// know how many interactions will be deleted in a single transaction).
        /// This will ensure that anyone who opens a transaction between our
        /// time-gated batches sees a thread with appropriately-updated values.
        tx.addFinalizationBlock(key: "BulkDeleteInteractionJobQueue") { tx in
            if let thread = self.threadStore.fetchThread(
                uniqueId: threadUniqueId,
                tx: tx
            ) {
                thread.updateOnInteractionsRemoved(
                    needsToUpdateLastInteractionRowId: true,
                    needsToUpdateLastVisibleSortId: true,
                    tx: tx
                )
            }
        }

        return interactionsToDelete.count
    }
}

// MARK: -

private class BulkDeleteInteractionJobRunnerFactory: JobRunnerFactory {
    typealias JobRunnerType = BulkDeleteInteractionJobRunner

    private let addressableMessageFinder: DeleteForMeAddressableMessageFinder
    private let db: any DB
    private let interactionDeleteManager: InteractionDeleteManager
    private let threadSoftDeleteManager: ThreadSoftDeleteManager
    private let threadStore: ThreadStore

    init(
        addressableMessageFinder: DeleteForMeAddressableMessageFinder,
        db: any DB,
        interactionDeleteManager: InteractionDeleteManager,
        threadSoftDeleteManager: ThreadSoftDeleteManager,
        threadStore: ThreadStore
    ) {
        self.addressableMessageFinder = addressableMessageFinder
        self.db = db
        self.interactionDeleteManager = interactionDeleteManager
        self.threadSoftDeleteManager = threadSoftDeleteManager
        self.threadStore = threadStore
    }

    func buildRunner() -> BulkDeleteInteractionJobRunner {
        return BulkDeleteInteractionJobRunner(
            addressableMessageFinder: addressableMessageFinder,
            db: db,
            interactionDeleteManager: interactionDeleteManager,
            threadSoftDeleteManager: threadSoftDeleteManager,
            threadStore: threadStore
        )
    }
}
