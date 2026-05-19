//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class ExperienceUpgradeManager {

    private weak static var lastPresented: ExperienceUpgradeView?

    static func presentNext(fromViewController: UIViewController) -> Bool {
        let db = DependenciesBridge.shared.db
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        var shouldClearNewDeviceNotification = false
        var shouldClearBackupsEnabledDetails = false

        let optionalNext = db.read { transaction -> ExperienceUpgrade? in
            let tx = transaction

            guard
                let registeredState = try? tsAccountManager.registeredState(tx: tx),
                let registrationDate = tsAccountManager.registrationDate(tx: tx)
            else {
                return nil
            }

            let now = Date()
            let timeIntervalSinceRegistration = now.timeIntervalSince(registrationDate)

            return ExperienceUpgradeFinder.allKnownExperienceUpgrades(transaction: tx)
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
                            .checkPreconditionsForIntroducingPins(transaction: transaction)
                    case .notificationPermissionReminder:
                        return ExperienceUpgradeManifest
                            .checkPreconditionsForNotificationsPermissionsReminder()
                    case .newLinkedDeviceNotification:
                        let result = ExperienceUpgradeManifest
                            .checkPreconditionsForNewLinkedDeviceNotification(tx: transaction)
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
                            .checkPreconditionsForCreateUsernameReminder(transaction: transaction)
                    case .remoteMegaphone(let megaphone):
                        return ExperienceUpgradeManifest
                            .checkPreconditionsForRemoteMegaphone(megaphone, tx: transaction)
                    case .inactiveLinkedDeviceReminder:
                        return ExperienceUpgradeManifest
                            .checkPreconditionsForInactiveLinkedDeviceReminder(tx: transaction)
                    case .inactivePrimaryDeviceReminder:
                        return ExperienceUpgradeManifest
                            .checkPreconditionsForInactivePrimaryDeviceReminder(tx: transaction)
                    case .pinReminder:
                        return ExperienceUpgradeManifest
                            .checkPreconditionsForPinReminder(transaction: transaction)
                    case .contactPermissionReminder:
                        return ExperienceUpgradeManifest
                            .checkPreconditionsForContactsPermissionReminder()
                    case .backupKeyReminder:
                        return ExperienceUpgradeManifest
                            .checkPreconditionsForRecoveryKeyReminder(
                                backupSettingsStore: BackupSettingsStore(),
                                tsAccountManager: DependenciesBridge.shared.tsAccountManager,
                                transaction: transaction,
                            )
                    case .enableBackupsReminder:
                        return ExperienceUpgradeManifest
                            .checkPreconditionsForBackupEnablementReminder(
                                backupSettingsStore: BackupSettingsStore(),
                                remoteConfigProvider: SSKEnvironment.shared.remoteConfigManagerRef,
                                tsAccountManager: DependenciesBridge.shared.tsAccountManager,
                                transaction: transaction,
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
                        }
                    case .unrecognized:
                        break
                    }

                    return false
                }
        }

        if shouldClearNewDeviceNotification {
            DependenciesBridge.shared.db.write { tx in
                DependenciesBridge.shared.deviceStore.clearMostRecentlyLinkedDeviceDetails(tx: tx)
            }
        }

        if shouldClearBackupsEnabledDetails {
            DependenciesBridge.shared.db.write { tx in
                BackupSettingsStore().clearLastBackupEnabledDetails(tx: tx)
            }
        }

        // If we already have presented this experience upgrade, do nothing.
        guard
            let next = optionalNext,
            lastPresented?.experienceUpgrade.manifest != next.manifest
        else {
            if optionalNext == nil {
                dismissLastPresented()
                return false
            } else {
                return true
            }
        }

        // Otherwise, dismiss any currently present experience upgrade. It's
        // no longer next and may have been completed.
        dismissLastPresented()

        let didPresentView: Bool
        if
            let megaphone = self.megaphone(
                forExperienceUpgrade: next,
                fromViewController: fromViewController,
            )
        {
            megaphone.present(fromViewController: fromViewController)
            lastPresented = megaphone
            didPresentView = true
        } else {
            didPresentView = false
        }

        db.write { tx in
            ExperienceUpgradeFinder.markAsViewed(experienceUpgrade: next, transaction: tx)
        }

        return didPresentView
    }

    // MARK: - Experience Specific Helpers

    static func dismissPINReminderIfNecessary() {
        dismissLastPresented(ifMatching: .pinReminder)
    }

    /// Marks the given upgrade as complete, and dismisses it if currently presented.
    static func clearExperienceUpgrade(_ manifest: ExperienceUpgradeManifest, transaction: DBWriteTransaction) {
        ExperienceUpgradeFinder.markAsComplete(experienceUpgradeManifest: manifest, transaction: transaction)

        transaction.addSyncCompletion {
            Task { @MainActor in
                dismissLastPresented(ifMatching: manifest)
            }
        }
    }

    private static func dismissLastPresented(ifMatching manifest: ExperienceUpgradeManifest? = nil) {
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

    // MARK: - Megaphone

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
                BackupSettingsStore().lastBackupEnabledDetails(tx: tx)
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

// MARK: - ExperienceUpgradeView

protocol ExperienceUpgradeView: AnyObject {
    var experienceUpgrade: ExperienceUpgrade { get }
    var isPresented: Bool { get }
    func dismiss(animated: Bool, completion: (() -> Void)?)
}

extension ExperienceUpgradeView {

    func markAsSnoozedWithSneakyTransaction() {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            ExperienceUpgradeFinder.markAsSnoozed(
                experienceUpgrade: self.experienceUpgrade,
                transaction: transaction,
            )
        }
    }

    func markAsCompleteWithSneakyTransaction() {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            ExperienceUpgradeFinder.markAsComplete(
                experienceUpgrade: self.experienceUpgrade,
                transaction: transaction,
            )
        }
    }
}
