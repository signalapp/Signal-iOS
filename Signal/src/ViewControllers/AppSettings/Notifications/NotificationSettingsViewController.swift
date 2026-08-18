//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
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

        contents.add(buildSoundsSection())
        contents.add(buildNotificationsSection())
        contents.add(buildContactJoinedSignalSection())
        contents.add(buildAppBadgeSection())
        contents.add(buildReregisterPushSection())

        self.contents = contents
    }

    private func buildSoundsSection() -> OWSTableSection {
        let soundsSection = OWSTableSection()
        soundsSection.headerTitle = OWSLocalizedString(
            "SETTINGS_SECTION_SOUNDS",
            comment: "Header Label for the sounds section of settings views.",
        )
        soundsSection.add(.item(
            name: OWSLocalizedString(
                "SETTINGS_ITEM_NOTIFICATION_SOUND",
                comment: "Label for settings view that allows user to change the notification sound.",
            ),
            accessoryText: Sounds.globalNotificationSound.displayName,
            actionBlock: { [weak self] in
                let vc = NotificationSettingsSoundViewController { self?.updateTableContents() }
                self?.present(OWSNavigationController(rootViewController: vc), animated: true)
            },
        ))
        soundsSection.add(.switch(
            withText: OWSLocalizedString(
                "NOTIFICATIONS_SECTION_INAPP",
                comment: "Table cell switch label. When disabled, Signal will not play notification sounds while the app is in the foreground.",
            ),
            isOn: { SSKEnvironment.shared.preferencesRef.soundInForeground },
            actionBlock: { [weak self] uiSwitch in
                self?.didToggleSoundNotifications(uiSwitch)
            },
        ))
        let messageSentSoundEnabled = SSKEnvironment.shared.preferencesRef.soundInForeground
        soundsSection.add(.switch(
            withText: OWSLocalizedString(
                "SETTINGS_MESSAGE_SENT_SOUND",
                comment: "Setting for enabling & disabling the sound effect played when a message is sent.",
            ),
            textColor: messageSentSoundEnabled ? nil : UIColor.Signal.secondaryLabel,
            isOn: { messageSentSoundEnabled && SSKEnvironment.shared.preferencesRef.isMessageSentSoundEnabled },
            isEnabled: { messageSentSoundEnabled },
            actionBlock: { [weak self] uiSwitch in
                self?.didToggleMessageSentSound(uiSwitch)
            },
        ))
        return soundsSection
    }

    private func buildNotificationsSection() -> OWSTableSection {
        let notificationsSection = OWSTableSection()
        notificationsSection.headerTitle = OWSLocalizedString(
            "SETTINGS_NOTIFICATIONS",
            comment: "The title for the notification settings.",
        )
        notificationsSection.footerTitle = OWSLocalizedString(
            "SETTINGS_NOTIFICATION_CONTENT_DESCRIPTION",
            comment: "table section footer",
        )
        notificationsSection.add(.disclosureItem(
            withText: OWSLocalizedString("NOTIFICATIONS_SHOW", comment: ""),
            accessoryText: SSKEnvironment.shared.databaseStorageRef.read { tx in
                return SSKEnvironment.shared.preferencesRef.notificationPreviewType(tx: tx).displayName
            },
            actionBlock: { [weak self] in
                let vc = NotificationSettingsContentViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            },
        ))
        return notificationsSection
    }

    private func buildAppBadgeSection() -> OWSTableSection {
        let appBadgeSection = OWSTableSection()
        appBadgeSection.headerTitle = OWSLocalizedString(
            "SETTINGS_NOTIFICATIONS_APP_BADGE_SECTION",
            comment: "Header for the section of notification settings controlling the app icon's badge.",
        )
        appBadgeSection.add(.switch(
            withText: OWSLocalizedString(
                "SETTINGS_NOTIFICATION_BADGE_COUNT_INCLUDES_MUTED_CONVERSATIONS",
                comment: "A setting controlling whether muted conversations are shown in the badge count",
            ),
            isOn: {
                SSKEnvironment.shared.databaseStorageRef.read { SSKPreferences.includeMutedThreadsInBadgeCount(transaction: $0) }
            },
            actionBlock: { [weak self] uiSwitch in
                self?.didToggleIncludesMutedConversationsInBadgeCount(uiSwitch)
            },
        ))
        return appBadgeSection
    }

    private func buildContactJoinedSignalSection() -> OWSTableSection {
        let contactJoinedSignalSection = OWSTableSection()
        contactJoinedSignalSection.footerTitle = OWSLocalizedString(
            "SETTINGS_NOTIFICATIONS_CONTACT_JOINED_SIGNAL_FOOTER",
            comment: "Explanation for the switch controlling whether a notification is shown when a phone contact joins Signal.",
        )
        contactJoinedSignalSection.add(.switch(
            withText: OWSLocalizedString(
                "SETTINGS_NOTIFICATION_EVENTS_CONTACT_JOINED_SIGNAL",
                comment: "When the local device discovers a contact has recently installed signal, the app can generates a message encouraging the local user to say hello. Turning this switch off disables that feature.",
            ),
            isOn: {
                SSKEnvironment.shared.databaseStorageRef.read { SSKEnvironment.shared.preferencesRef.shouldNotifyOfNewAccounts(transaction: $0) }
            },
            actionBlock: { [weak self] uiSwitch in
                self?.didToggleshouldNotifyOfNewAccounts(uiSwitch)
            },
        ))
        return contactJoinedSignalSection
    }

    private func buildReregisterPushSection() -> OWSTableSection {
        let reregisterPushSection = OWSTableSection()
        reregisterPushSection.add(.item(
            name: OWSLocalizedString("REREGISTER_FOR_PUSH", comment: ""),
            actionBlock: { [weak self] in
                self?.syncPushTokens()
            },
        ))
        return reregisterPushSection
    }

    private func didToggleSoundNotifications(_ sender: UISwitch) {
        SSKEnvironment.shared.preferencesRef.setSoundInForeground(sender.isOn)
        // Reload table, since the value of this setting affects others (i.e., message sent sound).
        updateTableContents()
    }

    private func didToggleMessageSentSound(_ sender: UISwitch) {
        SSKEnvironment.shared.preferencesRef.setIsMessageSentSoundEnabled(sender.isOn)
    }

    private func didToggleIncludesMutedConversationsInBadgeCount(_ sender: UISwitch) {
        SSKEnvironment.shared.databaseStorageRef.write { tx in SSKPreferences.setIncludeMutedThreadsInBadgeCount(sender.isOn, transaction: tx) }
        AppEnvironment.shared.badgeManager.invalidateBadgeValue()
    }

    private func didToggleshouldNotifyOfNewAccounts(_ sender: UISwitch) {
        let currentValue = SSKEnvironment.shared.databaseStorageRef.read { SSKEnvironment.shared.preferencesRef.shouldNotifyOfNewAccounts(transaction: $0) }
        guard currentValue != sender.isOn else { return }
        SSKEnvironment.shared.databaseStorageRef.write { SSKEnvironment.shared.preferencesRef.setShouldNotifyOfNewAccounts(sender.isOn, transaction: $0) }
    }

    private func syncPushTokens() {
        let job = SyncPushTokensJob(mode: .forceRotation)
        Task {
            do {
                try await job.run()
                OWSActionSheets.showActionSheet(title: OWSLocalizedString(
                    "PUSH_REGISTER_SUCCESS",
                    comment: "Title of alert shown when push tokens sync job succeeds.",
                ))
            } catch {
                OWSActionSheets.showActionSheet(title: OWSLocalizedString(
                    "REGISTRATION_BODY",
                    comment: "Title of alert shown when push tokens sync job fails.",
                ))
            }
        }
    }
}
