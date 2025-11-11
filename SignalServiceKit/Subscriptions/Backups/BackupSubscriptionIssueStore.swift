//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension Notification.Name {
    public static let backupSubscriptionAlreadyRedeemedDidChange = Notification.Name("BackupSubscriptionAlreadyRedeemedDidChange")
}

public struct BackupSubscriptionIssueStore {
    private enum Keys {
        enum IAPSubscriptionFailedToRenew {
            static let shouldWarn = "shouldWarnIAPSubscriptionFailedToRenew"
            static let lastWarnedEndOfCurrentPeriod = "lastWarnedIAPSubscriptionFailedToRenewEndOfCurrentPeriod"
        }

        enum IAPSubscriptionAlreadyRedeemed {
            static let shouldWarn = "IAPSubscriptionAlreadyRedeemed.shouldWarn"
            static let lastWarnedEndOfCurrentPeriod = "IAPSubscriptionAlreadyRedeemed.lastWarnedEndOfCurrentPeriod"
            static let shouldShowChatListBadge = "IAPSubscriptionAlreadyRedeemed.shouldShowChatListBadge"
            static let shouldShowChatListMenuItem = "IAPSubscriptionAlreadyRedeemed.shouldShowChatListMenuItem"
        }

        enum IAPSubscriptionExpired {
            static let shouldWarn = "shouldWarnIAPSubscriptionExpired"
        }

        enum TestFlightSubscriptionExpired {
            static let shouldWarn = "shouldWarnTestFlightSubscriptionExpired"
        }
    }

    private let kvStore: NewKeyValueStore

    public init() {
        self.kvStore = NewKeyValueStore(collection: "BackupSubscriptionIssueStore")
    }

    // MARK: -

    public func shouldWarnIAPSubscriptionFailedToRenew(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: Keys.IAPSubscriptionFailedToRenew.shouldWarn, tx: tx) ?? false
    }

    public func setShouldWarnIAPSubscriptionFailedToRenew(
        endOfCurrentPeriod: Date,
        tx: DBWriteTransaction,
    ) {
        if
            let lastWarnedEndOfCurrentPeriod = kvStore.fetchValue(
                Date.self,
                forKey: Keys.IAPSubscriptionFailedToRenew.lastWarnedEndOfCurrentPeriod,
                tx: tx,
            ),
            endOfCurrentPeriod == lastWarnedEndOfCurrentPeriod
        {
            // Only save a single warning per period-that-failed-to-renew.
            return
        }

        kvStore.writeValue(true, forKey: Keys.IAPSubscriptionFailedToRenew.shouldWarn, tx: tx)
        kvStore.writeValue(endOfCurrentPeriod, forKey: Keys.IAPSubscriptionFailedToRenew.lastWarnedEndOfCurrentPeriod, tx: tx)
    }

    public func setDidWarnIAPSubscriptionFailedToRenew(tx: DBWriteTransaction) {
        kvStore.writeValue(false, forKey: Keys.IAPSubscriptionFailedToRenew.shouldWarn, tx: tx)
    }

    // MARK: -

    public func shouldShowIAPSubscriptionAlreadyRedeemedWarning(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: Keys.IAPSubscriptionAlreadyRedeemed.shouldWarn, tx: tx) ?? false
    }

    public func shouldShowIAPSubscriptionFailedToRenewChatListBadge(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: Keys.IAPSubscriptionAlreadyRedeemed.shouldShowChatListBadge, tx: tx) ?? false
    }

    public func shouldShowIAPSubscriptionFailedToRenewChatListMenuItem(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: Keys.IAPSubscriptionAlreadyRedeemed.shouldShowChatListMenuItem, tx: tx) ?? false
    }

    public func setShouldWarnIAPSubscriptionAlreadyRedeemed(
        endOfCurrentPeriod: Date,
        tx: DBWriteTransaction,
    ) {
        if
            let lastWarnedEndOfCurrentPeriod = kvStore.fetchValue(
                Date.self,
                forKey: Keys.IAPSubscriptionAlreadyRedeemed.lastWarnedEndOfCurrentPeriod,
                tx: tx,
            ),
            endOfCurrentPeriod == lastWarnedEndOfCurrentPeriod
        {
            // Only save a single warning per period-that-was already-redeemed.
            return
        }

        kvStore.writeValue(true, forKey: Keys.IAPSubscriptionAlreadyRedeemed.shouldWarn, tx: tx)
        kvStore.writeValue(true, forKey: Keys.IAPSubscriptionAlreadyRedeemed.shouldShowChatListBadge, tx: tx)
        kvStore.writeValue(true, forKey: Keys.IAPSubscriptionAlreadyRedeemed.shouldShowChatListMenuItem, tx: tx)
        kvStore.writeValue(endOfCurrentPeriod, forKey: Keys.IAPSubscriptionAlreadyRedeemed.lastWarnedEndOfCurrentPeriod, tx: tx)

        tx.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(name: .backupSubscriptionAlreadyRedeemedDidChange, object: nil)
        }
    }

    public func setDidAckIAPSubscriptionAlreadyRedeemedChatListBadge(tx: DBWriteTransaction) {
        kvStore.writeValue(false, forKey: Keys.IAPSubscriptionAlreadyRedeemed.shouldShowChatListBadge, tx: tx)
    }

    public func setDidAckIAPSubscriptionAlreadyRedeemedChatListMenuItem(tx: DBWriteTransaction) {
        kvStore.writeValue(false, forKey: Keys.IAPSubscriptionAlreadyRedeemed.shouldShowChatListMenuItem, tx: tx)
    }

    public func setStopWarningIAPSubscriptionAlreadyRedeemed(tx: DBWriteTransaction) {
        kvStore.removeValue(forKey: Keys.IAPSubscriptionAlreadyRedeemed.shouldWarn, tx: tx)
        kvStore.removeValue(forKey: Keys.IAPSubscriptionAlreadyRedeemed.shouldShowChatListBadge, tx: tx)
        kvStore.removeValue(forKey: Keys.IAPSubscriptionAlreadyRedeemed.shouldShowChatListMenuItem, tx: tx)
        kvStore.removeValue(forKey: Keys.IAPSubscriptionAlreadyRedeemed.lastWarnedEndOfCurrentPeriod, tx: tx)

        tx.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(name: .backupSubscriptionAlreadyRedeemedDidChange, object: nil)
        }
    }

    // MARK: -

    public func shouldWarnIAPSubscriptionExpired(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: Keys.IAPSubscriptionExpired.shouldWarn, tx: tx) ?? false
    }

    public func setShouldWarnIAPSubscriptionExpired(_ value: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(value, forKey: Keys.IAPSubscriptionExpired.shouldWarn, tx: tx)
    }

    // MARK: -

    public func shouldWarnTestFlightSubscriptionExpired(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: Keys.TestFlightSubscriptionExpired.shouldWarn, tx: tx) ?? false
    }

    public func setShouldWarnTestFlightSubscriptionExpired(_ value: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(value, forKey: Keys.TestFlightSubscriptionExpired.shouldWarn, tx: tx)
    }
}
