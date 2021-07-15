//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

extension ConversationListViewController {
    @objc
    public func performAccessibilityCustomAction(_ action: HVCellAccessibilityCustomAction) {
        AssertIsOnMainThread()

        switch action.type {
        case .archive:
            archiveThread(threadViewModel: action.threadViewModel)
        case .delete:
            deleteThreadWithConfirmation(threadViewModel: action.threadViewModel)
        case .markRead:
            markThreadAsRead(threadViewModel: action.threadViewModel)
        case .markUnread:
            markThreadAsUnread(threadViewModel: action.threadViewModel)
        case .pin:
            pinThread(threadViewModel: action.threadViewModel)
        case .unpin:
            unpinThread(threadViewModel: action.threadViewModel)
        }
    }

    func archiveThread(threadViewModel: ThreadViewModel) {
        AssertIsOnMainThread()

        // If this conversation is currently selected, close it.
        if isConversationActive(forThread: threadViewModel.threadRecord) {
            conversationSplitViewController?.closeSelectedConversation(animated: true)
        }

        databaseStorage.write { transaction in
            switch self.conversationListMode {
            case .inbox:
                threadViewModel.associatedData.updateWith(isArchived: true,
                                                          updateStorageService: true,
                                                          transaction: transaction)
            case .archive:
                threadViewModel.associatedData.updateWith(isArchived: false,
                                                          updateStorageService: true,
                                                          transaction: transaction)
            }
        }
        updateViewState()
    }

    func deleteThreadWithConfirmation(threadViewModel: ThreadViewModel) {
        AssertIsOnMainThread()

        let alert = ActionSheetController(title: NSLocalizedString("CONVERSATION_DELETE_CONFIRMATION_ALERT_TITLE",
                                                                   comment: "Title for the 'conversation delete confirmation' alert."),
                                          message: NSLocalizedString("CONVERSATION_DELETE_CONFIRMATION_ALERT_MESSAGE",
                                                                     comment: "Message for the 'conversation delete confirmation' alert."))
        alert.addAction(ActionSheetAction(title: CommonStrings.deleteButton,
                                          style: .destructive) { [weak self] _ in
                            self?.deleteThread(threadViewModel: threadViewModel)
        })
        alert.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(alert)
    }

    func deleteThread(threadViewModel: ThreadViewModel) {
        AssertIsOnMainThread()

        // If this conversation is currently selected, close it.
        if isConversationActive(forThread: threadViewModel.threadRecord) {
            conversationSplitViewController?.closeSelectedConversation(animated: true)
        }

        databaseStorage.write { transaction in
            threadViewModel.threadRecord.softDelete(with: transaction)
        }

        // TODO: Rename this method.
        updateViewState()
    }

    func markThreadAsRead(threadViewModel: ThreadViewModel) {
        AssertIsOnMainThread()

        databaseStorage.write { transaction in
            threadViewModel.threadRecord.markAllAsRead(updateStorageService: true, transaction: transaction)
        }
    }

    func markThreadAsUnread(threadViewModel: ThreadViewModel) {
        AssertIsOnMainThread()

        databaseStorage.write { transaction in
            threadViewModel.associatedData.updateWith(isMarkedUnread: true, updateStorageService: true, transaction: transaction)
        }
    }

    func pinThread(threadViewModel: ThreadViewModel) {
        AssertIsOnMainThread()

        do {
            try databaseStorage.write { transaction in
                try PinnedThreadManager.pinThread(threadViewModel.threadRecord, updateStorageService: true, transaction: transaction)
            }
        } catch {
            if case PinnedThreadError.tooManyPinnedThreads = error {
                //            if (error == PinnedThreadManager.tooManyPinnedThreadsError) {
                OWSActionSheets.showActionSheet(title: NSLocalizedString("PINNED_CONVERSATION_LIMIT",
                                                                         comment: "An explanation that you have already pinned the maximum number of conversations."))
            } else {
                owsFailDebug("Error: \(error)")
            }
        }
    }

    func unpinThread(threadViewModel: ThreadViewModel) {
        AssertIsOnMainThread()

        do {
            try databaseStorage.write { transaction in
                try PinnedThreadManager.unpinThread(threadViewModel.threadRecord, updateStorageService: true, transaction: transaction)
            }
        } catch {
            owsFailDebug("Error: \(error)")
        }
    }
}
