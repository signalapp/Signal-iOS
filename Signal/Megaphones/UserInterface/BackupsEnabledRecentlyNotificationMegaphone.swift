//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import UIKit

class BackupsEnabledRecentlyNotificationMegaphone: Megaphone {
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

        bodyText = String.nonPluralLocalizedStringWithFormat(
            OWSLocalizedString(
                "BACKUPS_TURNED_ON_NOTIFICATION_BODY_FORMAT",
                comment: "Body for system notification or megaphone when backups is enabled. Embeds {{ time backups was enabled }}",
            ),
            backupsEnabledTime.formatted(date: .omitted, time: .shortened),
        )
        image = .backupsLogo

        let primaryButtonTitle = OWSLocalizedString(
            "BACKUPS_VIEW_SETTINGS_BUTTON",
            comment: "Action text for backups enabled megaphone taking user to backup settings",
        )
        let primaryButton = Button(title: primaryButtonTitle) { [weak self] in
            SignalApp.shared.showAppSettings(mode: .backups())
            self?.stopShowing()
        }

        let secondaryButton = Button(title: CommonStrings.okButton) { [weak self] in
            self?.stopShowing()
        }

        buttons = [primaryButton, secondaryButton]
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func stopShowing() {
        db.write { tx in
            backupSettingsStore.clearLastBackupEnabledDetails(tx: tx)
        }

        NotificationCenter.default.post(name: .megaphoneStateDidChange, object: nil)
    }
}
