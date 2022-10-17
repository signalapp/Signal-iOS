//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public class ExperienceUpgradeFinder: NSObject {

    // MARK: -

    public class func next(transaction: GRDBReadTransaction) -> ExperienceUpgrade? {
        return allKnownExperienceUpgrades(transaction: transaction.asAnyRead)
            .filter { upgrade in
                if
                    !upgrade.isComplete,
                    upgrade.manifest.shouldBeShown(transaction: transaction.asAnyRead)
                {
                    return true
                }

                return false
            }
            .first { !$0.isSnoozed }
    }

    public class func markAsViewed(experienceUpgrade: ExperienceUpgrade, transaction: GRDBWriteTransaction) {
        Logger.info("marking experience upgrade as seen \(experienceUpgrade.uniqueId)")
        experienceUpgrade.markAsViewed(transaction: transaction.asAnyWrite)
    }

    public class func markAsSnoozed(
        experienceUpgradeManifest: ExperienceUpgradeManifest,
        transaction: GRDBWriteTransaction
    ) {
        markAsSnoozed(
            experienceUpgrade: ExperienceUpgrade.makeNew(withManifest: experienceUpgradeManifest),
            transaction: transaction
        )
    }

    public class func markAsSnoozed(experienceUpgrade: ExperienceUpgrade, transaction: GRDBWriteTransaction) {
        Logger.info("marking experience upgrade as snoozed \(experienceUpgrade.uniqueId)")

        experienceUpgrade.markAsSnoozed(transaction: transaction.asAnyWrite)
    }

    public class func markAsComplete(
        experienceUpgradeManifest manifest: ExperienceUpgradeManifest,
        transaction: GRDBWriteTransaction
    ) {
        markAsComplete(
            experienceUpgrade: ExperienceUpgrade.makeNew(withManifest: manifest),
            transaction: transaction
        )
    }

    public class func markAsComplete(experienceUpgrade: ExperienceUpgrade, transaction: GRDBWriteTransaction) {
        guard experienceUpgrade.manifest.shouldComplete else {
            return Logger.info("Skipping marking complete for experience upgrade with uniqueId: \(experienceUpgrade.uniqueId)")
        }

        Logger.info("Marking complete experience upgrade with uniqueId: \(experienceUpgrade.uniqueId)")
        experienceUpgrade.markAsComplete(transaction: transaction.asAnyWrite)
    }

    @objc
    public class func markAllCompleteForNewUser(transaction: GRDBWriteTransaction) {
        allKnownExperienceUpgrades(transaction: transaction.asAnyRead)
            .filter { $0.manifest.skipForNewUsers }
            .forEach { markAsComplete(experienceUpgrade: $0, transaction: transaction) }
    }

    // MARK: -

    /// Returns an array of all recognized ``ExperienceUpgrade``s. Contains the
    /// persisted record if one exists and is applicable, and an in-memory
    /// model otherwise.
    private class func allKnownExperienceUpgrades(
        transaction: SDSAnyReadTransaction
    ) -> [ExperienceUpgrade] {
        var experienceUpgrades = [ExperienceUpgrade]()
        var localManifestsWithoutRecords = ExperienceUpgradeManifest.wellKnownLocalUpgradeManifests

        // Load any experience upgrades with persisted records...
        ExperienceUpgrade.anyEnumerate(transaction: transaction) { experienceUpgrade, _ in
            if case .unrecognized = experienceUpgrade.manifest {
                // Ignore any no-longer-recognized records.
                return
            }

            guard experienceUpgrade.manifest.shouldSave else {
                // Ignore saved records that we no longer persist.
                return
            }

            experienceUpgrades.append(experienceUpgrade)
            localManifestsWithoutRecords.remove(experienceUpgrade.manifest)
        }

        // ...and instantiate new (in-memory) models for any local manifests
        // without persisted records.
        for localManifest in localManifestsWithoutRecords {
            experienceUpgrades.append(ExperienceUpgrade.makeNew(withManifest: localManifest))
        }

        return experienceUpgrades.sortedByImportance()
    }
}

public extension ExperienceUpgrade {
    var isSnoozed: Bool {
        guard lastSnoozedTimestamp > 0 else { return false }

        // Check if enough time has passed since the last snooze date.
        let timeSinceLastSnooze = -Date(timeIntervalSince1970: lastSnoozedTimestamp).timeIntervalSinceNow
        return timeSinceLastSnooze <= manifest.snoozeDuration
    }

    var daysSinceFirstViewed: Int {
        guard firstViewedTimestamp > 0 else { return 0 }

        let secondsSinceFirstView = -Date(timeIntervalSince1970: firstViewedTimestamp).timeIntervalSinceNow
        return Int(secondsSinceFirstView / kDayInterval)
    }
}
