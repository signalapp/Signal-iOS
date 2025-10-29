//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public struct BackupSubscriptionIssueStore {
    private enum Keys {
        static let shouldWarnIAPSubscriptionFailedToRenew = "shouldWarnIAPSubscriptionFailedToRenew"
        static let lastWarnedIAPSubscriptionFailedToRenewEndOfCurrentPeriod = "lastWarnedIAPSubscriptionFailedToRenewEndOfCurrentPeriod"

        static let shouldWarnIAPSubscriptionExpired = "shouldWarnIAPSubscriptionExpired"
        static let shouldWarnTestFlightSubscriptionExpired = "shouldWarnTestFlightSubscriptionExpired"
    }

    private let kvStore: NewKeyValueStore

    public init() {
        self.kvStore = NewKeyValueStore(collection: "BackupSubscriptionIssueStore")
    }

    // MARK: -

    public func shouldWarnIAPSubscriptionFailedToRenew(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(
            Bool.self,
            forKey: Keys.shouldWarnIAPSubscriptionFailedToRenew,
            tx: tx,
        ) ?? false
    }

    public func setShouldWarnIAPSubscriptionFailedToRenew(
        endOfCurrentPeriod: Date,
        tx: DBWriteTransaction,
    ) {
        if
            let lastWarnedEndOfCurrentPeriod = kvStore.fetchValue(
                Date.self,
                forKey: Keys.lastWarnedIAPSubscriptionFailedToRenewEndOfCurrentPeriod,
                tx: tx,
            ),
            endOfCurrentPeriod == lastWarnedEndOfCurrentPeriod
        {
            // Only save a single warning per period-that-failed-to-renew.
            return
        }

        kvStore.writeValue(true, forKey: Keys.shouldWarnIAPSubscriptionFailedToRenew, tx: tx)
        kvStore.writeValue(endOfCurrentPeriod, forKey: Keys.lastWarnedIAPSubscriptionFailedToRenewEndOfCurrentPeriod, tx: tx)
    }

    public func setDidWarnIAPSubscriptionFailedToRenew(tx: DBWriteTransaction) {
        kvStore.writeValue(false, forKey: Keys.shouldWarnIAPSubscriptionFailedToRenew, tx: tx)
    }

    // MARK: -

    public func shouldWarnIAPSubscriptionExpired(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(
            Bool.self,
            forKey: Keys.shouldWarnIAPSubscriptionExpired,
            tx: tx,
        ) ?? false
    }

    public func setShouldWarnIAPSubscriptionExpired(_ value: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(value, forKey: Keys.shouldWarnIAPSubscriptionExpired, tx: tx)
    }

    // MARK: -

    public func shouldWarnTestFlightSubscriptionExpired(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(
            Bool.self,
            forKey: Keys.shouldWarnTestFlightSubscriptionExpired,
            tx: tx,
        ) ?? false
    }

    public func setShouldWarnTestFlightSubscriptionExpired(_ value: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(value, forKey: Keys.shouldWarnTestFlightSubscriptionExpired, tx: tx)
    }
}
