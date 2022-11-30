//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension OWSOrphanDataCleaner {
    @objc
    static func auditOnLaunchIfNecessary() {
        AssertIsOnMainThread()

        guard shouldAuditWithSneakyTransaction() else { return }

        // If we want to be cautious, we can disable orphan deletion using
        // flag - the cleanup will just be a dry run with logging.
        let shouldCleanUp = true
        auditAndCleanup(shouldCleanUp)
    }

    private static func shouldAuditWithSneakyTransaction() -> Bool {
        guard CurrentAppContext().isMainApp else {
            Logger.info("Orphan data audit skipped because we're not the main app")
            return false
        }

        guard !CurrentAppContext().isRunningTests else {
            Logger.info("Orphan data audit skipped because we're running tests")
            return false
        }

        let kvs = keyValueStore()
        let currentAppVersion = appVersion.currentAppReleaseVersion

        return databaseStorage.read { transaction -> Bool in
            guard TSAccountManager.shared.isRegistered(transaction: transaction) else {
                Logger.info("Orphan data audit skipped because we're not registered")
                return false
            }

            let lastCleaningVersion = kvs.getString(
                OWSOrphanDataCleaner_LastCleaningVersionKey,
                transaction: transaction
            )
            guard let lastCleaningVersion else {
                Logger.info("Performing orphan data cleanup because we've never done it")
                return true
            }
            guard lastCleaningVersion == currentAppVersion else {
                Logger.info("Performing orphan data cleanup because we're on a different app version (\(currentAppVersion)")
                return true
            }

            let lastCleaningDate = kvs.getDate(
                OWSOrphanDataCleaner_LastCleaningDateKey,
                transaction: transaction
            )
            guard let lastCleaningDate else {
                owsFailDebug("We have a \"last cleaned version\". Why don't we have a last cleaned date?")
                Logger.info("Performing orphan data cleanup because we've never done it")
                return true
            }

            #if DEBUG
            let hasEnoughTimePassed = DateUtil.dateIsOlderThanToday
            #else
            let hasEnoughTimePassed = DateUtil.dateIsOlderThanOneWeek
            #endif
            if hasEnoughTimePassed(lastCleaningDate) {
                Logger.info("Performing orphan data cleanup because enough time has passed")
                return true
            }

            Logger.info("Orphan data audit skipped because no other checks succeeded")
            return false
        }
    }
}
