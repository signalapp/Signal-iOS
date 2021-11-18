//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

class SubscriptionMegaphone: MegaphoneView {
    init(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) {
        super.init(experienceUpgrade: experienceUpgrade)

        titleText = NSLocalizedString("SUBSCRIPTION_MEGAPHONE_TITLE", comment: "Title for subscription megaphone")
        bodyText = NSLocalizedString("SUBSCRIPTION_MEGAPHONE_BODY", comment: "Body for subscription megaphone")
        imageName = "subscription-megaphone"

        setButtons(
            primary: Button(title: NSLocalizedString(
                "SUBSCRIPTION_MEGAPHONE_ACTION",
                comment: "Action text for subscription megaphone"
            )) {
                let vc = OWSNavigationController(rootViewController: SubscriptionViewController())
                fromViewController.present(vc, animated: true)
            },
            secondary: Button(title: NSLocalizedString(
                "SUBSCRIPTION_MEGAPHONE_CANCEL",
                comment: "Cancel text for subscription megaphone"
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
