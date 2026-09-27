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
        if BuildFlags.improvedNotifications {
            contents.add(buildReactionsSection())
        }
        contents.add(buildContactJoinedSignalSection())
        contents.add(buildAppBadgeSection())
        contents.add(buildReregisterPushSection())
        contents.add(buildResetSection())

        self.contents = contents
    }

    private func buildSoundsSection() -> OWSTableSection {
        let db = DependenciesBridge.shared.db
        let notificationPreferencesManager = DependenciesBridge.shared.notificationPreferencesManager
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
            accessoryText: db.read { tx in
                notificationPreferencesManager.globalNotificationSound(tx: tx).displayName
            },
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
            isOn: {
                db.read { tx in
                    notificationPreferencesManager.playSoundInForeground(tx: tx)
                }
            },
            actionBlock: { [weak self] uiSwitch in
                self?.didToggleSoundNotifications(uiSwitch)
            },
        ))
        let messageSentSoundEnabled = db.read { tx in
            notificationPreferencesManager.playSoundInForeground(tx: tx)
        }
        soundsSection.add(.switch(
            withText: OWSLocalizedString(
                "SETTINGS_MESSAGE_SENT_SOUND",
                comment: "Setting for enabling & disabling the sound effect played when a message is sent.",
            ),
            textColor: messageSentSoundEnabled ? nil : UIColor.Signal.secondaryLabel,
            isOn: {
                messageSentSoundEnabled && db.read { tx in
                    notificationPreferencesManager.isMessageSentSoundEnabled(tx: tx)
                }
            },
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
            accessoryText: DependenciesBridge.shared.db.read { tx in
                return DependenciesBridge.shared.notificationPreferencesManager.previewType(tx: tx).displayName
            },
            actionBlock: { [weak self] in
                let vc = NotificationSettingsContentViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            },
        ))
        if BuildFlags.improvedNotifications {
            notificationsSection.add(.disclosureItem(
                withText: NotificationSettingsWhileMutedViewController.titleString,
                accessoryText: DependenciesBridge.shared.db.read { tx in
                    DependenciesBridge.shared.notificationPreferencesManager.whileMutedEnabledString(tx: tx)
                },
                actionBlock: { [weak self] in
                    let vc = NotificationSettingsWhileMutedViewController()
                    self?.navigationController?.pushViewController(vc, animated: true)
                },
            ))
        }
        return notificationsSection
    }

    private func buildReactionsSection() -> OWSTableSection {
        let db = DependenciesBridge.shared.db
        let notificationPreferencesManager = DependenciesBridge.shared.notificationPreferencesManager
        let reactionsSection = OWSTableSection()
        reactionsSection.footerTitle = OWSLocalizedString(
            "SETTINGS_NOTIFICATIONS_REACTIONS_FOOTER",
            comment: "Explanation for the switch controlling whether reactions to your messages generate notifications.",
        )
        reactionsSection.add(.switch(
            withText: OWSLocalizedString(
                "SETTINGS_NOTIFICATIONS_REACTIONS",
                comment: "Label for a switch controlling whether reactions to your messages generate notifications.",
            ),
            isOn: {
                db.read { tx in
                    notificationPreferencesManager.areReactionNotificationsEnabled(tx: tx)
                }
            },
            actionBlock: { uiSwitch in
                db.write { tx in
                    notificationPreferencesManager.setAreReactionNotificationsEnabled(uiSwitch.isOn, tx: tx)
                }
            },
        ))
        return reactionsSection
    }

    private func buildAppBadgeSection() -> OWSTableSection {
        let db = DependenciesBridge.shared.db
        let appBadgeSection = OWSTableSection()
        appBadgeSection.headerTitle = OWSLocalizedString(
            "SETTINGS_NOTIFICATIONS_APP_BADGE_SECTION",
            comment: "Header for the section of notification settings controlling the app icon's badge.",
        )
        if BuildFlags.improvedNotifications {
            appBadgeSection.add(.disclosureItem(
                withText: OWSLocalizedString(
                    "SETTINGS_NOTIFICATION_BADGE_COUNT",
                    comment: "Label for the setting controlling whether the app icon badge counts unread messages or unread chats.",
                ),
                accessoryText: db.read { tx in
                    DependenciesBridge.shared.notificationPreferencesManager.badgeCountType(tx: tx).title
                },
                actionBlock: { [weak self] in
                    let vc = NotificationSettingsBadgeCountViewController()
                    self?.navigationController?.pushViewController(vc, animated: true)
                },
            ))
        }
        appBadgeSection.add(.switch(
            withText: OWSLocalizedString(
                "SETTINGS_NOTIFICATION_BADGE_COUNT_INCLUDES_MUTED_CONVERSATIONS",
                comment: "A setting controlling whether muted conversations are shown in the badge count",
            ),
            isOn: {
                db.read { tx in
                    DependenciesBridge.shared.notificationPreferencesManager.includeMutedThreadsInBadgeCount(tx: tx)
                }
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
                DependenciesBridge.shared.db.read { tx in
                    DependenciesBridge.shared.notificationPreferencesManager.shouldNotifyOfNewAccounts(tx: tx)
                }
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

    private func buildResetSection() -> OWSTableSection {
        let resetSection = OWSTableSection()
        resetSection.footerTitle = OWSLocalizedString(
            "SETTINGS_NOTIFICATIONS_RESET_FOOTER",
            comment: "Explanation for the button that resets all notification settings.",
        )
        resetSection.add(.item(
            name: OWSLocalizedString(
                "SETTINGS_NOTIFICATIONS_RESET",
                comment: "Label for a button that resets all notification settings to their defaults.",
            ),
            textColor: .Signal.red,
            actionBlock: { [weak self] in
                self?.didTapResetNotificationSettings()
            },
        ))
        return resetSection
    }

    private func didTapResetNotificationSettings() {
        let actionSheet = ActionSheetController(message: OWSLocalizedString(
            "SETTINGS_NOTIFICATIONS_RESET_CONFIRMATION_MESSAGE",
            comment: "Question confirming that notification settings should be reset.",
        ))
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SETTINGS_NOTIFICATIONS_RESET_CONFIRMATION_ACTION",
                comment: "Label for the button that confirms notification settings should be reset.",
            ),
            style: .destructive,
            handler: { [weak self] _ in
                guard let self else { return }
                ModalActivityIndicatorViewController.present(
                    fromViewController: self,
                    canCancel: false,
                    asyncBlock: { [weak self] modal in
                        await self?.resetNotificationSettings()
                        modal.dismiss()
                    },
                )
            },
        ))
        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    @MainActor
    private func resetNotificationSettings() async {
        let notificationPreferencesManager = DependenciesBridge.shared.notificationPreferencesManager
        await DependenciesBridge.shared.db.awaitableWrite { tx in
            notificationPreferencesManager.resetAll(tx: tx)
        }
        AppEnvironment.shared.badgeManager.invalidateBadgeValue()
        // The notification preview preference affects how calls are presented
        AppEnvironment.shared.callService.rebuildCallUIAdapter()
        updateTableContents()
    }

    private func didToggleSoundNotifications(_ sender: UISwitch) {
        DependenciesBridge.shared.db.write { tx in
            DependenciesBridge.shared.notificationPreferencesManager.setPlaySoundInForeground(sender.isOn, tx: tx)
        }
        // Reload table, since the value of this setting affects others (i.e., message sent sound).
        updateTableContents()
    }

    private func didToggleMessageSentSound(_ sender: UISwitch) {
        DependenciesBridge.shared.db.write { tx in
            DependenciesBridge.shared.notificationPreferencesManager.setIsMessageSentSoundEnabled(sender.isOn, tx: tx)
        }
    }

    private func didToggleIncludesMutedConversationsInBadgeCount(_ sender: UISwitch) {
        DependenciesBridge.shared.db.write { tx in
            DependenciesBridge.shared.notificationPreferencesManager.setIncludeMutedThreadsInBadgeCount(sender.isOn, tx: tx)
        }
        AppEnvironment.shared.badgeManager.invalidateBadgeValue()
    }

    private func didToggleshouldNotifyOfNewAccounts(_ sender: UISwitch) {
        let notificationPreferencesManager = DependenciesBridge.shared.notificationPreferencesManager
        let currentValue = DependenciesBridge.shared.db.read { tx in
            notificationPreferencesManager.shouldNotifyOfNewAccounts(tx: tx)
        }
        guard currentValue != sender.isOn else { return }
        DependenciesBridge.shared.db.write { tx in
            notificationPreferencesManager.setShouldNotifyOfNewAccounts(sender.isOn, tx: tx)
        }
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
