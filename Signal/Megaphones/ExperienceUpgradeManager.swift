//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class ExperienceUpgradeManager {

    private weak static var lastPresented: MegaphoneView?

    private static let backupSettingsStore = BackupSettingsStore()
    private static var db: DB { DependenciesBridge.shared.db }
    private static var deviceStore: OWSDeviceStore { DependenciesBridge.shared.deviceStore }
    private static let experienceUpgradeStore = ExperienceUpgradeStore()
    private static var remoteConfigManager: RemoteConfigManager { SSKEnvironment.shared.remoteConfigManagerRef }
    private static var tsAccountManager: TSAccountManager { DependenciesBridge.shared.tsAccountManager }

    static func presentNext(fromViewController: UIViewController) -> Bool {

        var shouldClearNewDeviceNotification = false
        var shouldClearBackupsEnabledDetails = false

        let nextExperienceUpgrade = db.read { tx -> ExperienceUpgrade? in
            guard
                let registeredState = try? tsAccountManager.registeredState(tx: tx),
                let registrationDate = tsAccountManager.registrationDate(tx: tx)
            else {
                return nil
            }

            let now = Date()
            let timeIntervalSinceRegistration = now.timeIntervalSince(registrationDate)

            return allKnownExperienceUpgrades(transaction: tx)
                .first { upgrade in
                    guard
                        !upgrade.isComplete,
                        !upgrade.isSnoozed(now: now),
                        !upgrade.hasPassedNumberOfDaysToShow(now: now),
                        timeIntervalSinceRegistration > upgrade.manifest.delayAfterRegistration,
                        now < upgrade.manifest.expirationDate,
                        (registeredState.isPrimary || upgrade.manifest.showOnLinkedDevices)
                    else {
                        return false
                    }

                    switch upgrade.manifest {
                    case .introducingPins:
                        return ExperienceUpgradeManifest
                            .checkPreconditionsForIntroducingPins(transaction: tx)
                    case .notificationPermissionReminder:
                        return ExperienceUpgradeManifest
                            .checkPreconditionsForNotificationsPermissionsReminder()
                    case .newLinkedDeviceNotification:
                        let result = ExperienceUpgradeManifest
                            .checkPreconditionsForNewLinkedDeviceNotification(tx: tx)
                        switch result {
                        case .display:
                            return true
                        case .skip:
                            return false
                        case .clearNotification:
                            shouldClearNewDeviceNotification = true
                            return false
                        }
                    case .createUsernameReminder:
                        return ExperienceUpgradeManifest
                            .checkPreconditionsForCreateUsernameReminder(transaction: tx)
                    case .remoteMegaphone(let megaphone):
                        return ExperienceUpgradeManifest
                            .checkPreconditionsForRemoteMegaphone(megaphone, tx: tx)
                    case .inactiveLinkedDeviceReminder:
                        return ExperienceUpgradeManifest
                            .checkPreconditionsForInactiveLinkedDeviceReminder(tx: tx)
                    case .inactivePrimaryDeviceReminder:
                        return ExperienceUpgradeManifest
                            .checkPreconditionsForInactivePrimaryDeviceReminder(tx: tx)
                    case .pinReminder:
                        return ExperienceUpgradeManifest
                            .checkPreconditionsForPinReminder(transaction: tx)
                    case .contactPermissionReminder:
                        return ExperienceUpgradeManifest
                            .checkPreconditionsForContactsPermissionReminder()
                    case .backupKeyReminder:
                        return ExperienceUpgradeManifest
                            .checkPreconditionsForRecoveryKeyReminder(
                                backupSettingsStore: backupSettingsStore,
                                tsAccountManager: tsAccountManager,
                                transaction: tx,
                            )
                    case .enableBackupsReminder:
                        return ExperienceUpgradeManifest
                            .checkPreconditionsForBackupEnablementReminder(
                                backupSettingsStore: backupSettingsStore,
                                remoteConfigProvider: remoteConfigManager,
                                tsAccountManager: tsAccountManager,
                                transaction: tx,
                            )
                    case .haveEnabledBackupsNotification:
                        let result = ExperienceUpgradeManifest
                            .checkPreconditionsForEnabledBackupsNotification(tx: tx)
                        switch result {
                        case .display:
                            return true
                        case .skip:
                            return false
                        case .clearStoredDetails:
                            shouldClearBackupsEnabledDetails = true
                            return false
                        }
                    case .unrecognized:
                        return false
                    }
                }
        }

        if shouldClearNewDeviceNotification {
            db.write { tx in
                deviceStore.clearMostRecentlyLinkedDeviceDetails(tx: tx)
            }
        }

        if shouldClearBackupsEnabledDetails {
            db.write { tx in
                backupSettingsStore.clearLastBackupEnabledDetails(tx: tx)
            }
        }

        guard let nextExperienceUpgrade else {
            dismissLastPresented()
            return false
        }

        if
            let lastPresented,
            lastPresented.experienceUpgrade.manifest == nextExperienceUpgrade.manifest
        {
            return true
        }

        // Otherwise, dismiss any currently present experience upgrade. It's
        // no longer next and may have been completed.
        dismissLastPresented()

        if
            let megaphone = self.megaphone(
                forExperienceUpgrade: nextExperienceUpgrade,
                fromViewController: fromViewController,
            )
        {
            megaphone.present(fromViewController: fromViewController)
            lastPresented = megaphone

            db.write { tx in
                experienceUpgradeStore.markAsViewed(
                    experienceUpgrade: nextExperienceUpgrade,
                    tx: tx,
                )
            }

            return true
        } else {
            return false
        }
    }

    /// Returns an array of all recognized ``ExperienceUpgrade``s. Contains the
    /// persisted record if one exists and is applicable, and an in-memory
    /// model otherwise.
    private static func allKnownExperienceUpgrades(
        transaction tx: DBReadTransaction,
    ) -> [ExperienceUpgrade] {
        var experienceUpgrades = [ExperienceUpgrade]()
        var localManifestsWithoutRecords = ExperienceUpgradeManifest.wellKnownLocalUpgradeManifests

        // Load any experience upgrades with persisted records...
        experienceUpgradeStore.enumerateExperienceUpgrades(tx: tx) { experienceUpgrade in
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

    // MARK: -

    static func dismissLastPresented(ifMatching manifest: ExperienceUpgradeManifest? = nil) {
        guard let lastPresented else {
            return
        }

        if
            let manifest,
            lastPresented.experienceUpgrade.manifest != manifest
        {
            return
        }

        lastPresented.dismiss(animated: false, completion: nil)
        self.lastPresented = nil
    }

    // MARK: -

    private static func hasMegaphone(forExperienceUpgrade experienceUpgrade: ExperienceUpgrade) -> Bool {
        switch experienceUpgrade.manifest {
        case
            .introducingPins,
            .pinReminder,
            .notificationPermissionReminder,
            .newLinkedDeviceNotification,
            .createUsernameReminder,
            .inactiveLinkedDeviceReminder,
            .inactivePrimaryDeviceReminder,
            .contactPermissionReminder,
            .backupKeyReminder,
            .enableBackupsReminder,
            .haveEnabledBackupsNotification:
            return true
        case .remoteMegaphone:
            // Remote megaphones are always presentable. We filter out any with
            // unpresentable fields (e.g., unrecognized actions) before we get
            // out of the `ExperienceUpgradeFinder`.
            return true
        case .unrecognized:
            return false
        }
    }

    private static func megaphone(forExperienceUpgrade experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) -> MegaphoneView? {
        let db = DependenciesBridge.shared.db
        let deviceStore = DependenciesBridge.shared.deviceStore
        let localUsernameManager = DependenciesBridge.shared.localUsernameManager
        let inactiveLinkedDeviceFinder = DependenciesBridge.shared.inactiveLinkedDeviceFinder

        switch experienceUpgrade.manifest {
        case .introducingPins:
            return IntroducingPinsMegaphone(experienceUpgrade: experienceUpgrade, fromViewController: fromViewController)
        case .pinReminder:
            return PinReminderMegaphone(experienceUpgrade: experienceUpgrade, fromViewController: fromViewController)
        case .notificationPermissionReminder:
            return NotificationPermissionReminderMegaphone(experienceUpgrade: experienceUpgrade, fromViewController: fromViewController)
        case .newLinkedDeviceNotification:
            let mostRecentlyLinkedDeviceDetails = db.read { tx in
                deviceStore.mostRecentlyLinkedDeviceDetails(tx: tx)
            }

            guard let mostRecentlyLinkedDeviceDetails else {
                owsFailDebug("Missing mostRecentlyLinkedDeviceDetails")
                return nil
            }

            return NewLinkedDeviceNotificationMegaphone(
                db: DependenciesBridge.shared.db,
                deviceStore: DependenciesBridge.shared.deviceStore,
                experienceUpgrade: experienceUpgrade,
                mostRecentlyLinkedDeviceDetails: mostRecentlyLinkedDeviceDetails,
            )
        case .createUsernameReminder:
            let usernameIsUnset: Bool = db.read { tx in
                return localUsernameManager.usernameState(tx: tx).isExplicitlyUnset
            }

            guard usernameIsUnset else {
                owsFailDebug("Should never try and show this megaphone if a username is set!")
                return nil
            }

            return CreateUsernameMegaphone(
                usernameSelectionCoordinator: .init(
                    currentUsername: nil,
                    context: .init(
                        databaseStorage: SSKEnvironment.shared.databaseStorageRef,
                        networkManager: SSKEnvironment.shared.networkManagerRef,
                        storageServiceManager: SSKEnvironment.shared.storageServiceManagerRef,
                        usernameEducationManager: DependenciesBridge.shared.usernameEducationManager,
                        localUsernameManager: DependenciesBridge.shared.localUsernameManager,
                    ),
                ),
                experienceUpgrade: experienceUpgrade,
                fromViewController: fromViewController,
            )
        case .inactiveLinkedDeviceReminder:
            let inactiveLinkedDevice: InactiveLinkedDevice? = db.read { tx in
                return inactiveLinkedDeviceFinder.findLeastActiveLinkedDevice(tx: tx)
            }

            guard let inactiveLinkedDevice else {
                owsFailDebug("Trying to show inactive linked device megaphone, but have no device!")
                return nil
            }

            return InactiveLinkedDeviceReminderMegaphone(
                inactiveLinkedDevice: inactiveLinkedDevice,
                fromViewController: fromViewController,
                experienceUpgrade: experienceUpgrade,
            )
        case .inactivePrimaryDeviceReminder:
            let isPrimaryDevice = db.read { tx in
                // If isPrimaryDevice is nil, it means we aren't registered yet, and shouldn't show the megaphone.
                return DependenciesBridge.shared.tsAccountManager.registrationState(tx: tx).isPrimaryDevice ?? true
            }

            guard !isPrimaryDevice else {
                owsFailDebug("Trying to show inactive primary device megaphone, but this is the primary device or an unregistered device")
                return nil
            }

            return InactivePrimaryDeviceReminderMegaphone(fromViewController: fromViewController, experienceUpgrade: experienceUpgrade)
        case .contactPermissionReminder:
            return ContactPermissionReminderMegaphone(experienceUpgrade: experienceUpgrade, fromViewController: fromViewController)
        case .remoteMegaphone(let megaphone):
            return RemoteMegaphone(
                experienceUpgrade: experienceUpgrade,
                remoteMegaphoneModel: megaphone,
                fromViewController: fromViewController,
            )
        case .backupKeyReminder:
            return RecoveryKeyReminderMegaphone(experienceUpgrade: experienceUpgrade, fromViewController: fromViewController)
        case .enableBackupsReminder:
            return BackupEnablementMegaphone(
                experienceUpgrade: experienceUpgrade,
                fromViewController: fromViewController,
            )
        case .haveEnabledBackupsNotification:
            let lastBackupsEnabledDetails = db.read { tx in
                backupSettingsStore.lastBackupEnabledDetails(tx: tx)
            }

            guard let lastBackupsEnabledDetails else {
                owsFailDebug("Missing lastBackupsEnabledDetails")
                return nil
            }

            return BackupsEnabledNotificationMegaphone(
                experienceUpgrade: experienceUpgrade,
                fromViewController: fromViewController,
                backupsEnabledTime: lastBackupsEnabledDetails.enabledTime,
                db: db,
            )
        case .unrecognized:
            return nil
        }
    }
}
