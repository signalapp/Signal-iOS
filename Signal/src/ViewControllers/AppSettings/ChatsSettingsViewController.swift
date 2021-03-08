//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import IntentsUI

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
        sharingSuggestionsSection.footerTitle = NSLocalizedString(
            "SETTINGS_SHARING_SUGGESTIONS_FOOTER",
            comment: "Footer for setting for enabling & disabling sharing suggestions."
        )
        sharingSuggestionsSection.add(.switch(
            withText: NSLocalizedString(
                "SETTINGS_SHARING_SUGGESTIONS",
                comment: "Setting for enabling & disabling sharing suggestions."
            ),
            isOn: {
                Self.databaseStorage.read { SSKPreferences.areSharingSuggestionsEnabled(transaction: $0) }
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
            ExperienceUpgradeManager.clearExperienceUpgrade(.linkPreviews, transaction: transaction.unwrapGrdbWrite)
            SSKPreferences.setAreLinkPreviewsEnabled(sender.isOn, sendSyncMessage: true, transaction: transaction)
        }
    }

    @objc
    func didToggleSharingSuggestionsEnabled(_ sender: UISwitch) {
        Logger.info("toggled to: \(sender.isOn)")

        if sender.isOn {
            databaseStorage.write { transaction in
                SSKPreferences.setAreSharingSuggestionsEnabled(true, transaction: transaction)
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
                        SSKPreferences.setAreSharingSuggestionsEnabled(false, transaction: transaction)
                    }
                }
            }
        }
    }

    @objc
    func didToggleAvatarPreference(_ sender: UISwitch) {
        Logger.info("toggled to: \(sender.isOn)")
        databaseStorage.write { transaction in
            SSKPreferences.setPreferContactAvatars(sender.isOn, transaction: transaction)
        }
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
            ThreadUtil.deleteAllContent()
        }
    }
}
