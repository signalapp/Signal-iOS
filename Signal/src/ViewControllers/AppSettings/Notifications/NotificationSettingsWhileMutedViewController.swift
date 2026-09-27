//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class NotificationSettingsWhileMutedViewController: OWSTableViewController2 {
    static let titleString = OWSLocalizedString(
        "SETTINGS_WHILE_MUTED",
        comment: "Title for the settings page controlling which notifications are still shown for muted chats. Also used as the label for the rows that link to this page.",
    )

    private let thread: TSThread?

    /// - Parameter thread: The thread to edit, or nil for the global preference
    init(thread: TSThread? = nil) {
        self.thread = thread
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = Self.titleString
        updateTableContents()
    }

    private func updateTableContents() {
        let notificationPreferencesManager = DependenciesBridge.shared.notificationPreferencesManager
        let db = DependenciesBridge.shared.db

        let contents = OWSTableContents()

        contents.add(buildSection(
            icon: .phone,
            name: NotificationPreferencesManager.whileMutedCallsTitle,
            footer: callsFooter,
            isOn: { [thread] in
                db.read { tx in
                    if let thread {
                        notificationPreferencesManager.notifyForCallsWhenMuted(thread: thread, tx: tx)
                    } else {
                        notificationPreferencesManager.defaultNotifyForCallsWhenMuted(tx: tx)
                    }
                }
            },
            setOn: { [thread] value in
                db.write { tx in
                    if let thread {
                        notificationPreferencesManager.setNotifyForCallsWhenMuted(value, thread: thread, tx: tx)
                    } else {
                        notificationPreferencesManager.setDefaultNotifyForCallsWhenMuted(value, tx: tx)
                    }
                }
            },
        ))

        if thread?.isGroupThread ?? true {
            contents.add(buildSection(
                icon: .at,
                name: NotificationPreferencesManager.whileMutedMentionsTitle,
                footer: mentionsFooter,
                isOn: { [thread] in
                    db.read { tx in
                        if let thread {
                            notificationPreferencesManager.notifyForMentionsWhenMuted(thread: thread, tx: tx)
                        } else {
                            notificationPreferencesManager.defaultNotifyForMentionsWhenMuted(tx: tx)
                        }
                    }
                },
                setOn: { [thread] value in
                    db.write { tx in
                        if let thread {
                            notificationPreferencesManager.setNotifyForMentionsWhenMuted(value, thread: thread, tx: tx)
                        } else {
                            notificationPreferencesManager.setDefaultNotifyForMentionsWhenMuted(value, tx: tx)
                        }
                    }
                },
            ))

            contents.add(buildSection(
                icon: .reply,
                name: NotificationPreferencesManager.whileMutedRepliesTitle,
                footer: repliesFooter,
                isOn: { [thread] in
                    db.read { tx in
                        if let thread {
                            notificationPreferencesManager.notifyForRepliesWhenMuted(thread: thread, tx: tx)
                        } else {
                            notificationPreferencesManager.defaultNotifyForRepliesWhenMuted(tx: tx)
                        }
                    }
                },
                setOn: { [thread] value in
                    db.write { tx in
                        if let thread {
                            notificationPreferencesManager.setNotifyForRepliesWhenMuted(value, thread: thread, tx: tx)
                        } else {
                            notificationPreferencesManager.setDefaultNotifyForRepliesWhenMuted(value, tx: tx)
                        }
                    }
                },
            ))
        }

        self.contents = contents
    }

    private var callsFooter: String {
        if thread != nil {
            OWSLocalizedString(
                "SETTINGS_WHILE_MUTED_CALLS_CHAT_FOOTER",
                comment: "Explanation for the switch controlling whether calls ring or notify while this chat is muted.",
            )
        } else {
            OWSLocalizedString(
                "SETTINGS_WHILE_MUTED_CALLS_FOOTER",
                comment: "Explanation for the switch controlling whether calls ring or notify in muted chats.",
            )
        }
    }

    private var mentionsFooter: String {
        if thread != nil {
            OWSLocalizedString(
                "SETTINGS_WHILE_MUTED_MENTIONS_CHAT_FOOTER",
                comment: "Explanation for the switch controlling whether mentions of you notify while this chat is muted.",
            )
        } else {
            OWSLocalizedString(
                "SETTINGS_WHILE_MUTED_MENTIONS_FOOTER",
                comment: "Explanation for the switch controlling whether mentions of you notify in muted chats.",
            )
        }
    }

    private var repliesFooter: String {
        if thread != nil {
            OWSLocalizedString(
                "SETTINGS_WHILE_MUTED_REPLIES_CHAT_FOOTER",
                comment: "Explanation for the switch controlling whether replies to your messages notify while this chat is muted.",
            )
        } else {
            OWSLocalizedString(
                "SETTINGS_WHILE_MUTED_REPLIES_FOOTER",
                comment: "Explanation for the switch controlling whether replies to your messages notify in muted chats.",
            )
        }
    }

    private func buildSection(
        icon: ImageResource,
        name: String,
        footer: String,
        isOn: @escaping () -> Bool,
        setOn: @escaping (Bool) -> Void,
    ) -> OWSTableSection {
        let section = OWSTableSection()
        section.footerTitle = footer
        section.add(.switch(
            withText: name,
            image: UIImage(resource: icon),
            isOn: isOn,
            actionBlock: { toggle in setOn(toggle.isOn) },
        ))
        return section
    }
}
