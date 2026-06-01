//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices
import SignalServiceKit
import SignalUI

class IntroducingPinsMegaphone: Megaphone {
    init(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) {
        super.init(experienceUpgrade: experienceUpgrade)

        titleText = OWSLocalizedString("PINS_MEGAPHONE_TITLE", comment: "Title for PIN megaphone when user doesn't have a PIN")
        bodyText = OWSLocalizedString("PINS_MEGAPHONE_BODY", comment: "Body for PIN megaphone when user doesn't have a PIN")
        image = .pinMegaphone

        let primaryButtonTitle = OWSLocalizedString("PINS_MEGAPHONE_ACTION", comment: "Action text for PIN megaphone when user doesn't have a PIN")

        let primaryButton = Button(title: primaryButtonTitle) { [weak self] in
            let viewController = PinSetupViewController(
                mode: .creating,
                showCancelButton: true,
                onSuccess: { pinSetupViewController in
                    pinSetupViewController.dismiss(animated: true) { [weak self, weak fromViewController] in
                        guard let self, let fromViewController else { return }

                        markAsCompleteWithSneakyTransaction()

                        fromViewController.presentToast(text: OWSLocalizedString(
                            "PINS_MEGAPHONE_TOAST",
                            comment: "Toast indicating that a PIN has been created.",
                        ))
                    }
                },
            )
            fromViewController.present(OWSNavigationController(rootViewController: viewController), animated: true)
        }

        let secondaryButton = snoozeButton(
            fromViewController: fromViewController,
            snoozeTitle: MegaphoneStrings.remindMeLater,
        )

        buttons = [primaryButton, secondaryButton]
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
