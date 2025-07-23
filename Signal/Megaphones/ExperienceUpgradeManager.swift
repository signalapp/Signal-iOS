//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class ExperienceUpgradeManager {

    private static weak var lastPresented: ExperienceUpgradeView?

    // The first day is day 0, so this gives the user 1 week of megaphone
    // before we display the splash.
    static let splashStartDay = 7

    static func presentNext(fromViewController: UIViewController) -> Bool {
        var shouldClearNewDeviceNotification = false

        let optionalNext = SSKEnvironment.shared.databaseStorageRef.read { transaction -> ExperienceUpgrade? in
            let tx = transaction

            guard let registrationDate = DependenciesBridge.shared.tsAccountManager.registrationDate(tx: tx) else {
                return nil
            }
            let timeIntervalSinceRegistration = Date().timeIntervalSince(registrationDate)

            let isRegisteredPrimaryDevice = DependenciesBridge.shared.tsAccountManager.registrationState(tx: transaction).isRegisteredPrimaryDevice

            return ExperienceUpgradeFinder.allKnownExperienceUpgrades(transaction: tx)
                .first { upgrade in
                    guard
                        upgrade.shouldCheckPreconditions,
                        upgrade.manifest.shouldCheckPreconditions(
                            timeIntervalSinceRegistration: timeIntervalSinceRegistration,
                            isRegisteredPrimaryDevice: isRegisteredPrimaryDevice,
                            tx: tx
                        )
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
                            .checkPreconditionsForBackupKeyReminder(
                                remoteConfig: RemoteConfig.current,
                                transaction: transaction,
                            )
                    case .enableBackupsReminder:
                        return ExperienceUpgradeManifest
                            .checkPreconditionsForBackupEnablementReminder(
                                remoteConfig: RemoteConfig.current,
                                transaction: transaction
                            )
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

        let hasMegaphone = self.hasMegaphone(forExperienceUpgrade: next)
        let hasSplash = self.hasSplash(forExperienceUpgrade: next)

        // If we have a megaphone and a splash, we only show the megaphone for
        // 7 days after the user first viewed the megaphone. After this point
        // we will display the splash. If there is only a megaphone we will
        // render it for as long as the upgrade is active. We don't show the
        // splash if the user currently has a selected thread, as we don't
        // ever want to block access to messaging (e.g. via tapping a notification).
        let didPresentView: Bool
        if (hasMegaphone && !hasSplash) || (hasMegaphone && next.daysSinceFirstViewed < splashStartDay) {
            let megaphone = self.megaphone(forExperienceUpgrade: next, fromViewController: fromViewController)
            megaphone?.present(fromViewController: fromViewController)
            lastPresented = megaphone
            didPresentView = true
        } else if hasSplash, !SignalApp.shared.hasSelectedThread, let splash = splash(forExperienceUpgrade: next) {
            fromViewController.presentFormSheet(OWSNavigationController(rootViewController: splash), animated: true)
            lastPresented = splash
            didPresentView = true
        } else {
            Logger.info("no megaphone or splash needed for experience upgrade: \(next.id as Optional)")
            didPresentView = false
        }

        // Track that we've successfully presented this experience upgrade once, or that it was not
        // needed to be presented.
        // If it was already marked as viewed, this will do nothing.
        SSKEnvironment.shared.databaseStorageRef.asyncWrite { transaction in
            ExperienceUpgradeFinder.markAsViewed(experienceUpgrade: next, transaction: transaction)
        }

        return didPresentView
    }

    // MARK: - Experience Specific Helpers

    static func dismissSplashWithoutCompletingIfNecessary() {
        guard let lastPresented = lastPresented as? SplashViewController else { return }
        lastPresented.dismissWithoutCompleting(animated: false, completion: nil)
    }

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
        guard let lastPresented = lastPresented else {
            return
        }

        if
            let manifest = manifest,
            lastPresented.experienceUpgrade.manifest != manifest
        {
            return
        }

        lastPresented.dismiss(animated: false, completion: nil)
        self.lastPresented = nil
    }

    // MARK: - Splash

    private static func hasSplash(forExperienceUpgrade experienceUpgrade: ExperienceUpgrade) -> Bool {
        switch experienceUpgrade.id {
        default:
            return false
        }
    }

    fileprivate static func splash(forExperienceUpgrade experienceUpgrade: ExperienceUpgrade) -> SplashViewController? {
        switch experienceUpgrade.id {
        default:
            return nil
        }
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
                .enableBackupsReminder:
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
                try? deviceStore.mostRecentlyLinkedDeviceDetails(tx: tx)
            }

            guard let mostRecentlyLinkedDeviceDetails else {
                owsFailDebug("Missing mostRecentlyLinkedDeviceDetails")
                return nil
            }

            return NewLinkedDeviceNotificationMegaphone(
                db: DependenciesBridge.shared.db,
                deviceStore: DependenciesBridge.shared.deviceStore,
                experienceUpgrade: experienceUpgrade,
                mostRecentlyLinkedDeviceDetails: mostRecentlyLinkedDeviceDetails
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
                        localUsernameManager: DependenciesBridge.shared.localUsernameManager
                    )
                ),
                experienceUpgrade: experienceUpgrade,
                fromViewController: fromViewController
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
                experienceUpgrade: experienceUpgrade
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
                fromViewController: fromViewController
            )
        case .backupKeyReminder:
            return BackupKeyReminderMegaphone(experienceUpgrade: experienceUpgrade, fromViewController: fromViewController)
        case .enableBackupsReminder:
            return BackupEnablementMegaphone(
                experienceUpgrade: experienceUpgrade,
                fromViewController: fromViewController
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
                transaction: transaction
            )
        }
    }

    func markAsCompleteWithSneakyTransaction() {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            ExperienceUpgradeFinder.markAsComplete(
                experienceUpgrade: self.experienceUpgrade,
                transaction: transaction
            )
        }
    }
}
