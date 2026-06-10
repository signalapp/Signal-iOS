//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import StoreKit

struct BackupPlanUpsellConfiguration {
    enum StoreKitAvailability {
        case available(paidPlanDisplayPrice: String)
        case unavailableForTesters
    }

    let backupSubscriptionConfiguration: BackupSubscriptionConfiguration
    let storeKitAvailability: StoreKitAvailability

    static func load(
        backupSubscriptionManager: BackupSubscriptionManager,
        db: DB,
        subscriptionConfigManager: SubscriptionConfigManager,
    ) async throws(SheetDisplayableError) -> BackupPlanUpsellConfiguration {
        let storeKitAvailability: StoreKitAvailability
        if BuildFlags.Backups.avoidStoreKitForTesters {
            storeKitAvailability = .unavailableForTesters
        } else {
            do {
                storeKitAvailability = .available(
                    paidPlanDisplayPrice: try await backupSubscriptionManager.subscriptionDisplayPrice(),
                )
            } catch StoreKitError.networkError {
                throw .networkError
            } catch {
                owsFailDebug("Failed to get paidPlanDisplayPrice!")
                throw .genericError
            }
        }

        let backupSubscriptionConfig = db.read { tx in
            subscriptionConfigManager.backupConfigurationOrDefault(tx: tx)
        }

        return BackupPlanUpsellConfiguration(
            backupSubscriptionConfiguration: backupSubscriptionConfig,
            storeKitAvailability: storeKitAvailability,
        )
    }
}
