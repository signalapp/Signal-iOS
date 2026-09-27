//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

enum BackupSubscriptionLoadingState: Equatable {
    enum LoadedBackupSubscription: Equatable {
        case freeAndEnabled
        case freeAndDisabled
        case paidButFreeForTesters
        case paid(price: FiatMoney, renewalDate: Date)
        case paidButExpiring(expirationDate: Date)
        case paidButExpired(expirationDate: Date)
        case paidButFailedToRenew
        case paidButIAPNotFoundLocally
    }

    case loading
    case loaded(LoadedBackupSubscription)
    case networkError
    case notRegisteredError
    case genericError
}

struct BackupSubscriptionLoader {
    let backupPlanManager: BackupPlanManager
    let backupSubscriptionManager: BackupSubscriptionManager
    let backupSubscriptionIssueStore: BackupSubscriptionIssueStore
    let db: DB

    func load() async throws -> BackupSubscriptionLoadingState.LoadedBackupSubscription {
        var currentBackupPlan = db.read { backupPlanManager.backupPlan(tx: $0) }

        switch currentBackupPlan {
        case .free:
            return .freeAndEnabled
        case .paidAsTester:
            return .paidButFreeForTesters
        case .disabling, .disabled:
            // Our IAP subscription may be active even if Backups are disabled,
            // and if so we want to load the state of said subscription.
            break
        case .paid, .paidExpiringSoon:
            break
        }

        let fetchedBackupSubscription: Subscription? = try await backupSubscriptionManager
            .fetchAndMaybeDowngradeSubscription()

        // Now that we've fetched a subscription, refetch state that may have
        // changed as a result.
        var backupIAPNotFoundLocally: Bool!
        db.read { tx in
            currentBackupPlan = backupPlanManager.backupPlan(tx: tx)
            backupIAPNotFoundLocally = backupSubscriptionIssueStore.shouldShowIAPSubscriptionNotFoundLocallyWarning(tx: tx)
        }

        if backupIAPNotFoundLocally {
            return .paidButIAPNotFoundLocally
        }

        let backupSubscription: Subscription
        switch currentBackupPlan {
        case .free:
            return .freeAndEnabled
        case .paidAsTester:
            return .paidButFreeForTesters
        case .disabling, .disabled:
            if let fetchedBackupSubscription {
                backupSubscription = fetchedBackupSubscription
            } else {
                return .freeAndDisabled
            }
        case .paid, .paidExpiringSoon:
            if let fetchedBackupSubscription {
                backupSubscription = fetchedBackupSubscription
            } else {
                owsFailDebug("Missing Backups subscription after fetch, but still on paid plan!")
                return .freeAndEnabled
            }
        }

        switch backupSubscription.status {
        case .canceled, .unrecognized:
            fallthrough
        case .active:
            let endOfCurrentPeriod = backupSubscription.endOfCurrentPeriod
            if backupSubscription.cancelAtEndOfPeriod {
                if endOfCurrentPeriod.isAfterNow {
                    return .paidButExpiring(expirationDate: endOfCurrentPeriod)
                } else {
                    return .paidButExpired(expirationDate: endOfCurrentPeriod)
                }
            } else {
                return .paid(
                    price: backupSubscription.amount,
                    renewalDate: endOfCurrentPeriod,
                )
            }
        case .pastDue:
            // The .pastDue status is returned if we're in the IAP "billing
            // retry", period, which indicates something has gone wrong with a
            // subscription renewal.
            //
            // SeeAlso: BackupSubscriptionManager
            return .paidButFailedToRenew
        }
    }
}
