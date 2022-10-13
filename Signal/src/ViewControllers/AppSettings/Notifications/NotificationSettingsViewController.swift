//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
class NotificationSettingsViewController: OWSTableViewController2 {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_NOTIFICATIONS", comment: "The title for the notification settings.")

        updateTableContents()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let soundsSection = OWSTableSection()
        soundsSection.headerTitle = NSLocalizedString(
            "SETTINGS_SECTION_SOUNDS",
            comment: "Header Label for the sounds section of settings views."
        )
        soundsSection.add(.disclosureItem(
            withText: NSLocalizedString(
                "SETTINGS_ITEM_NOTIFICATION_SOUND",
                comment: "Label for settings view that allows user to change the notification sound."
            ),
            detailText: OWSSounds.displayName(forSound: OWSSounds.globalNotificationSound()),
            actionBlock: { [weak self] in
                let vc = NotificationSettingsSoundViewController { self?.updateTableContents() }
                self?.present(OWSNavigationController(rootViewController: vc), animated: true)
            }
        ))
        soundsSection.add(.switch(
            withText: NSLocalizedString(
                "NOTIFICATIONS_SECTION_INAPP",
                comment: "Table cell switch label. When disabled, Signal will not play notification sounds while the app is in the foreground."
            ),
            isOn: { Self.preferences.soundInForeground() },
            target: self,
            selector: #selector(didToggleSoundNotificationsSwitch)
        ))
        contents.addSection(soundsSection)

        let notificationContentSection = OWSTableSection()
        notificationContentSection.headerTitle = NSLocalizedString(
            "SETTINGS_NOTIFICATION_CONTENT_TITLE",
            comment: "table section header"
        )
        notificationContentSection.footerTitle = NSLocalizedString(
            "SETTINGS_NOTIFICATION_CONTENT_DESCRIPTION",
            comment: "table section footer"
        )
        notificationContentSection.add(.disclosureItem(
            withText: NSLocalizedString("NOTIFICATIONS_SHOW", comment: ""),
            detailText: preferences.name(forNotificationPreviewType: preferences.notificationPreviewType()),
            actionBlock: { [weak self] in
                let vc = NotificationSettingsContentViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        contents.addSection(notificationContentSection)

        let badgeCountSection = OWSTableSection()
        badgeCountSection.headerTitle = NSLocalizedString(
            "SETTINGS_NOTIFICATION_BADGE_COUNT_TITLE",
            comment: "table section header"
        )
        badgeCountSection.add(.switch(
            withText: NSLocalizedString(
                "SETTINGS_NOTIFICATION_BADGE_COUNT_INCLUDES_MUTED_CONVERSATIONS",
                comment: "A setting controlling whether muted conversations are shown in the badge count"
            ),
            isOn: {
                Self.databaseStorage.read { SSKPreferences.includeMutedThreadsInBadgeCount(transaction: $0) }
            },
            target: self,
            selector: #selector(didToggleIncludesMutedConversationsInBadgeCountSwitch)
        ))
        contents.addSection(badgeCountSection)

        let notifyWhenSection = OWSTableSection()
        notifyWhenSection.headerTitle = NSLocalizedString(
            "SETTINGS_NOTIFICATION_NOTIFY_WHEN_TITLE",
            comment: "table section header"
        )
        notifyWhenSection.add(.switch(
            withText: NSLocalizedString(
                "SETTINGS_NOTIFICATION_EVENTS_CONTACT_JOINED_SIGNAL",
                comment: "When the local device discovers a contact has recently installed signal, the app can generates a message encouraging the local user to say hello. Turning this switch off disables that feature."
            ),
            isOn: {
                Self.databaseStorage.read { Self.preferences.shouldNotifyOfNewAccounts(transaction: $0) }
            },
            target: self,
            selector: #selector(didToggleshouldNotifyOfNewAccountsSwitch)
        ))
        contents.addSection(notifyWhenSection)

        let reregisterPushSection = OWSTableSection()
        reregisterPushSection.add(.actionItem(
            withText: NSLocalizedString("REREGISTER_FOR_PUSH", comment: ""),
            actionBlock: { [weak self] in
                self?.syncPushTokens()
            }
        ))
        contents.addSection(reregisterPushSection)

        self.contents = contents
    }

    @objc
    func didToggleSoundNotificationsSwitch(_ sender: UISwitch) {
        preferences.setSoundInForeground(sender.isOn)
    }

    @objc
    func didToggleIncludesMutedConversationsInBadgeCountSwitch(_ sender: UISwitch) {
        let currentValue = databaseStorage.read { SSKPreferences.includeMutedThreadsInBadgeCount(transaction: $0) }
        guard currentValue != sender.isOn else { return }
        databaseStorage.write { SSKPreferences.setIncludeMutedThreadsInBadgeCount(sender.isOn, transaction: $0) }
        messageManager.updateApplicationBadgeCount()
    }

    @objc
    func didToggleshouldNotifyOfNewAccountsSwitch(_ sender: UISwitch) {
        let currentValue = databaseStorage.read { Self.preferences.shouldNotifyOfNewAccounts(transaction: $0) }
        guard currentValue != sender.isOn else { return }
        databaseStorage.write { Self.preferences.shouldNotifyOfNewAccounts(sender.isOn, transaction: $0) }
    }

    private func syncPushTokens() {
        let job = SyncPushTokensJob(mode: .forceRotation)
        job.run().done {
            OWSActionSheets.showActionSheet(title: NSLocalizedString(
                "PUSH_REGISTER_SUCCESS",
                comment: "Title of alert shown when push tokens sync job succeeds."
            ))
        }.catch { _ in
            OWSActionSheets.showActionSheet(title: NSLocalizedString(
                "REGISTRATION_BODY",
                comment: "Title of alert shown when push tokens sync job fails."
            ))
        }
    }
}
