//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

class RecoveryKeyReminderMegaphone: MegaphoneView {
    init(
        experienceUpgrade: ExperienceUpgrade,
        fromViewController: UIViewController,
    ) {
        super.init(experienceUpgrade: experienceUpgrade)

        titleText = OWSLocalizedString(
            "BACKUP_KEY_REMINDER_MEGAPHONE_TITLE",
            comment: "Title for Recovery Key reminder megaphone",
        )
        bodyText = OWSLocalizedString(
            "BACKUP_KEY_REMINDER_MEGAPHONE_BODY",
            comment: "Body for Recovery Key reminder megaphone",
        )
        imageName = "backups-key"

        let primaryButtonTitle = OWSLocalizedString(
            "BACKUP_KEY_REMINDER_MEGAPHONE_ACTION",
            comment: "Action text for Recovery Key reminder megaphone",
        )
        let secondaryButtonTitle = OWSLocalizedString(
            "BACKUP_KEY_REMINDER_NOT_NOW_ACTION",
            comment: "Snooze text for Recovery Key reminder megaphone",
        )

        let primaryButton = MegaphoneView.Button(title: primaryButtonTitle) {
            let backupsReminderCoordinator = BackupsReminderCoordinator(
                fromViewController: fromViewController,
                dismissHandler: { success in
                    self.dismiss()
                    if success {
                        self.presentToastForNewRepetitionInterval(fromViewController: fromViewController)
                    }
                    DependenciesBridge.shared.db.write { tx in
                        BackupSettingsStore().setLastRecoveryKeyReminderDate(Date(), tx: tx)
                    }
                },
            )

            backupsReminderCoordinator.presentVerifyFlow()
        }

        let secondaryButton = snoozeButton(
            fromViewController: fromViewController,
            snoozeTitle: secondaryButtonTitle,
        )

        setButtons(primary: primaryButton, secondary: secondaryButton)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func presentToastForNewRepetitionInterval(fromViewController: UIViewController) {
        let toastText = OWSLocalizedString(
            "BACKUP_KEY_REMINDER_SUCCESSFUL_TOAST",
            comment: "Toast indicating that the Recovery Key was correct.",
        )

        presentToast(text: toastText, fromViewController: fromViewController)
    }
}
