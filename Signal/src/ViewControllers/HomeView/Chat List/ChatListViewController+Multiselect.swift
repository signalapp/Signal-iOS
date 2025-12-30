//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

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
        if viewState.chatListMode == .inbox {
            let doneButton: UIBarButtonItem = .cancelButton { [weak self] in
                self?.done()
            }
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
        loadCoordinator.loadIfNecessary(shouldForceLoad: true)
    }

    func leaveMultiselectMode() {
        AssertIsOnMainThread()

        guard viewState.multiSelectState.isActive else {
            return
        }

        if viewState.chatListMode == .archive {
            owsAssertDebug(navigationItem.rightBarButtonItem != nil, "can't change label of right bar button")
            navigationItem.rightBarButtonItem?.title = CommonStrings.selectButton
            navigationItem.rightBarButtonItem?.accessibilityHint = CommonStrings.selectButton
        }
        searchBar.isUserInteractionEnabled = true
        searchBar.alpha = 1
        viewState.multiSelectState.setIsActive(false, tableView: tableView)
        title = viewState.multiSelectState.title
        hideToolbar()
        loadCoordinator.loadIfNecessary(shouldForceLoad: true)

        if let lastViewedThreadUniqueId, isConversationActive(threadUniqueId: lastViewedThreadUniqueId) {
            ensureSelectedThreadUniqueId(lastViewedThreadUniqueId, animated: false)
        }
    }

    func showToolbar() {
        AssertIsOnMainThread()

        if #available(iOS 26, *), BuildFlags.iOS26SDKIsAvailable {
            self.updateCaptions()
            self.navigationController?.setToolbarHidden(false, animated: true)
            (self.tabBarController as? HomeTabBarController)?.setTabBarHidden(true)
            return
        }

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
                    self.viewState.multiSelectState.toolbar?.toolbar.setItems(
                        self.makeToolbarButtons(),
                        animated: false,
                    )
                }
                UIView.animate(withDuration: 0.25, animations: {
                    tbc.alpha = 1
                }) { [weak self] _ in
                    self?.tableView.contentSize.height += tbc.height
                }
            }
            if
                viewState.chatListMode == .inbox,
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

    @objc
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
        updateCaptions()
        leaveMultiselectMode()
        updateBarButtonItems()
        updateViewState()
        if viewState.chatListMode == .archive {
            navigationItem.rightBarButtonItem?.title = CommonStrings.selectButton
        }
    }

    private func makeToolbarButtons() -> [UIBarButtonItem] {
        let hasSelectedEntries = !(tableView.indexPathsForSelectedRows ?? []).isEmpty

        let archiveBtn = UIBarButtonItem(
            title: viewState.chatListMode == .archive ? CommonStrings.unarchiveAction : CommonStrings.archiveAction,
            style: .plain,
            target: self,
            action: #selector(performArchive),
        )
        if #available(iOS 26, *), BuildFlags.iOS26SDKIsAvailable {
            archiveBtn.image = UIImage(resource: .archive)
        }
        archiveBtn.isEnabled = hasSelectedEntries

        let readButton: UIBarButtonItem
        if hasSelectedEntries {
            readButton = UIBarButtonItem(title: CommonStrings.readAction, style: .plain, target: self, action: #selector(performRead))
            readButton.isEnabled = false
            for path in tableView.indexPathsForSelectedRows ?? [] {
                if let thread = tableDataSource.threadViewModel(forIndexPath: path), thread.hasUnreadMessages {
                    readButton.isEnabled = true
                    break
                }
            }
        } else {
            func hasUnreadEntry(threadUniqueIds: [String]) -> Bool {
                return threadUniqueIds.contains {
                    tableDataSource.threadViewModel(threadUniqueId: $0).hasUnreadMessages
                }
            }

            readButton = UIBarButtonItem(
                title: OWSLocalizedString(
                    "HOME_VIEW_TOOLBAR_READ_ALL",
                    comment: "Title 'Read All' button in the toolbar of the ChatList if multi-section is active.",
                ),
                style: .plain,
                target: self,
                action: #selector(performReadAll),
            )
            readButton.isEnabled = false
            readButton.isEnabled = readButton.isEnabled || hasUnreadEntry(threadUniqueIds: renderState.pinnedThreadUniqueIds)
            readButton.isEnabled = readButton.isEnabled || hasUnreadEntry(threadUniqueIds: renderState.unpinnedThreadUniqueIds)
        }

        let deleteBtn = UIBarButtonItem(title: CommonStrings.deleteButton, style: .plain, target: self, action: #selector(performDelete))
        if #available(iOS 26, *), BuildFlags.iOS26SDKIsAvailable {
            deleteBtn.image = UIImage(resource: .trash)
        }
        deleteBtn.isEnabled = hasSelectedEntries

        var entries: [UIBarButtonItem] = []
        for button in [archiveBtn, readButton, deleteBtn] {
            if !entries.isEmpty {
                entries.append(.flexibleSpace())
            }
            entries.append(button)
        }
        return entries
    }

    private func hideToolbar() {
        AssertIsOnMainThread()

        if #available(iOS 26, *), BuildFlags.iOS26SDKIsAvailable {
            (self.tabBarController as? HomeTabBarController)?.setTabBarHidden(false)
            self.navigationController?.setToolbarHidden(true, animated: true)
            return
        }

        if let toolbar = viewState.multiSelectState.toolbar {
            UIView.animate(withDuration: 0.25) { [weak self] in
                toolbar.alpha = 0
                if let tableView = self?.tableView {
                    // remove the extra space for the toolbar if necessary
                    tableView.contentSize.height = tableView.sizeThatFitsMaxSize.height
                }
            } completion: { [weak self] _ in
                toolbar.removeFromSuperview()
                self?.viewState.multiSelectState.toolbar = nil
                if
                    self?.viewState.chatListMode == .inbox,
                    let tabController = self?.tabBarController as? HomeTabBarController
                {
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
            let format = OWSLocalizedString(
                "MESSAGE_ACTIONS_TOOLBAR_CAPTION_%d",
                tableName: "PluralAware",
                comment: "Label for the toolbar used in the multi-select mode. The number of selected items (1 or more) is passed.",
            )
            title = String.localizedStringWithFormat(format, count)
        }

        if #available(iOS 26, *), BuildFlags.iOS26SDKIsAvailable {
            toolbarItems = makeToolbarButtons()
        } else {
            viewState.multiSelectState.toolbar?.toolbar.setItems(
                makeToolbarButtons(),
                animated: false,
            )
        }
    }

    // MARK: toolbar button actions

    /// Archives or unarchives the selected threads
    @objc
    func performArchive() {
        performOn(indexPaths: tableView.indexPathsForSelectedRows ?? []) { threadViewModels in
            for threadViewModel in threadViewModels {
                archiveThread(threadViewModel: threadViewModel, closeConversationBlock: nil)
            }
        }
        done()
    }

    @objc
    func performRead() {
        performOn(indexPaths: tableView.indexPathsForSelectedRows ?? []) { threadViewModels in
            for threadViewModel in threadViewModels {
                markThreadAsRead(threadViewModel: threadViewModel)
            }
        }
        done()
    }

    @objc
    func performReadAll() {
        let threadUniqueIds = renderState.pinnedThreadUniqueIds + renderState.unpinnedThreadUniqueIds
        let threadViewModels = threadUniqueIds.compactMap { threadUniqueId in
            let threadViewModel = tableDataSource.threadViewModel(threadUniqueId: threadUniqueId)
            return threadViewModel.hasUnreadMessages ? threadViewModel : nil
        }

        performOn(threadViewModels: threadViewModels) { threadViewModels in
            for threadViewModel in threadViewModels {
                markThreadAsRead(threadViewModel: threadViewModel)
            }
        }
        done()
    }

    @objc
    func performDelete() {
        AssertIsOnMainThread()

        guard !(tableView.indexPathsForSelectedRows ?? []).isEmpty else {
            return
        }

        let db = DependenciesBridge.shared.db
        let threadSoftDeleteManager = DependenciesBridge.shared.threadSoftDeleteManager

        /// We need to grab these now, since they'll be `nil`-ed out when we
        /// show the modal spinner below.
        let selectedIndexPaths = tableView.indexPathsForSelectedRows ?? []

        let title: String
        let message: String
        let labelFormat = OWSLocalizedString(
            "CONVERSATION_DELETE_CONFIRMATIONS_ALERT_TITLE_%d",
            tableName: "PluralAware",
            comment: "Title for the 'conversations delete confirmation' alert for multiple messages. Embeds: {{ %@ the number of currently selected items }}.",
        )
        title = String.localizedStringWithFormat(labelFormat, selectedIndexPaths.count)
        let messageFormat = OWSLocalizedString(
            "CONVERSATION_DELETE_CONFIRMATION_ALERT_MESSAGES_%d",
            tableName: "PluralAware",
            comment: "Message for the 'conversations delete confirmation' alert for multiple messages.",
        )
        message = String.localizedStringWithFormat(messageFormat, selectedIndexPaths.count)

        let alert = ActionSheetController(title: title, message: message)
        alert.addAction(ActionSheetAction(
            title: CommonStrings.deleteButton,
            style: .destructive,
        ) { [weak self] _ in
            guard let self else { return }

            // This deletion can be quite intensive, so we'll wrap the whole
            // thing in a UI-blocking modal.
            ModalActivityIndicatorViewController.present(
                fromViewController: self,
                canCancel: false,
            ) { modal in
                // We want to protect this whole operation with a single write
                // transaction, to ensure the contents of the threads don't
                // change as we're deleting them.
                db.write { transaction in
                    self.performOn(indexPaths: selectedIndexPaths) { threadViewModels in
                        threadSoftDeleteManager.softDelete(
                            threads: threadViewModels.map { $0.threadRecord },
                            sendDeleteForMeSyncMessage: true,
                            tx: transaction,
                        )
                    }
                }
                DispatchQueue.main.async {
                    modal.dismiss()
                }
            }

            self.done()
        })
        alert.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(alert)
    }

    private func performOn(indexPaths: [IndexPath], action: ([ThreadViewModel]) -> Void) {
        let threadViewModels = indexPaths.compactMap(tableDataSource.threadViewModel(forIndexPath:))
        performOn(threadViewModels: threadViewModels, action: action)
    }

    private func performOn(threadViewModels: [ThreadViewModel], action: ([ThreadViewModel]) -> Void) {
        guard !threadViewModels.isEmpty else { return }

        viewState.multiSelectState.actionPerformed = true
        action(threadViewModels)
    }
}

// MARK: - object encapsulating the complete state of the MultiSelect process

public class MultiSelectState {

    static let multiSelectionModeDidChange = Notification.Name("multiSelectionModeDidChange")

    fileprivate var title: String?
    fileprivate var toolbar: BlurredToolbarContainer?
    private var _isActive = false
    var actionPerformed = false
    var locked = false

    var isActive: Bool { return _isActive }

    fileprivate func setIsActive(_ active: Bool, tableView: UITableView? = nil, cancelCurrentEditAction: Bool = true) {
        if active != _isActive {
            AssertIsOnMainThread()

            _isActive = active
            // turn off current edit mode if necessary (removes leading and trailing actions)
            if let tableView, active && tableView.isEditing && cancelCurrentEditAction {
                tableView.setEditing(false, animated: true)
            }
            if active || !actionPerformed {
                tableView?.setEditing(active, animated: true)
            } else if let tableView {
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
