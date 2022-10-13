//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// TODO: Decompose into multiple source files?
@objc
public extension ChatListViewController {

    var renderState: CLVRenderState { viewState.tableDataSource.renderState }

    func threadViewModel(forThread thread: TSThread) -> ThreadViewModel {
        tableDataSource.threadViewModel(forThread: thread)
    }

    func thread(forIndexPath indexPath: IndexPath) -> TSThread? {
        tableDataSource.thread(forIndexPath: indexPath)
    }

    func threadViewModel(forIndexPath indexPath: IndexPath) -> ThreadViewModel? {
        tableDataSource.threadViewModel(forIndexPath: indexPath)
    }

    var numberOfInboxThreads: UInt { renderState.inboxCount }
    var numberOfArchivedThreads: UInt { renderState.archiveCount }

    // MARK: -

    func isConversationActive(forThread thread: TSThread) -> Bool {
        AssertIsOnMainThread()

        guard let conversationSplitViewController = splitViewController as? ConversationSplitViewController else {
            owsFailDebug("Missing conversationSplitViewController.")
            return false
        }
        return conversationSplitViewController.selectedThread?.uniqueId == thread.uniqueId
    }

    func dismissSearchKeyboard() {
        AssertIsOnMainThread()

        searchBar.resignFirstResponder()
        owsAssertDebug(!searchBar.isFirstResponder)
    }

    func showArchivedConversations(offerMultiSelectMode: Bool = true) {
        AssertIsOnMainThread()

        owsAssertDebug(self.chatListMode == .inbox)

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
        self.show(chatList, sender: self)
    }

    var presentedChatListViewController: ChatListViewController? {
        AssertIsOnMainThread()

        guard let topViewController = navigationController?.topViewController as? ChatListViewController,
              topViewController != self else {
            return nil
        }
        return topViewController
    }

    func applyDefaultBackButton() {
        AssertIsOnMainThread()

        // We don't show any text for the back button, so there's no need to localize it. But because we left align the
        // conversation title view, we add a little tappable padding after the back button, by having a title of spaces.
        // Admittedly this is kind of a hack and not super fine grained, but it's simple and results in the interactive pop
        // gesture animating our title view nicely vs. creating our own back button bar item with custom padding, which does
        // not properly animate with the "swipe to go back" or "swipe left for info" gestures.
        let paddingLength: Int = 3
        let paddingString = "".padding(toLength: paddingLength, withPad: " ", startingAt: 0)

        navigationItem.backBarButtonItem = UIBarButtonItem(title: paddingString,
                                                           style: .plain,
                                                           target: nil,
                                                           action: nil,
                                                           accessibilityIdentifier: "back")
    }

    func applyArchiveBackButton() {
        AssertIsOnMainThread()

        navigationItem.backBarButtonItem = UIBarButtonItem(title: CommonStrings.backButton,
                                                           style: .plain,
                                                           target: nil,
                                                           action: nil,
                                                           accessibilityIdentifier: "back")
    }

    // MARK: - Previews

    func canPresentPreview(fromIndexPath indexPath: IndexPath?) -> Bool {
        AssertIsOnMainThread()

        guard !tableView.isEditing else {
            return false
        }
        guard let indexPath = indexPath else {
            return false
        }
        guard let section = ChatListSection(rawValue: indexPath.section) else {
            owsFailDebug("Invalid section: \(indexPath.section).")
            return false
        }
        switch section {
        case .pinned, .unpinned:
            let currentSelectedThreadId = self.conversationSplitViewController?.selectedThread?.uniqueId
            if self.thread(forIndexPath: indexPath)?.uniqueId == currentSelectedThreadId {
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
        self.lastViewedThread = threadViewModel.threadRecord

        let vc = ConversationViewController(threadViewModel: threadViewModel,
                                            action: .none,
                                            focusMessageId: nil)
        vc.previewSetup()
        return vc
    }

    func commitPreviewController(_ previewController: UIViewController) {
        AssertIsOnMainThread()

        guard let previewController = previewController as? ConversationViewController else {
            owsFailDebug("Invalid previewController: \(type(of: previewController))")
            return
        }
        present(previewController.thread, action: .none, animated: false)
    }
}
