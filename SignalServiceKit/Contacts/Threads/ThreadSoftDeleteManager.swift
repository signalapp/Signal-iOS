//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Intents
import SignalCoreKit

public protocol ThreadSoftDeleteManager {
    func softDelete(thread: TSThread, tx: any DBWriteTransaction)

    func removeAllInteractions(thread: TSThread, tx: any DBWriteTransaction)
}

final class ThreadSoftDeleteManagerImpl: ThreadSoftDeleteManager {
    private enum Constants {
        static let interactionDeletionBatchSize: Int = 500
    }

    private let interactionDeleteManager: InteractionDeleteManager
    private let threadReplyInfoStore: ThreadReplyInfoStore

    private let logger = PrefixedLogger(prefix: "[ThreadDeleteMgr]")

    init(
        interactionDeleteManager: InteractionDeleteManager,
        threadReplyInfoStore: ThreadReplyInfoStore
    ) {
        self.interactionDeleteManager = interactionDeleteManager
        self.threadReplyInfoStore = threadReplyInfoStore
    }

    func softDelete(thread: TSThread, tx: any DBWriteTransaction) {
        logger.info("Deleting thread with ID \(thread.uniqueId).")

        removeAllInteractions(thread: thread, tx: tx)

        thread.anyUpdate(transaction: SDSDB.shimOnlyBridge(tx)) { thread in
            thread.messageDraft = nil
            thread.shouldThreadBeVisible = false
        }
        threadReplyInfoStore.remove(for: thread.uniqueId, tx: tx)

        INInteraction.delete(with: thread.uniqueId)
    }

    func removeAllInteractions(
        thread: TSThread,
        tx: any DBWriteTransaction
    ) {
        let sdsTx = SDSDB.shimOnlyBridge(tx)

        do {
            var moreInteractionsRemaining = true
            while moreInteractionsRemaining {
                try autoreleasepool {
                    let interactionBatch = try InteractionFinder(
                        threadUniqueId: thread.uniqueId
                    ).fetchAllInteractions(
                        rowIdFilter: .newest,
                        limit: Constants.interactionDeletionBatchSize,
                        tx: sdsTx
                    )

                    for interaction in interactionBatch {
                        interactionDeleteManager.delete(
                            interaction,
                            sideEffects: .custom(updateThreadOnEachDeletedInteraction: false),
                            tx: tx
                        )
                    }

                    moreInteractionsRemaining = !interactionBatch.isEmpty
                }
            }
        } catch {
            owsFailDebug("Failed to delete batch of interactions!")
            return
        }

        /// Because we skipped updating the thread for each deleted interaction,
        /// now that we're done deleting we'll do a one-time update of
        /// properties on the thread.
        thread.anyUpdate(transaction: sdsTx) { thread in
            thread.lastInteractionRowId = 0
        }
    }
}

// MARK: -

private extension InteractionFinder {
    func fetchAllInteractions(
        rowIdFilter: RowIdFilter,
        limit: Int,
        tx: SDSAnyReadTransaction
    ) throws -> [TSInteraction] {
        var interactions: [TSInteraction] = []

        try enumerateAllInteractions(
            rowIdFilter: rowIdFilter,
            limit: limit,
            tx: tx
        ) { interaction -> Bool in
            interactions.append(interaction)
            return true
        }

        return interactions
    }
}

// MARK: -

#if TESTABLE_BUILD

open class MockThreadSoftDeleteManager: ThreadSoftDeleteManager {
    open func softDelete(thread: TSThread, tx: any DBWriteTransaction) {}
    open func removeAllInteractions(thread: TSThread, tx: any DBWriteTransaction) {}
}

#endif
