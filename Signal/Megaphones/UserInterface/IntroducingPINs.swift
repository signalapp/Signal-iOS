//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices
import SignalServiceKit
import SignalUI

class IntroducingPinsMegaphone: MegaphoneView {
    init(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) {
        super.init(experienceUpgrade: experienceUpgrade)

        titleText = OWSLocalizedString("PINS_MEGAPHONE_TITLE", comment: "Title for PIN megaphone when user doesn't have a PIN")
        bodyText = OWSLocalizedString("PINS_MEGAPHONE_BODY", comment: "Body for PIN megaphone when user doesn't have a PIN")
        imageName = "PIN_megaphone"

        let primaryButtonTitle = OWSLocalizedString("PINS_MEGAPHONE_ACTION", comment: "Action text for PIN megaphone when user doesn't have a PIN")

        let primaryButton = MegaphoneView.Button(title: primaryButtonTitle) { [weak self] in
            let viewController = PinSetupViewController(
                mode: .creating,
                hideNavigationBar: false,
                showCancelButton: true,
                completionHandler: { [weak self, weak fromViewController] _, error in
                    guard let self, let fromViewController else { return }
                    if let error {
                        Logger.error("failed to create pin: \(error)")
                    } else {
                        // success
                        self.markAsCompleteWithSneakyTransaction()
                    }
                    self.dismiss(animated: false)
                    fromViewController.dismiss(animated: true) {
                        self.presentToast(
                            text: OWSLocalizedString("PINS_MEGAPHONE_TOAST", comment: "Toast indicating that a PIN has been created."),
                            fromViewController: fromViewController
                        )
                    }
                }
            )
            fromViewController.present(OWSNavigationController(rootViewController: viewController), animated: true)
        }

        let secondaryButton = snoozeButton(fromViewController: fromViewController)

        setButtons(primary: primaryButton, secondary: secondaryButton)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
