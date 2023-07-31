//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class ExperienceUpgradeManager: Dependencies {

    private static weak var lastPresented: ExperienceUpgradeView?

    // The first day is day 0, so this gives the user 1 week of megaphone
    // before we display the splash.
    static let splashStartDay = 7

    static func presentNext(fromViewController: UIViewController) -> Bool {
        let optionalNext = databaseStorage.read(block: { transaction in
            return ExperienceUpgradeFinder.next(transaction: transaction.unwrapGrdbRead)
        })

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
        databaseStorage.asyncWrite { transaction in
            ExperienceUpgradeFinder.markAsViewed(experienceUpgrade: next, transaction: transaction.unwrapGrdbWrite)
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
    static func clearExperienceUpgrade(_ manifest: ExperienceUpgradeManifest, transaction: GRDBWriteTransaction) {
        ExperienceUpgradeFinder.markAsComplete(experienceUpgradeManifest: manifest, transaction: transaction)

        transaction.addAsyncCompletion(queue: .main) {
            dismissLastPresented(ifMatching: manifest)
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
                .createUsernameReminder,
                .contactPermissionReminder:
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
        switch experienceUpgrade.manifest {
        case .introducingPins:
            return IntroducingPinsMegaphone(experienceUpgrade: experienceUpgrade, fromViewController: fromViewController)
        case .pinReminder:
            return PinReminderMegaphone(experienceUpgrade: experienceUpgrade, fromViewController: fromViewController)
        case .notificationPermissionReminder:
            return NotificationPermissionReminderMegaphone(experienceUpgrade: experienceUpgrade, fromViewController: fromViewController)
        case .createUsernameReminder:
            let usernameIsUnset: Bool = databaseStorage.read { tx in
                return DependenciesBridge.shared.localUsernameManager
                    .usernameState(tx: tx.asV2Read).isExplicitlyUnset
            }

            guard usernameIsUnset else {
                owsFailDebug("Should never try and show this megaphone if a username is set!")
                return nil
            }

            return CreateUsernameMegaphone(
                usernameSelectionCoordinator: .init(
                    currentUsername: nil,
                    context: .init(
                        databaseStorage: databaseStorage,
                        networkManager: networkManager,
                        schedulers: DependenciesBridge.shared.schedulers,
                        storageServiceManager: storageServiceManager,
                        usernameEducationManager: DependenciesBridge.shared.usernameEducationManager,
                        localUsernameManager: DependenciesBridge.shared.localUsernameManager
                    )
                ),
                experienceUpgrade: experienceUpgrade,
                fromViewController: fromViewController
            )
        case .contactPermissionReminder:
            return ContactPermissionReminderMegaphone(experienceUpgrade: experienceUpgrade, fromViewController: fromViewController)
        case .remoteMegaphone(let megaphone):
            return RemoteMegaphone(
                experienceUpgrade: experienceUpgrade,
                remoteMegaphoneModel: megaphone,
                fromViewController: fromViewController
            )
        case .unrecognized:
            return nil
        }
    }
}

// MARK: - ExperienceUpgradeView

protocol ExperienceUpgradeView: AnyObject, Dependencies {
    var experienceUpgrade: ExperienceUpgrade { get }
    var isPresented: Bool { get }
    func dismiss(animated: Bool, completion: (() -> Void)?)
}

extension ExperienceUpgradeView {

    func markAsSnoozedWithSneakyTransaction() {
        databaseStorage.write { transaction in
            ExperienceUpgradeFinder.markAsSnoozed(
                experienceUpgrade: self.experienceUpgrade,
                transaction: transaction.unwrapGrdbWrite
            )
        }
    }

    func markAsCompleteWithSneakyTransaction() {
        databaseStorage.write { transaction in
            ExperienceUpgradeFinder.markAsComplete(
                experienceUpgrade: self.experienceUpgrade,
                transaction: transaction.unwrapGrdbWrite
            )
        }
    }
}
