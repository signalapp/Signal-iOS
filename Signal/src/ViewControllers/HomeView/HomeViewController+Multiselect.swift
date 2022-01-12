//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
extension HomeViewController {

    func showOrHideMenu(_ sender: UIButton) {
        AssertIsOnMainThread()

        if viewState.multiSelectState.parentButton == nil {
            showMenu(button: sender)
        } else {
            hideMenu()
        }
    }

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
        searchBar.isUserInteractionEnabled = false
        searchBar.alpha = 0.5
        showToolbar()
    }

    func leaveMultiselectMode() {
        AssertIsOnMainThread()

        hideToolbar()
    }

    func showToolbar() {
        AssertIsOnMainThread()

        viewState.multiSelectState.setIsActive(true, tableView: tableView)
        if viewState.multiSelectState.toolbar == nil {
            let tbc = BlurredToolbarContainer()
            tbc.alpha = 0
            view.addSubview(tbc)
            tbc.autoPinWidthToSuperview()
            tbc.autoPinEdge(toSuperviewEdge: .bottom)
            viewState.multiSelectState.toolbar = tbc
            UIView.animate(withDuration: 0.25) {
                tbc.alpha = 1
            }
        }
        updateCaptions()
    }

    func switchMultiSelectState(_ sender: UIBarButtonItem) {
        AssertIsOnMainThread()

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
                ContextMenuAction(
                    title: NSLocalizedString("HOME_VIEW_TITLE_SELECT_CHATS", comment: "Title for the 'Select Chats' option in the HomeView."),
                    image: Theme.isDarkThemeEnabled ? UIImage(named: "check-circle-solid-24")?.tintedImage(color: .white) : UIImage(named: "check-circle-outline-24"),
                    attributes: [],
                    handler: { [weak self] (_) in
                        self?.hideMenu()
                        self?.willEnterMultiselectMode()
                }))
        }
        contextMenuActions.append(
            ContextMenuAction(
                title: CommonStrings.openSettingsButton,
                image: Theme.isDarkThemeEnabled ? UIImage(named: "settings-solid-24")?.tintedImage(color: .white) : UIImage(named: "settings-outline-24"),
                attributes: [],
                handler: { [weak self] (_) in
                    self?.hideMenu()
                    self?.showAppSettings(mode: .none)
            }))
        if renderState.archiveCount > 1 {
            contextMenuActions.append(
                ContextMenuAction(
                    title: NSLocalizedString("HOME_VIEW_TITLE_ARCHIVE", comment: "Title for the conversation list's 'archive' mode."),
                    image: Theme.isDarkThemeEnabled ? UIImage(named: "archive-solid-24")?.tintedImage(color: .white) : UIImage(named: "archive-outline-24"),
                    attributes: [],
                    handler: { [weak self] (_) in
                        self?.hideMenu()
                        self?.showArchivedConversations(offerMultiSelectMode: true)
                }))
        }

        viewState.multiSelectState.parentButton = button
        navigationController?.navigationBar.addGestureRecognizer(TapToCloseGestureRecognizer(target: self))

        let v = ContextMenuActionsView(menu: ContextMenu(contextMenuActions))
        let size = v.sizeThatFitsMaxSize
        v.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        v.delegate = self

        viewState.multiSelectState.contextMenuView = ContextMenuActionsViewContainer(v)
        viewState.multiSelectState.contextMenuView!.addGestureRecognizer(TapToCloseGestureRecognizer(target: self))
        view.addSubview(viewState.multiSelectState.contextMenuView!)
        animateIn(menu: viewState.multiSelectState.contextMenuView!, from: button)
    }

    private func done() {
        leaveMultiselectMode()
        updateBarButtonItems()
        if self.homeViewMode == .archive {
            navigationItem.rightBarButtonItem?.title = CommonStrings.selectButton
        }
    }

    private func hideMenu() {
        AssertIsOnMainThread()

        if let navBar = navigationController?.navigationBar {
            for recognizer in navBar.gestureRecognizers ?? [] {
                if let tapper = recognizer as? TapToCloseGestureRecognizer {
                    navBar.removeGestureRecognizer(tapper)
                }
            }
        }

        animateOut(menu: viewState.multiSelectState.contextMenuView, from: viewState.multiSelectState.parentButton) { [weak self] (_) in
            self?.viewState.multiSelectState.parentButton = nil
            self?.viewState.multiSelectState.contextMenuView = nil
        }
    }

    private func animateIn(menu: UIView, from: UIView?) {
        let oldAnchor = menu.layer.anchorPoint

        menu.autoPinEdge(toSuperviewSafeArea: .top)
        menu.autoPinEdge(toSuperviewSafeArea: .leading)
        menu.alpha = 0
        menu.layer.anchorPoint = .zero
        menu.transform = .scale(0.1)
        animate({
            from?.alpha = 0.4
            menu.alpha = 1
            menu.transform = .identity
        }) { (_) in
            menu.layer.anchorPoint = oldAnchor
            menu.autoPinEdgesToSuperviewSafeArea()
        }
    }

    private func animateOut(menu: UIView?, from: UIView?, completion: ((Bool) -> Void)?) {
        guard let menu = menu else {
            completion?(false)
            return
        }

        let frame = menu.frame
        menu.autoPinEdge(toSuperviewSafeArea: .top)
        menu.autoPinEdge(toSuperviewSafeArea: .leading)
        menu.layer.anchorPoint = .zero
        menu.frame = frame
        animate({
            from?.alpha = 1
            menu.alpha = 0
            menu.transform = .scale(0.1)
        }) { (result) in
            menu.removeFromSuperview()
            completion?(result)
        }
    }

    private func animate(_ animations: @escaping (() -> Void), completion: ((Bool) -> Void)?) {
        UIView.animate(withDuration: 0.4,
                       delay: 0,
                       usingSpringWithDamping: 0.8,
                       initialSpringVelocity: 1,
                       options: [.curveEaseInOut, .beginFromCurrentState],
                       animations: animations,
                       completion: completion)
    }

    private func adjustToolbarButtons(_ toolbar: UIToolbar?) {
        let hasSelectedEntries = !(tableView.indexPathsForSelectedRows ?? []).isEmpty

        let archiveBtn = UIBarButtonItem(
            title: homeViewMode == .archive ? CommonStrings.unarchiveAction : CommonStrings.archiveAction,
            style: .plain, target: self, action: #selector(performUnarchive))
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
            readButton = UIBarButtonItem(title: NSLocalizedString("HOME_VIEW_TOOLBAR_READ_ALL", comment: "Title 'Read All' button in the toolbar of the homeview if multi-section is active."), style: .plain, target: self, action: #selector(performReadAll))
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

        tableView.allowsSelectionDuringEditing = false
        tableView.allowsMultipleSelectionDuringEditing = false
        searchBar.isUserInteractionEnabled = true
        searchBar.alpha = 1
        viewState.multiSelectState.setIsActive(false, tableView: tableView)

        if let toolbar = viewState.multiSelectState.toolbar {
            UIView.animate(withDuration: 0.25) {
                toolbar.alpha = 0
            } completion: { [weak self] (_) in
                toolbar.removeFromSuperview()
                self?.viewState.multiSelectState.toolbar = nil
            }
        }
        title = viewState.multiSelectState.title
    }

    public func updateCaptions() {
        AssertIsOnMainThread()

        let count = tableView.indexPathsForSelectedRows?.count ?? 0
        if count == 0 {
            title = viewState.multiSelectState.title
        } else if count == 1 {
            title = NSLocalizedString("MESSAGE_ACTIONS_TOOLBAR_LABEL_1", comment: "Label for the toolbar used in the multi-select mode of conversation view when 1 item is selected.")
        } else {
            let labelFormat = NSLocalizedString("MESSAGE_ACTIONS_TOOLBAR_LABEL_N_FORMAT", comment: "Format for the toolbar used in the multi-select mode of conversation view. Embeds: {{ %@ the number of currently selected items }}.")
            title = String(format: labelFormat, OWSFormat.formatInt(count))
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

    // private tagging interface
    private class TapToCloseGestureRecognizer: UITapGestureRecognizer {
        init(target: Any?) {
            super.init(target: target, action: #selector(hideMenu))
        }
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
    private let offset = CGPoint(x: 16, y: 0)

    required init(_ target: UIView) {
        super.init(frame: target.frame)
        var frame = target.bounds
        frame.origin = offset
        let radius = target.layer.cornerRadius
        let shadowView = UIView(frame: CGRect(x: offset.x + radius,
                                              y: offset.y + radius,
                                              width: frame.width - 2 * radius,
                                              height: frame.height - 2 * radius))
        shadowView.backgroundColor = Theme.isDarkThemeEnabled ? .black : .white
        shadowView.setShadow(radius: 40, opacity: 0.3, offset: CGSize(width: 8, height: 20))
        target.frame = frame
        self.addSubview(shadowView)
        self.addSubview(target)
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
    fileprivate var toolbar: BlurredToolbarContainer?
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
