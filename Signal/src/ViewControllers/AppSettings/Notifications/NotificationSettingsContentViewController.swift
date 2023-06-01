//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

class NotificationSettingsContentViewController: OWSTableViewController2 {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("SETTINGS_NOTIFICATION_CONTENT_TITLE", comment: "")

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let section = OWSTableSection()
        section.footerTitle = OWSLocalizedString("NOTIFICATIONS_FOOTER_WARNING", comment: "")

        let selectedType = preferences.notificationPreviewType
        let allTypes: [NotificationType] = [.namePreview, .nameNoPreview, .noNameNoPreview]
        for type in allTypes {
            section.add(.init(
                text: type.displayName,
                actionBlock: { [weak self] in
                    self?.preferences.setNotificationPreviewType(type)

                    // rebuild callUIAdapter since notification configuration changed.
                    Self.callService.createCallUIAdapter()

                    self?.updateTableContents()
                },
                accessoryType: type == selectedType ? .checkmark : .none
            ))
        }

        contents.addSection(section)

        self.contents = contents
    }
}
