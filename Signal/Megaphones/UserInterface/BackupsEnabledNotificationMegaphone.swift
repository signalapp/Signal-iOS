//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

class BackupsEnabledNotificationMegaphone: MegaphoneView {
    private let db: DB
    private let backupSettingsStore: BackupSettingsStore
    init(
        experienceUpgrade: ExperienceUpgrade,
        fromViewController: UIViewController,
        backupsEnabledTime: Date,
        db: DB,
        backupSettingsStore: BackupSettingsStore = BackupSettingsStore(),
    ) {
        self.db = db
        self.backupSettingsStore = backupSettingsStore

        super.init(experienceUpgrade: experienceUpgrade)

        titleText = OWSLocalizedString(
            "BACKUPS_TURNED_ON_TITLE",
            comment: "Title for system notification or megaphone when backups is enabled",
        )

        bodyText = String(
            format: OWSLocalizedString(
                "BACKUPS_TURNED_ON_NOTIFICATION_BODY_FORMAT",
                comment: "Body for system notification or megaphone when backups is enabled. Embeds {{ time backups was enabled }}",
            ),
            backupsEnabledTime.formatted(date: .omitted, time: .shortened),
        )
        imageName = "backups-logo"

        let primaryButtonTitle = OWSLocalizedString(
            "BACKUPS_VIEW_SETTINGS_BUTTON",
            comment: "Action text for backups enabled megaphone taking user to backup settings",
        )
        let primaryButton = MegaphoneView.Button(title: primaryButtonTitle) { [weak self] in
            SignalApp.shared.showAppSettings(mode: .backups)
            self?.markAsViewed()
            self?.dismiss(animated: true)
        }

        let secondaryButton = MegaphoneView.Button(title: CommonStrings.okButton) { [weak self] in
            self?.markAsViewed()
            self?.dismiss(animated: true)
        }

        setButtons(primary: primaryButton, secondary: secondaryButton)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func markAsViewed() {
        db.write { tx in
            backupSettingsStore.clearLastBackupEnabledDetails(tx: tx)
        }
    }
}
