//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

final class SoundAndNotificationsSettingsViewController: OWSTableViewController2 {
    let threadViewModel: ThreadViewModel
    init(threadViewModel: ThreadViewModel) {
        self.threadViewModel = threadViewModel
    }

    private lazy var muteContextButton = ContextMenuButton(empty: ())

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SOUND_AND_NOTIFICATION_SETTINGS",
            comment: "table cell label in conversation settings"
        )

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let section = OWSTableSection()

        section.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self = self else {
                owsFailDebug("Missing self")
                return OWSTableItem.newCell()
            }

            let sound = Sounds.notificationSoundWithSneakyTransaction(forThreadUniqueId: self.threadViewModel.threadRecord.uniqueId)
            let cell = OWSTableItem.buildCell(
                icon: .chatSettingsMessageSound,
                itemName: OWSLocalizedString(
                    "SETTINGS_ITEM_NOTIFICATION_SOUND",
                    comment: "Label for settings view that allows user to change the notification sound."
                ),
                accessoryText: sound.displayName,
                accessoryType: .disclosureIndicator
            )
            cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "notifications")
            return cell
        },
        actionBlock: { [weak self] in
            self?.showSoundSettingsView()
        }))

        section.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self = self else {
                owsFailDebug("Missing self")
                return OWSTableItem.newCell()
            }

            var muteStatus = OWSLocalizedString(
                "CONVERSATION_SETTINGS_MUTE_NOT_MUTED",
                comment: "Indicates that the current thread is not muted."
            )

            let now = Date()

            if self.threadViewModel.mutedUntilTimestamp == ThreadAssociatedData.alwaysMutedTimestamp {
                muteStatus = OWSLocalizedString(
                    "CONVERSATION_SETTINGS_MUTED_ALWAYS",
                    comment: "Indicates that this thread is muted forever."
                )
            } else if let mutedUntilDate = self.threadViewModel.mutedUntilDate, mutedUntilDate > now {
                let calendar = Calendar.current
                let muteUntilComponents = calendar.dateComponents([.year, .month, .day], from: mutedUntilDate)
                let nowComponents = calendar.dateComponents([.year, .month, .day], from: now)
                let dateFormatter = DateFormatter()
                if nowComponents.year != muteUntilComponents.year
                    || nowComponents.month != muteUntilComponents.month
                    || nowComponents.day != muteUntilComponents.day {

                    dateFormatter.dateStyle = .short
                    dateFormatter.timeStyle = .short
                } else {
                    dateFormatter.dateStyle = .none
                    dateFormatter.timeStyle = .short
                }

                let formatString = OWSLocalizedString(
                    "CONVERSATION_SETTINGS_MUTED_UNTIL_FORMAT",
                    comment: "Indicates that this thread is muted until a given date or time. Embeds {{The date or time which the thread is muted until}}."
                )
                muteStatus = String(
                    format: formatString,
                    dateFormatter.string(from: mutedUntilDate)
                )
            }

            let cell = OWSTableItem.buildCell(
                icon: .chatSettingsMute,
                itemName: OWSLocalizedString(
                    "CONVERSATION_SETTINGS_MUTE_LABEL",
                    comment: "label for 'mute thread' cell in conversation settings"
                ),
                accessoryText: muteStatus,
                accessoryType: .disclosureIndicator
            )

            // I wasn't able to get the button to present context menu by
            // invoking `sendActions(for:)`. Therefore the button is sized
            // to take the entire cell.
            muteContextButton.backgroundColor = .clear
            muteContextButton.menu = ConversationSettingsViewController.muteUnmuteMenu(
                for: threadViewModel,
                actionExecuted: { [weak self] in
                    self?.updateTableContents()
                }
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

        if threadViewModel.threadRecord.allowsMentionSend {
            section.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }

                let cell = OWSTableItem.buildCell(
                    icon: .chatSettingsMentions,
                    itemName: OWSLocalizedString(
                        "CONVERSATION_SETTINGS_MENTIONS_LABEL",
                        comment: "label for 'mentions' cell in conversation settings"
                    ),
                    accessoryText: self.nameForMentionMode(self.threadViewModel.threadRecord.mentionNotificationMode),
                    accessoryType: .disclosureIndicator
                )

                cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "mentions")

                return cell
            },
            actionBlock: { [weak self] in
                self?.showMentionNotificationModeActionSheet()
            }))
        }

        contents.add(section)

        self.contents = contents
    }

    func showSoundSettingsView() {
        let vc = NotificationSettingsSoundViewController(thread: threadViewModel.threadRecord) { [weak self] in
            self?.updateTableContents()
        }
        presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
    }

    func showMentionNotificationModeActionSheet() {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString("CONVERSATION_SETTINGS_MENTION_NOTIFICATION_MODE_ACTION_SHEET_TITLE",
                                     comment: "Title of the 'mention notification mode' action sheet.")
        )

        for mode: TSThreadMentionNotificationMode in [.always, .never] {
            let action =
                ActionSheetAction(
                    title: nameForMentionMode(mode),
                ) { [weak self] _ in
                    self?.setMentionNotificationMode(mode)
                }
            actionSheet.addAction(action)
        }

        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    private func setMentionNotificationMode(_ value: TSThreadMentionNotificationMode) {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            self.threadViewModel.threadRecord.updateWithMentionNotificationMode(value, wasLocallyInitiated: true, transaction: transaction)
        }

        updateTableContents()
    }

    func nameForMentionMode(_ mode: TSThreadMentionNotificationMode) -> String {
        switch mode {
        case .default, .always:
            return OWSLocalizedString(
                "CONVERSATION_SETTINGS_MENTION_MODE_AlWAYS",
                comment: "label for 'always' option for mention notifications in conversation settings"
            )
        case .never:
            return OWSLocalizedString(
                "CONVERSATION_SETTINGS_MENTION_MODE_NEVER",
                comment: "label for 'never' option for mention notifications in conversation settings"
            )
        }
    }
}
