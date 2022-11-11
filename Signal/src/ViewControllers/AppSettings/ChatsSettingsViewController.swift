//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import IntentsUI
import SignalMessaging

@objc
class ChatsSettingsViewController: OWSTableViewController2 {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_CHATS", comment: "Title for the 'chats' link in settings.")

        updateTableContents()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: .OWSSyncManagerConfigurationSyncDidComplete,
            object: nil
        )
    }

    @objc
    func updateTableContents() {
        let contents = OWSTableContents()

        let linkPreviewSection = OWSTableSection()
        linkPreviewSection.footerTitle = NSLocalizedString(
            "SETTINGS_LINK_PREVIEWS_FOOTER",
            comment: "Footer for setting for enabling & disabling link previews."
        )
        linkPreviewSection.add(.switch(
            withText: NSLocalizedString(
                "SETTINGS_LINK_PREVIEWS",
                comment: "Setting for enabling & disabling link previews."
            ),
            isOn: {
                Self.databaseStorage.read { SSKPreferences.areLinkPreviewsEnabled(transaction: $0) }
            },
            target: self,
            selector: #selector(didToggleLinkPreviewsEnabled)
        ))
        contents.addSection(linkPreviewSection)

        let sharingSuggestionsSection = OWSTableSection()
        if #available(iOS 15, *) {
            sharingSuggestionsSection.footerTitle = NSLocalizedString(
                "SETTINGS_SHARING_SUGGESTIONS_NOTIFICATIONS_FOOTER",
                comment: "Footer for setting for enabling & disabling contact and notification sharing with iOS."
            )
        } else {
            sharingSuggestionsSection.footerTitle = NSLocalizedString(
                "SETTINGS_SHARING_SUGGESTIONS_FOOTER",
                comment: "Footer for setting for enabling & disabling contact sharing with iOS."
            )
        }

        sharingSuggestionsSection.add(.switch(
            withText: NSLocalizedString(
                "SETTINGS_SHARING_SUGGESTIONS",
                comment: "Setting for enabling & disabling iOS contact sharing."
            ),
            isOn: {
                Self.databaseStorage.read { SSKPreferences.areIntentDonationsEnabled(transaction: $0) }
            },
            target: self,
            selector: #selector(didToggleSharingSuggestionsEnabled)
        ))
        contents.addSection(sharingSuggestionsSection)

        let contactSection = OWSTableSection()
        contactSection.footerTitle = NSLocalizedString(
            "SETTINGS_APPEARANCE_AVATAR_FOOTER",
            comment: "Footer for avatar section in appearance settings")
        contactSection.add(.switch(
            withText: NSLocalizedString(
                "SETTINGS_APPEARANCE_AVATAR_PREFERENCE_LABEL",
                comment: "Title for switch to toggle preference between contact and profile avatars"),
            isOn: {
                SDSDatabaseStorage.shared.read { SSKPreferences.preferContactAvatars(transaction: $0) }
            },
            target: self,
            selector: #selector(didToggleAvatarPreference)
        ))
        contents.addSection(contactSection)

        if RemoteConfig.keepMutedChatsArchivedOption {
            let keepMutedChatsArchived = OWSTableSection()
            keepMutedChatsArchived.add(.switch(
                withText: NSLocalizedString("SETTINGS_KEEP_MUTED_ARCHIVED_LABEL", comment: "When a chat is archived and receives a new message, it is unarchived. Turning this switch on disables this feature if the chat in question is also muted. This string is a brief label for a switch paired with a longer description underneath, in the Chats settings."),
                isOn: {
                    Self.databaseStorage.read { SSKPreferences.shouldKeepMutedChatsArchived(transaction: $0) }
                },
                target: self,
                selector: #selector(didToggleShouldKeepMutedChatsArchivedSwitch)
            ))
            keepMutedChatsArchived.footerTitle = NSLocalizedString(
                "SETTINGS_KEEP_MUTED_ARCHIVED_DESCRIPTION",
                comment: "When a chat is archived and receives a new message, it is unarchived. Turning this switch on disables this feature if the chat in question is also muted. This string is a thorough description paired with a labeled switch above, in the Chats settings."
            )
            contents.addSection(keepMutedChatsArchived)
        }

        let clearHistorySection = OWSTableSection()
        clearHistorySection.add(.actionItem(
            withText: NSLocalizedString("SETTINGS_CLEAR_HISTORY", comment: ""),
            textColor: .ows_accentRed,
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "clear_chat_history"),
            actionBlock: { [weak self] in
                self?.didTapClearHistory()
            }
        ))
        contents.addSection(clearHistorySection)

        self.contents = contents
    }

    @objc
    func didToggleLinkPreviewsEnabled(_ sender: UISwitch) {
        Logger.info("toggled to: \(sender.isOn)")
        databaseStorage.write { transaction in
            SSKPreferences.setAreLinkPreviewsEnabled(sender.isOn, sendSyncMessage: true, transaction: transaction)
        }
    }

    @objc
    func didToggleSharingSuggestionsEnabled(_ sender: UISwitch) {
        Logger.info("toggled to: \(sender.isOn)")

        if sender.isOn {
            databaseStorage.write { transaction in
                SSKPreferences.setAreIntentDonationsEnabled(true, transaction: transaction)
            }
        } else {
            INInteraction.deleteAll { error in
                if let error = error {
                    owsFailDebug("Failed to disable sharing suggestions \(error)")
                    sender.setOn(true, animated: true)
                    OWSActionSheets.showActionSheet(title: NSLocalizedString(
                        "SHARING_SUGGESTIONS_DISABLE_ERROR",
                        comment: "Title of alert indicating sharing suggestions failed to deactivate"
                    ))
                } else {
                    Self.databaseStorage.write { transaction in
                        SSKPreferences.setAreIntentDonationsEnabled(false, transaction: transaction)
                    }
                }
            }
        }
    }

    @objc
    func didToggleAvatarPreference(_ sender: UISwitch) {
        Logger.info("toggled to: \(sender.isOn)")
        let currentValue = databaseStorage.read { SSKPreferences.preferContactAvatars(transaction: $0) }
        guard currentValue != sender.isOn else { return }

        databaseStorage.write { SSKPreferences.setPreferContactAvatars(sender.isOn, transaction: $0) }
    }

    @objc
    func didToggleShouldKeepMutedChatsArchivedSwitch(_ sender: UISwitch) {
        Logger.info("toggled to \(sender.isOn)")
        let currentValue = databaseStorage.read { SSKPreferences.shouldKeepMutedChatsArchived(transaction: $0) }
        guard currentValue != sender.isOn else { return }

        databaseStorage.write { SSKPreferences.setShouldKeepMutedChatsArchived(sender.isOn, transaction: $0) }

        Self.storageServiceManager.recordPendingLocalAccountUpdates()
    }

    private func didTapClearHistory() {
        OWSActionSheets.showConfirmationAlert(
            title: NSLocalizedString(
                "SETTINGS_DELETE_HISTORYLOG_CONFIRMATION",
                comment: "Alert message before user confirms clearing history"
            ),
            proceedTitle: NSLocalizedString(
                "SETTINGS_DELETE_HISTORYLOG_CONFIRMATION_BUTTON",
                comment: "Confirmation text for button which deletes all message, calling, attachments, etc."
            ),
            proceedStyle: .destructive
        ) { _ in
            ThreadUtil.deleteAllContentWithSneakyTransaction()
        }
    }
}
