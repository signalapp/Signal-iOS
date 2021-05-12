//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

class DonateMegaphone: MegaphoneView {
    init(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) {
        super.init(experienceUpgrade: experienceUpgrade)

        titleText = NSLocalizedString("DONATION_MEGAPHONE_TITLE", comment: "Title for donation megaphone")
        bodyText = NSLocalizedString("DONATION_MEGAPHONE_BODY", comment: "Body for donation megaphone")
        imageName = "donation-megaphone"

        setButtons(
            primary: Button(title: NSLocalizedString(
                "DONATION_MEGAPHONE_ACTION",
                comment: "Action text for donation megaphone"
            )) {
                let vc = OWSNavigationController(rootViewController: DonationViewController())
                fromViewController.present(vc, animated: true)
            },
            secondary: Button(title: NSLocalizedString(
                "DONATION_MEGAPHONE_CANCEL",
                comment: "Cancel text for donation megaphone"
            )) { [weak self] in
                self?.markAsSnoozed()
                self?.dismiss()
            }
        )
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
