//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SafariServices

final class InactivePrimaryDeviceReminderMegaphone: MegaphoneView {
    private var learnMoreURL: URL { URL(string: "https://support.signal.org/hc/articles/9021007554074")! }

    init(
        fromViewController: UIViewController,
        experienceUpgrade: ExperienceUpgrade
    ) {
        super.init(experienceUpgrade: experienceUpgrade)

        titleText = OWSLocalizedString(
            "INACTIVE_PRIMARY_DEVICE_REMINDER_MEGAPHONE_TITLE",
            comment: "Title for an in-app megaphone about a user's inactive primary device."
        )

        bodyText = OWSLocalizedString(
            "INACTIVE_PRIMARY_DEVICE_REMINDER_MEGAPHONE_BODY",
            comment: "Body for an in-app megaphone about a user's inactive primary device."
        )

        imageName = "phone-warning"
        imageContentMode = .center

        let viewControllerRef = fromViewController
        let learnMoreButton = Button(title: OWSLocalizedString(
            "INACTIVE_PRIMARY_DEVICE_REMINDER_MEGAPHONE_LEARN_MORE_BUTTON",
            comment: "Title for a button in an in-app megaphone about a user's inactive linked device, indicating the user wants to learn more."
        )) { [weak viewControllerRef] in
            viewControllerRef?.present(SFSafariViewController(url: self.learnMoreURL), animated: true)
        }

        let gotItButton = snoozeButton(
            fromViewController: fromViewController,
            snoozeTitle: OWSLocalizedString(
                "INACTIVE_PRIMARY_DEVICE_REMINDER_MEGAPHONE_GOT_IT_BUTTON",
                comment: "Title for a button in an in-app megaphone about a user's inactive primary device, temporarily dismissing the megaphone."
            )
        )
        setButtons(primary: gotItButton, secondary: learnMoreButton)
    }

    @available(*, unavailable, message: "Use other constructor!")
    required init(coder: NSCoder) {
        owsFail("Use other constructor!")
    }
}
