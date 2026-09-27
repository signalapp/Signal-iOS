//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class NotificationSettingsBadgeCountViewController: OWSTableViewController2 {
    private let db = DependenciesBridge.shared.db
    private let notificationPreferencesManager = DependenciesBridge.shared.notificationPreferencesManager

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SETTINGS_NOTIFICATION_BADGE_COUNT",
            comment: "Label for the setting controlling whether the app icon badge counts unread messages or unread chats.",
        )

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let section = OWSTableSection()
        section.footerTitle = OWSLocalizedString(
            "SETTINGS_NOTIFICATION_BADGE_COUNT_FOOTER",
            comment: "Explanation for the setting controlling whether the app icon badge counts unread messages or unread chats.",
        )

        let selectedType = db.read(block: notificationPreferencesManager.badgeCountType(tx:))
        for type in BadgeCountType.allCases {
            section.add(OWSTableItem(
                text: type.title,
                actionBlock: { [weak self] in
                    guard let self else { return }
                    self.db.write { tx in
                        self.notificationPreferencesManager.setBadgeCountType(type, tx: tx)
                    }

                    AppEnvironment.shared.badgeManager.invalidateBadgeValue()

                    self.updateTableContents()
                },
                accessoryType: type == selectedType ? .checkmark : .none,
            ))
        }

        contents.add(section)

        self.contents = contents
    }
}
