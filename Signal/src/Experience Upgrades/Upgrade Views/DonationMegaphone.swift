//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

class DonationMegaphone: MegaphoneView {
    init(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) {
        super.init(experienceUpgrade: experienceUpgrade)

        titleText = NSLocalizedString(
            "DONATE_MEGAPHONE_TITLE",
            value: "Donate to Signal",
            comment: "Title for donate megaphone"
        )
        bodyText = NSLocalizedString(
            "DONATE_MEGAPHONE_BODY",
            value: "Signal is funded by your donations. Privacy over profit.",
            comment: "Body for donate megaphone"
        )
        imageName = "donate-megaphone"

        setButtons(
            primary: Button(title: NSLocalizedString(
                "DONATE_MEGAPHONE_ACTION",
                comment: "Action text for donate megaphone"
            )) {
                let vc = OWSNavigationController(rootViewController: DonationSettingsViewController())
                fromViewController.present(vc, animated: true)
            },
            secondary: Button(title: NSLocalizedString(
                "DONATE_MEGAPHONE_CANCEL",
                comment: "Cancel text for donate megaphone"
            )) { [weak self] in
                self?.markAsSnoozedWithSneakyTransaction()
                self?.dismiss()
            }
        )
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
 }
