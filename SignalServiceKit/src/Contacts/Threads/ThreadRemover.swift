//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol ThreadRemover {
    func remove(_ thread: TSPrivateStoryThread, tx: DBWriteTransaction)
}

class ThreadRemoverImpl: ThreadRemover {
    private let databaseStorage: Shims.DatabaseStorage
    private let disappearingMessagesConfigurationStore: DisappearingMessagesConfigurationStore
    private let fullTextSearchFinder: Shims.FullTextSearchFinder
    private let interactionRemover: Shims.InteractionRemover
    private let threadAssociatedDataStore: ThreadAssociatedDataStore
    private let threadReadCache: Shims.ThreadReadCache
    private let threadReplyInfoStore: ThreadReplyInfoStore
    private let threadStore: ThreadStore

    init(
        databaseStorage: Shims.DatabaseStorage,
        disappearingMessagesConfigurationStore: DisappearingMessagesConfigurationStore,
        fullTextSearchFinder: Shims.FullTextSearchFinder,
        interactionRemover: Shims.InteractionRemover,
        threadAssociatedDataStore: ThreadAssociatedDataStore,
        threadReadCache: Shims.ThreadReadCache,
        threadReplyInfoStore: ThreadReplyInfoStore,
        threadStore: ThreadStore
    ) {
        self.databaseStorage = databaseStorage
        self.disappearingMessagesConfigurationStore = disappearingMessagesConfigurationStore
        self.fullTextSearchFinder = fullTextSearchFinder
        self.interactionRemover = interactionRemover
        self.threadAssociatedDataStore = threadAssociatedDataStore
        self.threadReadCache = threadReadCache
        self.threadReplyInfoStore = threadReplyInfoStore
        self.threadStore = threadStore
    }

    func remove(_ thread: TSPrivateStoryThread, tx: DBWriteTransaction) {
        databaseStorage.updateIdMapping(thread: thread, tx: tx)
        interactionRemover.removeAllInteractions(in: thread, tx: tx)
        disappearingMessagesConfigurationStore.remove(for: thread, tx: tx)
        threadAssociatedDataStore.remove(for: thread.uniqueId, tx: tx)
        threadReplyInfoStore.remove(for: thread.uniqueId, tx: tx)
        threadStore.removeThread(thread, tx: tx)
        threadReadCache.didRemove(thread: thread, tx: tx)

        if type(of: thread).ftsIndexMode != .never {
            fullTextSearchFinder.modelWasRemoved(model: thread, tx: tx)
        }
    }
}

// MARK: -

extension ThreadRemoverImpl {
    enum Shims {
        typealias InteractionRemover = _ThreadRemoverImpl_InteractionRemoverShim
        typealias FullTextSearchFinder = _ThreadRemoverImpl_FullTextSearchFinderShim
        typealias ThreadReadCache = _ThreadRemoverImpl_ThreadReadCacheShim
        typealias DatabaseStorage = _ThreadRemoverImpl_DatabaseStorageShim
    }
    enum Wrappers {
        typealias InteractionRemover = _ThreadRemoverImpl_InteractionRemoverWrapper
        typealias FullTextSearchFinder = _ThreadRemoverImpl_FullTextSearchFinderWrapper
        typealias ThreadReadCache = _ThreadRemoverImpl_ThreadReadCacheWrapper
        typealias DatabaseStorage = _ThreadRemoverImpl_DatabaseStorageWrapper
    }
}

protocol _ThreadRemoverImpl_InteractionRemoverShim {
    func removeAllInteractions(in thread: TSThread, tx: DBWriteTransaction)
}

class _ThreadRemoverImpl_InteractionRemoverWrapper: _ThreadRemoverImpl_InteractionRemoverShim {
    func removeAllInteractions(in thread: TSThread, tx: DBWriteTransaction) {
        thread.removeAllThreadInteractions(transaction: SDSDB.shimOnlyBridge(tx))
    }
}

protocol _ThreadRemoverImpl_FullTextSearchFinderShim {
    func modelWasRemoved(model: SDSIndexableModel, tx: DBWriteTransaction)
}

class _ThreadRemoverImpl_FullTextSearchFinderWrapper: _ThreadRemoverImpl_FullTextSearchFinderShim {
    func modelWasRemoved(model: SDSIndexableModel, tx: DBWriteTransaction) {
        FullTextSearchFinder.modelWasRemoved(model: model, transaction: SDSDB.shimOnlyBridge(tx))
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
        threadReadCache.didRemove(thread: thread, transaction: SDSDB.shimOnlyBridge(tx))
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
        databaseStorage.updateIdMapping(thread: thread, transaction: SDSDB.shimOnlyBridge(tx))
    }
}
