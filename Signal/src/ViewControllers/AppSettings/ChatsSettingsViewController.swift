//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import IntentsUI
import SignalServiceKit
import SignalUI

class ChatsSettingsViewController: OWSTableViewController2 {

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("SETTINGS_CHATS", comment: "Title for the 'chats' link in settings.")

        updateTableContents()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: .syncManagerConfigurationSyncDidComplete,
            object: nil,
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateTableContents()
    }

    @objc
    private func updateTableContents() {
        let contents = OWSTableContents()

        let linkPreviewSection = OWSTableSection()
        linkPreviewSection.footerTitle = OWSLocalizedString(
            "SETTINGS_LINK_PREVIEWS_FOOTER",
            comment: "Footer for setting for enabling & disabling link previews.",
        )
        linkPreviewSection.add(.switch(
            withText: OWSLocalizedString(
                "SETTINGS_LINK_PREVIEWS",
                comment: "Setting for enabling & disabling link previews.",
            ),
            isOn: {
                SSKEnvironment.shared.databaseStorageRef.read { DependenciesBridge.shared.linkPreviewSettingStore.areLinkPreviewsEnabled(tx: $0) }
            },
            actionBlock: { [weak self] uiSwitch in
                self?.didToggleLinkPreviewsEnabled(uiSwitch)
            },
        ))
        contents.add(linkPreviewSection)

        let sharingSuggestionsSection = OWSTableSection()
        sharingSuggestionsSection.footerTitle = OWSLocalizedString(
            "SETTINGS_SHARING_SUGGESTIONS_NOTIFICATIONS_FOOTER",
            comment: "Footer for setting for enabling & disabling contact and notification sharing with iOS.",
        )

        sharingSuggestionsSection.add(.switch(
            withText: OWSLocalizedString(
                "SETTINGS_SHARING_SUGGESTIONS",
                comment: "Setting for enabling & disabling iOS contact sharing.",
            ),
            isOn: {
                SSKEnvironment.shared.databaseStorageRef.read { SSKPreferences.areIntentDonationsEnabled(transaction: $0) }
            },
            actionBlock: { [weak self] uiSwitch in
                self?.didToggleSharingSuggestionsEnabled(uiSwitch)
            },
        ))
        contents.add(sharingSuggestionsSection)

        let contactSection = OWSTableSection()
        contactSection.footerTitle = OWSLocalizedString(
            "SETTINGS_APPEARANCE_AVATAR_FOOTER",
            comment: "Footer for avatar section in appearance settings",
        )
        contactSection.add(.switch(
            withText: OWSLocalizedString(
                "SETTINGS_APPEARANCE_AVATAR_PREFERENCE_LABEL",
                comment: "Title for switch to toggle preference between contact and profile avatars",
            ),
            isOn: {
                SSKEnvironment.shared.databaseStorageRef.read { SSKPreferences.preferContactAvatars(transaction: $0) }
            },
            actionBlock: { [weak self] uiSwitch in
                self?.didToggleAvatarPreference(uiSwitch)
            },
        ))
        contents.add(contactSection)

        let keepMutedChatsArchived = OWSTableSection()
        keepMutedChatsArchived.add(.switch(
            withText: OWSLocalizedString("SETTINGS_KEEP_MUTED_ARCHIVED_LABEL", comment: "When a chat is archived and receives a new message, it is unarchived. Turning this switch on disables this feature if the chat in question is also muted. This string is a brief label for a switch paired with a longer description underneath, in the Chats settings."),
            isOn: {
                SSKEnvironment.shared.databaseStorageRef.read { SSKPreferences.shouldKeepMutedChatsArchived(transaction: $0) }
            },
            actionBlock: { [weak self] uiSwitch in
                self?.didToggleShouldKeepMutedChatsArchivedSwitch(uiSwitch)
            },
        ))
        keepMutedChatsArchived.footerTitle = OWSLocalizedString(
            "SETTINGS_KEEP_MUTED_ARCHIVED_DESCRIPTION",
            comment: "When a chat is archived and receives a new message, it is unarchived. Turning this switch on disables this feature if the chat in question is also muted. This string is a thorough description paired with a labeled switch above, in the Chats settings.",
        )
        contents.add(keepMutedChatsArchived)

        let (othersAction, ownAction) = SSKEnvironment.shared.databaseStorageRef.read { tx in
            (
                SSKPreferences.doubleTapOthersMessagesAction(transaction: tx),
                SSKPreferences.doubleTapOwnMessagesAction(transaction: tx),
            )
        }

        let doubleTapSection = OWSTableSection()
        doubleTapSection.headerTitle = OWSLocalizedString(
            "SETTINGS_DOUBLE_TAP_SECTION_TITLE",
            comment: "Section title for double-tap message action settings.",
        )
        doubleTapSection.footerTitle = OWSLocalizedString(
            "SETTINGS_DOUBLE_TAP_SECTION_FOOTER",
            comment: "Footer explaining configurable double-tap actions on messages.",
        )
        doubleTapSection.add(.disclosureItem(
            withText: OWSLocalizedString(
                "SETTINGS_DOUBLE_TAP_OTHERS_MESSAGES",
                comment: "Setting for double-tap action on messages from other people.",
            ),
            accessoryText: othersAction.displayName,
            actionBlock: { [weak self] in
                guard let self else { return }
                let vc = DoubleTapActionSettingsViewController(
                    title: OWSLocalizedString(
                        "SETTINGS_DOUBLE_TAP_OTHERS_MESSAGES",
                        comment: "Setting for double-tap action on messages from other people.",
                    ),
                    options: SSKPreferences.DoubleTapOthersMessagesAction.allCases.map { ($0.displayName, $0 == othersAction) },
                ) { index in
                    let action = SSKPreferences.DoubleTapOthersMessagesAction.allCases[index]
                    SSKEnvironment.shared.databaseStorageRef.write {
                        SSKPreferences.setDoubleTapOthersMessagesAction(action, transaction: $0)
                    }
                }
                self.navigationController?.pushViewController(vc, animated: true)
            },
        ))
        doubleTapSection.add(.disclosureItem(
            withText: OWSLocalizedString(
                "SETTINGS_DOUBLE_TAP_OWN_MESSAGES",
                comment: "Setting for double-tap action on your own messages.",
            ),
            accessoryText: ownAction.displayName,
            actionBlock: { [weak self] in
                guard let self else { return }
                let vc = DoubleTapActionSettingsViewController(
                    title: OWSLocalizedString(
                        "SETTINGS_DOUBLE_TAP_OWN_MESSAGES",
                        comment: "Setting for double-tap action on your own messages.",
                    ),
                    options: SSKPreferences.DoubleTapOwnMessagesAction.allCases.map { ($0.displayName, $0 == ownAction) },
                ) { index in
                    let action = SSKPreferences.DoubleTapOwnMessagesAction.allCases[index]
                    SSKEnvironment.shared.databaseStorageRef.write {
                        SSKPreferences.setDoubleTapOwnMessagesAction(action, transaction: $0)
                    }
                }
                self.navigationController?.pushViewController(vc, animated: true)
            },
        ))
        doubleTapSection.add(.switch(
            withText: OWSLocalizedString(
                "SETTINGS_DOUBLE_TAP_REACT_STICKERS",
                comment: "Toggle for allowing double-tap quick react on sticker messages.",
            ),
            isOn: {
                SSKEnvironment.shared.databaseStorageRef.read {
                    SSKPreferences.isDoubleTapReactEnabledForStickers(transaction: $0)
                }
            },
            actionBlock: { sender in
                SSKEnvironment.shared.databaseStorageRef.write {
                    SSKPreferences.setDoubleTapReactEnabledForStickers(sender.isOn, transaction: $0)
                }
            },
        ))
        doubleTapSection.add(.switch(
            withText: OWSLocalizedString(
                "SETTINGS_DOUBLE_TAP_REACT_PHOTOS",
                comment: "Toggle for allowing double-tap quick react on photo and video messages.",
            ),
            isOn: {
                SSKEnvironment.shared.databaseStorageRef.read {
                    SSKPreferences.isDoubleTapReactEnabledForPhotos(transaction: $0)
                }
            },
            actionBlock: { sender in
                SSKEnvironment.shared.databaseStorageRef.write {
                    SSKPreferences.setDoubleTapReactEnabledForPhotos(sender.isOn, transaction: $0)
                }
            },
        ))
        contents.add(doubleTapSection)

        let clearHistorySection = OWSTableSection()
        clearHistorySection.add(.item(
            name: OWSLocalizedString("SETTINGS_CLEAR_HISTORY", comment: ""),
            textColor: .Signal.red,
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "clear_chat_history"),
            actionBlock: { [weak self] in
                self?.didTapClearHistory()
            },
        ))
        contents.add(clearHistorySection)

        self.contents = contents
    }

    private func didToggleLinkPreviewsEnabled(_ sender: UISwitch) {
        Logger.info("toggled to: \(sender.isOn)")
        let db = DependenciesBridge.shared.db
        db.write { tx in
            let linkPreviewSettingManager = DependenciesBridge.shared.linkPreviewSettingManager
            linkPreviewSettingManager.setAreLinkPreviewsEnabled(sender.isOn, shouldSendSyncMessage: true, tx: tx)
        }
    }

    private func didToggleSharingSuggestionsEnabled(_ sender: UISwitch) {
        Logger.info("toggled to: \(sender.isOn)")

        if sender.isOn {
            SSKEnvironment.shared.databaseStorageRef.write { transaction in
                SSKPreferences.setAreIntentDonationsEnabled(true, transaction: transaction)
            }
        } else {
            INInteraction.deleteAll { error in
                if let error {
                    owsFailDebug("Failed to disable sharing suggestions \(error)")
                    sender.setOn(true, animated: true)
                    OWSActionSheets.showActionSheet(title: OWSLocalizedString(
                        "SHARING_SUGGESTIONS_DISABLE_ERROR",
                        comment: "Title of alert indicating sharing suggestions failed to deactivate",
                    ))
                } else {
                    SSKEnvironment.shared.databaseStorageRef.write { transaction in
                        SSKPreferences.setAreIntentDonationsEnabled(false, transaction: transaction)
                    }
                }
            }
        }
    }

    private func didToggleAvatarPreference(_ sender: UISwitch) {
        Logger.info("toggled to: \(sender.isOn)")
        let currentValue = SSKEnvironment.shared.databaseStorageRef.read { SSKPreferences.preferContactAvatars(transaction: $0) }
        guard currentValue != sender.isOn else { return }

        SSKEnvironment.shared.databaseStorageRef.write { SSKPreferences.setPreferContactAvatars(sender.isOn, transaction: $0) }
    }

    private func didToggleShouldKeepMutedChatsArchivedSwitch(_ sender: UISwitch) {
        Logger.info("toggled to \(sender.isOn)")
        let currentValue = SSKEnvironment.shared.databaseStorageRef.read { SSKPreferences.shouldKeepMutedChatsArchived(transaction: $0) }
        guard currentValue != sender.isOn else { return }

        SSKEnvironment.shared.databaseStorageRef.write { SSKPreferences.setShouldKeepMutedChatsArchived(sender.isOn, transaction: $0) }

        SSKEnvironment.shared.storageServiceManagerRef.recordPendingLocalAccountUpdates()
    }

    // MARK: -

    private func didTapClearHistory() {
        let primaryConfirmDeletionTitle = OWSLocalizedString(
            "SETTINGS_DELETE_HISTORYLOG_CONFIRMATION",
            comment: "Alert message before user confirms clearing history",
        )
        let secondaryConfirmDeletionTitle = OWSLocalizedString(
            "SETTINGS_DELETE_HISTORYLOG_CONFIRMATION_SECONDARY_TITLE",
            comment: "Secondary alert title before user confirms clearing history",
        )
        let secondaryConfirmDeletionMessage = OWSLocalizedString(
            "SETTINGS_DELETE_HISTORYLOG_CONFIRMATION_SECONDARY_MESSAGE",
            comment: "Secondary alert message before user confirms clearing history",
        )
        let confirmDeletionButtonTitle = OWSLocalizedString(
            "SETTINGS_DELETE_HISTORYLOG_CONFIRMATION_BUTTON",
            comment: "Confirmation text for button which deletes all message, calling, attachments, etc.",
        )

        // Show two layers of confirmation here – this is a maximally
        // destructive action.
        OWSActionSheets.showConfirmationAlert(
            title: primaryConfirmDeletionTitle,
            proceedTitle: confirmDeletionButtonTitle,
            proceedStyle: .destructive,
        ) { [weak self] _ in
            OWSActionSheets.showConfirmationAlert(
                title: secondaryConfirmDeletionTitle,
                message: secondaryConfirmDeletionMessage,
                proceedTitle: confirmDeletionButtonTitle,
                proceedStyle: .destructive,
            ) { [weak self] _ in
                self?.clearHistoryBehindSpinner()
            }
        }
    }

    private func clearHistoryBehindSpinner() {
        let threadDeletionManager = DependenciesBridge.shared.threadDeletionManager

        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            title: CommonStrings.deletingModal,
            canCancel: false,
            presentationDelay: 0.5,
            backgroundBlockQueueQos: .userInitiated,
            backgroundBlock: { modal in
                self.clearHistoryWithSneakyTransaction(
                    threadDeletionManager: threadDeletionManager,
                )

                DispatchQueue.main.async {
                    modal.dismiss()
                }
            },
        )
    }

    private func clearHistoryWithSneakyTransaction(
        threadDeletionManager: any ThreadDeletionManager,
    ) {
        Logger.info("")
        let db = DependenciesBridge.shared.db
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        db.write { tx in
            let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx).owsFailUnwrap("never registered")

            threadDeletionManager.deleteThreads(
                TSThread.anyFetchAll(transaction: tx),
                sendDeleteForMeSyncMessage: true,
                updateStorageService: true,
                localIdentifiers: localIdentifiers,
                tx: tx,
            )

            // Need to instantiate these to remove them, since `StoryMessage`
            // has an `anyDidRemove` hook.
            for storyMessage in StoryMessage.anyFetchAll(transaction: tx) {
                storyMessage.anyRemove(transaction: tx)
            }
        }

        AttachmentStream.deleteAllAttachmentFiles()
    }
}

// MARK: -

private final class DoubleTapActionSettingsViewController: OWSTableViewController2 {
    private let options: [(title: String, isSelected: Bool)]
    private let onSelect: (Int) -> Void

    init(title: String, options: [(String, Bool)], onSelect: @escaping (Int) -> Void) {
        self.options = options
        self.onSelect = onSelect
        super.init()
        self.title = title
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let section = OWSTableSection()
        for (index, option) in options.enumerated() {
            section.add(.init(
                text: option.title,
                actionBlock: { [weak self] in
                    guard let self else { return }
                    self.onSelect(index)
                    self.navigationController?.popViewController(animated: true)
                },
                accessoryType: option.isSelected ? .checkmark : .none,
            ))
        }
        contents = OWSTableContents(sections: [section])
    }
}

private extension SSKPreferences.DoubleTapOthersMessagesAction {
    var displayName: String {
        switch self {
        case .off:
            return OWSLocalizedString("SETTINGS_DOUBLE_TAP_ACTION_OFF", comment: "Double-tap action: disabled.")
        case .react:
            return OWSLocalizedString(
                "SETTINGS_DOUBLE_TAP_ACTION_REACT",
                comment: "Double-tap action: react with the first quick-reaction emoji.",
            )
        case .reply:
            return OWSLocalizedString("SETTINGS_DOUBLE_TAP_ACTION_REPLY", comment: "Double-tap action: reply to the message.")
        }
    }
}

private extension SSKPreferences.DoubleTapOwnMessagesAction {
    var displayName: String {
        switch self {
        case .off:
            return OWSLocalizedString("SETTINGS_DOUBLE_TAP_ACTION_OFF", comment: "Double-tap action: disabled.")
        case .edit:
            return OWSLocalizedString("SETTINGS_DOUBLE_TAP_ACTION_EDIT", comment: "Double-tap action: edit your message.")
        case .reply:
            return OWSLocalizedString("SETTINGS_DOUBLE_TAP_ACTION_REPLY", comment: "Double-tap action: reply to the message.")
        }
    }
}
