//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class ExperienceUpgradeManager: NSObject {
    private static var databaseStorage: SDSDatabaseStorage {
        return .shared
    }

    private static weak var currentlyPresented: UIView?

    @objc
    static func presentNext(fromViewController: UIViewController) -> Bool {
        // If we already have a experience upgrade
        // in the view hierarchy, do nothing
        guard currentlyPresented?.superview == nil else { return true }

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

        if (hasMegaphone && !hasSplash) || (hasMegaphone && next.daysSinceFirstViewed < 8) {
            let megaphone = self.megaphone(forExperienceUpgrade: next, fromViewController: fromViewController)
            megaphone?.present(fromViewController: fromViewController)
            currentlyPresented = megaphone
        } else if let splash = splash(forExperienceUpgrade: next) {
            fromViewController.presentFormSheet(splash, animated: true)
            currentlyPresented = splash.view
        } else {
            owsFailDebug("no megaphone or splash for experience upgrade! \(next.id)")
            return false
        }

        // Track that we've successfully presented this experience upgrade once.
        // If it was already marked as viewed, this will do nothing.
        databaseStorage.write { transaction in
            ExperienceUpgradeFinder.markAsViewed(experienceUpgrade: next, transaction: transaction.unwrapGrdbWrite)
        }

        return true
    }

    // MARK: - Splash

    private static func hasSplash(forExperienceUpgrade experienceUpgrade: ExperienceUpgrade) -> Bool {
        switch experienceUpgrade.id {
        case .introducingPins:
            return true
        default:
            return false
        }
    }

    fileprivate static func splash(forExperienceUpgrade experienceUpgrade: ExperienceUpgrade) -> UIViewController? {
        switch experienceUpgrade.id {
        case .introducingPins:
            let vc = IntroducingPinsSplash(experienceUpgrade: experienceUpgrade)
            return OWSNavigationController(rootViewController: vc)
        default:
            return nil
        }
    }

    // MARK: - Megaphone

    private static func hasMegaphone(forExperienceUpgrade experienceUpgrade: ExperienceUpgrade) -> Bool {
        switch experienceUpgrade.id {
        case .introducingPins:
            return true
        default:
            return false
        }
    }

    fileprivate static func megaphone(forExperienceUpgrade experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) -> MegaphoneView? {
        switch experienceUpgrade.id {
        case .introducingPins:
            return IntroducingPinsMegaphone(experienceUpgrade: experienceUpgrade, fromViewController: fromViewController)
        default:
            return nil
        }
    }
}

// MARK: -

protocol ExperienceUpgradeView {
    var experienceUpgrade: ExperienceUpgrade { get }
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
