//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

extension HomeViewController {

    @objc
    func showOrHideMenu(_ sender: UIButton) {
        AssertIsOnMainThread()

        if viewState.multiSelectState.parentButton == nil {
            showMenu(button: sender)
        } else {
            hideMenu()
        }
    }

    @objc
    func willEnterMultiselectMode() {
        AssertIsOnMainThread()

        viewState.multiSelectState.title = title
        if homeViewMode == .inbox {
            let doneButton = UIBarButtonItem(title: CommonStrings.cancelButton, style: .plain, target: self, action: #selector(done), accessibilityIdentifier: CommonStrings.cancelButton)
            navigationItem.setLeftBarButton(doneButton, animated: true)
            navigationItem.setRightBarButtonItems(nil, animated: true)
        }
        tableView.allowsSelectionDuringEditing = true
        tableView.allowsMultipleSelectionDuringEditing = true
        showToolbar()
    }

    @objc
    func showToolbar() {
        AssertIsOnMainThread()

        viewState.multiSelectState.setIsActive(true, tableView: tableView)
        if let nav = navigationController {
            if nav.isToolbarHidden {
                adjustNavigationBarTitles(nav.toolbar)
                nav.setToolbarHidden(false, animated: true)
            }
            nav.toolbar.barTintColor = Theme.isDarkThemeEnabled ? .ows_blackAlpha40 : .ows_whiteAlpha40
            nav.toolbar.tintColor = Theme.primaryTextColor
        }
        updateCaptions()
    }

    @objc
    func switchMultiSelectState(_ sender: UIBarButtonItem) {
        if viewState.multiSelectState.isActive {
            sender.title = CommonStrings.selectButton
            hideToolbar()
        } else {
            sender.title = CommonStrings.doneButton
            willEnterMultiselectMode()
        }
    }

    // MARK: private helper

    private func showMenu(button: UIButton) {
        AssertIsOnMainThread()

        guard viewState.multiSelectState.contextMenuView == nil else {
            return
        }

        var contextMenuActions: [ContextMenuAction] = []
        if renderState.inboxCount > 0 {
            contextMenuActions.append(
                ContextMenuAction(title: NSLocalizedString("HOME_VIEW_TITLE_SELECT_MESSAGES", comment: "Title for the 'Select Messages' option in the HomeView."), image: Theme.isDarkThemeEnabled ? UIImage(named: "check-circle-solid-24")?.tintedImage(color: .white) : UIImage(named: "check-circle-outline-24"), attributes: [], handler: { [weak self] (_) in
                    self?.hideMenu()
                    self?.willEnterMultiselectMode()
                }))
        }
        contextMenuActions.append(
            ContextMenuAction(title: CommonStrings.openSettingsButton, image: Theme.isDarkThemeEnabled ? UIImage(named: "settings-solid-24")?.tintedImage(color: .white) : UIImage(named: "settings-outline-24"), attributes: [], handler: { [weak self] (_) in
                self?.hideMenu()
                self?.showAppSettings(mode: .none)
            }))
        if renderState.archiveCount > 1 {
            contextMenuActions.append(
                ContextMenuAction(title: NSLocalizedString("HOME_VIEW_TITLE_ARCHIVE", comment: "Title for the conversation list's 'archive' mode."), image: Theme.isDarkThemeEnabled ? UIImage(named: "archive-solid-24")?.tintedImage(color: .white) : UIImage(named: "archive-outline-24"), attributes: [], handler: { [weak self] (_) in
                    self?.hideMenu()
                    self?.showArchivedConversations(offerMultiSelectMode: true)
                }))
        }

        viewState.multiSelectState.parentButton = button
        let v = ContextMenuActionsView(menu: ContextMenu(contextMenuActions))
        let size = v.sizeThatFitsMaxSize
        v.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        v.delegate = self

        viewState.multiSelectState.contextMenuView = ContextMenuActionsViewContainer(v)
        viewState.multiSelectState.contextMenuView?.alpha = 0
        view.addSubview(viewState.multiSelectState.contextMenuView!)
        viewState.multiSelectState.contextMenuView?.autoPinEdgesToSuperviewSafeArea()
        viewState.multiSelectState.contextMenuView?.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(hideMenu)))
        UIView.animate(withDuration: 0.25) { [weak self] in
            self?.viewState.multiSelectState.parentButton?.alpha = 0.4
            self?.viewState.multiSelectState.contextMenuView?.alpha = 1
        }
    }

    @objc
    private func done() {
        AssertIsOnMainThread()

        hideToolbar()
        if self.homeViewMode == .archive {
            self.navigationController?.popViewController(animated: true)
        } else {
            updateBarButtonItems()
        }
    }

    @objc
    private func hideMenu() {
        AssertIsOnMainThread()

        UIView.animate(withDuration: 0.25, animations: { [weak self] in
            self?.viewState.multiSelectState.parentButton?.alpha = 1
            self?.viewState.multiSelectState.contextMenuView?.alpha = 0
        }, completion: { [weak self] (_) in
            self?.viewState.multiSelectState.parentButton = nil
            self?.viewState.multiSelectState.contextMenuView?.removeFromSuperview()
            self?.viewState.multiSelectState.contextMenuView = nil
        })
    }

    private func adjustNavigationBarTitles(_ toolbar: UIToolbar?) {
        let hasSelectedEntries = !(tableView.indexPathsForSelectedRows ?? []).isEmpty

        let archiveBtn = UIBarButtonItem(title: homeViewMode == .archive ? CommonStrings.unarchiveAction : CommonStrings.archiveAction, style: .plain, target: self, action: #selector(performUnarchive))
        archiveBtn.isEnabled = hasSelectedEntries
        var buttons: [UIBarButtonItem] = [archiveBtn]
        if !hasSelectedEntries {
            let btn = UIBarButtonItem(title: NSLocalizedString("HOME_VIEW_TOOLBAR_READ_ALL", comment: "Title 'Read All' button in the toolbar of the homeview if multi-section is active."), style: .plain, target: self, action: #selector(performReadAll))
            btn.isEnabled = hasUnreadEntry(threads: Array(renderState.pinnedThreads.orderedValues)) || hasUnreadEntry(threads: Array(renderState.unpinnedThreads))
            buttons.append(btn)
        } else {
            let btn = UIBarButtonItem(title: CommonStrings.readAction, style: .plain, target: self, action: #selector(performRead))
            btn.isEnabled = false
            for path in tableView.indexPathsForSelectedRows ?? [] {
                if let thread = tableDataSource.threadViewModel(forIndexPath: path), thread.isMarkedUnread {
                    btn.isEnabled = true
                    break
                }
            }
            buttons.append(btn)
        }
        let deleteBtn = UIBarButtonItem(title: CommonStrings.deleteButton, style: .plain, target: self, action: #selector(performDelete))
        deleteBtn.isEnabled = hasSelectedEntries
        buttons.append(deleteBtn)

        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        var entries: [UIBarButtonItem] = [spacer]
        for button in buttons {
            entries.append(button)
            entries.append(spacer)
        }
        toolbar?.setItems(entries, animated: false)
    }

    private func hasUnreadEntry(threads: [TSThread]? = nil) -> Bool {
        if let entries = threads {
            for entry in entries {
                if tableDataSource.threadViewModel(forThread: entry).isMarkedUnread {
                    return true
                }
            }
        }
        return false
    }

    private func hideToolbar() {
        AssertIsOnMainThread()

        tableView.allowsSelectionDuringEditing = false
        tableView.allowsMultipleSelectionDuringEditing = false
        viewState.multiSelectState.setIsActive(false, tableView: tableView)

        navigationController?.setToolbarHidden(true, animated: true)
        navigationController?.toolbar.setItems(nil, animated: false)
        title = viewState.multiSelectState.title
    }

    public func updateCaptions() {
        AssertIsOnMainThread()

        for item in navigationController?.toolbar.items ?? [] {
            item.isEnabled = item.target != nil && !(tableView.indexPathsForSelectedRows ?? []).isEmpty
        }

        let count = tableView.indexPathsForSelectedRows?.count ?? 0
        if count == 0 {
            title = viewState.multiSelectState.title
        } else if count == 1 {
            title = NSLocalizedString("MESSAGE_ACTIONS_TOOLBAR_LABEL_1", comment: "Label for the toolbar used in the multi-select mode of conversation view when 1 item is selected.")
        } else {
            let labelFormat = NSLocalizedString("MESSAGE_ACTIONS_TOOLBAR_LABEL_N_FORMAT", comment: "Format for the toolbar used in the multi-select mode of conversation view. Embeds: {{ %@ the number of currently selected items }}.")
            title = String(format: labelFormat, OWSFormat.formatInt(count))
        }
        adjustNavigationBarTitles(navigationController?.toolbar)
    }

    // MARK: toolbar button actions

    @objc
    func performArchive() {
        performOnAllSelectedEntries { thread in
            archiveThread(threadViewModel: thread, closeConversationBlock: nil)
        }
        done()
    }

    @objc
    func performUnarchive() {
        performOnAllSelectedEntries { thread in
            archiveThread(threadViewModel: thread, closeConversationBlock: nil)
        }
        done()
    }

    @objc
    func performRead() {
        performOnAllSelectedEntries { thread in
            markThreadRead(threadViewModel: thread)
        }
        done()
    }

    @objc
    func performReadAll() {
        var entries: [ThreadViewModel] = []
        var threads = Array(renderState.pinnedThreads.orderedValues)
        threads.append(contentsOf: renderState.unpinnedThreads)
        for t in threads {
            let thread = tableDataSource.threadViewModel(forThread: t)
            if thread.isMarkedUnread {
                entries.append(thread)
            }
        }

        performOn(entries: entries) { thread in
            markThreadRead(threadViewModel: thread)
        }
        done()
    }

    @objc
    func performDelete() {
        AssertIsOnMainThread()

        guard !(tableView.indexPathsForSelectedRows ?? []).isEmpty else {
            return
        }

        let title: String
        let message: String
        let count = tableView.indexPathsForSelectedRows?.count ?? 0
        if count > 1 {
            let labelFormat = NSLocalizedString("CONVERSATION_DELETE_CONFIRMATIONS_ALERT_TITLE",
                                                comment: "Title for the 'conversations delete confirmation' alert for multiple messages. Embeds: {{ %@ the number of currently selected items }}.")
            title = String(format: labelFormat, OWSFormat.formatInt(count))
            message = NSLocalizedString("CONVERSATION_DELETE_CONFIRMATION_ALERT_MESSAGES",
                                        comment: "Message for the 'conversations delete confirmation' alert for multiple messages.")
        } else {
            title = NSLocalizedString("CONVERSATION_DELETE_CONFIRMATION_ALERT_TITLE",
                                      comment: "Title for the 'conversation delete confirmation' alert.")
            message = NSLocalizedString("CONVERSATION_DELETE_CONFIRMATION_ALERT_MESSAGE",
                                        comment: "Message for the 'conversation delete confirmation' alert.")
        }

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
            if let thread = tableDataSource.threadViewModel(forIndexPath: path) {
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

// MARK: - implementation of ContextMenuActionsViewDelegate
extension HomeViewController: ContextMenuActionsViewDelegate {
    func contextMenuActionViewDidSelectAction(contextMenuAction: ContextMenuAction) {
        contextMenuAction.handler(contextMenuAction)
    }
}

// MARK: - view helper class (providing a rounded view *with* a shadow)
private class ContextMenuActionsViewContainer: UIView {
    required init(_ child: UIView) {
        super.init(frame: child.frame)
        let frame = child.bounds
        let radius = child.layer.cornerRadius
        let shadowView = UIView(frame: CGRect(x: radius,
                                              y: radius,
                                              width: frame.width - 2 * radius,
                                              height: frame.height - 2 * radius))
        shadowView.backgroundColor = Theme.isDarkThemeEnabled ? .black : .white
        shadowView.setShadow(radius: 40, opacity: 0.3, offset: CGSize(width: 8, height: 20))
        child.frame = frame
        self.addSubview(shadowView)
        self.addSubview(child)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - object encapsulating the complete state of the MultiSelect process
@objc
public class MultiSelectState: NSObject {
    fileprivate var parentButton: UIButton?
    fileprivate var title: String?
    fileprivate var contextMenuView: ContextMenuActionsViewContainer?
    private var _isActive = false
    var actionPerformed = false

    @objc
    var isActive: Bool { return _isActive}

    fileprivate func setIsActive(_ active: Bool, tableView: UITableView? = nil) {
        if active != _isActive {
            _isActive = active
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
        }
    }
}
