//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import UIKit

class RecoveryKeyReminderMegaphone: Megaphone {
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
        image = .backupsKey

        let primaryButtonTitle = OWSLocalizedString(
            "BACKUP_KEY_REMINDER_MEGAPHONE_ACTION",
            comment: "Action text for Recovery Key reminder megaphone",
        )
        let secondaryButtonTitle = OWSLocalizedString(
            "BACKUP_KEY_REMINDER_NOT_NOW_ACTION",
            comment: "Snooze text for Recovery Key reminder megaphone",
        )

        let primaryButton = Button(title: primaryButtonTitle) {
            let accountKeyStore = DependenciesBridge.shared.accountKeyStore
            let backupSettingsStore = BackupSettingsStore()
            let db = DependenciesBridge.shared.db

            guard let aep = db.read(block: { accountKeyStore.getAccountEntropyPool(tx: $0) }) else {
                return
            }

            BackupRecoveryKeyReminderCoordinator(
                aep: aep,
                fromViewController: fromViewController,
                onSuccess: {
                    db.write { tx in
                        backupSettingsStore.setLastRecoveryKeyReminderDate(Date(), tx: tx)
                    }

                    let toastText = OWSLocalizedString(
                        "BACKUP_KEY_REMINDER_SUCCESSFUL_TOAST",
                        comment: "Toast indicating that the Recovery Key was correct.",
                    )
                    fromViewController.presentToast(text: toastText)

                    NotificationCenter.default.post(name: .megaphoneStateDidChange, object: nil)
                },
            ).presentVerifyFlow()
        }

        let secondaryButton = snoozeButton(
            fromViewController: fromViewController,
            snoozeTitle: secondaryButtonTitle,
        )

        buttons = [primaryButton, secondaryButton]
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
