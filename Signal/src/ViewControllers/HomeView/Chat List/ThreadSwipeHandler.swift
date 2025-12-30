//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol ThreadSwipeHandler {
    func updateUIAfterSwipeAction()
}

extension ThreadSwipeHandler where Self: UIViewController {

    func leadingSwipeActionsConfiguration(for threadViewModel: ThreadViewModel?) -> UISwipeActionsConfiguration? {
        AssertIsOnMainThread()

        guard let threadViewModel else {
            return nil
        }

        let isThreadPinned = threadViewModel.isPinned
        let pinnedStateAction: UIContextualAction
        if isThreadPinned {
            pinnedStateAction = ContextualActionBuilder.makeContextualAction(
                style: .normal,
                color: UIColor(rgbHex: 0xff990a),
                image: "pin-slash-fill",
                title: CommonStrings.unpinAction,
            ) { [weak self] completion in
                self?.unpinThread(threadViewModel: threadViewModel)
                completion(false)
            }
        } else {
            pinnedStateAction = ContextualActionBuilder.makeContextualAction(
                style: .destructive,
                color: UIColor(rgbHex: 0xff990a),
                image: "pin-fill",
                title: CommonStrings.pinAction,
            ) { [weak self] completion in
                self?.pinThread(threadViewModel: threadViewModel)
                completion(false)
            }
        }

        let readStateAction: UIContextualAction
        if threadViewModel.hasUnreadMessages {
            readStateAction = ContextualActionBuilder.makeContextualAction(
                style: .destructive,
                color: UIColor.Signal.ultramarine,
                image: "chat-check-fill",
                title: CommonStrings.readAction,
            ) { [weak self] completion in
                completion(false)
                self?.markThreadAsRead(threadViewModel: threadViewModel)
            }
        } else {
            readStateAction = ContextualActionBuilder.makeContextualAction(
                style: .normal,
                color: UIColor.Signal.ultramarine,
                image: "chat-badge-fill",
                title: CommonStrings.unreadAction,
            ) { [weak self] completion in
                completion(false)
                self?.markThreadAsUnread(threadViewModel: threadViewModel)
            }
        }

        // The first action will be auto-performed for "very long swipes".
        return UISwipeActionsConfiguration(actions: [readStateAction, pinnedStateAction])
    }

    func trailingSwipeActionsConfiguration(for threadViewModel: ThreadViewModel?, closeConversationBlock: (() -> Void)? = nil) -> UISwipeActionsConfiguration? {
        AssertIsOnMainThread()

        guard let threadViewModel else {
            return nil
        }

        let muteAction = ContextualActionBuilder.makeContextualAction(
            style: .normal,
            color: UIColor.Signal.indigo,
            image: threadViewModel.isMuted ? "bell-fill" : "bell-slash-fill",
            title: threadViewModel.isMuted ? CommonStrings.unmuteButton : CommonStrings.muteButton,
        ) { [weak self] completion in
            if threadViewModel.isMuted {
                self?.unmuteThread(threadViewModel: threadViewModel)
            } else {
                self?.muteThreadWithSelection(threadViewModel: threadViewModel)
            }
            completion(false)
        }

        let deleteAction = ContextualActionBuilder.makeContextualAction(
            style: .destructive,
            color: UIColor.Signal.red,
            image: "trash-fill",
            title: CommonStrings.deleteButton,
        ) { [weak self] completion in
            self?.deleteThreadWithConfirmation(
                threadViewModel: threadViewModel,
                closeConversationBlock: closeConversationBlock,
            )
            completion(false)
        }

        let archiveAction = ContextualActionBuilder.makeContextualAction(
            style: .normal,
            color: Theme.isDarkThemeEnabled ? .ows_gray45 : .ows_gray25,
            image: threadViewModel.isArchived ? "archive-up-fill" : "archive-fill",
            title: threadViewModel.isArchived ? CommonStrings.unarchiveAction : CommonStrings.archiveAction,
        ) { [weak self] completion in
            self?.archiveThread(threadViewModel: threadViewModel, closeConversationBlock: closeConversationBlock)
            completion(false)
        }

        // The first action will be auto-performed for "very long swipes".
        return UISwipeActionsConfiguration(actions: [archiveAction, deleteAction, muteAction])
    }

    func archiveThread(threadViewModel: ThreadViewModel, closeConversationBlock: (() -> Void)?) {
        AssertIsOnMainThread()

        closeConversationBlock?()
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            threadViewModel.associatedData.updateWith(
                isArchived: !threadViewModel.isArchived,
                updateStorageService: true,
                transaction: transaction,
            )
        }
        updateUIAfterSwipeAction()
    }

    fileprivate func deleteThreadWithConfirmation(
        threadViewModel: ThreadViewModel,
        closeConversationBlock: (() -> Void)?,
    ) {
        AssertIsOnMainThread()
        let db = DependenciesBridge.shared.db
        let threadSoftDeleteManager = DependenciesBridge.shared.threadSoftDeleteManager

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

            closeConversationBlock?()

            ModalActivityIndicatorViewController.present(
                fromViewController: self,
            ) { [weak self] modal in
                guard let self else { return }

                await db.awaitableWrite { tx in
                    threadSoftDeleteManager.softDelete(
                        threads: [threadViewModel.threadRecord],
                        sendDeleteForMeSyncMessage: true,
                        tx: tx,
                    )
                }

                modal.dismiss {
                    self.updateUIAfterSwipeAction()
                }
            }
        })
        alert.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(alert)
    }

    func markThreadAsRead(threadViewModel: ThreadViewModel) {
        AssertIsOnMainThread()

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            threadViewModel.threadRecord.markAllAsRead(updateStorageService: true, transaction: transaction)
        }
    }

    fileprivate func markThreadAsUnread(threadViewModel: ThreadViewModel) {
        AssertIsOnMainThread()

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            threadViewModel.associatedData.updateWith(isMarkedUnread: true, updateStorageService: true, transaction: transaction)
        }
    }

    fileprivate func muteThreadWithSelection(threadViewModel: ThreadViewModel) {
        AssertIsOnMainThread()

        let alert = ActionSheetController(title: OWSLocalizedString(
            "CONVERSATION_MUTE_CONFIRMATION_ALERT_TITLE",
            comment: "Title for the 'conversation mute confirmation' alert.",
        ))
        for (title, seconds) in [
            (OWSLocalizedString("CONVERSATION_MUTE_CONFIRMATION_OPTION_1H", comment: "1 hour"), TimeInterval.hour),
            (OWSLocalizedString("CONVERSATION_MUTE_CONFIRMATION_OPTION_8H", comment: "8 hours"), 8 * TimeInterval.hour),
            (OWSLocalizedString("CONVERSATION_MUTE_CONFIRMATION_OPTION_1D", comment: "1 day"), TimeInterval.day),
            (OWSLocalizedString("CONVERSATION_MUTE_CONFIRMATION_OPTION_1W", comment: "1 week"), TimeInterval.week),
            (OWSLocalizedString("CONVERSATION_MUTE_CONFIRMATION_OPTION_ALWAYS", comment: "Always"), -1),
        ] {
            alert.addAction(ActionSheetAction(title: title, style: .default) { [weak self] _ in
                self?.muteThread(threadViewModel: threadViewModel, duration: seconds)
            })
        }
        alert.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(alert)
    }

    fileprivate func muteThread(threadViewModel: ThreadViewModel, duration seconds: TimeInterval) {
        AssertIsOnMainThread()

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            let timestamp = seconds < 0
                ? ThreadAssociatedData.alwaysMutedTimestamp
                : (seconds == 0 ? 0 : Date.ows_millisecondTimestamp() + UInt64(seconds * 1000))
            threadViewModel.associatedData.updateWith(mutedUntilTimestamp: timestamp, updateStorageService: true, transaction: transaction)
        }
    }

    fileprivate func unmuteThread(threadViewModel: ThreadViewModel) {
        AssertIsOnMainThread()

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            threadViewModel.associatedData.updateWith(mutedUntilTimestamp: 0, updateStorageService: true, transaction: transaction)
        }
    }

    fileprivate func pinThread(threadViewModel: ThreadViewModel) {
        AssertIsOnMainThread()

        do {
            try SSKEnvironment.shared.databaseStorageRef.write { transaction in
                try DependenciesBridge.shared.pinnedThreadManager.pinThread(
                    threadViewModel.threadRecord,
                    updateStorageService: true,
                    tx: transaction,
                )
            }
        } catch {
            if case PinnedThreadError.tooManyPinnedThreads = error {
                OWSActionSheets.showActionSheet(title: OWSLocalizedString(
                    "PINNED_CONVERSATION_LIMIT",
                    comment: "An explanation that you have already pinned the maximum number of conversations.",
                ))
            } else {
                owsFailDebug("Error: \(error)")
            }
        }
    }

    fileprivate func unpinThread(threadViewModel: ThreadViewModel) {
        AssertIsOnMainThread()

        do {
            try SSKEnvironment.shared.databaseStorageRef.write { transaction in
                try DependenciesBridge.shared.pinnedThreadManager.unpinThread(
                    threadViewModel.threadRecord,
                    updateStorageService: true,
                    tx: transaction,
                )
            }
        } catch {
            owsFailDebug("Error: \(error)")
        }
    }

}
