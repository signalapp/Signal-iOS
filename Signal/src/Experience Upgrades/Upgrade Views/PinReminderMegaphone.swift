//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

class PinReminderMegaphone: MegaphoneView {
    init(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) {
        super.init(experienceUpgrade: experienceUpgrade)

        titleText = NSLocalizedString("PIN_REMINDER_MEGAPHONE_TITLE", comment: "Title for PIN reminder megaphone")
        bodyText = NSLocalizedString("PIN_REMINDER_MEGAPHONE_BODY", comment: "Body for PIN reminder megaphone")
        imageName = "PIN_megaphone"

        let primaryButtonTitle = NSLocalizedString("PIN_REMINDER_MEGAPHONE_ACTION", comment: "Action text for PIN reminder megaphone")

        let primaryButton = MegaphoneView.Button(title: primaryButtonTitle) { [weak self] in
            let vc = PinReminderViewController { result in
                // Always dismiss the PIN reminder view (we dismiss the *megaphone* later).
                fromViewController.dismiss(animated: true)

                guard let self else { return }
                switch result {
                case .succeeded, .canceled(didGuessWrong: true):
                    self.dismiss(animated: false)
                    self.presentToastForNewRepetitionInterval(fromViewController: fromViewController)
                case .changedOrRemovedPin:
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

    func presentToastForNewRepetitionInterval(fromViewController: UIViewController) {
        let toastText: String
        switch OWS2FAManager.shared.repetitionInterval {
        case (1 * kDayInterval):
            toastText = NSLocalizedString("PIN_REMINDER_MEGAPHONE_TOMORROW_TOAST",
                                          comment: "Toast indicating that we'll ask you for your PIN again tomorrow.")
        case (3 * kDayInterval):
            toastText = NSLocalizedString("PIN_REMINDER_MEGAPHONE_FEW_DAYS_TOAST",
                                          comment: "Toast indicating that we'll ask you for your PIN again in 3 days.")
        case (7 * kDayInterval):
            toastText = NSLocalizedString("PIN_REMINDER_MEGAPHONE_WEEK_TOAST",
                                          comment: "Toast indicating that we'll ask you for your PIN again in a week.")
        case (14 * kDayInterval):
            toastText = NSLocalizedString("PIN_REMINDER_MEGAPHONE_TWO_WEEK_TOAST",
                                          comment: "Toast indicating that we'll ask you for your PIN again in 2 weeks.")
        default:
            toastText = MegaphoneStrings.weWillRemindYouLater
        }

        presentToast(text: toastText, fromViewController: fromViewController)
    }
}
