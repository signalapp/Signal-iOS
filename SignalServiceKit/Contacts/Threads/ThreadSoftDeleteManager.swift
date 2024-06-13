//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Intents
import LibSignalClient
import SignalCoreKit

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
        tx: any DBWriteTransaction
    )

    func removeAllInteractions(
        thread: TSThread,
        sendDeleteForMeSyncMessage: Bool,
        tx: any DBWriteTransaction
    )
}

final class ThreadSoftDeleteManagerImpl: ThreadSoftDeleteManager {
    private enum Constants {
        static let interactionDeletionBatchSize: Int = 500
    }

    private let deleteForMeOutgoingSyncMessageManager: DeleteForMeOutgoingSyncMessageManager
    private let deleteForMeSyncMessageSettingsStore: DeleteForMeSyncMessageSettingsStore
    private let intentsManager: Shims.IntentsManager
    private let interactionDeleteManager: InteractionDeleteManager
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let storyManager: Shims.StoryManager
    private let threadReplyInfoStore: ThreadReplyInfoStore
    private let tsAccountManager: TSAccountManager

    private let logger = PrefixedLogger(prefix: "[ThreadDeleteMgr]")

    init(
        deleteForMeOutgoingSyncMessageManager: DeleteForMeOutgoingSyncMessageManager,
        deleteForMeSyncMessageSettingsStore: DeleteForMeSyncMessageSettingsStore,
        intentsManager: Shims.IntentsManager,
        interactionDeleteManager: InteractionDeleteManager,
        recipientDatabaseTable: RecipientDatabaseTable,
        storyManager: Shims.StoryManager,
        threadReplyInfoStore: ThreadReplyInfoStore,
        tsAccountManager: TSAccountManager
    ) {
        self.deleteForMeOutgoingSyncMessageManager = deleteForMeOutgoingSyncMessageManager
        self.deleteForMeSyncMessageSettingsStore = deleteForMeSyncMessageSettingsStore
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
        tx: any DBWriteTransaction
    ) {
        var threadDeletionContexts = [DeleteForMeSyncMessage.Outgoing.ThreadDeletionContext]()

        for thread in threads {
            /// If we're gonna send a `DeleteForMe` sync message we need to get
            /// a deletion context before deleting the thread, since the context
            /// relies on data that will be deleted when the thread is deleted.
            if
                sendDeleteForMeSyncMessage,
                let additionalContext = deleteForMeOutgoingSyncMessageManager.buildThreadDeletionContext(
                    thread: thread,
                    isFullDelete: true,
                    tx: tx
                )
            {
                threadDeletionContexts.append(additionalContext)
            }

            softDelete(
                thread: thread,
                tx: tx
            )
        }

        if sendDeleteForMeSyncMessage {
            deleteForMeOutgoingSyncMessageManager.send(
                threadDeletionContexts: threadDeletionContexts,
                tx: tx
            )
        }
    }

    func removeAllInteractions(
        thread: TSThread,
        sendDeleteForMeSyncMessage: Bool,
        tx: any DBWriteTransaction
    ) {
        var threadDeletionContext: DeleteForMeSyncMessage.Outgoing.ThreadDeletionContext?
        if sendDeleteForMeSyncMessage {
            threadDeletionContext = deleteForMeOutgoingSyncMessageManager.buildThreadDeletionContext(
                thread: thread,
                isFullDelete: false,
                tx: tx
            )
        }

        removeAllInteractions(
            thread: thread,
            tx: tx
        )

        if let threadDeletionContext {
            deleteForMeOutgoingSyncMessageManager.send(
                threadDeletionContexts: [threadDeletionContext],
                tx: tx
            )
        }
    }

    private func softDelete(
        thread: TSThread,
        tx: any DBWriteTransaction
    ) {
        logger.info("Deleting thread with ID \(thread.uniqueId).")

        removeAllInteractions(
            thread: thread,
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
        tx: any DBWriteTransaction
    ) {
        let sdsTx = SDSDB.shimOnlyBridge(tx)

        let isDeleteForMeSyncMessageSendingEnabled = deleteForMeSyncMessageSettingsStore
            .isSendingEnabled(tx: tx)

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

                    let callDeleteBehavior: InteractionDelete.SideEffects.AssociatedCallDeleteBehavior = {
                        if isDeleteForMeSyncMessageSendingEnabled {
                            /// If we're able to send a `DeleteForMe` sync
                            /// message, we don't need to send `CallEvent`s...
                            return .localDeleteOnly
                        } else {
                            /// ...otherwise, we still should.
                            return .localDeleteAndSendCallEventSyncMessage
                        }
                    }()

                    interactionDeleteManager.delete(
                        interactions: interactionBatch,
                        sideEffects: .custom(
                            associatedCallDelete: callDeleteBehavior,
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
    open func softDelete(threads: [TSThread], sendDeleteForMeSyncMessage: Bool, tx: any DBWriteTransaction) {}
    open func removeAllInteractions(thread: TSThread, sendDeleteForMeSyncMessage: Bool, tx: any DBWriteTransaction) {}
}

#endif
