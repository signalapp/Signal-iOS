//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class ExperienceUpgradeManager: NSObject {
    private static var databaseStorage: SDSDatabaseStorage {
        return .shared
    }

    private static weak var lastPresented: ExperienceUpgradeView?

    // The first day is day 0, so this gives the user 1 week of megaphone
    // before we display the splash.
    static let splashStartDay = 7

    @objc
    static func presentNext(fromViewController: UIViewController) -> Bool {
        // If we already have a experience upgrade in the view hierarchy, do nothing
        guard lastPresented?.isPresented != true else { return true }

        guard let next = databaseStorage.read(block: { transaction in
            return ExperienceUpgradeFinder.next(transaction: transaction.unwrapGrdbRead)
        }) else {
            return false
        }

        let hasMegaphone = self.hasMegaphone(forExperienceUpgrade: next)
        let hasSplash = self.hasSplash(forExperienceUpgrade: next)

        // If we have a megaphone and a splash, we only show the megaphone for
        // 7 days after the user first viewed the megaphone. After this point
        // we will display the splash. If there is only a megaphone we will
        // render it for as long as the upgrade is active.

        let didPresentView: Bool
        if (hasMegaphone && !hasSplash) || (hasMegaphone && next.daysSinceFirstViewed < splashStartDay) {
            let megaphone = self.megaphone(forExperienceUpgrade: next, fromViewController: fromViewController)
            megaphone?.present(fromViewController: fromViewController)
            lastPresented = megaphone
            didPresentView = true
        } else if hasSplash, let splash = splash(forExperienceUpgrade: next) {
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
        databaseStorage.write { transaction in
            ExperienceUpgradeFinder.markAsViewed(experienceUpgrade: next, transaction: transaction.unwrapGrdbWrite)
        }

        return didPresentView
    }

    // MARK: - Experience Specific Helpers

    /// Marks the specified type up of upgrade as complete and dismisses it if it is currently presented.
    static func clearExperienceUpgrade(_ experienceUpgradeId: ExperienceUpgradeId, transaction: GRDBWriteTransaction) {
        ExperienceUpgradeFinder.markAsComplete(experienceUpgradeId: experienceUpgradeId, transaction: transaction)
        transaction.addAsyncCompletion(queue: .main) {
            // If it's currently being presented, dismiss it.
            guard lastPresented?.experienceUpgrade.id == experienceUpgradeId else { return }
            lastPresented?.dismiss(animated: false, completion: nil)
        }
    }

    @objc
    static func clearReactionsExperienceUpgrade(transaction: GRDBWriteTransaction) {
        clearExperienceUpgrade(.reactions, transaction: transaction)
    }

    @objc
    static func clearProfileNameReminder(transaction: GRDBWriteTransaction) {
        clearExperienceUpgrade(.profileNameReminder, transaction: transaction)
    }

    // MARK: - Splash

    private static func hasSplash(forExperienceUpgrade experienceUpgrade: ExperienceUpgrade) -> Bool {
        switch experienceUpgrade.id {
        case .introducingPins:
            return RemoteConfig.mandatoryPins
        case .messageRequests:
            // Only use a splash for message requests if the user doesn't have a profile name.
            return !OWSProfileManager.shared().hasProfileName
        default:
            return false
        }
    }

    fileprivate static func splash(forExperienceUpgrade experienceUpgrade: ExperienceUpgrade) -> SplashViewController? {
        switch experienceUpgrade.id {
        case .introducingPins:
            return IntroducingPinsSplash(experienceUpgrade: experienceUpgrade)
        case .messageRequests:
            return MessageRequestsSplash(experienceUpgrade: experienceUpgrade)
        default:
            return nil
        }
    }

    // MARK: - Megaphone

    private static func hasMegaphone(forExperienceUpgrade experienceUpgrade: ExperienceUpgrade) -> Bool {
        switch experienceUpgrade.id {
        case .introducingPins,
             .reactions,
             .profileNameReminder,
             .pinReminder:
            return true
        case .messageRequests:
            // no need to annoy user with banner for message requests. They are self explanatory.
            return false
        default:
            return false
        }
    }

    fileprivate static func megaphone(forExperienceUpgrade experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) -> MegaphoneView? {
        switch experienceUpgrade.id {
        case .introducingPins:
            return IntroducingPinsMegaphone(experienceUpgrade: experienceUpgrade, fromViewController: fromViewController)
        case .reactions:
            return ReactionsMegaphone(experienceUpgrade: experienceUpgrade, fromViewController: fromViewController)
        case .profileNameReminder:
            return ProfileNameReminderMegaphone(experienceUpgrade: experienceUpgrade, fromViewController: fromViewController)
        case .pinReminder:
            return PinReminderMegaphone(experienceUpgrade: experienceUpgrade, fromViewController: fromViewController)
        case .messageRequests:
            // no need to annoy user with banner for message requests. They are self explanatory.
            return nil
        default:
            return nil
        }
    }
}

// MARK: -

protocol ExperienceUpgradeView: class {
    var experienceUpgrade: ExperienceUpgrade { get }
    var isPresented: Bool { get }
    func dismiss(animated: Bool, completion: (() -> Void)?)
}

extension ExperienceUpgradeView {
    var databaseStorage: SDSDatabaseStorage {
        return .shared
    }

    func presentToast(text: String, fromViewController: UIViewController) {
        let toastController = ToastController(text: text)

        let bottomInset = fromViewController.bottomLayoutGuide.length + 8
        toastController.presentToastView(fromBottomOfView: fromViewController.view, inset: bottomInset)
    }

    func markAsSnoozed() {
        databaseStorage.write { transaction in
            ExperienceUpgradeFinder.markAsSnoozed(
                experienceUpgrade: self.experienceUpgrade,
                transaction: transaction.unwrapGrdbWrite
            )
        }
    }

    func markAsComplete() {
        databaseStorage.write { transaction in
            ExperienceUpgradeFinder.markAsComplete(
                experienceUpgrade: self.experienceUpgrade,
                transaction: transaction.unwrapGrdbWrite
            )
        }
    }
}
