//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

public extension ChatListViewController {

    var presentedChatListViewController: ChatListViewController? {
        AssertIsOnMainThread()

        guard
            let topViewController = navigationController?.topViewController as? ChatListViewController,
            topViewController != self
        else {
            return nil
        }
        return topViewController
    }

    func isConversationActive(threadUniqueId: String) -> Bool {
        AssertIsOnMainThread()

        guard let conversationSplitViewController = splitViewController as? ConversationSplitViewController else {
            owsFailDebug("Missing conversationSplitViewController.")
            return false
        }
        return conversationSplitViewController.selectedThread?.uniqueId == threadUniqueId
    }

    func updateLastViewedThreadUniqueId(_ threadUniqueId: String, animated: Bool) {
        lastViewedThreadUniqueId = threadUniqueId

        // First ensure that the given thread is selected in the current state
        // of the table. This will update the view state and set a flag
        // indicating whether a load is necessary.
        ensureSelectedThreadUniqueId(threadUniqueId, animated: animated)

        // Schedule a load if necessary.
        loadCoordinator.loadIfNecessary(suppressAnimations: !animated)

        // The chat list render state may now be changed, invalidating the
        // just-selected index path, so update the selection once more to
        // reflect the loaded data.
        ensureSelectedThreadUniqueId(threadUniqueId, animated: animated)

        tableView.scrollToNearestSelectedRow(at: .none, animated: animated)
    }

    /// Verifies that the currently selected cell matches the provided thread.
    /// If it does or if the user's in multi-select: Do nothing.
    /// If it doesn't: Select the first cell matching the provided thread, if one exists. Otherwise, deselect the current row.
    func ensureSelectedThreadUniqueId(_ targetThreadUniqueId: String, animated: Bool) {
        // Ignore any updates if we're in multiselect mode. I don't think this can happen,
        // but if it does let's avoid stepping over the user's manual selection.
        let selectedIndexPaths = tableView.indexPathsForSelectedRows ?? []

        guard viewState.multiSelectState.isActive == false, selectedIndexPaths.count < 2 else {
            return
        }

        let selectedIndexPath = selectedIndexPaths.first
        let selectedThreadUniqueId = selectedIndexPath.flatMap { renderState.threadUniqueId(forIndexPath: $0) }

        tableView.performBatchUpdates {
            viewState.lastSelectedThreadId = targetThreadUniqueId

            if let selectedIndexPath, selectedThreadUniqueId != targetThreadUniqueId {
                tableView.deselectRow(at: selectedIndexPath, animated: animated)
            }

            if let targetIndexPath = renderState.indexPath(forUniqueId: targetThreadUniqueId) {
                tableView.selectRow(at: targetIndexPath, animated: animated, scrollPosition: .none)
            }
        }
    }

    // MARK: Archive

    func archiveSelectedConversation() {
        AssertIsOnMainThread()

        Logger.info("")

        guard let selectedThread = conversationSplitViewController?.selectedThread else { return }

        let threadAssociatedData = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            ThreadAssociatedData.fetchOrDefault(for: selectedThread, transaction: transaction)
        }

        guard !threadAssociatedData.isArchived else { return }

        conversationSplitViewController?.closeSelectedConversation(animated: true)

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            threadAssociatedData.updateWith(isArchived: true, updateStorageService: true, transaction: transaction)
        }

        updateViewState()
    }

    func unarchiveSelectedConversation() {
        AssertIsOnMainThread()

        Logger.info("")

        guard let selectedThread = conversationSplitViewController?.selectedThread else { return }

        let threadAssociatedData = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            ThreadAssociatedData.fetchOrDefault(for: selectedThread, transaction: transaction)
        }

        guard threadAssociatedData.isArchived else { return }

        conversationSplitViewController?.closeSelectedConversation(animated: true)

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            threadAssociatedData.updateWith(isArchived: false, updateStorageService: true, transaction: transaction)
        }

        updateViewState()
    }

    func showArchivedConversations(offerMultiSelectMode: Bool = true) {
        AssertIsOnMainThread()

        owsAssertDebug(viewState.chatListMode == .inbox)

        // When showing archived conversations, we want to use a conventional "back" button
        // to return to the "inbox" conversation list.
        applyArchiveBackButton()

        // Push a separate instance of this view using "archive" mode.
        let chatList = ChatListViewController(chatListMode: .archive, appReadiness: appReadiness)
        chatList.hidesBottomBarWhenPushed = true

        if offerMultiSelectMode {
            chatList.navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: CommonStrings.selectButton,
                style: .plain,
                target: chatList,
                action: #selector(chatList.switchMultiSelectState),
                accessibilityIdentifier: "select",
            )
        }
        show(chatList, sender: self)
    }

    func applyArchiveBackButton() {
        AssertIsOnMainThread()

        if #available(iOS 26, *), BuildFlags.iOS26SDKIsAvailable { return }

        navigationItem.backBarButtonItem = UIBarButtonItem(
            title: CommonStrings.backButton,
            style: .plain,
            target: nil,
            action: nil,
            accessibilityIdentifier: "back",
        )
    }
}

// MARK: Previews

extension ChatListViewController {
    func canPresentPreview(fromIndexPath indexPath: IndexPath) -> Bool {
        guard !tableView.isEditing else {
            return false
        }

        switch renderState.sections[indexPath.section].type {
        case .pinned, .unpinned:
            let currentSelectedThreadId = conversationSplitViewController?.selectedThread?.uniqueId
            // Currently, no previewing the currently selected thread.
            // Though, in a scene-aware, multiwindow world, we may opt to permit this.
            // If only to allow the user to pick up and drag a conversation to a new window.
            return renderState.threadUniqueId(forIndexPath: indexPath) != currentSelectedThreadId

        default:
            return false
        }
    }

    func createPreviewController(atIndexPath indexPath: IndexPath) -> UIViewController? {
        guard let threadViewModel = tableDataSource.threadViewModel(forIndexPath: indexPath) else {
            owsFailDebug("Missing threadViewModel.")
            return nil
        }
        let vc = SSKEnvironment.shared.databaseStorageRef.read { tx in
            ConversationViewController.load(
                appReadiness: appReadiness,
                threadViewModel: threadViewModel,
                action: .none,
                focusMessageId: nil,
                tx: tx,
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
        presentThread(
            threadUniqueId: previewController.thread.uniqueId,
            animated: false,
        )
    }
}
