//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Responsible for hard-deleting a thread.
///
/// This type is an implementation detail; if you're looking to colloquially
/// "delete a thread", e.g. in response to a user action, you probably want
/// ``ThreadDeletionManager``.
public protocol ThreadRemover {
    func remove(_ thread: TSThread, tx: DBWriteTransaction)
}

class ThreadRemoverImpl: ThreadRemover {
    private let chatColorSettingStore: ChatColorSettingStore
    private let databaseStorage: Shims.DatabaseStorage
    private let deletedCallRecordStore: any DeletedCallRecordStore
    private let disappearingMessagesConfigurationStore: DisappearingMessagesConfigurationStore
    private let lastVisibleInteractionStore: LastVisibleInteractionStore
    private let threadAssociatedDataStore: ThreadAssociatedDataStore
    private let threadReadCache: Shims.ThreadReadCache
    private let threadReplyInfoStore: ThreadReplyInfoStore
    private let threadStore: ThreadStore
    private let wallpaperStore: WallpaperStore

    init(
        chatColorSettingStore: ChatColorSettingStore,
        databaseStorage: Shims.DatabaseStorage,
        deletedCallRecordStore: any DeletedCallRecordStore,
        disappearingMessagesConfigurationStore: DisappearingMessagesConfigurationStore,
        lastVisibleInteractionStore: LastVisibleInteractionStore,
        threadAssociatedDataStore: ThreadAssociatedDataStore,
        threadReadCache: Shims.ThreadReadCache,
        threadReplyInfoStore: ThreadReplyInfoStore,
        threadStore: ThreadStore,
        wallpaperStore: WallpaperStore,
    ) {
        self.chatColorSettingStore = chatColorSettingStore
        self.databaseStorage = databaseStorage
        self.deletedCallRecordStore = deletedCallRecordStore
        self.disappearingMessagesConfigurationStore = disappearingMessagesConfigurationStore
        self.lastVisibleInteractionStore = lastVisibleInteractionStore
        self.threadAssociatedDataStore = threadAssociatedDataStore
        self.threadReadCache = threadReadCache
        self.threadReplyInfoStore = threadReplyInfoStore
        self.threadStore = threadStore
        self.wallpaperStore = wallpaperStore
    }

    func remove(_ thread: TSThread, tx: DBWriteTransaction) {
        let threadId = thread.id.owsFailUnwrap("must have rowid")
        chatColorSettingStore.setRawSetting(nil, for: thread.uniqueId, tx: tx)
        databaseStorage.updateIdMapping(thread: thread, tx: tx)
        deletedCallRecordStore.deleteRecords(forThreadId: threadId, tx: tx)
        disappearingMessagesConfigurationStore.remove(for: thread, tx: tx)
        threadAssociatedDataStore.remove(for: thread.uniqueId, tx: tx)
        threadReplyInfoStore.remove(for: thread.uniqueId, tx: tx)
        threadStore.removeThread(thread, tx: tx)
        threadReadCache.didRemove(thread: thread, tx: tx)
        wallpaperStore.reset(for: thread, tx: tx)
        lastVisibleInteractionStore.clearLastVisibleInteraction(for: thread, tx: tx)
    }
}

// MARK: -

extension ThreadRemoverImpl {
    enum Shims {
        typealias ThreadReadCache = _ThreadRemoverImpl_ThreadReadCacheShim
        typealias DatabaseStorage = _ThreadRemoverImpl_DatabaseStorageShim
    }

    enum Wrappers {
        typealias ThreadReadCache = _ThreadRemoverImpl_ThreadReadCacheWrapper
        typealias DatabaseStorage = _ThreadRemoverImpl_DatabaseStorageWrapper
    }
}

protocol _ThreadRemoverImpl_ThreadReadCacheShim {
    func didRemove(thread: TSThread, tx: DBWriteTransaction)
}

class _ThreadRemoverImpl_ThreadReadCacheWrapper: _ThreadRemoverImpl_ThreadReadCacheShim {
    private let threadReadCache: ThreadReadCache
    init(_ threadReadCache: ThreadReadCache) {
        self.threadReadCache = threadReadCache
    }

    func didRemove(thread: TSThread, tx: DBWriteTransaction) {
        threadReadCache.didRemove(thread: thread, transaction: tx)
    }
}

protocol _ThreadRemoverImpl_DatabaseStorageShim {
    func updateIdMapping(thread: TSThread, tx: DBWriteTransaction)
}

class _ThreadRemoverImpl_DatabaseStorageWrapper: _ThreadRemoverImpl_DatabaseStorageShim {
    private let databaseStorage: SDSDatabaseStorage
    init(_ databaseStorage: SDSDatabaseStorage) {
        self.databaseStorage = databaseStorage
    }

    func updateIdMapping(thread: TSThread, tx: DBWriteTransaction) {
        databaseStorage.updateIdMapping(thread: thread, transaction: tx)
    }
}

// MARK: - Unit Tests

#if TESTABLE_BUILD

class ThreadRemover_MockThreadReadCache: ThreadRemoverImpl.Shims.ThreadReadCache {
    func didRemove(thread: TSThread, tx: DBWriteTransaction) {}
}

class ThreadRemover_MockDatabaseStorage: ThreadRemoverImpl.Shims.DatabaseStorage {
    func updateIdMapping(thread: TSThread, tx: DBWriteTransaction) {}
}

#endif
