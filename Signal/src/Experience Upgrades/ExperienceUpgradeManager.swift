//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class ExperienceUpgradeManager: NSObject {

    private static weak var lastPresented: ExperienceUpgradeView?

    // The first day is day 0, so this gives the user 1 week of megaphone
    // before we display the splash.
    static let splashStartDay = 7

    private static func dismissLastPresented() {
        lastPresented?.dismiss(animated: false, completion: nil)
        lastPresented = nil
    }

    @objc
    static func presentNext(fromViewController: UIViewController) -> Bool {
        let optionalNext = databaseStorage.read(block: { transaction in
            return ExperienceUpgradeFinder.next(transaction: transaction.unwrapGrdbRead)
        })

        // If we already have presented this experience upgrade, do nothing.
        guard let next = optionalNext, lastPresented?.experienceUpgrade.uniqueId != next.uniqueId else {
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
        } else if hasSplash, !SignalApp.shared().hasSelectedThread, let splash = splash(forExperienceUpgrade: next) {
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

    @objc
    static func dismissSplashWithoutCompletingIfNecessary() {
        guard let lastPresented = lastPresented as? SplashViewController else { return }
        lastPresented.dismissWithoutCompleting(animated: false, completion: nil)
    }

    @objc
    static func dismissPINReminderIfNecessary() {
        guard lastPresented?.experienceUpgrade.experienceId == .pinReminder else { return }
        lastPresented?.dismiss(animated: false, completion: nil)
    }

    /// Marks the specified type up of upgrade as complete and dismisses it if it is currently presented.
    static func clearExperienceUpgrade(_ experienceUpgradeId: ExperienceUpgradeId, transaction: GRDBWriteTransaction) {
        ExperienceUpgradeFinder.markAsComplete(experienceUpgradeId: experienceUpgradeId, transaction: transaction)
        transaction.addAsyncCompletion(queue: .main) {
            // If it's currently being presented, dismiss it.
            guard lastPresented?.experienceUpgrade.experienceId == experienceUpgradeId else { return }
            lastPresented?.dismiss(animated: false, completion: nil)
        }
    }

    /// Marks the specified type up of upgrade as complete and dismisses it if it is currently presented.
    static func snoozeExperienceUpgrade(_ experienceUpgradeId: ExperienceUpgradeId, transaction: GRDBWriteTransaction) {
        ExperienceUpgradeFinder.markAsSnoozed(experienceUpgradeId: experienceUpgradeId, transaction: transaction)
        transaction.addAsyncCompletion(queue: .main) {
            // If it's currently being presented, dismiss it.
            guard lastPresented?.experienceUpgrade.experienceId == experienceUpgradeId else { return }
            lastPresented?.dismiss(animated: false, completion: nil)
        }
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
        switch experienceUpgrade.experienceId {
        case .introducingPins,
             .pinReminder,
             .notificationPermissionReminder,
             .contactPermissionReminder,
             .subscriptionMegaphone:
            return true
        default:
            return false
        }
    }

    fileprivate static func megaphone(forExperienceUpgrade experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) -> MegaphoneView? {
        switch experienceUpgrade.experienceId {
        case .introducingPins:
            return IntroducingPinsMegaphone(experienceUpgrade: experienceUpgrade, fromViewController: fromViewController)
        case .pinReminder:
            return PinReminderMegaphone(experienceUpgrade: experienceUpgrade, fromViewController: fromViewController)
        case .notificationPermissionReminder:
            return NotificationPermissionReminderMegaphone(experienceUpgrade: experienceUpgrade, fromViewController: fromViewController)
        case .contactPermissionReminder:
            return ContactPermissionReminderMegaphone(experienceUpgrade: experienceUpgrade, fromViewController: fromViewController)
        case .subscriptionMegaphone:
            return DonationMegaphone(experienceUpgrade: experienceUpgrade, fromViewController: fromViewController)
        default:
            return nil
        }
    }
}

// MARK: -

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
