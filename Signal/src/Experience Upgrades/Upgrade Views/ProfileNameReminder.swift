//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import Lottie

class ProfileNameReminderMegaphone: MegaphoneView {
    init(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) {
        super.init(experienceUpgrade: experienceUpgrade)

        let hasProfileNameAlready = OWSProfileManager.shared().localFullName()?.isEmpty == false

        titleText = hasProfileNameAlready
            ? NSLocalizedString("PROFILE_NAME_REMINDER_MEGAPHONE_HAS_NAME_TITLE",
                                comment: "Title for profile name reminder megaphone when user already has a profile name")
            : NSLocalizedString("PROFILE_NAME_REMINDER_MEGAPHONE_NO_NAME_TITLE",
                                comment: "Title for profile name reminder megaphone when user doesn't have a profile name")
        bodyText = hasProfileNameAlready
            ? NSLocalizedString("PROFILE_NAME_REMINDER_MEGAPHONE_HAS_NAME_BODY",
                                comment: "Body for profile name reminder megaphone when user already has a profile name")
            : NSLocalizedString("PROFILE_NAME_REMINDER_MEGAPHONE_NO_NAME_BODY",
                                comment: "Body for profile name reminder megaphone when user doesn't have a profile name")
        imageName = "profileMegaphone"

        let primaryButton = MegaphoneView.Button(
            title: NSLocalizedString("PROFILE_NAME_REMINDER_MEGAPHONE_ACTION",
                                     comment: "Action text for profile name reminder megaphone")
        ) { [weak self] in
            let vc = ProfileViewController(mode: .experienceUpgrade) { _ in
                self?.markAsComplete()
                fromViewController.navigationController?.popToViewController(fromViewController, animated: true) {
                    fromViewController.navigationController?.setNavigationBarHidden(false, animated: false)
                    self?.dismiss(animated: false)
                    self?.presentToast(
                        text: NSLocalizedString("PROFILE_NAME_REMINDER_MEGAPHONE_TOAST",
                                                comment: "Toast indicating that a PIN has been created."),
                        fromViewController: fromViewController
                    )
                }
            }

            fromViewController.navigationController?.pushViewController(vc, animated: true)
        }

        let secondaryButton = snoozeButton(fromViewController: fromViewController)
        setButtons(primary: primaryButton, secondary: secondaryButton)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
