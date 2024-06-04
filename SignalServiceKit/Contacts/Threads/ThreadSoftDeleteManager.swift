//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Intents
import LibSignalClient
import SignalCoreKit

public protocol ThreadSoftDeleteManager {
    func softDelete(
        thread: TSThread,
        associatedCallDeleteBehavior: InteractionDelete.SideEffects.AssociatedCallDeleteBehavior,
        tx: any DBWriteTransaction
    )

    func removeAllInteractions(
        thread: TSThread,
        associatedCallDeleteBehavior: InteractionDelete.SideEffects.AssociatedCallDeleteBehavior,
        tx: any DBWriteTransaction
    )
}

public extension ThreadSoftDeleteManager {
    func softDelete(
        thread: TSThread,
        tx: any DBWriteTransaction
    ) {
        softDelete(
            thread: thread,
            associatedCallDeleteBehavior: .localDeleteAndSendSyncMessage,
            tx: tx
        )
    }

    func removeAllInteractions(
        thread: TSThread,
        tx: any DBWriteTransaction
    ) {
        removeAllInteractions(
            thread: thread,
            associatedCallDeleteBehavior: .localDeleteAndSendSyncMessage,
            tx: tx
        )
    }
}

final class ThreadSoftDeleteManagerImpl: ThreadSoftDeleteManager {
    private enum Constants {
        static let interactionDeletionBatchSize: Int = 500
    }

    private let intentsManager: Shims.IntentsManager
    private let interactionDeleteManager: InteractionDeleteManager
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let storyManager: Shims.StoryManager
    private let threadReplyInfoStore: ThreadReplyInfoStore
    private let tsAccountManager: TSAccountManager

    private let logger = PrefixedLogger(prefix: "[ThreadDeleteMgr]")

    init(
        intentsManager: Shims.IntentsManager,
        interactionDeleteManager: InteractionDeleteManager,
        recipientDatabaseTable: RecipientDatabaseTable,
        storyManager: Shims.StoryManager,
        threadReplyInfoStore: ThreadReplyInfoStore,
        tsAccountManager: TSAccountManager
    ) {
        self.intentsManager = intentsManager
        self.interactionDeleteManager = interactionDeleteManager
        self.recipientDatabaseTable = recipientDatabaseTable
        self.storyManager = storyManager
        self.threadReplyInfoStore = threadReplyInfoStore
        self.tsAccountManager = tsAccountManager
    }

    func softDelete(
        thread: TSThread,
        associatedCallDeleteBehavior: InteractionDelete.SideEffects.AssociatedCallDeleteBehavior,
        tx: any DBWriteTransaction
    ) {
        logger.info("Deleting thread with ID \(thread.uniqueId).")

        removeAllInteractions(
            thread: thread,
            associatedCallDeleteBehavior: associatedCallDeleteBehavior,
            tx: tx
        )

        thread.anyUpdate(transaction: SDSDB.shimOnlyBridge(tx)) { thread in
            thread.messageDraft = nil
            thread.shouldThreadBeVisible = false
        }
        threadReplyInfoStore.remove(for: thread.uniqueId, tx: tx)

        if
            let contactThread = thread as? TSContactThread,
            let contactAci = recipientDatabaseTable.fetchServiceId(contactThread: contactThread, tx: tx)
                .flatMap({ $0 as? Aci }),
            let localIdentifiers = self.tsAccountManager.localIdentifiers(tx: tx),
            !localIdentifiers.contains(serviceId: contactAci)
        {
            storyManager.deleteAllStories(contactAci: contactAci, tx: tx)
        } else if let groupThread = thread as? TSGroupThread {
            storyManager.deleteAllStories(groupId: groupThread.groupId, tx: tx)
        }

        intentsManager.deleteAllIntents(withGroupIdentifier: thread.uniqueId)
    }

    func removeAllInteractions(
        thread: TSThread,
        associatedCallDeleteBehavior: InteractionDelete.SideEffects.AssociatedCallDeleteBehavior,
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
                            sideEffects: .custom(
                                associatedCallDelete: associatedCallDeleteBehavior,
                                updateThreadOnInteractionDelete: .doNotUpdate
                            ),
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

// MARK: - Shims

extension ThreadSoftDeleteManagerImpl {
    enum Shims {
        typealias StoryManager = _ThreadSoftDeleteManagerImpl_StoryManager_Shim
        typealias IntentsManager = _ThreadSoftDeleteManagerImpl_IntentsManager_Shim
    }

    enum Wrappers {
        typealias StoryManager = _ThreadSoftDeleteManagerImpl_StoryManager_Wrapper
        typealias IntentsManager = _ThreadSoftDeleteManagerImpl_IntentsManager_Wrapper
    }
}

// MARK: StoryManager

protocol _ThreadSoftDeleteManagerImpl_StoryManager_Shim {
    func deleteAllStories(contactAci: Aci, tx: DBWriteTransaction)
    func deleteAllStories(groupId: Data, tx: DBWriteTransaction)
}

final class _ThreadSoftDeleteManagerImpl_StoryManager_Wrapper: _ThreadSoftDeleteManagerImpl_StoryManager_Shim {
    init() {}

    func deleteAllStories(contactAci: Aci, tx: any DBWriteTransaction) {
        StoryManager.deleteAllStories(forSender: contactAci, tx: SDSDB.shimOnlyBridge(tx))
    }

    func deleteAllStories(groupId: Data, tx: any DBWriteTransaction) {
        StoryManager.deleteAllStories(forGroupId: groupId, tx: SDSDB.shimOnlyBridge(tx))
    }
}

// MARK: Intents

protocol _ThreadSoftDeleteManagerImpl_IntentsManager_Shim {
    func deleteAllIntents(withGroupIdentifier groupIdentifier: String)
}

final class _ThreadSoftDeleteManagerImpl_IntentsManager_Wrapper: _ThreadSoftDeleteManagerImpl_IntentsManager_Shim {
    init() {}

    func deleteAllIntents(withGroupIdentifier groupIdentifier: String) {
        INInteraction.delete(with: groupIdentifier)
    }
}

// MARK: -

#if TESTABLE_BUILD

open class MockThreadSoftDeleteManager: ThreadSoftDeleteManager {
    open func softDelete(thread: TSThread, associatedCallDeleteBehavior: InteractionDelete.SideEffects.AssociatedCallDeleteBehavior, tx: any DBWriteTransaction) {}
    open func removeAllInteractions(thread: TSThread, associatedCallDeleteBehavior: InteractionDelete.SideEffects.AssociatedCallDeleteBehavior, tx: any DBWriteTransaction) {}
}

#endif
