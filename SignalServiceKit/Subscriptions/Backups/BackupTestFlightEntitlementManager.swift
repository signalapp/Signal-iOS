//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Responsible for managing paid-tier Backup entitlements for TestFlight users,
/// who aren't able to use StoreKit or perform real-money transactions.
public final class BackupTestFlightEntitlementManager {
    private enum StoreKeys {
        static let lastEntitlementRenewalDate = "lastEntitlementRenewalDate"
    }

    private let backupPlanManager: BackupPlanManager
    private let dateProvider: DateProvider
    private let db: DB
    private let logger: PrefixedLogger
    private let kvStore: KeyValueStore
    private let networkManager: NetworkManager

    init(
        backupPlanManager: BackupPlanManager,
        dateProvider: @escaping DateProvider,
        db: DB,
        networkManager: NetworkManager,
    ) {
        self.backupPlanManager = backupPlanManager
        self.dateProvider = dateProvider
        self.db = db
        self.logger = PrefixedLogger(prefix: "[Backups]")
        self.kvStore = KeyValueStore(collection: "BackupTestFlightEntitlementManager")
        self.networkManager = networkManager
    }

    // MARK: -

    public func acquireEntitlement() async throws {
        owsPrecondition(FeatureFlags.Backups.avoidStoreKitForTesters)

        guard TSConstants.isUsingProductionService else {
            // If we're on Staging, no need to do anything – all accounts on
            // Staging get the entitlement automatically.
            return
        }

        try await _acquireEntitlementUsingDeviceCheck()
    }

    private func _acquireEntitlementUsingDeviceCheck() async throws {
        // TODO: @sasha call into DeviceCheck, make API request to ChatService
    }

    // MARK: -

    public func renewEntitlementIfNecessary() async throws {
        let isCurrentlyTesterBuild = FeatureFlags.Backups.avoidStoreKitForTesters
        let (
            currentBackupPlan,
            lastEntitlementRenewalDate
        ): (
            BackupPlan,
            Date?
        ) = db.read { tx in
            (
                backupPlanManager.backupPlan(tx: tx),
                kvStore.getDate(StoreKeys.lastEntitlementRenewalDate, transaction: tx)
            )
        }

        switch currentBackupPlan {
        case .disabled, .disabling, .free, .paid, .paidExpiringSoon:
            // If we're not a paid-tier tester, nothing to do.
            return
        case .paidAsTester:
            break
        }

        guard isCurrentlyTesterBuild else {
            // Uh oh: we think we're a paid-tier tester, but our current build
            // isn't a tester build. We likely downgraded to prod builds, so
            // correspondingly downgrade our BackupPlan to free.
            try await db.awaitableWriteWithRollbackIfThrows { tx in
                try backupPlanManager.setBackupPlan(.free, tx: tx)
            }
            return
        }

        if
            let lastEntitlementRenewalDate,
            lastEntitlementRenewalDate.addingTimeInterval(3 * .day) > dateProvider()
        {
            logger.info("Not renewing; we did so recently.")
            return
        }

        try await acquireEntitlement()

        await db.awaitableWrite { tx in
            kvStore.setDate(
                dateProvider(),
                key: StoreKeys.lastEntitlementRenewalDate,
                transaction: tx
            )
        }
    }
}
