//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
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
        let chatList = ChatListViewController()
        chatList.chatListMode = .archive
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

extension ChatListViewController: UIViewControllerPreviewingDelegate {

    public func previewingContext(
        _ previewingContext: UIViewControllerPreviewing,
        viewControllerForLocation location: CGPoint
    ) -> UIViewController? {

        guard let indexPath = tableView.indexPathForRow(at: location),
              canPresentPreview(fromIndexPath: indexPath)
        else {
            return nil
        }

        // TODO: Use UIContextMenuInteraction instead.
        previewingContext.sourceRect = tableView.rectForRow(at: indexPath)
        return createPreviewController(atIndexPath: indexPath)
    }

    public func previewingContext(
        _ previewingContext: UIViewControllerPreviewing,
        commit viewControllerToCommit: UIViewController
    ) {
        commitPreviewController(viewControllerToCommit)
    }

    func canPresentPreview(fromIndexPath indexPath: IndexPath?) -> Bool {
        AssertIsOnMainThread()

        guard !tableView.isEditing else {
            return false
        }
        guard let indexPath else {
            return false
        }
        guard let section = ChatListSection(rawValue: indexPath.section) else {
            owsFailDebug("Invalid section: \(indexPath.section).")
            return false
        }
        switch section {
        case .pinned, .unpinned:
            let currentSelectedThreadId = conversationSplitViewController?.selectedThread?.uniqueId
            if thread(forIndexPath: indexPath)?.uniqueId == currentSelectedThreadId {
                // Currently, no previewing the currently selected thread.
                // Though, in a scene-aware, multiwindow world, we may opt to permit this.
                // If only to allow the user to pick up and drag a conversation to a new window.
                return false
            } else {
                return true
            }
        default:
            return false
        }
    }

    func createPreviewController(atIndexPath indexPath: IndexPath) -> UIViewController? {
        AssertIsOnMainThread()

        guard let threadViewModel = threadViewModel(forIndexPath: indexPath) else {
            owsFailDebug("Missing threadViewModel.")
            return nil
        }
        let vc = databaseStorage.read { tx in ConversationViewController.load(threadViewModel: threadViewModel, tx: tx) }
        vc.previewSetup()
        return vc
    }

    func commitPreviewController(_ previewController: UIViewController) {
        AssertIsOnMainThread()

        guard let previewController = previewController as? ConversationViewController else {
            owsFailDebug("Invalid previewController: \(type(of: previewController))")
            return
        }
        presentThread(previewController.thread, animated: false)
    }
}
