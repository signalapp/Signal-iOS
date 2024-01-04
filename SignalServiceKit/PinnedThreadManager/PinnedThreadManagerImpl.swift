//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum PinnedThreadError: Error {
    case tooManyPinnedThreads
}

// MARK: -

public class PinnedThreadManagerImpl: PinnedThreadManager {

    private let db: DB
    private let pinnedThreadStore: PinnedThreadStoreWrite
    private let storageServiceManager: StorageServiceManager
    private let threadStore: ThreadStore

    public init(
        db: DB,
        pinnedThreadStore: PinnedThreadStoreWrite,
        storageServiceManager: StorageServiceManager,
        threadStore: ThreadStore
    ) {
        self.db = db
        self.pinnedThreadStore = pinnedThreadStore
        self.storageServiceManager = storageServiceManager
        self.threadStore = threadStore
    }

    public func pinnedThreadIds(tx: DBReadTransaction) -> [String] {
        return pinnedThreadStore.pinnedThreadIds(tx: tx)
    }

    public func pinnedThreads(tx: DBReadTransaction) -> [TSThread] {
        return pinnedThreadIds(tx: tx).compactMap { threadId in
            guard let thread = threadStore.fetchThread(uniqueId: threadId, tx: tx) else {
                Logger.warn("pinned thread record no longer exists \(threadId)")
                return nil
            }

            let associatedData = threadStore.fetchOrDefaultAssociatedData(for: thread, tx: tx)

            // Ignore deleted or archived pinned threads. These should exist, but it's
            // possible they are incorrectly received from linked devices.
            guard canPin(thread, with: associatedData) else {
                Logger.warn("Ignoring deleted or archived pinned thread \(threadId)")
                return nil
            }
            return thread
        }
    }

    public func isThreadPinned(_ thread: TSThread, tx: DBReadTransaction) -> Bool {
        return pinnedThreadStore.isThreadPinned(thread, tx: tx)
    }

    public func updatePinnedThreadIds(
        _ pinnedThreadIds: [String],
        updateStorageService: Bool,
        tx: DBWriteTransaction
    ) {
        let previousPinnedThreadIds = pinnedThreadStore.pinnedThreadIds(tx: tx)
        pinnedThreadStore.updatePinnedThreadIds(pinnedThreadIds, tx: tx)
        // Read again to get the final new value.
        let pinnedThreadIds = pinnedThreadStore.pinnedThreadIds(tx: tx)

        if previousPinnedThreadIds != pinnedThreadIds {
            let changedThreadIds = Set(previousPinnedThreadIds).symmetricDifference(pinnedThreadIds)

            // Touch any threads whose pin state changed, so we update the UI
            for threadId in changedThreadIds {
                guard let thread = threadStore.fetchThread(uniqueId: threadId, tx: tx) else {
                    // In some legitimate cases, we may not yet have a thread for a pinned
                    // thread. For example, if you received a pinned GV2 thread via a storage
                    // sync, but have not yet fetched the GV2 thread. We'll update the UI to
                    // reflect it when the thread is ready.
                    continue
                }

                let associatedData = threadStore.fetchOrDefaultAssociatedData(for: thread, tx: tx)

                if pinnedThreadIds.contains(threadId) && (associatedData.isArchived || !thread.shouldThreadBeVisible) {
                    // Pinning a thread should unarchive it and make it visible if it was not already so.
                    threadStore.updateAssociatedData(
                        associatedData,
                        isArchived: false,
                        updateStorageService: updateStorageService,
                        tx: tx
                    )
                    threadStore.update(thread, withShouldThreadBeVisible: true, tx: tx)
                } else {
                    self.db.touch(thread, shouldReindex: false, tx: tx)
                }
            }
        }
    }

    public func pinThread(
        _ thread: TSThread,
        updateStorageService: Bool,
        tx: DBWriteTransaction
    ) throws {
        // When pinning a thread, we want to treat the existing list of pinned
        // threads as only those that actually have current threads. Otherwise,
        // there may be a pinned thread that you can't see preventing you from
        // pinning a new conversation (e.g. a v2 group we haven't created yet)
        var pinnedThreadIds = pinnedThreads(tx: tx).map { $0.uniqueId }

        guard !pinnedThreadIds.contains(thread.uniqueId) else {
            throw OWSGenericError("Attempted to pin thread that is already pinned.")
        }

        guard pinnedThreadIds.count < PinnedThreads.maxPinnedThreads else { throw PinnedThreadError.tooManyPinnedThreads }

        pinnedThreadIds.append(thread.uniqueId)
        updatePinnedThreadIds(pinnedThreadIds, updateStorageService: updateStorageService, tx: tx)

        if updateStorageService {
            storageServiceManager.recordPendingLocalAccountUpdates()
        }
    }

    public func unpinThread(
        _ thread: TSThread,
        updateStorageService: Bool,
        tx: DBWriteTransaction
    ) throws {
        var pinnedThreadIds = pinnedThreadStore.pinnedThreadIds(tx: tx)

        guard let idx = pinnedThreadIds.firstIndex(of: thread.uniqueId) else {
            throw OWSGenericError("Attempted to unpin thread that is not pinned.")
        }

        pinnedThreadIds.remove(at: idx)
        updatePinnedThreadIds(pinnedThreadIds, updateStorageService: updateStorageService, tx: tx)

        if updateStorageService {
            self.storageServiceManager.recordPendingLocalAccountUpdates()
        }
    }

    public func handleUpdatedThread(_ thread: TSThread, tx: DBWriteTransaction) {
        guard pinnedThreadStore.pinnedThreadIds(tx: tx).contains(thread.uniqueId) else { return }

        let associatedData = threadStore.fetchOrDefaultAssociatedData(for: thread, tx: tx)

        // If we now can't pin a thread, we should unpin it.
        guard !canPin(thread, with: associatedData) else { return }

        do {
            try unpinThread(thread, updateStorageService: true, tx: tx)
        } catch {
            owsFailDebug("Failed to upin updated thread \(error)")
        }
    }

    private func canPin(_ thread: TSThread, with associatedData: ThreadAssociatedData) -> Bool {
        owsAssertDebug(thread.uniqueId == associatedData.threadUniqueId)
        return thread.shouldThreadBeVisible && !associatedData.isArchived
    }
}
