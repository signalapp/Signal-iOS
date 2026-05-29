//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class ExperienceUpgradeFinder {

    // MARK: -

    public class func markAsViewed(experienceUpgrade: ExperienceUpgrade, transaction tx: DBWriteTransaction) {
        ExperienceUpgradeStore().markAsViewed(experienceUpgrade: experienceUpgrade, tx: tx)
    }

    public class func markAsSnoozed(experienceUpgrade: ExperienceUpgrade, transaction tx: DBWriteTransaction) {
        ExperienceUpgradeStore().markAsSnoozed(experienceUpgrade: experienceUpgrade, tx: tx)
    }

    public class func markAsComplete(
        experienceUpgradeManifest: ExperienceUpgradeManifest,
        transaction tx: DBWriteTransaction,
    ) {
        markAsComplete(experienceUpgrade: .makeNew(withManifest: experienceUpgradeManifest), transaction: tx)
    }

    public class func markAsComplete(experienceUpgrade: ExperienceUpgrade, transaction tx: DBWriteTransaction) {
        ExperienceUpgradeStore().markAsComplete(experienceUpgrade: experienceUpgrade, tx: tx)
    }

    public class func markAllCompleteForNewUser(transaction: DBWriteTransaction) {
        allKnownExperienceUpgrades(transaction: transaction)
            .filter { $0.manifest.skipForNewUsers }
            .forEach { markAsComplete(experienceUpgrade: $0, transaction: transaction) }
    }

    // MARK: -

    /// Returns an array of all recognized ``ExperienceUpgrade``s. Contains the
    /// persisted record if one exists and is applicable, and an in-memory
    /// model otherwise.
    public class func allKnownExperienceUpgrades(
        transaction tx: DBReadTransaction,
    ) -> [ExperienceUpgrade] {
        var experienceUpgrades = [ExperienceUpgrade]()
        var localManifestsWithoutRecords = ExperienceUpgradeManifest.wellKnownLocalUpgradeManifests

        // Load any experience upgrades with persisted records...
        ExperienceUpgradeStore().enumerateExperienceUpgrades(tx: tx) { experienceUpgrade in
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

        return ExperienceUpgradeManifest.sortedByImportance(experienceUpgrades)
    }
}
