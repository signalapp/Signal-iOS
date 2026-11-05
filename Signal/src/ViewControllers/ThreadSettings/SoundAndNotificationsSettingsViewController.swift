//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class SoundAndNotificationsSettingsViewController: OWSTableViewController2 {
    private let db = DependenciesBridge.shared.db
    private let notificationPreferencesManager = DependenciesBridge.shared.notificationPreferencesManager
    private let unreadReminderManager = DependenciesBridge.shared.unreadReminderManager

    let threadViewModel: ThreadViewModel
    init(threadViewModel: ThreadViewModel) {
        self.threadViewModel = threadViewModel
    }

    private lazy var muteContextButton = ContextMenuButton(empty: ())

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SOUND_AND_NOTIFICATION_SETTINGS",
            comment: "table cell label in conversation settings",
        )

        updateTableContents()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let section = OWSTableSection()

        section.add(OWSTableItem(
            customCellBlock: { [weak self] in
                guard let self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }

                let sound = Sounds.notificationSoundWithSneakyTransaction(forThreadUniqueId: self.threadViewModel.threadRecord.uniqueId)
                let cell = OWSTableItem.buildCell(
                    icon: .chatSettingsMessageSound,
                    itemName: OWSLocalizedString(
                        "SETTINGS_ITEM_NOTIFICATION_SOUND",
                        comment: "Label for settings view that allows user to change the notification sound.",
                    ),
                    accessoryText: sound.displayName,
                    accessoryType: .disclosureIndicator,
                )
                cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "notifications")
                return cell
            },
            actionBlock: { [weak self] in
                self?.showSoundSettingsView()
            },
        ))

        section.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self else {
                owsFailDebug("Missing self")
                return OWSTableItem.newCell()
            }

            var muteStatus = OWSLocalizedString(
                "CONVERSATION_SETTINGS_MUTE_NOT_MUTED",
                comment: "Indicates that the current thread is not muted.",
            )

            let now = Date()

            if self.threadViewModel.mutedUntilTimestamp == TSThread.alwaysMutedTimestamp {
                muteStatus = OWSLocalizedString(
                    "CONVERSATION_SETTINGS_MUTED_ALWAYS",
                    comment: "Indicates that this thread is muted forever.",
                )
            } else if let mutedUntilDate = self.threadViewModel.mutedUntilDate, mutedUntilDate > now {
                let calendar = Calendar.current
                let muteUntilComponents = calendar.dateComponents([.year, .month, .day], from: mutedUntilDate)
                let nowComponents = calendar.dateComponents([.year, .month, .day], from: now)
                let dateFormatter = DateFormatter()
                if
                    nowComponents.year != muteUntilComponents.year
                    || nowComponents.month != muteUntilComponents.month
                    || nowComponents.day != muteUntilComponents.day
                {

                    dateFormatter.dateStyle = .short
                    dateFormatter.timeStyle = .short
                } else {
                    dateFormatter.dateStyle = .none
                    dateFormatter.timeStyle = .short
                }

                let formatString = OWSLocalizedString(
                    "CONVERSATION_SETTINGS_MUTED_UNTIL_FORMAT",
                    comment: "Indicates that this thread is muted until a given date or time. Embeds {{The date or time which the thread is muted until}}.",
                )
                muteStatus = String.nonPluralLocalizedStringWithFormat(
                    formatString,
                    dateFormatter.string(from: mutedUntilDate),
                )
            }

            let cell = OWSTableItem.buildCell(
                icon: .chatSettingsMute,
                itemName: OWSLocalizedString(
                    "CONVERSATION_SETTINGS_MUTE_LABEL",
                    comment: "label for 'mute thread' cell in conversation settings",
                ),
                accessoryText: muteStatus,
                accessoryType: .disclosureIndicator,
            )

            // I wasn't able to get the button to present context menu by
            // invoking `sendActions(for:)`. Therefore the button is sized
            // to take the entire cell.
            muteContextButton.backgroundColor = .clear
            muteContextButton.menu = ConversationSettingsViewController.muteUnmuteMenu(
                for: threadViewModel,
                from: self,
                actionExecuted: { [weak self] in
                    self?.updateTableContents()
                },
            )
            cell.contentView.addSubview(muteContextButton)
            muteContextButton.autoPinEdgesToSuperviewEdges()

            // Select / deselect row.
            muteContextButton.addAction(UIAction(handler: { [weak self, weak cell] _ in
                guard let self, let cell else { return }
                self.tableView.selectRow(at: self.tableView.indexPath(for: cell)!, animated: true, scrollPosition: .none)
            }), for: .touchDown)
            muteContextButton.addAction(UIAction(handler: { [weak self, weak cell] _ in
                guard let self, let cell else { return }
                self.tableView.deselectRow(at: self.tableView.indexPath(for: cell)!, animated: true)
            }), for: [.touchUpInside, .touchUpOutside, .touchDragExit, .touchCancel])

            cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "mute")

            return cell
        }))

        if BuildFlags.improvedNotifications {
            section.add(OWSTableItem(
                customCellBlock: { [weak self] in
                    guard let self else {
                        return OWSTableItem.newCell()
                    }

                    let cell = OWSTableItem.buildCell(
                        icon: .settingsNotifications,
                        itemName: NotificationSettingsWhileMutedViewController.titleString,
                        accessoryText: self.db.read { tx in
                            self.notificationPreferencesManager.whileMutedEnabledString(
                                thread: self.threadViewModel.threadRecord,
                                tx: tx,
                            )
                        },
                        accessoryType: .disclosureIndicator,
                    )

                    return cell
                },
                actionBlock: { [weak self] in
                    guard let self else { return }
                    let vc = NotificationSettingsWhileMutedViewController(thread: self.threadViewModel.threadRecord)
                    self.navigationController?.pushViewController(vc, animated: true)
                },
            ))
        }

        if !BuildFlags.improvedNotifications, threadViewModel.threadRecord.allowsMentionSend {
            section.add(OWSTableItem(
                customCellBlock: { [weak self] in
                    guard let self else {
                        owsFailDebug("Missing self")
                        return OWSTableItem.newCell()
                    }

                    let cell = OWSTableItem.buildCell(
                        icon: .chatSettingsMentions,
                        itemName: OWSLocalizedString(
                            "CONVERSATION_SETTINGS_MENTIONS_LABEL",
                            comment: "label for 'mentions' cell in conversation settings",
                        ),
                        accessoryText: self.nameForShouldNotifyForMentionsWhenMuted(
                            self.threadViewModel.threadRecord.shouldNotifyForMentionsWhenMutedLegacy,
                        ),
                        accessoryType: .disclosureIndicator,
                    )

                    cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "mentions")

                    return cell
                },
                actionBlock: { [weak self] in
                    self?.showMentionNotificationModeActionSheet()
                },
            ))
        }

        contents.add(section)

        let thread = threadViewModel.threadRecord
        if BuildFlags.improvedNotifications, !thread.isNoteToSelf, !thread.isReleaseNotesThread {
            contents.add(buildUnreadRemindersSection())
        }

        self.contents = contents
    }

    private func buildUnreadRemindersSection() -> OWSTableSection {
        let thread = threadViewModel.threadRecord
        let section = OWSTableSection()
        section.footerTitle = OWSLocalizedString(
            "SETTINGS_NOTIFICATIONS_UNREAD_REMINDERS_CHAT_FOOTER",
            comment: "Explanation for the switch controlling whether reminders about unread messages are shown in this chat while it is muted.",
        )
        section.add(.switch(
            withText: NotificationPreferencesManager.unreadRemindersTitle,
            image: UIImage(resource: .chatBadge).withTintColor(.Signal.label, renderingMode: .alwaysOriginal),
            isOn: { [db, notificationPreferencesManager] in
                db.read { tx in
                    notificationPreferencesManager.showUnreadReminders(thread: thread, tx: tx)
                }
            },
            actionBlock: { [db, unreadReminderManager] uiSwitch in
                db.write { tx in
                    unreadReminderManager.setShowUnreadReminders(
                        uiSwitch.isOn,
                        thread: thread,
                        updateStorageService: true,
                        tx: tx,
                    )
                }
            },
        ))
        return section
    }

    func showSoundSettingsView() {
        let vc = NotificationSettingsSoundViewController(thread: threadViewModel.threadRecord) { [weak self] in
            self?.updateTableContents()
        }
        presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
    }

    func showMentionNotificationModeActionSheet() {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "CONVERSATION_SETTINGS_MENTION_NOTIFICATION_MODE_ACTION_SHEET_TITLE",
                comment: "Title of the 'mention notification mode' action sheet.",
            ),
        )

        for shouldNotify in [true, false] {
            let action = ActionSheetAction(title: nameForShouldNotifyForMentionsWhenMuted(shouldNotify)) { [weak self] _ in
                self?.setShouldNotifyForMentionsWhenMuted(shouldNotify)
            }
            actionSheet.addAction(action)
        }

        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    private func setShouldNotifyForMentionsWhenMuted(_ value: Bool) {
        db.write { transaction in
            DependenciesBridge.shared.notificationPreferencesManager.setNotifyForMentionsWhenMutedFromLegacyUI(
                value,
                thread: self.threadViewModel.threadRecord,
                tx: transaction,
            )
        }

        updateTableContents()
    }

    func nameForShouldNotifyForMentionsWhenMuted(_ shouldNotifyForMentionsWhenMuted: Bool) -> String {
        if shouldNotifyForMentionsWhenMuted {
            return OWSLocalizedString(
                "CONVERSATION_SETTINGS_MENTION_MODE_AlWAYS",
                comment: "label for 'always' option for mention notifications in conversation settings",
            )
        } else {
            return OWSLocalizedString(
                "CONVERSATION_SETTINGS_MENTION_MODE_NEVER",
                comment: "label for 'never' option for mention notifications in conversation settings",
            )
        }
    }
}
