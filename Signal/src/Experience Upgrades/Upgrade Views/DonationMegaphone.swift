//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

class DonationMegaphone: MegaphoneView {
    init(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) {
        super.init(experienceUpgrade: experienceUpgrade)

        titleText = NSLocalizedString("DONATE_MEGAPHONE_TITLE", comment: "Title for donate megaphone")
        bodyText = NSLocalizedString("DONATE_MEGAPHONE_BODY", comment: "Body for donate megaphone")
        imageName = "donate-megaphone"

        setButtons(
            primary: Button(title: NSLocalizedString(
                "DONATE_MEGAPHONE_ACTION",
                comment: "Action text for donate megaphone"
            )) {
                let vc = OWSNavigationController(rootViewController: DonationViewController())
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
