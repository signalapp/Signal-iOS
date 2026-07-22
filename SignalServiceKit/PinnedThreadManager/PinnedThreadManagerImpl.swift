//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class PinnedThreadManagerImpl: PinnedThreadManager {

    private let db: any DB
    private let pinnedThreadStore: PinnedThreadStore
    private let storageServiceManager: StorageServiceManager
    private let threadStore: ThreadStore

    public init(
        db: any DB,
        pinnedThreadStore: PinnedThreadStore,
        storageServiceManager: StorageServiceManager,
        threadStore: ThreadStore,
    ) {
        self.db = db
        self.pinnedThreadStore = pinnedThreadStore
        self.storageServiceManager = storageServiceManager
        self.threadStore = threadStore
    }

    public func pinnedThreads(tx: DBReadTransaction) -> [TSThread] {
        return pinnedThreadStore.pinnedThreadUniqueIds(tx: tx).compactMap { threadUniqueId in
            guard let thread = threadStore.fetchThread(uniqueId: threadUniqueId, tx: tx) else {
                Logger.warn("pinned thread record no longer exists \(threadUniqueId)")
                return nil
            }

            let associatedData = threadStore.fetchOrDefaultAssociatedData(for: thread, tx: tx)

            // Ignore deleted or archived pinned threads. These shouldn't exist, but
            // it's possible they are incorrectly received from linked devices.
            guard canPin(thread, with: associatedData) else {
                Logger.warn("Ignoring deleted or archived pinned thread \(threadUniqueId)")
                return nil
            }
            return thread
        }
    }

    public func updatePinnedThreadUniqueIds(
        _ pinnedThreadUniqueIds: [String],
        updateStorageService: Bool,
        tx: DBWriteTransaction,
    ) {
        let oldPinnedThreadUniqueIds = pinnedThreadStore.pinnedThreadUniqueIds(tx: tx)
        if pinnedThreadUniqueIds == oldPinnedThreadUniqueIds {
            return
        }
        pinnedThreadStore.updatePinnedThreadUniqueIds(pinnedThreadUniqueIds, tx: tx)

        let changedThreadIds = Set(oldPinnedThreadUniqueIds).symmetricDifference(pinnedThreadUniqueIds)

        // Touch any threads whose pin state changed, so we update the UI
        for threadUniqueId in changedThreadIds {
            guard let thread = threadStore.fetchThread(uniqueId: threadUniqueId, tx: tx) else {
                // In some legitimate cases, we may not yet have a thread for a pinned
                // thread. For example, if you received a pinned GV2 thread via a storage
                // sync, but have not yet fetched the GV2 thread. We'll update the UI to
                // reflect it when the thread is ready.
                continue
            }

            let associatedData = threadStore.fetchOrDefaultAssociatedData(for: thread, tx: tx)

            if pinnedThreadUniqueIds.contains(threadUniqueId), !canPin(thread, with: associatedData) {
                // Pinning a thread should unarchive it and make it visible if it was not already so.
                threadStore.updateAssociatedData(
                    associatedData,
                    isArchived: false,
                    updateStorageService: updateStorageService,
                    tx: tx,
                )
                threadStore.update(thread, withShouldThreadBeVisible: true, tx: tx)
            } else {
                self.db.touch(thread: thread, shouldReindex: false, shouldUpdateChatListUi: true, tx: tx)
            }
        }
    }

    public func pinThread(
        uniqueId: String,
        updateStorageService: Bool,
        tx: DBWriteTransaction,
    ) throws(TooManyPinnedThreadsError) {
        // When pinning a thread, we want to treat the existing list of pinned
        // threads as only those that actually have current threads. Otherwise,
        // there may be a pinned thread that you can't see preventing you from
        // pinning a new conversation (e.g. a v2 group we haven't created yet)
        var pinnedThreadUniqueIds = pinnedThreads(tx: tx).map { $0.uniqueId }

        guard !pinnedThreadUniqueIds.contains(uniqueId) else {
            return
        }

        guard pinnedThreadUniqueIds.count < PinnedThreads.maxPinnedThreads else {
            throw TooManyPinnedThreadsError()
        }

        pinnedThreadUniqueIds.append(uniqueId)
        updatePinnedThreadUniqueIds(pinnedThreadUniqueIds, updateStorageService: updateStorageService, tx: tx)

        if updateStorageService {
            storageServiceManager.recordPendingLocalAccountUpdates()
        }
    }

    public func unpinThread(
        uniqueId: String,
        updateStorageService: Bool,
        tx: DBWriteTransaction,
    ) {
        var pinnedThreadUniqueIds = pinnedThreadStore.pinnedThreadUniqueIds(tx: tx)

        guard let idx = pinnedThreadUniqueIds.firstIndex(of: uniqueId) else {
            return
        }

        pinnedThreadUniqueIds.remove(at: idx)
        updatePinnedThreadUniqueIds(pinnedThreadUniqueIds, updateStorageService: updateStorageService, tx: tx)

        if updateStorageService {
            self.storageServiceManager.recordPendingLocalAccountUpdates()
        }
    }

    public func handleUpdatedThread(_ thread: TSThread, tx: DBWriteTransaction) {
        guard pinnedThreadStore.pinnedThreadUniqueIds(tx: tx).contains(thread.uniqueId) else {
            return
        }

        let associatedData = threadStore.fetchOrDefaultAssociatedData(for: thread, tx: tx)

        if canPin(thread, with: associatedData) {
            return
        }
        // If we now can't pin a thread, we should unpin it.
        unpinThread(uniqueId: thread.uniqueId, updateStorageService: true, tx: tx)
    }

    private func canPin(_ thread: TSThread, with associatedData: ThreadAssociatedData) -> Bool {
        owsAssertDebug(thread.uniqueId == associatedData.threadUniqueId)
        return thread.shouldThreadBeVisible && !associatedData.isArchived
    }
}
