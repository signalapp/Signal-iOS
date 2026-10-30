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
            "SETTINGS_CHATS_PREFER_ADDRESS_BOOK_PHOTOS_FOOTER",
            comment: "Footer below the switch in Chats settings that chooses between contact photos from the phone's address book and Signal profile photos.",
        )
        contactSection.add(.switch(
            withText: OWSLocalizedString(
                "SETTINGS_CHATS_PREFER_ADDRESS_BOOK_PHOTOS_LABEL",
                comment: "Label for the switch in Chats settings that, when on, shows contact photos from the phone's address book instead of Signal profile photos.",
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

        if BuildFlags.Backups.takeoutExport {
            let exportChatsSection = OWSTableSection()
            exportChatsSection.footerTitle = OWSLocalizedString(
                "SETTINGS_CHATS_EXPORT_FOOTER",
                comment: "Footer for the section in Chats settings containing a button to export the user's chat history.",
            )
            exportChatsSection.add(.item(
                name: OWSLocalizedString(
                    "SETTINGS_CHATS_EXPORT_BUTTON",
                    comment: "Title for a button in Chats settings that starts exporting the user's chat history.",
                ),
                textColor: .Signal.accent,
                actionBlock: { [weak self] in
                    self?.didTapExportChats()
                },
            ))
            contents.add(exportChatsSection)
        }

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

    // MARK: - Export Chats

    private func didTapExportChats() {
        Task {
            guard
                let authSuccess = await LocalDeviceAuthentication(useCase: .exportChats)
                    .performBiometricAuth()
            else {
                return
            }

            showExportChatsConfirmationSheet(authSuccess: authSuccess)
        }
    }

    private func showExportChatsConfirmationSheet(
        authSuccess: LocalDeviceAuthentication.AuthSuccess,
    ) {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "SETTINGS_CHATS_EXPORT_CONFIRMATION_SHEET_TITLE",
                comment: "Title for a sheet shown when the user starts exporting their chat history from Chats settings.",
            ),
            message: OWSLocalizedString(
                "SETTINGS_CHATS_EXPORT_CONFIRMATION_SHEET_MESSAGE",
                comment: "Message for a sheet shown when the user starts exporting their chat history from Chats settings.",
            ),
        )
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SETTINGS_CHATS_EXPORT_CONFIRMATION_SHEET_WITH_MEDIA_BUTTON",
                comment: "Title for a button in a sheet shown when the user starts exporting their chat history, which exports their chat history including attachments.",
            ),
        ) { [weak self] _ in
            self?.showExportChatsChooseFolderSheet(includeAttachments: true)
        })
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SETTINGS_CHATS_EXPORT_CONFIRMATION_SHEET_WITHOUT_MEDIA_BUTTON",
                comment: "Title for a button in a sheet shown when the user starts exporting their chat history, which exports their chat history excluding attachments.",
            ),
        ) { [weak self] _ in
            self?.showExportChatsChooseFolderSheet(includeAttachments: false)
        })
        actionSheet.addAction(.cancel)

        presentActionSheet(actionSheet)
    }

    private func showExportChatsChooseFolderSheet(
        includeAttachments: Bool,
    ) {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "SETTINGS_CHATS_EXPORT_CHOOSE_FOLDER_SHEET_TITLE",
                comment: "Title for a sheet shown before the user chooses a folder to export their chat history into.",
            ),
            message: OWSLocalizedString(
                "SETTINGS_CHATS_EXPORT_CHOOSE_FOLDER_SHEET_MESSAGE",
                comment: "Message for a sheet shown before the user chooses a folder to export their chat history into.",
            ),
        )
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SETTINGS_CHATS_EXPORT_CHOOSE_FOLDER_SHEET_CHOOSE_BUTTON",
                comment: "Title for a button in a sheet shown before the user chooses a folder to export their chat history into, which opens a folder picker.",
            ),
        ) { [weak self] _ in
            self?.pickFolderAndExportChats(includeAttachments: includeAttachments)
        })
        actionSheet.addAction(.cancel)

        presentActionSheet(actionSheet)
    }

    private func pickFolderAndExportChats(
        includeAttachments: Bool,
    ) {
        Task {
            guard
                let folderUrl = try? await DocumentPickerCoordinator().pickDocument(
                    fromViewController: self,
                    contentTypes: [.folder],
                )
            else {
                return
            }

            exportChatsWithProgress(
                folderUrl: folderUrl,
                includeAttachments: includeAttachments,
            )
        }
    }

    private func exportChatsWithProgress(
        folderUrl: URL,
        includeAttachments: Bool,
    ) {
        let deviceSleepManager = DependenciesBridge.shared.deviceSleepManager
        let plaintextTakeoutManager = DependenciesBridge.shared.plaintextTakeoutManager

        let (progressUpdates, progressContinuation) = AsyncStream<Float>.makeStream()
        let progressSink = OWSSequentialProgress<PlaintextTakeoutProgressPhase>.createSink { progress in
            progressContinuation.yield(progress.percentComplete)
        }

        Task {
            let sleepBlock = DeviceSleepBlockObject(blockReason: "chat export")
            deviceSleepManager?.addBlock(blockObject: sleepBlock)
            defer { deviceSleepManager?.removeBlock(blockObject: sleepBlock) }

            do {
                let exportDirectoryUrl = try await ModalCircularProgressViewController.presentAndRun(
                    from: self,
                    title: OWSLocalizedString(
                        "SETTINGS_CHATS_EXPORT_PROGRESS_TITLE",
                        comment: "Title for a progress modal shown while the user's chat history is being exported.",
                    ),
                    progressUpdates: progressUpdates,
                ) {
                    return try await plaintextTakeoutManager.exportTakeout(
                        destinationFolderUrl: folderUrl,
                        includeAttachments: includeAttachments,
                        progress: progressSink,
                    )
                }

                showExportChatsCompleteSheet(exportDirectoryUrl: exportDirectoryUrl)
            } catch is CancellationError {
                // Nothing
            } catch {
                OWSActionSheets.showContactSupportActionSheet(
                    message: CommonStrings.somethingWentWrongTryAgainLaterError,
                    emailFilter: .custom("iOS Plaintext Takeout Failed"),
                    fromViewController: self,
                )
            }
        }
    }

    private func showExportChatsCompleteSheet(
        exportDirectoryUrl: URL,
    ) {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "SETTINGS_CHATS_EXPORT_COMPLETE_SHEET_TITLE",
                comment: "Title for a sheet shown after the user's chat history has been exported.",
            ),
            message: OWSLocalizedString(
                "SETTINGS_CHATS_EXPORT_COMPLETE_SHEET_MESSAGE",
                comment: "Message for a sheet shown after the user's chat history has been exported.",
            ),
        )
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SETTINGS_CHATS_EXPORT_COMPLETE_SHEET_VIEW_IN_FILES_BUTTON",
                comment: "Title for a button in a sheet shown after the user's chat history has been exported, which opens the exported folder in the Files app.",
            ),
        ) { _ in
            // The Files app opens "shareddocuments" URLs at the given path.
            let filesAppUrlString = exportDirectoryUrl.absoluteString.replacingOccurrences(
                of: "file://",
                with: "shareddocuments://",
            )
            guard let filesAppUrl = URL(string: filesAppUrlString) else {
                owsFailDebug("Failed to build Files app URL!")
                return
            }

            UIApplication.shared.open(filesAppUrl)
        })
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.okButton))

        presentActionSheet(actionSheet)
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
