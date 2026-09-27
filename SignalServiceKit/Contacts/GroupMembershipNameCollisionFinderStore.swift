//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct GroupMembershipNameCollisionFinderStore: ThreadRemoverObserver {
    private let keyValueStore = NewKeyValueStore(collection: "GroupThreadCollisionFinder")

    public init() {
    }

    public func recentProfileUpdateSearchStartId(forThreadUniqueId threadUniqueId: String, tx: DBReadTransaction) -> UInt64? {
        return keyValueStore.fetchValue(UInt64.self, forKey: threadUniqueId, tx: tx)
    }

    public func setRecentProfileUpdateSearchStartId(_ newValue: UInt64, forThreadUniqueId threadUniqueId: String, tx: DBWriteTransaction) {
        let existingValue = recentProfileUpdateSearchStartId(forThreadUniqueId: threadUniqueId, tx: tx) ?? 0
        keyValueStore.writeValue(max(newValue, existingValue), forKey: threadUniqueId, tx: tx)
    }

    public func didRemoveThread(_ thread: TSThread, tx: DBWriteTransaction) {
        keyValueStore.removeValue(forKey: thread.uniqueId, tx: tx)
    }
}
