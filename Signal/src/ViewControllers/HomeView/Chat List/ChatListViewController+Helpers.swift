//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

public extension ChatListViewController {

    var presentedChatListViewController: ChatListViewController? {
        AssertIsOnMainThread()

        guard let topViewController = navigationController?.topViewController as? ChatListViewController,
              topViewController != self else {
            return nil
        }
        return topViewController
    }

    func isConversationActive(forThread thread: TSThread) -> Bool {
        AssertIsOnMainThread()

        guard let conversationSplitViewController = splitViewController as? ConversationSplitViewController else {
            owsFailDebug("Missing conversationSplitViewController.")
            return false
        }
        return conversationSplitViewController.selectedThread?.uniqueId == thread.uniqueId
    }

    func updateLastViewedThread(_ thread: TSThread, animated: Bool) {
        lastViewedThread = thread
        ensureSelectedThread(thread, animated: animated)
    }

    /// Verifies that the currently selected cell matches the provided thread.
    /// If it does or if the user's in multi-select: Do nothing.
    /// If it doesn't: Select the first cell matching the provided thread, if one exists. Otherwise, deselect the current row.
    private func ensureSelectedThread(_ targetThread: TSThread, animated: Bool) {
        // Ignore any updates if we're in multiselect mode. I don't think this can happen,
        // but if it does let's avoid stepping over the user's manual selection.
        let currentSelection = tableView.indexPathsForSelectedRows ?? []
        guard viewState.multiSelectState.isActive == false, currentSelection.count < 2 else {
            return
        }

        let currentlySelectedThread = currentSelection.first.flatMap {
            self.tableDataSource.thread(forIndexPath: $0, expectsSuccess: false)
        }

        if currentlySelectedThread?.uniqueId != targetThread.uniqueId {
            if let targetPath = tableDataSource.renderState.indexPath(forUniqueId: targetThread.uniqueId) {
                tableView.selectRow(at: targetPath, animated: animated, scrollPosition: .none)
                tableView.scrollToRow(at: targetPath, at: .none, animated: animated)
            } else if let stalePath = currentSelection.first {
                tableView.deselectRow(at: stalePath, animated: animated)
            }
        }
    }

    // MARK: Archive

    func archiveSelectedConversation() {
        AssertIsOnMainThread()

        Logger.info("")

        guard let selectedThread = conversationSplitViewController?.selectedThread else { return }

        let threadAssociatedData = databaseStorage.read { transaction in
            ThreadAssociatedData.fetchOrDefault(for: selectedThread, transaction: transaction)
        }

        guard !threadAssociatedData.isArchived else { return }

        conversationSplitViewController?.closeSelectedConversation(animated: true)

        databaseStorage.write { transaction in
            threadAssociatedData.updateWith(isArchived: true, updateStorageService: true, transaction: transaction)
        }

        updateViewState()
    }

    func unarchiveSelectedConversation() {
        AssertIsOnMainThread()

        Logger.info("")

        guard let selectedThread = conversationSplitViewController?.selectedThread else { return }

        let threadAssociatedData = databaseStorage.read { transaction in
            ThreadAssociatedData.fetchOrDefault(for: selectedThread, transaction: transaction)
        }

        guard threadAssociatedData.isArchived else { return }

        conversationSplitViewController?.closeSelectedConversation(animated: true)

        databaseStorage.write { transaction in
            threadAssociatedData.updateWith(isArchived: false, updateStorageService: true, transaction: transaction)
        }

        updateViewState()
    }

    func showArchivedConversations(offerMultiSelectMode: Bool = true) {
        AssertIsOnMainThread()

        owsAssertDebug(chatListMode == .inbox)

        // When showing archived conversations, we want to use a conventional "back" button
        // to return to the "inbox" conversation list.
        applyArchiveBackButton()

        // Push a separate instance of this view using "archive" mode.
        let chatList = ChatListViewController(chatListMode: .archive)
        chatList.hidesBottomBarWhenPushed = true

        if offerMultiSelectMode {
            chatList.navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: CommonStrings.selectButton,
                style: .plain,
                target: chatList,
                action: #selector(chatList.switchMultiSelectState),
                accessibilityIdentifier: "select")
        }
        show(chatList, sender: self)
    }

    func applyArchiveBackButton() {
        AssertIsOnMainThread()

        navigationItem.backBarButtonItem = UIBarButtonItem(title: CommonStrings.backButton,
                                                           style: .plain,
                                                           target: nil,
                                                           action: nil,
                                                           accessibilityIdentifier: "back")
    }
}

// MARK: Previews

extension ChatListViewController {
    func canPresentPreview(fromIndexPath indexPath: IndexPath) -> Bool {
        guard !tableView.isEditing else {
            return false
        }
        guard let section = ChatListSection(rawValue: indexPath.section) else {
            owsFailDebug("Invalid section: \(indexPath.section).")
            return false
        }
        switch section {
        case .pinned, .unpinned:
            let currentSelectedThreadId = conversationSplitViewController?.selectedThread?.uniqueId
            // Currently, no previewing the currently selected thread.
            // Though, in a scene-aware, multiwindow world, we may opt to permit this.
            // If only to allow the user to pick up and drag a conversation to a new window.
            return thread(forIndexPath: indexPath)?.uniqueId != currentSelectedThreadId
        default:
            return false
        }
    }

    func createPreviewController(atIndexPath indexPath: IndexPath) -> UIViewController? {
        guard let threadViewModel = threadViewModel(forIndexPath: indexPath) else {
            owsFailDebug("Missing threadViewModel.")
            return nil
        }
        let vc = databaseStorage.read { tx in
            ConversationViewController.load(
                threadViewModel: threadViewModel,
                isSelectedDelegate: nil,
                action: .none,
                focusMessageId: nil,
                tx: tx
            )
        }
        vc.previewSetup()
        return vc
    }

    func commitPreviewController(_ previewController: UIViewController) {
        guard let previewController = previewController as? ConversationViewController else {
            owsFailDebug("Invalid previewController: \(type(of: previewController))")
            return
        }
        presentThread(previewController.thread, animated: false)
    }
}
