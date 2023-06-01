//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

class NotificationSettingsViewController: OWSTableViewController2 {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("SETTINGS_NOTIFICATIONS", comment: "The title for the notification settings.")

        updateTableContents()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let soundsSection = OWSTableSection()
        soundsSection.headerTitle = OWSLocalizedString(
            "SETTINGS_SECTION_SOUNDS",
            comment: "Header Label for the sounds section of settings views."
        )
        soundsSection.add(.disclosureItem(
            withText: OWSLocalizedString(
                "SETTINGS_ITEM_NOTIFICATION_SOUND",
                comment: "Label for settings view that allows user to change the notification sound."
            ),
            detailText: Sounds.globalNotificationSound.displayName,
            actionBlock: { [weak self] in
                let vc = NotificationSettingsSoundViewController { self?.updateTableContents() }
                self?.present(OWSNavigationController(rootViewController: vc), animated: true)
            }
        ))
        soundsSection.add(.switch(
            withText: OWSLocalizedString(
                "NOTIFICATIONS_SECTION_INAPP",
                comment: "Table cell switch label. When disabled, Signal will not play notification sounds while the app is in the foreground."
            ),
            isOn: { Self.preferences.soundInForeground },
            target: self,
            selector: #selector(didToggleSoundNotificationsSwitch)
        ))
        contents.addSection(soundsSection)

        let notificationContentSection = OWSTableSection()
        notificationContentSection.headerTitle = OWSLocalizedString(
            "SETTINGS_NOTIFICATION_CONTENT_TITLE",
            comment: "table section header"
        )
        notificationContentSection.footerTitle = OWSLocalizedString(
            "SETTINGS_NOTIFICATION_CONTENT_DESCRIPTION",
            comment: "table section footer"
        )
        notificationContentSection.add(.disclosureItem(
            withText: OWSLocalizedString("NOTIFICATIONS_SHOW", comment: ""),
            detailText: preferences.notificationPreviewType.displayName,
            actionBlock: { [weak self] in
                let vc = NotificationSettingsContentViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        contents.addSection(notificationContentSection)

        let badgeCountSection = OWSTableSection()
        badgeCountSection.headerTitle = OWSLocalizedString(
            "SETTINGS_NOTIFICATION_BADGE_COUNT_TITLE",
            comment: "table section header"
        )
        badgeCountSection.add(.switch(
            withText: OWSLocalizedString(
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
        notifyWhenSection.headerTitle = OWSLocalizedString(
            "SETTINGS_NOTIFICATION_NOTIFY_WHEN_TITLE",
            comment: "table section header"
        )
        notifyWhenSection.add(.switch(
            withText: OWSLocalizedString(
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
            withText: OWSLocalizedString("REREGISTER_FOR_PUSH", comment: ""),
            actionBlock: { [weak self] in
                self?.syncPushTokens()
            }
        ))
        contents.addSection(reregisterPushSection)

        self.contents = contents
    }

    @objc
    private func didToggleSoundNotificationsSwitch(_ sender: UISwitch) {
        preferences.setSoundInForeground(sender.isOn)
    }

    @objc
    private func didToggleIncludesMutedConversationsInBadgeCountSwitch(_ sender: UISwitch) {
        databaseStorage.write { tx in SSKPreferences.setIncludeMutedThreadsInBadgeCount(sender.isOn, transaction: tx) }
        AppEnvironment.shared.badgeManager.invalidateBadgeValue()
    }

    @objc
    private func didToggleshouldNotifyOfNewAccountsSwitch(_ sender: UISwitch) {
        let currentValue = databaseStorage.read { Self.preferences.shouldNotifyOfNewAccounts(transaction: $0) }
        guard currentValue != sender.isOn else { return }
        databaseStorage.write { Self.preferences.setShouldNotifyOfNewAccounts(sender.isOn, transaction: $0) }
    }

    private func syncPushTokens() {
        let job = SyncPushTokensJob(mode: .forceRotation)
        job.run().done {
            OWSActionSheets.showActionSheet(title: OWSLocalizedString(
                "PUSH_REGISTER_SUCCESS",
                comment: "Title of alert shown when push tokens sync job succeeds."
            ))
        }.catch { _ in
            OWSActionSheets.showActionSheet(title: OWSLocalizedString(
                "REGISTRATION_BODY",
                comment: "Title of alert shown when push tokens sync job fails."
            ))
        }
    }
}
