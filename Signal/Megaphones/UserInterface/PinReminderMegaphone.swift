//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

class PinReminderMegaphone: MegaphoneView {
    init(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) {
        super.init(experienceUpgrade: experienceUpgrade)

        titleText = OWSLocalizedString("PIN_REMINDER_MEGAPHONE_TITLE", comment: "Title for PIN reminder megaphone")
        bodyText = OWSLocalizedString("PIN_REMINDER_MEGAPHONE_BODY", comment: "Body for PIN reminder megaphone")
        imageName = "PIN_megaphone"

        let primaryButtonTitle = OWSLocalizedString("PIN_REMINDER_MEGAPHONE_ACTION", comment: "Action text for PIN reminder megaphone")

        let primaryButton = MegaphoneView.Button(title: primaryButtonTitle) { [weak self] in
            let vc = PinReminderViewController { result in
                // Always dismiss the PIN reminder view (we dismiss the *megaphone* later).
                fromViewController.dismiss(animated: true)

                guard let self else { return }
                switch result {
                case .succeeded:
                    self.dismiss(animated: false)
                    self.presentToastForNewRepetitionInterval(
                        wasSuccessful: true,
                        fromViewController: fromViewController,
                    )
                case .canceled(didGuessWrong: true):
                    self.dismiss(animated: false)
                    self.presentToastForNewRepetitionInterval(
                        wasSuccessful: false,
                        fromViewController: fromViewController,
                    )
                case .changedPin:
                    self.dismiss(animated: false)
                case .canceled(didGuessWrong: false):
                    break
                }
            }

            fromViewController.present(vc, animated: true)
        }

        setButtons(primary: primaryButton)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func presentToastForNewRepetitionInterval(
        wasSuccessful: Bool,
        fromViewController: UIViewController,
    ) {
        let toastText: String
        switch (SSKEnvironment.shared.ows2FAManagerRef.repetitionInterval, wasSuccessful) {
        case (1 * .day, false):
            toastText = OWSLocalizedString(
                "PIN_REMINDER_MEGAPHONE_TOMORROW_TOAST",
                comment: "Toast indicating that we'll ask you for your PIN again tomorrow.",
            )
        case (1 * .day, true):
            toastText = OWSLocalizedString(
                "PIN_REMINDER_MEGAPHONE_TOMORROW_SUCCESSFUL_TOAST",
                comment: "Toast indicating that we'll ask you for your PIN again tomorrow, after successfully entering it.",
            )
        case (3 * .day, false):
            toastText = OWSLocalizedString(
                "PIN_REMINDER_MEGAPHONE_FEW_DAYS_TOAST",
                comment: "Toast indicating that we'll ask you for your PIN again in 3 days.",
            )
        case (3 * .day, true):
            toastText = OWSLocalizedString(
                "PIN_REMINDER_MEGAPHONE_FEW_DAYS_SUCCESSFUL_TOAST",
                comment: "Toast indicating that we'll ask you for your PIN again tomorrow, after successfully entering it.",
            )
        case (7 * .day, false):
            toastText = OWSLocalizedString(
                "PIN_REMINDER_MEGAPHONE_WEEK_TOAST",
                comment: "Toast indicating that we'll ask you for your PIN again in a week.",
            )
        case (7 * .day, true):
            toastText = OWSLocalizedString(
                "PIN_REMINDER_MEGAPHONE_WEEK_SUCCESSFUL_TOAST",
                comment: "Toast indicating that we'll ask you for your PIN again tomorrow, after successfully entering it.",
            )
        case (14 * .day, false):
            toastText = OWSLocalizedString(
                "PIN_REMINDER_MEGAPHONE_TWO_WEEK_TOAST",
                comment: "Toast indicating that we'll ask you for your PIN again tomorrow.",
            )
        case (14 * .day, true):
            toastText = OWSLocalizedString(
                "PIN_REMINDER_MEGAPHONE_TWO_WEEK_SUCCESSFUL_TOAST",
                comment: "Toast indicating that we'll ask you for your PIN again in 2 weeks, after successfully entering it.",
            )
        default:
            toastText = MegaphoneStrings.weWillRemindYouLater
        }

        presentToast(text: toastText, fromViewController: fromViewController)
    }
}
