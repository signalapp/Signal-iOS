//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

// TODO: Decompose into multiple source files?
@objc
public extension ConversationListViewController {

    var renderState: HVRenderState { viewState.tableDataSource.renderState }

    func threadViewModel(forThread thread: TSThread) -> ThreadViewModel {
        renderState.threadViewModel(forThread: thread)
    }

    func thread(forIndexPath indexPath: IndexPath) -> TSThread? {
        renderState.thread(forIndexPath: indexPath)
    }

    func threadViewModel(forIndexPath indexPath: IndexPath) -> ThreadViewModel? {
        renderState.threadViewModel(forIndexPath: indexPath)
    }

    // MARK: - Accessors with side effects

    var hasVisibleReminders: Bool {
        get { viewState.hasVisibleReminders }
        set {
            guard viewState.hasVisibleReminders != newValue else {
                return
            }
            viewState.hasVisibleReminders = newValue

            // If the reminders show/hide, reload the table.
            self.lastReloadDate = Date()
            tableView.reloadData()
        }
    }

    var isViewVisible: Bool {
        get { viewState.isViewVisible }
        set {
            viewState.isViewVisible = newValue

            updateShouldObserveDBModifications()
        }
    }

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

    func showArchivedConversations() {
        AssertIsOnMainThread()

        owsAssertDebug(self.conversationListMode == .inbox)

        // When showing archived conversations, we want to use a conventional "back" button
        // to return to the "inbox" conversation list.
        applyArchiveBackButton()

        // Push a separate instance of this view using "archive" mode.
        let conversationList = ConversationListViewController()
        conversationList.conversationListMode = .archive

        // TODO: What is this?
        self.show(conversationList, sender: self)
    }

    var presentedConversationListViewController: ConversationListViewController? {
        AssertIsOnMainThread()

        guard let topViewController = navigationController?.topViewController as? ConversationListViewController,
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

        guard let indexPath = indexPath else {
            return false
        }
        guard let section = HomeViewSection(rawValue: indexPath.section) else {
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
