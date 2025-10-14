//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public struct BackupSubscriptionIssueStore {
    private enum Keys {
        static let shouldWarnSubscriptionExpired = "shouldWarnSubscriptionExpired"
    }

    private let kvStore: NewKeyValueStore

    public init() {
        self.kvStore = NewKeyValueStore(collection: "BackupSubscriptionIssueStore")
    }

    // MARK: -

    public func shouldWarnSubscriptionExpired(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(
            Bool.self,
            forKey: Keys.shouldWarnSubscriptionExpired,
            tx: tx,
        ) ?? false
    }

    public func setShouldWarnSubscriptionExpired(_ value: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(value, forKey: Keys.shouldWarnSubscriptionExpired, tx: tx)
    }
}
