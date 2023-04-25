//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import UIKit

@objc
extension ChatListViewController {

    // MARK: - multi select mode

    func willEnterMultiselectMode() {
        willEnterMultiselectMode(cancelCurrentEditAction: true)
    }

    func willEnterMultiselectMode(cancelCurrentEditAction: Bool) {
        AssertIsOnMainThread()

        guard !viewState.multiSelectState.isActive else {
            return
        }

        // multi selection does not work well with displaying search results, so let's clear the search for now
        searchBar.delegate?.searchBarCancelButtonClicked?(searchBar)
        viewState.multiSelectState.title = title
        if chatListMode == .inbox {
            let doneButton = UIBarButtonItem(title: CommonStrings.cancelButton, style: .plain, target: self, action: #selector(done), accessibilityIdentifier: CommonStrings.cancelButton)
            navigationItem.setLeftBarButton(doneButton, animated: true)
            navigationItem.setRightBarButtonItems(nil, animated: true)
        } else {
            owsAssertDebug(navigationItem.rightBarButtonItem != nil, "can't change label of right bar button")
            navigationItem.rightBarButtonItem?.title = CommonStrings.doneButton
            navigationItem.rightBarButtonItem?.accessibilityHint = CommonStrings.doneButton
        }
        searchBar.isUserInteractionEnabled = false
        searchBar.alpha = 0.5
        viewState.multiSelectState.setIsActive(true, tableView: tableView, cancelCurrentEditAction: cancelCurrentEditAction)
        showToolbar()
    }

    func leaveMultiselectMode() {
        AssertIsOnMainThread()

        guard viewState.multiSelectState.isActive else {
            return
        }

        if chatListMode == .archive {
            owsAssertDebug(navigationItem.rightBarButtonItem != nil, "can't change label of right bar button")
            navigationItem.rightBarButtonItem?.title = CommonStrings.selectButton
            navigationItem.rightBarButtonItem?.accessibilityHint = CommonStrings.selectButton
        }
        searchBar.isUserInteractionEnabled = true
        searchBar.alpha = 1
        viewState.multiSelectState.setIsActive(false, tableView: tableView)
        title = viewState.multiSelectState.title
        hideToolbar()
    }

    func showToolbar() {
        AssertIsOnMainThread()

        if viewState.multiSelectState.toolbar == nil {
            let tbc = BlurredToolbarContainer()
            tbc.alpha = 0
            view.addSubview(tbc)
            tbc.autoPinWidthToSuperview()
            tbc.autoPinEdge(toSuperviewEdge: .bottom)
            viewState.multiSelectState.toolbar = tbc
            let animateToolbar = {
                // Hack to get the toolbar to update its safe area correctly after any
                // tab bar hidden state changes. Unclear why this is needed or why it needs
                // to be async, but without it the toolbar inherits stale safe area insets from
                // its parent, and its own safe area doesn't line up.
                DispatchQueue.main.async {
                    self.adjustToolbarButtons(self.viewState.multiSelectState.toolbar?.toolbar)
                }
                UIView.animate(withDuration: 0.25, animations: {
                    tbc.alpha = 1
                }) { [weak self] (_) in
                    self?.tableView.contentSize.height += tbc.height
                }
            }
            if
                self.chatListMode == .inbox,
                StoryManager.areStoriesEnabled,
                let tabController = self.tabBarController as? HomeTabBarController
            {
                tabController.setTabBarHidden(true, animated: true, duration: 0.1) { _ in
                    animateToolbar()
                }
            } else {
                animateToolbar()
            }
        }
        updateCaptions()
    }

    func switchMultiSelectState(_ sender: UIBarButtonItem) {
        AssertIsOnMainThread()

        if viewState.multiSelectState.isActive {
            leaveMultiselectMode()
        } else {
            willEnterMultiselectMode()
        }
    }

    // MARK: - theme changes

    func applyThemeToContextMenuAndToolbar() {
        viewState.multiSelectState.toolbar?.themeChanged()
    }

    // MARK: private helper

    private func done() {
        leaveMultiselectMode()
        updateBarButtonItems()
        if self.chatListMode == .archive {
            navigationItem.rightBarButtonItem?.title = CommonStrings.selectButton
        }
    }

    private func adjustToolbarButtons(_ toolbar: UIToolbar?) {
        let hasSelectedEntries = !(tableView.indexPathsForSelectedRows ?? []).isEmpty

        let archiveBtn = UIBarButtonItem(
            title: chatListMode == .archive ? CommonStrings.unarchiveAction : CommonStrings.archiveAction,
            style: .plain, target: self, action: #selector(performUnarchive))
        archiveBtn.isEnabled = hasSelectedEntries

        let readButton: UIBarButtonItem
        if hasSelectedEntries {
            readButton = UIBarButtonItem(title: CommonStrings.readAction, style: .plain, target: self, action: #selector(performRead))
            readButton.isEnabled = false
            for path in tableView.indexPathsForSelectedRows ?? [] {
                if let thread = tableDataSource.threadViewModel(forIndexPath: path, expectsSuccess: false), thread.hasUnreadMessages {
                    readButton.isEnabled = true
                    break
                }
            }
        } else {
            readButton = UIBarButtonItem(title: OWSLocalizedString("HOME_VIEW_TOOLBAR_READ_ALL", comment: "Title 'Read All' button in the toolbar of the ChatList if multi-section is active."), style: .plain, target: self, action: #selector(performReadAll))
            readButton.isEnabled = hasUnreadEntry(threads: Array(renderState.pinnedThreads.orderedValues)) || hasUnreadEntry(threads: Array(renderState.unpinnedThreads))
        }

        let deleteBtn = UIBarButtonItem(title: CommonStrings.deleteButton, style: .plain, target: self, action: #selector(performDelete))
        deleteBtn.isEnabled = hasSelectedEntries

        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        var entries: [UIBarButtonItem] = []
        for button in [archiveBtn, readButton, deleteBtn] {
            if !entries.isEmpty {
                entries.append(spacer)
            }
            entries.append(button)
        }
        toolbar?.setItems(entries, animated: false)
    }

    private func hasUnreadEntry(threads: [TSThread]? = nil) -> Bool {
        if let entries = threads {
            for entry in entries {
                if tableDataSource.threadViewModel(forThread: entry).hasUnreadMessages {
                    return true
                }
            }
        }
        return false
    }

    private func hideToolbar() {
        AssertIsOnMainThread()

        if let toolbar = viewState.multiSelectState.toolbar {
            UIView.animate(withDuration: 0.25) { [weak self] in
                toolbar.alpha = 0
                if let tableView = self?.tableView {
                    // remove the extra space for the toolbar if necessary
                    tableView.contentSize.height = tableView.sizeThatFitsMaxSize.height
                }
            } completion: { [weak self] (_) in
                toolbar.removeFromSuperview()
                self?.viewState.multiSelectState.toolbar = nil
                if self?.chatListMode == .inbox, StoryManager.areStoriesEnabled, let tabController = self?.tabBarController as? HomeTabBarController {
                    tabController.setTabBarHidden(false, animated: true, duration: 0.1)
                }
            }
        }
    }

    public func updateCaptions() {
        AssertIsOnMainThread()

        let count = tableView.indexPathsForSelectedRows?.count ?? 0
        if count == 0 {
            title = viewState.multiSelectState.title
        } else {
            let format = OWSLocalizedString("MESSAGE_ACTIONS_TOOLBAR_CAPTION_%d", tableName: "PluralAware",
                                           comment: "Label for the toolbar used in the multi-select mode. The number of selected items (1 or more) is passed.")
            title = String.localizedStringWithFormat(format, count)
        }
        adjustToolbarButtons(viewState.multiSelectState.toolbar?.toolbar)
    }

    // MARK: toolbar button actions

    func performArchive() {
        performOnAllSelectedEntries { thread in
            archiveThread(threadViewModel: thread, closeConversationBlock: nil)
        }
        done()
    }

    func performUnarchive() {
        performOnAllSelectedEntries { thread in
            archiveThread(threadViewModel: thread, closeConversationBlock: nil)
        }
        done()
    }

    func performRead() {
        performOnAllSelectedEntries { thread in
            markThreadAsRead(threadViewModel: thread)
        }
        done()
    }

    func performReadAll() {
        var entries: [ThreadViewModel] = []
        var threads = Array(renderState.pinnedThreads.orderedValues)
        threads.append(contentsOf: renderState.unpinnedThreads)
        for t in threads {
            let thread = tableDataSource.threadViewModel(forThread: t)
            if thread.hasUnreadMessages {
                entries.append(thread)
            }
        }

        performOn(entries: entries) { thread in
            markThreadAsRead(threadViewModel: thread)
        }
        done()
    }

    func performDelete() {
        AssertIsOnMainThread()

        guard !(tableView.indexPathsForSelectedRows ?? []).isEmpty else {
            return
        }

        let title: String
        let message: String
        let count = tableView.indexPathsForSelectedRows?.count ?? 0
        let labelFormat = OWSLocalizedString("CONVERSATION_DELETE_CONFIRMATIONS_ALERT_TITLE_%d", tableName: "PluralAware",
                                            comment: "Title for the 'conversations delete confirmation' alert for multiple messages. Embeds: {{ %@ the number of currently selected items }}.")
        title = String.localizedStringWithFormat(labelFormat, count)
        let messageFormat = OWSLocalizedString("CONVERSATION_DELETE_CONFIRMATION_ALERT_MESSAGES_%d", tableName: "PluralAware",
                                              comment: "Message for the 'conversations delete confirmation' alert for multiple messages.")
        message = String.localizedStringWithFormat(messageFormat, count)

        let alert = ActionSheetController(title: title, message: message)
        alert.addAction(ActionSheetAction(title: CommonStrings.deleteButton,
                                          style: .destructive) { [weak self] _ in
            self?.performOnAllSelectedEntries { thread in
                self?.deleteThread(threadViewModel: thread, closeConversationBlock: nil)
            }
            self?.done()
        })
        alert.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(alert)
    }

    private func performOnAllSelectedEntries(action: ((ThreadViewModel) -> Void)) {
        var entries: [ThreadViewModel] = []
        for path in tableView.indexPathsForSelectedRows ?? [] {
            if let thread = tableDataSource.threadViewModel(forIndexPath: path, expectsSuccess: false) {
                entries.append(thread)
            }
        }
        performOn(entries: entries, action: action)
    }

    private func performOn(entries: [ThreadViewModel]?, action: ((ThreadViewModel) -> Void)) {
        for thread in entries ?? [] {
            viewState.multiSelectState.actionPerformed = true
            action(thread)
        }
        updateCaptions()
    }
}

// MARK: - object encapsulating the complete state of the MultiSelect process
@objc
public class MultiSelectState: NSObject {
    @objc
    public static let multiSelectionModeDidChange = Notification.Name("multiSelectionModeDidChange")

    fileprivate var title: String?
    fileprivate var toolbar: BlurredToolbarContainer?
    private var _isActive = false
    var actionPerformed = false
    var locked = false

    @objc
    var isActive: Bool { return _isActive }

    fileprivate func setIsActive(_ active: Bool, tableView: UITableView? = nil, cancelCurrentEditAction: Bool = true) {
        if active != _isActive {
            AssertIsOnMainThread()

            _isActive = active
            // turn off current edit mode if necessary (removes leading and trailing actions)
            if let tableView = tableView, active && tableView.isEditing && cancelCurrentEditAction {
                tableView.setEditing(false, animated: true)
            }
            if active || !actionPerformed {
                tableView?.setEditing(active, animated: true)
            } else if let tableView = tableView {
                // The animation of unsetting the setEditing flag will be performed
                // in the tableView.beginUpdates/endUpdates block (called in applyPartialLoadResult).
                // This results in a nice combined animation.
                // The following code is usually not needed and serves only as an
                // emergency exit if the provided mechanism does not work.
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1) {
                    if tableView.isEditing {
                        tableView.setEditing(active, animated: false)
                    }
                }
            }
            actionPerformed = false
            NotificationCenter.default.post(name: Self.multiSelectionModeDidChange, object: active)
        }
    }
}
