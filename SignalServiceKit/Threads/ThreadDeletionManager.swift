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
public protocol ThreadDeletionManager {
    func deleteThreads(
        _ threads: [TSThread],
        sendDeleteForMeSyncMessage: Bool,
        updateStorageService: Bool,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction,
    )

    func removeAllInteractions(
        thread: TSThread,
        deleteForMeSyncMessagePolicy: DeleteForMeSyncMessagePolicy?,
        tx: DBWriteTransaction,
    )

    func removeIntentsForTerminatedGroup(threadUniqueId: String)
}

public enum DeleteForMeSyncMessagePolicy {
    case send(LocalIdentifiers)
}

final class ThreadDeletionManagerImpl: ThreadDeletionManager {
    private enum Constants {
        static let interactionDeletionBatchSize: Int = 500
    }

    private typealias SyncMessageContext = DeleteForMeSyncMessage.Outgoing.ThreadDeletionContext

    private let db: any DB
    private let deleteForMeOutgoingSyncMessageManager: DeleteForMeOutgoingSyncMessageManager
    private let intentsManager: Shims.IntentsManager
    private let interactionDeleteManager: InteractionDeleteManager
    private let pinnedThreadManager: any PinnedThreadManager
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let storyManager: Shims.StoryManager
    private let threadRemover: any ThreadRemover
    private let threadReplyInfoStore: ThreadReplyInfoStore

    private let logger = PrefixedLogger(prefix: "[ThreadDeleteMgr]")

    init(
        db: any DB,
        deleteForMeOutgoingSyncMessageManager: DeleteForMeOutgoingSyncMessageManager,
        intentsManager: Shims.IntentsManager,
        interactionDeleteManager: InteractionDeleteManager,
        pinnedThreadManager: any PinnedThreadManager,
        recipientDatabaseTable: RecipientDatabaseTable,
        storyManager: Shims.StoryManager,
        threadRemover: any ThreadRemover,
        threadReplyInfoStore: ThreadReplyInfoStore,
    ) {
        self.db = db
        self.deleteForMeOutgoingSyncMessageManager = deleteForMeOutgoingSyncMessageManager
        self.intentsManager = intentsManager
        self.interactionDeleteManager = interactionDeleteManager
        self.pinnedThreadManager = pinnedThreadManager
        self.recipientDatabaseTable = recipientDatabaseTable
        self.storyManager = storyManager
        self.threadRemover = threadRemover
        self.threadReplyInfoStore = threadReplyInfoStore
    }

    func deleteThreads(
        _ threads: [TSThread],
        sendDeleteForMeSyncMessage: Bool,
        updateStorageService: Bool,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction,
    ) {
        var syncMessageContexts = [SyncMessageContext]()

        for thread in threads {
            var syncMessageContext: SyncMessageContext?
            if sendDeleteForMeSyncMessage {
                syncMessageContext = deleteForMeOutgoingSyncMessageManager.makeThreadDeletionContext(
                    thread: thread,
                    isFullDelete: true,
                    localIdentifiers: localIdentifiers,
                    tx: tx,
                )
            }

            deleteThread(
                thread,
                syncMessageContext: syncMessageContext,
                updateStorageService: updateStorageService,
                localIdentifiers: localIdentifiers,
                tx: tx,
            )

            if let syncMessageContext {
                syncMessageContexts.append(syncMessageContext)
            }
        }

        if sendDeleteForMeSyncMessage {
            deleteForMeOutgoingSyncMessageManager.send(
                threadDeletionContexts: syncMessageContexts,
                tx: tx,
            )
        }
    }

    func removeAllInteractions(
        thread: TSThread,
        deleteForMeSyncMessagePolicy: DeleteForMeSyncMessagePolicy?,
        tx: DBWriteTransaction,
    ) {
        var syncMessageContext: SyncMessageContext?
        switch deleteForMeSyncMessagePolicy {
        case .send(let localIdentifiers):
            syncMessageContext = deleteForMeOutgoingSyncMessageManager.makeThreadDeletionContext(
                thread: thread,
                isFullDelete: false,
                localIdentifiers: localIdentifiers,
                tx: tx,
            )
        case nil:
            break
        }

        removeAllInteractions(
            thread: thread,
            syncMessageContext: syncMessageContext,
            tx: tx,
        )

        if let syncMessageContext {
            deleteForMeOutgoingSyncMessageManager.send(
                threadDeletionContexts: [syncMessageContext],
                tx: tx,
            )
        }
    }

    func removeIntentsForTerminatedGroup(threadUniqueId: String) {
        intentsManager.deleteAllIntents(withGroupIdentifier: threadUniqueId)
    }

    private func deleteThread(
        _ thread: TSThread,
        syncMessageContext: SyncMessageContext?,
        updateStorageService: Bool,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction,
    ) {
        logger.info("Deleting thread with ID \(thread.logString).")

        removeAllInteractions(
            thread: thread,
            syncMessageContext: syncMessageContext,
            tx: tx,
        )

        pinnedThreadManager.unpinThread(thread, updateStorageService: updateStorageService, tx: tx)

        if shouldHardDeleteThread(thread, localIdentifiers: localIdentifiers) {
            threadRemover.remove(thread, tx: tx)
        } else {
            thread.anyUpdate(transaction: tx) { thread in
                thread.messageDraft = nil
                thread.shouldThreadBeVisible = false
            }
            threadReplyInfoStore.remove(for: thread.uniqueId, tx: tx)
        }

        if
            let contactThread = thread as? TSContactThread,
            let contactAci = recipientDatabaseTable.fetchServiceId(contactThread: contactThread, tx: tx)
                .flatMap({ $0 as? Aci }),
            !localIdentifiers.contains(serviceId: contactAci)
        {
            storyManager.deleteAllStories(contactAci: contactAci, tx: tx)
        } else if let groupThread = thread as? TSGroupThread {
            storyManager.deleteAllStories(groupId: groupThread.groupId, tx: tx)
        }

        intentsManager.deleteAllIntents(withGroupIdentifier: thread.uniqueId)
    }

    private func shouldHardDeleteThread(_ thread: TSThread, localIdentifiers: LocalIdentifiers) -> Bool {
        switch thread {
        case let thread as TSGroupThread:
            return thread.canBeDeleted(localIdentifiers: localIdentifiers)
        case is TSPrivateStoryThread:
            return true
        default:
            return false
        }
    }

    private func removeAllInteractions(
        thread: TSThread,
        syncMessageContext: SyncMessageContext?,
        tx: DBWriteTransaction,
    ) {
        do {
            var moreInteractionsRemaining = true
            while moreInteractionsRemaining {
                try autoreleasepool {
                    let interactionBatch = try InteractionFinder(
                        threadUniqueId: thread.uniqueId,
                    ).fetchAllInteractions(
                        rowIdFilter: .newest,
                        limit: Constants.interactionDeletionBatchSize,
                        tx: tx,
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
                            updateThreadOnInteractionDelete: .doNotUpdate,
                        ),
                        tx: tx,
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
        thread.anyUpdate(transaction: tx) { thread in
            thread.lastInteractionRowId = 0
            thread.lastDraftInteractionRowId = 0
            thread.lastDraftUpdateTimestamp = 0
        }
    }
}

// MARK: - Shims

extension ThreadDeletionManagerImpl {
    enum Shims {
        typealias StoryManager = _ThreadDeletionManagerImpl_StoryManager_Shim
        typealias IntentsManager = _ThreadDeletionManagerImpl_IntentsManager_Shim
    }

    enum Wrappers {
        typealias StoryManager = _ThreadDeletionManagerImpl_StoryManager_Wrapper
        typealias IntentsManager = _ThreadDeletionManagerImpl_IntentsManager_Wrapper
    }
}

// MARK: StoryManager

protocol _ThreadDeletionManagerImpl_StoryManager_Shim {
    func deleteAllStories(contactAci: Aci, tx: DBWriteTransaction)
    func deleteAllStories(groupId: Data, tx: DBWriteTransaction)
}

final class _ThreadDeletionManagerImpl_StoryManager_Wrapper: _ThreadDeletionManagerImpl_StoryManager_Shim {
    init() {}

    func deleteAllStories(contactAci: Aci, tx: DBWriteTransaction) {
        StoryManager.deleteAllStories(forSender: contactAci, tx: tx)
    }

    func deleteAllStories(groupId: Data, tx: DBWriteTransaction) {
        StoryManager.deleteAllStories(forGroupId: groupId, tx: tx)
    }
}

// MARK: Intents

protocol _ThreadDeletionManagerImpl_IntentsManager_Shim {
    func deleteAllIntents(withGroupIdentifier groupIdentifier: String)
}

final class _ThreadDeletionManagerImpl_IntentsManager_Wrapper: _ThreadDeletionManagerImpl_IntentsManager_Shim {
    init() {}

    func deleteAllIntents(withGroupIdentifier groupIdentifier: String) {
        INInteraction.delete(with: groupIdentifier)
    }
}

// MARK: -

#if TESTABLE_BUILD

open class MockThreadDeletionManager: ThreadDeletionManager {
    open func deleteThreads(_ threads: [TSThread], sendDeleteForMeSyncMessage: Bool, updateStorageService: Bool, localIdentifiers: LocalIdentifiers, tx: DBWriteTransaction) {}
    open func removeAllInteractions(thread: TSThread, deleteForMeSyncMessagePolicy: DeleteForMeSyncMessagePolicy?, tx: DBWriteTransaction) {}
    open func removeIntentsForTerminatedGroup(threadUniqueId: String) {}
}

#endif
