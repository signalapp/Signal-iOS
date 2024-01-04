//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol PinnedThreadStore {

    func pinnedThreadIds(tx: DBReadTransaction) -> [String]

    func isThreadPinned(_ thread: TSThread, tx: DBReadTransaction) -> Bool
}

/// Only to be used by PinnedThreadStoreManager
public protocol PinnedThreadStoreWrite: PinnedThreadStore {

    func updatePinnedThreadIds(_ pinnedThreadIds: [String], tx: DBWriteTransaction)
}

public class PinnedThreadStoreImpl: PinnedThreadStoreWrite {

    private static let pinnedThreadIdsKey = "pinnedThreadIds"

    private let keyValueStore: KeyValueStore

    public init(
        keyValueStoreFactory: KeyValueStoreFactory
    ) {
        self.keyValueStore = keyValueStoreFactory.keyValueStore(collection: "PinnedConversationManager")
    }

    public func pinnedThreadIds(tx: DBReadTransaction) -> [String] {
        return keyValueStore.getObject(
            forKey: Self.pinnedThreadIdsKey,
            transaction: tx
        ) as? [String] ?? []
    }

    public func isThreadPinned(_ thread: TSThread, tx: DBReadTransaction) -> Bool {
        return pinnedThreadIds(tx: tx).contains(thread.uniqueId)
    }

    public func updatePinnedThreadIds(_ pinnedThreadIds: [String], tx: DBWriteTransaction) {
        let pinnedThreadIds: [String] = Array(pinnedThreadIds.prefix(PinnedThreads.maxPinnedThreads))
        keyValueStore.setObject(pinnedThreadIds, key: Self.pinnedThreadIdsKey, transaction: tx)
    }
}
