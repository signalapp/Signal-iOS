//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension Notification.Name {
    public static let backupSubscriptionAlreadyRedeemedDidChange = Notification.Name("BackupSubscriptionAlreadyRedeemedDidChange")
    public static let backupIAPNotFoundLocallyDidChange = Notification.Name("BackupIAPNotFoundLocallyDidChange")
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

        enum IAPSubscriptionNotFoundLocally {
            static let shouldWarn = "IAPSubscriptionNotFoundLocally.shouldWarn"
            static let shouldShowChatListBadge = "IAPSubscriptionNotFoundLocally.shouldShowChatListBadge"
            static let shouldShowChatListMenuItem = "IAPSubscriptionNotFoundLocally.shouldShowChatListMenuItem"
        }

        enum IAPSubscriptionExpired {
            static let shouldWarn = "shouldWarnIAPSubscriptionExpired"
        }

        enum TestFlightSubscriptionExpired {
            static let shouldWarn = "shouldWarnTestFlightSubscriptionExpired"
        }
    }

    private let kvStore: NewKeyValueStore
    private let logger: PrefixedLogger

    public init() {
        self.kvStore = NewKeyValueStore(collection: "BackupSubscriptionIssueStore")
        self.logger = PrefixedLogger(prefix: "[Backups][Sub]")
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

        logger.warn("")
        kvStore.writeValue(true, forKey: Keys.IAPSubscriptionFailedToRenew.shouldWarn, tx: tx)
        kvStore.writeValue(endOfCurrentPeriod, forKey: Keys.IAPSubscriptionFailedToRenew.lastWarnedEndOfCurrentPeriod, tx: tx)
    }

    public func setDidWarnIAPSubscriptionFailedToRenew(tx: DBWriteTransaction) {
        kvStore.writeValue(false, forKey: Keys.IAPSubscriptionFailedToRenew.shouldWarn, tx: tx)
        // Don't wipe lastWarnedEndOfCurrentPeriod, because we never again need
        // to re-warn for a given subscription failing to renew.
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

        logger.warn("")
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
        logger.info("")
        kvStore.removeValue(forKey: Keys.IAPSubscriptionAlreadyRedeemed.shouldWarn, tx: tx)
        kvStore.removeValue(forKey: Keys.IAPSubscriptionAlreadyRedeemed.shouldShowChatListBadge, tx: tx)
        kvStore.removeValue(forKey: Keys.IAPSubscriptionAlreadyRedeemed.shouldShowChatListMenuItem, tx: tx)
        // Remove the lastWarnedEndOfCurrentPeriod, because it's possible to
        // clear this warning (e.g., downgrade to free) and try again to redeem
        // the same already-redeemed subscription period, in which case we
        // should warn again.
        kvStore.removeValue(forKey: Keys.IAPSubscriptionAlreadyRedeemed.lastWarnedEndOfCurrentPeriod, tx: tx)

        tx.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(name: .backupSubscriptionAlreadyRedeemedDidChange, object: nil)
        }
    }

    // MARK: -

    public func shouldShowIAPSubscriptionNotFoundLocallyWarning(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: Keys.IAPSubscriptionNotFoundLocally.shouldWarn, tx: tx) ?? false
    }

    public func shouldShowIAPSubscriptionNotFoundLocallyChatListBadge(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: Keys.IAPSubscriptionNotFoundLocally.shouldShowChatListBadge, tx: tx) ?? false
    }

    public func shouldShowIAPSubscriptionNotFoundLocallyChatListMenuItem(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: Keys.IAPSubscriptionNotFoundLocally.shouldShowChatListMenuItem, tx: tx) ?? false
    }

    public func setShouldWarnIAPSubscriptionNotFoundLocally(tx: DBWriteTransaction) {
        logger.warn("")
        kvStore.writeValue(true, forKey: Keys.IAPSubscriptionNotFoundLocally.shouldWarn, tx: tx)
        kvStore.writeValue(true, forKey: Keys.IAPSubscriptionNotFoundLocally.shouldShowChatListBadge, tx: tx)
        kvStore.writeValue(true, forKey: Keys.IAPSubscriptionNotFoundLocally.shouldShowChatListMenuItem, tx: tx)

        tx.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(name: .backupIAPNotFoundLocallyDidChange, object: nil)
        }
    }

    public func setDidAckIAPSubscriptionNotFoundLocallyChatListBadge(tx: DBWriteTransaction) {
        kvStore.writeValue(false, forKey: Keys.IAPSubscriptionNotFoundLocally.shouldShowChatListBadge, tx: tx)
    }

    public func setDidAckIAPSubscriptionNotFoundLocallyChatListMenuItem(tx: DBWriteTransaction) {
        kvStore.writeValue(false, forKey: Keys.IAPSubscriptionNotFoundLocally.shouldShowChatListMenuItem, tx: tx)
    }

    public func setStopWarningIAPSubscriptionNotFoundLocally(tx: DBWriteTransaction) {
        logger.info("")
        kvStore.removeValue(forKey: Keys.IAPSubscriptionNotFoundLocally.shouldWarn, tx: tx)
        kvStore.removeValue(forKey: Keys.IAPSubscriptionNotFoundLocally.shouldShowChatListBadge, tx: tx)
        kvStore.removeValue(forKey: Keys.IAPSubscriptionNotFoundLocally.shouldShowChatListMenuItem, tx: tx)

        tx.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(name: .backupIAPNotFoundLocallyDidChange, object: nil)
        }
    }

    // MARK: -

    public func shouldWarnIAPSubscriptionExpired(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: Keys.IAPSubscriptionExpired.shouldWarn, tx: tx) ?? false
    }

    public func setShouldWarnIAPSubscriptionExpired(_ value: Bool, tx: DBWriteTransaction) {
        if value { logger.warn("") }
        kvStore.writeValue(value, forKey: Keys.IAPSubscriptionExpired.shouldWarn, tx: tx)
    }

    // MARK: -

    public func shouldWarnTestFlightSubscriptionExpired(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: Keys.TestFlightSubscriptionExpired.shouldWarn, tx: tx) ?? false
    }

    public func setShouldWarnTestFlightSubscriptionExpired(_ value: Bool, tx: DBWriteTransaction) {
        if value { logger.warn("") }
        kvStore.writeValue(value, forKey: Keys.TestFlightSubscriptionExpired.shouldWarn, tx: tx)
    }
}
