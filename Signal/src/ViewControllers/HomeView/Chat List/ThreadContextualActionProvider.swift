//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

// MARK: -

private struct ThreadContextualAction {
    let style: UIContextualAction.Style
    let color: UIColor
    let imageFilled: UIImage
    let imageStroked: UIImage
    let title: String
    let action: @MainActor () -> Void
}

// MARK: -

protocol ThreadContextualActionProvider: AnyObject {
    func threadContextualActionShouldCloseThreadIfActive(threadViewModel: ThreadViewModel)
    func threadContextualActionDidComplete()
    func deleteThreadWithConfirmation(threadViewModel: ThreadViewModel)
    func toggleThreadIsArchived(threadViewModel: ThreadViewModel)
}

extension ThreadContextualActionProvider where Self: UIViewController {

    func leadingSwipeActionsConfiguration(threadViewModel: ThreadViewModel) -> UISwipeActionsConfiguration? {
        AssertIsOnMainThread()

        let actions: [ThreadContextualAction] = [
            readStateContextualAction(threadViewModel: threadViewModel),
            pinnedStateContextualAction(threadViewModel: threadViewModel),
        ]

        return UISwipeActionsConfiguration(actions: actions.map { action in
            makeUIContextualAction(threadContextualAction: action)
        })
    }

    func trailingSwipeActionsConfiguration(threadViewModel: ThreadViewModel) -> UISwipeActionsConfiguration? {
        AssertIsOnMainThread()

        let actions: [ThreadContextualAction] = [
            archiveStateContextualAction(threadViewModel: threadViewModel),
            deleteContextualAction(threadViewModel: threadViewModel),
            muteStateContextualAction(threadViewModel: threadViewModel),
        ]

        return UISwipeActionsConfiguration(actions: actions.map { action in
            makeUIContextualAction(threadContextualAction: action)
        })
    }

    private func makeUIContextualAction(threadContextualAction action: ThreadContextualAction) -> UIContextualAction {
        return ContextualActionBuilder.makeContextualAction(
            style: action.style,
            color: action.color,
            image: action.imageFilled,
            title: action.title,
            handler: { completion in
                MainActor.assumeIsolated {
                    action.action()
                    completion(false)
                }
            },
        )
    }

    // MARK: -

    func contextMenuActions(threadViewModel: ThreadViewModel) -> [UIMenuElement] {
        AssertIsOnMainThread()

        let actions: [ThreadContextualAction] = [
            readStateContextualAction(threadViewModel: threadViewModel),
            muteStateContextualAction(threadViewModel: threadViewModel),
            pinnedStateContextualAction(threadViewModel: threadViewModel),
            archiveStateContextualAction(threadViewModel: threadViewModel),
        ]

        var destructiveActions: [ThreadContextualAction] = []
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        if
            let groupThread = threadViewModel.threadRecord as? TSGroupThread,
            let groupModel = groupThread.groupModel as? TSGroupModelV2,
            let localAci = tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci,
            groupModel.groupMembership.isLocalUserFullOrInvitedMember
        {
            destructiveActions.append(leaveGroupContextualAction(
                threadViewModel: threadViewModel,
                groupModel: groupModel,
                groupThread: groupThread,
                localAci: localAci,
            ))
        }

        destructiveActions.append(deleteContextualAction(threadViewModel: threadViewModel))

        let allActions = actions + destructiveActions

        var menuElements: [UIMenuElement] = allActions.map { action in
            makeUIAction(threadContextualAction: action)
        }
        if let folderMenu = chatFolderMenu(thread: threadViewModel.threadRecord) {
            // Add it right before the destructive actions
            menuElements.insert(folderMenu, at: actions.count)
        }
        return menuElements
    }

    private func chatFolderMenu(thread: TSThread) -> UIMenu? {
        guard
            BuildFlags.chatFolders,
            thread is TSContactThread || thread is TSGroupThread,
            let threadRowId = thread.sqliteRowId
        else {
            return nil
        }

        let db = DependenciesBridge.shared.db
        let chatFolderManager = DependenciesBridge.shared.chatFolderManager
        let folders = db.read { tx in
            chatFolderManager.fetchFoldersForDisplay(tx: tx).filter { $0.folderType == .custom }
        }
        var actions: [UIMenuElement] = folders.map { folder in
            UIAction(title: folder.displayName, image: .folder) { [weak self] _ in
                let folderName: String? = db.write { tx in
                    guard
                        let folder = chatFolderManager.fetch(chatFolderId: folder.chatFolderId, tx: tx),
                        !folder.isDeleted
                    else {
                        return nil
                    }
                    var draft = folder.draft
                    draft.excludedThreadRowIds.remove(threadRowId)
                    draft.includedThreadRowIds.insert(threadRowId)
                    chatFolderManager.update(chatFolderId: folder.chatFolderId, draft: draft, tx: tx)
                    return folder.displayName
                }
                if let folderName {
                    self?.presentAddedToFolderToast(folderName: folderName)
                }
            }
        }
        actions.append(UIAction(
            title: ChatFolderStrings.createFolder,
            image: .plus,
        ) { [weak self] _ in
            guard let self else { return }
            let editor = ChatFolderEditorViewController(
                newDraft: ChatFolderDraft(includedThreadRowIds: [threadRowId]),
            ) { [weak self] folderName in
                self?.presentAddedToFolderToast(folderName: folderName)
            }
            presentFormSheet(OWSNavigationController(rootViewController: editor), animated: true)
        })

        return UIMenu(
            title: OWSLocalizedString(
                "CHAT_FOLDERS_ADD_TO_FOLDER",
                comment: "Chat context menu action that opens the folder selection submenu.",
            ),
            image: .folder,
            children: [UIMenu(
                title: OWSLocalizedString(
                    "CHAT_FOLDERS_CHOOSE_FOLDER",
                    comment: "Header of the chat context submenu for choosing a folder.",
                ),
                options: .displayInline,
                children: actions,
            )],
        )
    }

    private func presentAddedToFolderToast(folderName: String) {
        presentToast(
            text: String.nonPluralLocalizedStringWithFormat(
                OWSLocalizedString(
                    "CHAT_FOLDERS_ADDED_TO_FOLDER_TOAST_FORMAT",
                    comment: "Toast shown after adding a chat to a folder. Embeds {{ folder name }}.",
                ),
                folderName,
            ),
            image: .folder,
        )
    }

    private func makeUIAction(
        threadContextualAction action: ThreadContextualAction,
    ) -> UIAction {
        let attributes: UIMenuElement.Attributes = switch action.style {
        case .normal: []
        case .destructive: [.destructive]
        @unknown default: []
        }

        return UIAction(
            title: action.title,
            image: action.imageStroked,
            attributes: attributes,
            handler: { _ in
                MainActor.assumeIsolated {
                    action.action()
                }
            },
        )
    }

    // MARK: -

    private func pinnedStateContextualAction(threadViewModel: ThreadViewModel) -> ThreadContextualAction {
        if threadViewModel.isPinned {
            return ThreadContextualAction(
                style: .normal,
                color: UIColor(rgbHex: 0xff990a),
                imageFilled: .pinSlashFill,
                imageStroked: .pinSlash,
                title: CommonStrings.unpinAction,
            ) { [weak self] in
                self?.unpinThread(threadViewModel: threadViewModel)
            }
        } else {
            return ThreadContextualAction(
                style: .normal,
                color: UIColor(rgbHex: 0xff990a),
                imageFilled: .pinFill,
                imageStroked: .pin,
                title: CommonStrings.pinAction,
            ) { [weak self] in
                self?.pinThread(threadViewModel: threadViewModel)
            }
        }
    }

    private func readStateContextualAction(threadViewModel: ThreadViewModel) -> ThreadContextualAction {
        if threadViewModel.hasUnreadMessages {
            return ThreadContextualAction(
                style: .normal,
                color: UIColor.Signal.ultramarine,
                imageFilled: .chatCheckFill,
                imageStroked: .chatCheck,
                title: CommonStrings.readAction,
            ) { [weak self] in
                self?.markThreadAsRead(threadViewModel: threadViewModel)
            }
        } else {
            return ThreadContextualAction(
                style: .normal,
                color: UIColor.Signal.ultramarine,
                imageFilled: .chatBadgeFill,
                imageStroked: .chatBadge,
                title: CommonStrings.unreadAction,
            ) { [weak self] in
                self?.markThreadAsUnread(threadViewModel: threadViewModel)
            }
        }
    }

    private func muteStateContextualAction(threadViewModel: ThreadViewModel) -> ThreadContextualAction {
        if threadViewModel.isMuted {
            return ThreadContextualAction(
                style: .normal,
                color: UIColor.Signal.indigo,
                imageFilled: .bellFill,
                imageStroked: .bell,
                title: CommonStrings.unmuteButton,
                action: { [weak self] in
                    self?.unmuteThread(threadViewModel: threadViewModel)
                },
            )
        } else {
            return ThreadContextualAction(
                style: .normal,
                color: UIColor.Signal.indigo,
                imageFilled: .bellSlashFill,
                imageStroked: .bellSlash,
                title: CommonStrings.muteButton,
                action: { [weak self] in
                    self?.muteThreadWithSelection(threadViewModel: threadViewModel)
                },
            )
        }
    }

    private func deleteContextualAction(threadViewModel: ThreadViewModel) -> ThreadContextualAction {
        return ThreadContextualAction(
            style: .destructive,
            color: .Signal.red,
            imageFilled: .trashFill,
            imageStroked: .trash,
            title: CommonStrings.deleteButton,
        ) { [weak self] in
            self?.deleteThreadWithConfirmation(threadViewModel: threadViewModel)
        }
    }

    private func archiveStateContextualAction(threadViewModel: ThreadViewModel) -> ThreadContextualAction {
        if threadViewModel.isArchived {
            return ThreadContextualAction(
                style: .normal,
                color: Theme.isDarkThemeEnabled ? .ows_gray45 : .ows_gray25,
                imageFilled: .archiveUpFill,
                imageStroked: .archiveUp,
                title: CommonStrings.unarchiveAction,
                action: { [weak self] in
                    self?.toggleThreadIsArchived(threadViewModel: threadViewModel)
                },
            )
        } else {
            return ThreadContextualAction(
                style: .normal,
                color: Theme.isDarkThemeEnabled ? .ows_gray45 : .ows_gray25,
                imageFilled: .archiveFill,
                imageStroked: .archive,
                title: CommonStrings.archiveAction,
                action: { [weak self] in
                    self?.toggleThreadIsArchived(threadViewModel: threadViewModel)
                },
            )
        }
    }

    private func leaveGroupContextualAction(
        threadViewModel: ThreadViewModel,
        groupModel: TSGroupModelV2,
        groupThread: TSGroupThread,
        localAci: Aci,
    ) -> ThreadContextualAction {
        return ThreadContextualAction(
            style: .destructive,
            color: .Signal.label, // Not used: only relevant for swipe action
            imageFilled: .leave, // Not used: only relevant for swipe action
            imageStroked: .leave,
            title: CommonStrings.leaveButton,
            action: {
                LeaveGroupCoordinator(
                    groupThread: groupThread,
                    groupModel: groupModel,
                    localAci: localAci,
                    onSuccess: {},
                ).startLeaveGroupFlow(rootViewController: self)
            },
        )
    }

    // MARK: -

    func toggleThreadIsArchived(threadViewModel: ThreadViewModel) {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let pinnedThreadManager = DependenciesBridge.shared.pinnedThreadManager

        threadContextualActionShouldCloseThreadIfActive(threadViewModel: threadViewModel)

        let isArchived = !threadViewModel.isArchived

        databaseStorage.write { transaction in
            if isArchived {
                pinnedThreadManager.unpinThread(
                    threadViewModel.threadRecord,
                    updateStorageService: true,
                    tx: transaction,
                )
            }
            threadViewModel.threadRecord.updateWith(
                isArchived: isArchived,
                updateStorageService: true,
                transaction: transaction,
            )
        }

        // This method might be called from modally presented ConversationSettingsViewController
        // that needs to be dismissed once the chat is archived.
        if let presentedViewController {
            presentedViewController.dismiss(animated: true)
        }

        threadContextualActionDidComplete()
    }

    func deleteThreadWithConfirmation(threadViewModel: ThreadViewModel) {
        // Deletion might have been initiated from a modally presented view controller (ConversationSettingsViewController).
        // View controller can't present more than one modal - the modal should be presented from the topmost VC.
        // Therefore grab the topmost modal and present action sheet from that.
        let presenter = topMostPresentedViewController()

        let db = DependenciesBridge.shared.db
        let threadDeletionManager = DependenciesBridge.shared.threadDeletionManager
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        let alert = ActionSheetController(
            title: OWSLocalizedString(
                "CONVERSATION_DELETE_CONFIRMATION_ALERT_TITLE",
                comment: "Title for the 'conversation delete confirmation' alert.",
            ),
            message: OWSLocalizedString(
                "CONVERSATION_DELETE_CONFIRMATION_ALERT_MESSAGE",
                comment: "Message for the 'conversation delete confirmation' alert.",
            ),
        )
        alert.addAction(ActionSheetAction(
            title: CommonStrings.deleteButton,
            style: .destructive,
        ) { [weak self] _ in
            guard let self else { return }

            // Dismiss modal VC deletion was initiated from, if any.
            if presenter !== self {
                presenter.dismiss(animated: true)
            }

            threadContextualActionShouldCloseThreadIfActive(threadViewModel: threadViewModel)

            ModalActivityIndicatorViewController.present(
                fromViewController: self,
                title: CommonStrings.deletingModal,
            ) { [weak self] modal in
                guard let self else { return }

                await db.awaitableWrite { tx in
                    let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx).owsFailUnwrap("never registered")
                    threadDeletionManager.deleteThreads(
                        [threadViewModel.threadRecord],
                        sendDeleteForMeSyncMessage: true,
                        updateStorageService: true,
                        localIdentifiers: localIdentifiers,
                        tx: tx,
                    )
                }

                modal.dismiss {
                    self.threadContextualActionDidComplete()
                }
            }
        })
        alert.addAction(OWSActionSheets.cancelAction)

        presenter.presentActionSheet(alert)
    }

    func markThreadAsRead(threadViewModel: ThreadViewModel) {
        AssertIsOnMainThread()

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            threadViewModel.threadRecord.markAllAsRead(updateStorageService: true, transaction: transaction)
        }
    }

    private func markThreadAsUnread(threadViewModel: ThreadViewModel) {
        AssertIsOnMainThread()

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            threadViewModel.threadRecord.updateWith(isMarkedUnread: true, updateStorageService: true, transaction: transaction)
        }
    }

    private func muteThreadWithSelection(threadViewModel: ThreadViewModel) {
        AssertIsOnMainThread()

        ConversationMuteManager().presentMuteActionSheet(for: [threadViewModel], from: self)
    }

    private func unmuteThread(threadViewModel: ThreadViewModel) {
        AssertIsOnMainThread()
        ConversationMuteManager().unmute(threadViewModel)
    }

    private func pinThread(threadViewModel: ThreadViewModel) {
        AssertIsOnMainThread()

        do throws(TooManyPinnedThreadsError) {
            try SSKEnvironment.shared.databaseStorageRef.write { (tx) throws(TooManyPinnedThreadsError) in
                try DependenciesBridge.shared.pinnedThreadManager.pinThread(
                    threadViewModel.threadRecord,
                    updateStorageService: true,
                    tx: tx,
                )
            }
        } catch {
            let format = OWSLocalizedString(
                "PINNED_CONVERSATION_LIMIT",
                tableName: "PluralAware",
                comment: "An explanation that you have already pinned the maximum number of conversations. Embeds {{ the maximum number of pinned conversations }}.",
            )
            OWSActionSheets.showActionSheet(title: String.localizedStringWithFormat(
                format,
                Int(clamping: PinnedThreads.maxPinnedThreads),
            ))
        }
    }

    private func unpinThread(threadViewModel: ThreadViewModel) {
        AssertIsOnMainThread()

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            DependenciesBridge.shared.pinnedThreadManager.unpinThread(
                threadViewModel.threadRecord,
                updateStorageService: true,
                tx: transaction,
            )
        }
    }
}
