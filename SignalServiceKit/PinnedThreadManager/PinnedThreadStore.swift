//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct PinnedThreadStore {

    private static let pinnedThreadIdsKey = "pinnedThreadIds"

    private let keyValueStore: KeyValueStore

    public init() {
        self.keyValueStore = KeyValueStore(collection: "PinnedConversationManager")
    }

    public func pinnedThreadUniqueIds(tx: DBReadTransaction) -> [String] {
        return keyValueStore.getStringArray(Self.pinnedThreadIdsKey, transaction: tx) ?? []
    }

    public func updatePinnedThreadUniqueIds(_ pinnedThreadIds: [String], tx: DBWriteTransaction) {
        keyValueStore.setStringArray(pinnedThreadIds, key: Self.pinnedThreadIdsKey, transaction: tx)
    }
}
