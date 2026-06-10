//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension Notification.Name {
    public static let megaphoneStateDidChange = Notification.Name("ExperienceUpgradeManager.MegaphoneStateDidChange")
}

// MARK: -

public struct ExperienceUpgradeStore {

    public init() {}

    // MARK: -

    public func markAsSnoozed(experienceUpgrade: ExperienceUpgrade, tx: DBWriteTransaction) {
        Logger.info("Marking snoozed: \(experienceUpgrade.uniqueId)")

        experienceUpgrade.lastSnoozedTimestamp = Date().timeIntervalSince1970
        experienceUpgrade.snoozeCount += 1
        upsert(experienceUpgrade: experienceUpgrade, tx: tx)
    }

    public func markAsComplete(experienceUpgrade: ExperienceUpgrade, tx: DBWriteTransaction) {
        guard experienceUpgrade.manifest.shouldComplete else {
            Logger.info("Skipping marking complete: \(experienceUpgrade.uniqueId)")
            return
        }

        Logger.info("Marking complete: \(experienceUpgrade.uniqueId)")

        experienceUpgrade.isComplete = true
        upsert(experienceUpgrade: experienceUpgrade, tx: tx)
    }

    public func markAsViewed(experienceUpgrade: ExperienceUpgrade, tx: DBWriteTransaction) {
        guard experienceUpgrade.firstViewedTimestamp == 0 else {
            Logger.info("Already marked viewed, skipping: \(experienceUpgrade.uniqueId)")
            return
        }

        Logger.info("Marking first viewed: \(experienceUpgrade.uniqueId)")

        experienceUpgrade.firstViewedTimestamp = Date().timeIntervalSince1970
        upsert(experienceUpgrade: experienceUpgrade, tx: tx)
    }

    /// Updates a subset of properties on the existing manifest with the given
    /// re-fetched megaphone. Does nothing if the given megaphone does not
    /// match the existing.
    public func upsertRemoteMegaphone(
        experienceUpgrade: ExperienceUpgrade,
        newRemoteMegaphoneModel: RemoteMegaphoneModel,
        tx: DBWriteTransaction,
    ) {
        guard
            case .remoteMegaphone(var remoteMegaphoneModel) = experienceUpgrade.manifest
        else {
            owsFailDebug("Attempting to update remote megaphone, but upgrade is not a remote megaphone! \(experienceUpgrade.uniqueId)")
            return
        }

        remoteMegaphoneModel.updateSelectively(newRemoteMegaphoneModel: newRemoteMegaphoneModel)

        experienceUpgrade.manifest = .remoteMegaphone(megaphone: remoteMegaphoneModel)
        upsert(experienceUpgrade: experienceUpgrade, tx: tx)
    }

    private func upsert(experienceUpgrade: ExperienceUpgrade, tx: DBWriteTransaction) {
        guard experienceUpgrade.manifest.shouldSave else {
            return
        }

        failIfThrows {
            try experienceUpgrade.upsert(tx: tx)
        }
    }

    // MARK: -

    public func enumerateExperienceUpgrades(
        tx: DBReadTransaction,
        block: (ExperienceUpgrade) -> Void,
    ) {
        var cursor = FailIfThrowsRecordCursor {
            try ExperienceUpgrade.fetchCursor(tx.database)
        }

        while let upgrade = cursor.next() {
            block(upgrade)
        }
    }

    // MARK: -

    public func remove(experienceUpgrade: ExperienceUpgrade, tx: DBWriteTransaction) {
        failIfThrows {
            try experienceUpgrade.delete(tx.database)
        }

        switch experienceUpgrade.manifest {
        case .introducingPins,
             .notificationPermissionReminder,
             .newLinkedDeviceNotification,
             .createUsernameReminder,
             .inactiveLinkedDeviceReminder,
             .inactivePrimaryDeviceReminder,
             .pinReminder,
             .contactPermissionReminder,
             .backupKeyReminder,
             .backupsUpsellReminder,
             .backupsEnabledRecentlyNotification,
             .unrecognized:
            return
        case .remoteMegaphone(let megaphone):
            guard megaphone.translation.hasImage else {
                return
            }

            do {
                let imageLocalUrl = RemoteMegaphoneModel.imagesDirectory
                    .appendingPathComponent(megaphone.translation.imageLocalRelativePath)

                try FileManager.default.removeItem(at: imageLocalUrl)
            } catch let error {
                owsFailDebug("Failed to remove image file for removed remote megaphone with ID \(megaphone.id)! \(error)")
            }
        }
    }
}
