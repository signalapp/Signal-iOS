//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Intents
import LibSignalClient

/// Responsible for "soft-deleting" threads, or removing their contents without
/// removing the `TSThread` record itself. The app's architecture is to never\*
/// delete the thread itself, but instead to delete all data associated with the
/// thread, in case the thread is needed again later on.
///
/// \*Threads can be hard-deleted, but only in niche scenarios.
///
/// - SeeAlso ``ThreadRemover``.
///
/// - SeeAlso
/// If you're calling this type for a user-initiated deletion, consider using
/// ``DeleteForMeInfoSheetCoordinator`` in the Signal target instead, which
/// handles some one-time informational UX.
public protocol ThreadSoftDeleteManager {
    func softDelete(
        threads: [TSThread],
        sendDeleteForMeSyncMessage: Bool,
        tx: DBWriteTransaction
    )

    func removeAllInteractions(
        thread: TSThread,
        sendDeleteForMeSyncMessage: Bool,
        tx: DBWriteTransaction
    )
}

final class ThreadSoftDeleteManagerImpl: ThreadSoftDeleteManager {
    private enum Constants {
        static let interactionDeletionBatchSize: Int = 500
    }

    private typealias SyncMessageContext = DeleteForMeSyncMessage.Outgoing.ThreadDeletionContext

    private let deleteForMeOutgoingSyncMessageManager: DeleteForMeOutgoingSyncMessageManager
    private let intentsManager: Shims.IntentsManager
    private let interactionDeleteManager: InteractionDeleteManager
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let storyManager: Shims.StoryManager
    private let threadReplyInfoStore: ThreadReplyInfoStore
    private let tsAccountManager: TSAccountManager

    private let logger = PrefixedLogger(prefix: "[ThreadDeleteMgr]")

    init(
        deleteForMeOutgoingSyncMessageManager: DeleteForMeOutgoingSyncMessageManager,
        intentsManager: Shims.IntentsManager,
        interactionDeleteManager: InteractionDeleteManager,
        recipientDatabaseTable: RecipientDatabaseTable,
        storyManager: Shims.StoryManager,
        threadReplyInfoStore: ThreadReplyInfoStore,
        tsAccountManager: TSAccountManager
    ) {
        self.deleteForMeOutgoingSyncMessageManager = deleteForMeOutgoingSyncMessageManager
        self.intentsManager = intentsManager
        self.interactionDeleteManager = interactionDeleteManager
        self.recipientDatabaseTable = recipientDatabaseTable
        self.storyManager = storyManager
        self.threadReplyInfoStore = threadReplyInfoStore
        self.tsAccountManager = tsAccountManager
    }

    func softDelete(
        threads: [TSThread],
        sendDeleteForMeSyncMessage: Bool,
        tx: DBWriteTransaction
    ) {
        var syncMessageContexts = [SyncMessageContext]()

        for thread in threads {
            var syncMessageContext: SyncMessageContext?
            if
                sendDeleteForMeSyncMessage,
                let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx)
            {
                syncMessageContext = deleteForMeOutgoingSyncMessageManager.makeThreadDeletionContext(
                    thread: thread,
                    isFullDelete: true,
                    localIdentifiers: localIdentifiers,
                    tx: tx
                )
            }

            softDelete(
                thread: thread,
                syncMessageContext: syncMessageContext,
                tx: tx
            )

            if let syncMessageContext {
                syncMessageContexts.append(syncMessageContext)
            }
        }

        if sendDeleteForMeSyncMessage {
            deleteForMeOutgoingSyncMessageManager.send(
                threadDeletionContexts: syncMessageContexts,
                tx: tx
            )
        }
    }

    func removeAllInteractions(
        thread: TSThread,
        sendDeleteForMeSyncMessage: Bool,
        tx: DBWriteTransaction
    ) {
        var syncMessageContext: SyncMessageContext?
        if
            sendDeleteForMeSyncMessage,
            let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx)
        {
            syncMessageContext = deleteForMeOutgoingSyncMessageManager.makeThreadDeletionContext(
                thread: thread,
                isFullDelete: false,
                localIdentifiers: localIdentifiers,
                tx: tx
            )
        }

        removeAllInteractions(
            thread: thread,
            syncMessageContext: syncMessageContext,
            tx: tx
        )

        if let syncMessageContext {
            deleteForMeOutgoingSyncMessageManager.send(
                threadDeletionContexts: [syncMessageContext],
                tx: tx
            )
        }
    }

    private func softDelete(
        thread: TSThread,
        syncMessageContext: SyncMessageContext?,
        tx: DBWriteTransaction
    ) {
        logger.info("Deleting thread with ID \(thread.logString).")

        removeAllInteractions(
            thread: thread,
            syncMessageContext: syncMessageContext,
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

    private func removeAllInteractions(
        thread: TSThread,
        syncMessageContext: SyncMessageContext?,
        tx: DBWriteTransaction
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

                    if let syncMessageContext {
                        for messageToDelete: TSMessage in interactionBatch.compactMap({ $0 as? TSMessage }) {
                            syncMessageContext.registerMessageDeletedFromThread(messageToDelete)
                        }
                    }

                    interactionDeleteManager.delete(
                        interactions: interactionBatch,
                        sideEffects: .custom(
                            associatedCallDelete: .localDeleteOnly,
                            updateThreadOnInteractionDelete: .doNotUpdate
                        ),
                        tx: tx
                    )

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
            thread.lastDraftInteractionRowId = 0
            thread.lastDraftUpdateTimestamp = 0
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

    func deleteAllStories(contactAci: Aci, tx: DBWriteTransaction) {
        StoryManager.deleteAllStories(forSender: contactAci, tx: SDSDB.shimOnlyBridge(tx))
    }

    func deleteAllStories(groupId: Data, tx: DBWriteTransaction) {
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
    open func softDelete(threads: [TSThread], sendDeleteForMeSyncMessage: Bool, tx: DBWriteTransaction) {}
    open func removeAllInteractions(thread: TSThread, sendDeleteForMeSyncMessage: Bool, tx: DBWriteTransaction) {}
}

#endif
