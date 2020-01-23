//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class ExperienceUpgradeManager: NSObject {
    private static var databaseStorage: SDSDatabaseStorage {
        return .shared
    }

    private static var finder: ExperienceUpgradeFinder {
        return .shared
    }

    private static weak var currentlyPresented: UIView?

    @objc
    static func presentNext(fromViewController: UIViewController) -> Bool {
        // If we already have a experience upgrade
        // in the view hierarchy, do nothing
        guard currentlyPresented?.superview == nil else { return true }

        guard let next = databaseStorage.read(block: { transaction in
            return finder.next(transaction: transaction.unwrapGrdbRead)
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
        markAsViewed(experienceUpgrade: next)

        return true
    }

    // MARK: - Splash

    private static func hasSplash(forExperienceUpgrade experienceUpgrade: ExperienceUpgrade) -> Bool {
        switch experienceUpgrade.id {
        case .introducingPins,
             .introducingStickers:
            return true
        default:
            return false
        }
    }

    fileprivate static func splash(forExperienceUpgrade experienceUpgrade: ExperienceUpgrade) -> UIViewController? {
        switch experienceUpgrade.id {
        case .introducingStickers:
            return IntroducingStickersExperienceUpgradeViewController(experienceUpgrade: experienceUpgrade)
        case .introducingPins:
            let vc = IntroducingPinsExperienceUpgradeViewController(experienceUpgrade: experienceUpgrade)
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

    // MARK: - Megaphone Helpers

    fileprivate static func presentToast(text: String, fromViewController: UIViewController) {
        let toastController = ToastController(text: text)

        let bottomInset = fromViewController.bottomLayoutGuide.length + 8
        toastController.presentToastView(fromBottomOfView: fromViewController.view, inset: bottomInset)
    }

    fileprivate static func markAsViewed(experienceUpgrade: ExperienceUpgrade) {
        databaseStorage.write { transaction in
            finder.markAsViewed(experienceUpgrade: experienceUpgrade, transaction: transaction.unwrapGrdbWrite)
        }
    }

    fileprivate static func markAsSnoozed(experienceUpgrade: ExperienceUpgrade) {
        databaseStorage.write { transaction in
            finder.markAsSnoozed(experienceUpgrade: experienceUpgrade, transaction: transaction.unwrapGrdbWrite)
        }
    }

    fileprivate static func markAsComplete(experienceUpgrade: ExperienceUpgrade) {
        databaseStorage.write { transaction in
            finder.markAsComplete(experienceUpgrade: experienceUpgrade, transaction: transaction.unwrapGrdbWrite)
        }
    }
}

// MARK: -

private extension MegaphoneView {
    func snoozeButton(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) -> Button {
        return MegaphoneView.Button(title: MegaphoneStrings.remindMeLater) { [weak self] in
            ExperienceUpgradeManager.markAsSnoozed(experienceUpgrade: experienceUpgrade)
            self?.dismiss {
                ExperienceUpgradeManager.presentToast(text: MegaphoneStrings.weWillRemindYouLater, fromViewController: fromViewController)
            }
        }
    }
}

private class IntroducingPinsMegaphone: MegaphoneView {
    init(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) {
        super.init(frame: .zero)

        let hasPinAlready = OWS2FAManager.shared().is2FAEnabled()

        titleText = hasPinAlready
            ? NSLocalizedString("PINS_MEGAPHONE_HAS_PIN_TITLE", comment: "Title for PIN megaphone when user already has a PIN")
            : NSLocalizedString("PINS_MEGAPHONE_NO_PIN_TITLE", comment: "Title for PIN megaphone when user doesn't have a PIN")
        bodyText = hasPinAlready
            ? NSLocalizedString("PINS_MEGAPHONE_HAS_PIN_BODY", comment: "Body for PIN megaphone when user already has a PIN")
            : NSLocalizedString("PINS_MEGAPHONE_NO_PIN_BODY", comment: "Body for PIN megaphone when user already has a PIN")
        imageName = "PIN_megaphone"

        let primaryButtonTitle = hasPinAlready
            ? NSLocalizedString("PINS_MEGAPHONE_HAS_PIN_ACTION", comment: "Action text for PIN megaphone when user already has a PIN")
            : NSLocalizedString("PINS_MEGAPHONE_NO_PIN_ACTION", comment: "Action text for PIN megaphone when user already has a PIN")

        let primaryButton = MegaphoneView.Button(title: primaryButtonTitle) { [weak self] in
            let vc = PinSetupViewController {
                ExperienceUpgradeManager.markAsComplete(experienceUpgrade: experienceUpgrade)
                fromViewController.navigationController?.popToViewController(fromViewController, animated: true) {
                    fromViewController.navigationController?.setNavigationBarHidden(false, animated: false)
                    self?.dismiss(animated: false)
                    ExperienceUpgradeManager.presentToast(
                        text: NSLocalizedString("PINS_MEGAPHONE_TOAST", comment: "Toast indicating that a PIN has been created."),
                        fromViewController: fromViewController
                    )
                }
            }

            fromViewController.navigationController?.pushViewController(vc, animated: true)
        }

        let secondaryButton = snoozeButton(experienceUpgrade: experienceUpgrade, fromViewController: fromViewController)
        setButtons(primary: primaryButton, secondary: secondaryButton)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
