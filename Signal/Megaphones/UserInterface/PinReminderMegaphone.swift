//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import UIKit

class PinReminderMegaphone: Megaphone {
    private var db: DB { DependenciesBridge.shared.db }
    private var ows2FAManager: OWS2FAManager { SSKEnvironment.shared.ows2FAManagerRef }

    init(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) {
        super.init(experienceUpgrade: experienceUpgrade)

        titleText = OWSLocalizedString("PIN_REMINDER_MEGAPHONE_TITLE", comment: "Title for PIN reminder megaphone")
        bodyText = OWSLocalizedString("PIN_REMINDER_MEGAPHONE_BODY", comment: "Body for PIN reminder megaphone")
        image = .pinMegaphone

        let primaryButton = Button(
            title: OWSLocalizedString(
                "PIN_REMINDER_MEGAPHONE_ACTION",
                comment: "Action text for PIN reminder megaphone",
            ),
        ) { [weak fromViewController] in
            guard let fromViewController else { return }

            let vc = PinReminderViewController { [weak self] pinReminderViewController, result in
                // Always dismiss the PIN reminder view (we dismiss the *megaphone* later).
                pinReminderViewController.dismiss(animated: true)

                guard let self else { return }

                switch result {
                case .succeeded:
                    presentToastForNewRepetitionInterval(
                        wasSuccessful: true,
                        fromViewController: fromViewController,
                    )
                case .canceled(didGuessWrong: true):
                    presentToastForNewRepetitionInterval(
                        wasSuccessful: false,
                        fromViewController: fromViewController,
                    )
                case .changedPin, .canceled(didGuessWrong: false):
                    break
                }

                NotificationCenter.default.post(name: .megaphoneStateDidChange, object: nil)
            }

            fromViewController.present(vc, animated: true)
        }

        let secondaryButton = Button(
            title: CommonStrings.notNowButton,
        ) { [weak self, weak fromViewController] in
            guard let self, let fromViewController else { return }

            db.write { tx in
                self.ows2FAManager.recordReminderCompleted(
                    repetitionIntervalAdjustment: nil,
                    tx: tx,
                )
            }

            presentToastForNewRepetitionInterval(
                wasSuccessful: false,
                fromViewController: fromViewController,
            )

            NotificationCenter.default.post(name: .megaphoneStateDidChange, object: nil)
        }

        buttons = [primaryButton, secondaryButton]
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func presentToastForNewRepetitionInterval(
        wasSuccessful: Bool,
        fromViewController: UIViewController,
    ) {
        let newRepetitionInterval: OWS2FAManager.PinReminderRepetitionInterval = db.read { tx in
            ows2FAManager.repetitionInterval(tx: tx)
        }

        let toastText: String
        switch (newRepetitionInterval, wasSuccessful) {
        case (.threeDays, false):
            toastText = OWSLocalizedString(
                "PIN_REMINDER_MEGAPHONE_FEW_DAYS_TOAST",
                comment: "Toast indicating that we'll ask you for your PIN again in 3 days.",
            )
        case (.threeDays, true):
            toastText = OWSLocalizedString(
                "PIN_REMINDER_MEGAPHONE_FEW_DAYS_SUCCESSFUL_TOAST",
                comment: "Toast indicating that we'll ask you for your PIN again tomorrow, after successfully entering it.",
            )
        case (.oneWeek, false):
            toastText = OWSLocalizedString(
                "PIN_REMINDER_MEGAPHONE_WEEK_TOAST",
                comment: "Toast indicating that we'll ask you for your PIN again in a week.",
            )
        case (.oneWeek, true):
            toastText = OWSLocalizedString(
                "PIN_REMINDER_MEGAPHONE_WEEK_SUCCESSFUL_TOAST",
                comment: "Toast indicating that we'll ask you for your PIN again tomorrow, after successfully entering it.",
            )
        case (.twoWeeks, false):
            toastText = OWSLocalizedString(
                "PIN_REMINDER_MEGAPHONE_TWO_WEEK_TOAST",
                comment: "Toast indicating that we'll ask you for your PIN again tomorrow.",
            )
        case (.twoWeeks, true):
            toastText = OWSLocalizedString(
                "PIN_REMINDER_MEGAPHONE_TWO_WEEK_SUCCESSFUL_TOAST",
                comment: "Toast indicating that we'll ask you for your PIN again in 2 weeks, after successfully entering it.",
            )
        case (.fourWeeks, _):
            toastText = MegaphoneStrings.weWillRemindYouLater
        }

        fromViewController.presentToast(text: toastText)
    }
}
