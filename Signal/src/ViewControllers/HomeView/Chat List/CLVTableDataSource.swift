//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI

public enum ChatListMode: Int, CaseIterable {
    case archive
    case inbox
}

public enum ChatListSectionType: String, CaseIterable {
    case reminders
    case backupDownloadProgressView
    case backupExportProgressView
    case pinned
    case unpinned
    case archiveButton
    case inboxFilterFooter
}

// MARK: -

class CLVTableDataSource: NSObject, UITableViewDataSource, UITableViewDelegate {
    private var viewState: CLVViewState!

    let tableView = CLVTableView()

    /// CLVTableDataSource is itself a UITableViewDelegate and thus conforms to
    /// UIScrollViewDelegate. Any UIScrollViewDelegate methods implemented by
    /// this class are either manually forwarded after being handled, or automatically
    /// forwarded in the implementation of `forwardingTarget(for:)`.
    ///
    /// - Note: This must be set before calling `configure(viewState:)`.
    weak var scrollViewDelegate: (any UIScrollViewDelegate)?

    weak var viewController: ChatListViewController?

    fileprivate var splitViewController: UISplitViewController? { viewController?.splitViewController }

    var renderState: CLVRenderState = .empty

    /// Used to let  chat list cells know when they should use rounded corners for background in `selected` state,
    var useSideBarChatListCellAppearance: Bool = false

    /// While table view selection is changing, i.e., between
    /// `tableView(_:willSelectRowAt:)` and `tableView(_:didSelectRowAt:)`,
    /// records the identifier of the newly selected thread, or `nil` if
    /// being deselected.
    ///
    /// This is because `tableView(_:didDeselectRowAt:)` is always called before
    /// `tableView(_:didSelectRowAt:)`, whether the previous selection is being
    /// set to `nil` (i.e., deselecting the current row) or to a new index path
    /// (changing the selection to a new row). Distinguishing between these two
    /// cases allows us to avoid spurious changes to selection that could trigger
    /// unwanted side-effects.
    private var threadIdBeingSelected: String?

    fileprivate var lastReloadDate: Date? { tableView.lastReloadDate }

    fileprivate var lastPreloadCellDate: Date?

    fileprivate var updateTimer: Timer?

    fileprivate var nextUpdateAt: Date? {
        didSet {
            guard nextUpdateAt != oldValue else {
                return
            }

            updateTimer?.invalidate()
            updateTimer = nil
            if let interval = nextUpdateAt?.timeIntervalSinceNow {
                updateTimer = Timer.scheduledTimer(withTimeInterval: max(1, interval), repeats: false) { [weak self] _ in
                    if let self {
                        for path in self.tableView.indexPathsForVisibleRows ?? [] {
                            self.updateCellContent(at: path, for: self.tableView)
                        }
                        self.calcRefreshTimer()
                    }
                }
            }
        }
    }

    override func responds(to selector: Selector!) -> Bool {
        if super.responds(to: selector) {
            return true
        }

        if let scrollViewDelegate, protocol_getMethodDescription(UIScrollViewDelegate.self, selector, false, true).name != nil {
            return scrollViewDelegate.responds(to: selector)
        }

        return false
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        guard let scrollViewDelegate else { return nil }

        // We're relying on `responds(to:)` first validating the selector is a
        // method in `UIScrollViewDelegate`, and not claiming to respond to
        // any other selectors.
        assert(scrollViewDelegate.responds(to: selector))

        return scrollViewDelegate
    }

    func configure(viewState: CLVViewState) {
        AssertIsOnMainThread()

        self.viewState = viewState

        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.separatorColor = Theme.tableView2SeparatorColor
        tableView.register(ChatListCell.self)
        tableView.register(ArchivedConversationsCell.self)
        tableView.register(ChatListFilterFooterCell.self)
        tableView.tableFooterView = UIView()
    }

    func threadViewModel(threadUniqueId: String) -> ThreadViewModel {
        let threadViewModelCache = viewState.threadViewModelCache
        if let value = threadViewModelCache.get(key: threadUniqueId) {
            return value
        }
        let threadViewModel = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return ThreadViewModel(
                threadUniqueId: threadUniqueId,
                forChatList: true,
                transaction: tx,
            )
        }
        threadViewModelCache.set(key: threadUniqueId, value: threadViewModel)
        return threadViewModel
    }

    func threadViewModel(forIndexPath indexPath: IndexPath) -> ThreadViewModel? {
        renderState.threadUniqueId(forIndexPath: indexPath).map { threadViewModel(threadUniqueId: $0) }
    }

    func selectedThreadUniqueIds(in tableView: UITableView) -> [String] {
        let selectedIndexPaths = tableView.indexPathsForSelectedRows ?? []
        return selectedIndexPaths.compactMap { renderState.threadUniqueId(forIndexPath: $0) }
    }

    private func preloadCellsIfNecessary() {
        AssertIsOnMainThread()

        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return
        }
        guard viewController.hasEverAppeared else {
            return
        }
        let newContentOffset = tableView.contentOffset
        let oldContentOffset = viewController.lastKnownTableViewContentOffset
        viewController.lastKnownTableViewContentOffset = newContentOffset
        guard let oldContentOffset else {
            return
        }
        let deltaY = (newContentOffset - oldContentOffset).y
        guard deltaY != 0 else {
            return
        }
        let isScrollingDownward = deltaY > 0

        // Debounce.
        let maxPreloadFrequency: TimeInterval = .second / 100
        if
            let lastPreloadCellDate = self.lastPreloadCellDate,
            abs(lastPreloadCellDate.timeIntervalSinceNow) < maxPreloadFrequency
        {
            return
        }
        lastPreloadCellDate = Date()

        guard let visibleIndexPaths = tableView.indexPathsForVisibleRows else {
            owsFailDebug("Missing visibleIndexPaths.")
            return
        }
        let conversationIndexPaths = visibleIndexPaths.compactMap { indexPath -> IndexPath? in
            switch renderState.sections[indexPath.section].type {
            case .reminders,
                 .backupDownloadProgressView,
                 .backupExportProgressView,
                 .archiveButton,
                 .inboxFilterFooter:
                return nil
            case .pinned, .unpinned:
                return indexPath
            }
        }
        guard !conversationIndexPaths.isEmpty else {
            return
        }
        let sortedIndexPaths = conversationIndexPaths.sorted()
        var indexPathsToPreload = [IndexPath]()
        func tryToEnqueue(_ indexPath: IndexPath) {
            let rowCount = renderState.numberOfRows(in: renderState.sections[indexPath.section])
            guard
                indexPath.row >= 0,
                indexPath.row < rowCount
            else {
                return
            }
            indexPathsToPreload.append(indexPath)
        }

        let preloadCount: Int = 3
        if isScrollingDownward {
            guard let lastIndexPath = sortedIndexPaths.last else {
                owsFailDebug("Missing indexPath.")
                return
            }
            // Order matters; we want to preload in order of proximity
            // to viewport.
            for index in 0..<preloadCount {
                let offset = +index
                tryToEnqueue(IndexPath(
                    row: lastIndexPath.row + offset,
                    section: lastIndexPath.section,
                ))
            }
        } else {
            guard let firstIndexPath = sortedIndexPaths.first else {
                owsFailDebug("Missing indexPath.")
                return
            }
            guard firstIndexPath.row > 0 else {
                return
            }
            // Order matters; we want to preload in order of proximity
            // to viewport.
            for index in 0..<preloadCount {
                let offset = -index
                tryToEnqueue(IndexPath(
                    row: firstIndexPath.row + offset,
                    section: firstIndexPath.section,
                ))
            }
        }

        for indexPath in indexPathsToPreload {
            preloadCellIfNecessaryAsync(indexPath: indexPath)
        }
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        return UITableViewCell.EditingStyle.none
    }

    func tableView(_ tableView: UITableView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        return !viewState.multiSelectState.locked
    }

    func tableView(_ tableView: UITableView, willBeginEditingRowAt indexPath: IndexPath) {
        // editing a single row (by swiping to the left or right) calls this method
        // we have to disable the two-finger gesture for entering the multi-select mode
        viewState.multiSelectState.locked = true
    }

    func tableView(_ tableView: UITableView, didEndEditingRowAt indexPath: IndexPath?) {
        // this method is called if the current single row edit has ended (even without
        // explicit user-interaction eg. due to table reload).
        // we can to enable the two-finger gesture for entering the multi-select mode again
        viewState.multiSelectState.locked = false
    }

    func tableView(_ tableView: UITableView, didBeginMultipleSelectionInteractionAt indexPath: IndexPath) {
        guard let viewController = self.viewController, !viewState.multiSelectState.isActive, !viewState.multiSelectState.locked else {
            return
        }

        // the tableView has be switch to edit mode already (by the OS), we don't want to
        // change this, because otherwise the selection swipe gesture is cancelled.
        viewController.willEnterMultiselectMode(cancelCurrentEditAction: false)
    }

    func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        return false
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let section = renderState.sections[section]

        // Without returning a header with a non-zero height, Grouped
        // table view will use a default spacing between sections. We
        // do not want that spacing so we use the smallest possible height.
        return section.title == nil ? .leastNormalMagnitude : UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        // Without returning a footer with a non-zero height, Grouped
        // table view will use a default spacing between sections. We
        // do not want that spacing so we use the smallest possible height.
        return .leastNormalMagnitude
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let title = renderState.sections[section].title else { return UIView() }

        let container = UIView()
        container.layoutMargins = UIEdgeInsets(top: 14, leading: 16, bottom: 8, trailing: 16)

        let label = UILabel()
        container.addSubview(label)
        label.autoPinEdgesToSuperviewMargins()
        label.font = UIFont.dynamicTypeHeadline
        label.textColor = .Signal.label
        label.text = title

        return container
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        UIView()
    }

    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        switch renderState.sections[indexPath.section].type {
        case .reminders, .inboxFilterFooter:
            return nil

        case .backupDownloadProgressView, .backupExportProgressView, .archiveButton:
            return indexPath

        case .pinned, .unpinned:
            guard let threadUniqueId = renderState.threadUniqueId(forIndexPath: indexPath) else {
                owsFailDebug("Missing thread at index path: \(indexPath)")
                return nil
            }
            threadIdBeingSelected = threadUniqueId
            return indexPath
        }
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if threadIdBeingSelected == nil {
            viewState.lastSelectedThreadId = nil
        }

        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return
        }

        if viewState.multiSelectState.isActive {
            viewController.updateCaptions()
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return
        }

        defer {
            viewController.cancelSearch()
        }

        let sectionType = renderState.sections[indexPath.section].type

        switch sectionType {
        case .reminders, .inboxFilterFooter:
            owsFailDebug("Unexpected selection in section \(sectionType)")
            tableView.deselectRow(at: indexPath, animated: false)

        case .backupDownloadProgressView:
            tableView.deselectRow(at: indexPath, animated: false)
            viewController.handleBackupDownloadProgressViewTapped()

        case .backupExportProgressView:
            tableView.deselectRow(at: indexPath, animated: false)
            viewController.handleBackupExportProgressViewTapped()

        case .pinned, .unpinned:
            guard let threadUniqueId = renderState.threadUniqueId(forIndexPath: indexPath) else {
                owsFailDebug("Missing thread.")
                return
            }
            owsAssertDebug(threadUniqueId == threadIdBeingSelected)
            threadIdBeingSelected = nil
            viewState.lastSelectedThreadId = threadUniqueId

            if viewState.multiSelectState.isActive {
                viewController.updateCaptions()
            } else {
                viewController.presentThread(threadUniqueId: threadUniqueId, animated: true)
            }

        case .archiveButton:
            owsAssertDebug(!viewState.multiSelectState.isActive)
            viewController.showArchivedConversations()
        }
    }

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint,
    ) -> UIContextMenuConfiguration? {
        switch renderState.sections[indexPath.section].type {
        case .pinned,
             .unpinned:
            guard
                let chatListViewController = viewController,
                chatListViewController.canPresentPreview(fromIndexPath: indexPath),
                let threadViewModel = threadViewModel(forIndexPath: indexPath)
            else {
                return nil
            }

            return UIContextMenuConfiguration(
                identifier: threadViewModel.threadUniqueId as NSString,
                previewProvider: { [weak chatListViewController] in
                    guard let chatListViewController else { return nil }
                    return chatListViewController.createPreviewController(atIndexPath: indexPath)
                },
                actionProvider: { [weak chatListViewController] _ in
                    guard let chatListViewController else { return nil }
                    let actions = chatListViewController.contextMenuActions(threadViewModel: threadViewModel)
                    return UIMenu(children: actions)
                },
            )
        case .backupExportProgressView:
            return UIContextMenuConfiguration(
                actionProvider: { [weak self] _ in
                    guard let self else { return nil }
                    let actions = viewState.backupExportProgressView.contextMenuActions()
                    return UIMenu(children: actions)
                },
            )
        case .reminders,
             .backupDownloadProgressView,
             .archiveButton,
             .inboxFilterFooter:
            return nil
        }
    }

    func tableView(
        _ tableView: UITableView,
        previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration,
    ) -> UITargetedPreview? {
        guard
            let threadId = configuration.identifier as? String,
            let indexPath = renderState.indexPath(forUniqueId: threadId)
        else {
            return nil
        }

        // Below is a partial workaround for database updates causing cells to reload mid-transition:
        // When the conversation view controller is dismissed, it touches the database which causes
        // the row to update.
        //
        // The way this *should* appear is that during presentation and dismissal, the row animates
        // into and out of the platter. Currently, it looks like UIKit uses a portal view to accomplish
        // this. It seems the row stays in its original position and is occluded by context menu internals
        // while the portal view is translated.
        //
        // But in our case, when the table view is updated the old cell will be removed and hidden by
        // UITableView. So mid-transition, the cell appears to disappear. What's left is the background
        // provided by UIPreviewParameters. By default this is opaque and the end result is that an empty
        // row appears while dismissal completes.
        //
        // A straightforward way to work around this is to just set the background color to clear. When
        // the row is updated because of a database change, it will appear to snap into position instead
        // of properly animating. This isn't *too* much of an issue since the row is usually occluded by
        // the platter anyway. This avoids the empty row issue. A better solution would probably be to
        // defer data source updates until the transition completes but, as far as I can tell, we aren't
        // notified when this happens.

        guard let cell = tableView.cellForRow(at: indexPath) as? ChatListCell else {
            owsFailDebug("Invalid cell.")
            return nil
        }
        let cellFrame = tableView.rectForRow(at: indexPath)
        let center = cellFrame.center
        let target = UIPreviewTarget(container: tableView, center: center)
        let params = UIPreviewParameters()
        params.backgroundColor = .clear
        return UITargetedPreview(view: cell, parameters: params, target: target)
    }

    func tableView(
        _ tableView: UITableView,
        willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionCommitAnimating,
    ) {
        AssertIsOnMainThread()

        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return
        }
        guard let vc = animator.previewViewController else {
            owsFailDebug("Missing previewViewController.")
            return
        }
        animator.addAnimations { [weak viewController] in
            viewController?.commitPreviewController(vc)
        }
    }

    func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath,
    ) {
        AssertIsOnMainThread()

        guard let cell = cell as? ChatListCell else {
            return
        }
        viewController?.updateCellVisibility(cell: cell, isCellVisible: true)

        preloadCellsIfNecessary()
    }

    func tableView(
        _ tableView: UITableView,
        didEndDisplaying cell: UITableViewCell,
        forRowAt indexPath: IndexPath,
    ) {
        AssertIsOnMainThread()

        guard let cell = cell as? ChatListCell else {
            return
        }
        viewController?.updateCellVisibility(cell: cell, isCellVisible: false)
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        renderState.sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        renderState.numberOfRows(in: renderState.sections[section])
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch renderState.sections[indexPath.section].type {
        case .reminders, .archiveButton, .inboxFilterFooter, .backupExportProgressView, .backupDownloadProgressView:
            return UITableView.automaticDimension
        case .pinned, .unpinned:
            return measureConversationCell(tableView: tableView, indexPath: indexPath)
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return UITableViewCell()
        }

        let cell: UITableViewCell
        let section = renderState.sections[indexPath.section]

        switch section.type {
        case .reminders:
            cell = viewController.viewState.reminderViews.reminderViewCell
        case .backupDownloadProgressView:
            cell = viewController.viewState.backupDownloadProgressView.backupDownloadProgressViewCell
        case .backupExportProgressView:
            cell = viewController.viewState.backupExportProgressView.backupExportProgressViewCell
        case .pinned, .unpinned:
            cell = buildConversationCell(tableView: tableView, indexPath: indexPath)
        case .archiveButton:
            cell = buildArchivedConversationsButtonCell(tableView: tableView, indexPath: indexPath)
        case .inboxFilterFooter:
            let filterFooterCell = tableView.dequeueReusableCell(ChatListFilterFooterCell.self, for: indexPath)
            filterFooterCell.primaryAction = .disableChatListFilter(target: viewController)
            filterFooterCell.title = OWSLocalizedString("CHAT_LIST_EMPTY_FILTER_CLEAR_BUTTON", comment: "Button displayed in chat list to clear the unread filter when no chats are unread")
            cell = filterFooterCell
            guard let inboxFilterSection = renderState.inboxFilterSection else {
                owsFailDebug("Missing view model in inbox filter section")
                break
            }
            filterFooterCell.isExpanded = inboxFilterSection.isEmptyState
            filterFooterCell.message = inboxFilterSection.message
        }

        cell.tintColor = .ows_accentBlue
        return cell
    }

    private func measureConversationCell(tableView: UITableView, indexPath: IndexPath) -> CGFloat {
        AssertIsOnMainThread()

        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return UITableView.automaticDimension
        }
        if let result = viewController.conversationCellHeightCache {
            return result
        }
        guard let cellContentToken = buildCellContentToken(for: indexPath) else {
            owsFailDebug("Missing cellConfigurationAndContentToken.")
            return UITableView.automaticDimension
        }
        let result = ChatListCell.measureCellHeight(cellContentToken: cellContentToken)
        viewController.conversationCellHeightCache = result
        return result
    }

    private func buildConversationCell(tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        AssertIsOnMainThread()

        let cell = tableView.dequeueReusableCell(ChatListCell.self, for: indexPath)

        guard let contentToken = buildCellContentToken(for: indexPath) else {
            owsFailDebug("Missing cellConfigurationAndContentToken.")
            return UITableViewCell()
        }

        cell.configure(cellContentToken: contentToken, spoilerAnimationManager: viewState.spoilerAnimationManager)
        cell.useSidebarAppearance = useSideBarChatListCellAppearance

        if
            let conversationSplitViewController = viewController?.conversationSplitViewController,
            conversationSplitViewController.selectedThread?.uniqueId == contentToken.thread.uniqueId
        {
            tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
        } else if !viewState.multiSelectState.isActive {
            tableView.deselectRow(at: indexPath, animated: false)
        }

        updateAndSetRefreshTimer(for: cell)
        return cell
    }

    private func buildArchivedConversationsButtonCell(tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        AssertIsOnMainThread()
        let cell = tableView.dequeueReusableCell(ArchivedConversationsCell.self, for: indexPath)
        cell.configure(enabled: !viewState.multiSelectState.isActive)
        return cell
    }

    // MARK: - Edit Actions

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        // TODO: Is this method necessary?
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        switch renderState.sections[indexPath.section].type {
        case .reminders,
             .backupDownloadProgressView,
             .backupExportProgressView,
             .archiveButton,
             .inboxFilterFooter:
            return nil

        case .pinned, .unpinned:
            guard let threadViewModel = threadViewModel(forIndexPath: indexPath) else {
                owsFailDebug("Missing threadViewModel.")
                return nil
            }
            guard let viewController = self.viewController else {
                owsFailDebug("Missing viewController.")
                return nil
            }

            return viewController.trailingSwipeActionsConfiguration(threadViewModel: threadViewModel)
        }
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        switch renderState.sections[indexPath.section].type {
        case .reminders,
             .backupDownloadProgressView,
             .backupExportProgressView,
             .archiveButton,
             .inboxFilterFooter:
            return false
        case .pinned, .unpinned:
            return true
        }
    }

    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        switch renderState.sections[indexPath.section].type {
        case .reminders,
             .backupDownloadProgressView,
             .backupExportProgressView,
             .archiveButton,
             .inboxFilterFooter:
            return nil

        case .pinned, .unpinned:
            guard let threadViewModel = threadViewModel(forIndexPath: indexPath) else {
                owsFailDebug("Missing threadViewModel.")
                return nil
            }
            guard let viewController = self.viewController else {
                owsFailDebug("Missing viewController.")
                return nil
            }

            return viewController.leadingSwipeActionsConfiguration(threadViewModel: threadViewModel)
        }
    }

    // MARK: -

    func updateAndSetRefreshTimer(for cell: ChatListCell?) {
        if let cell, let timestamp = cell.nextUpdateTimestamp {
            if nextUpdateAt == nil || timestamp < nextUpdateAt! {
                nextUpdateAt = timestamp
            }
        }
    }

    func stopRefreshTimer() {
        nextUpdateAt = nil
    }

    func updateAndSetRefreshTimer() {
        for path in tableView.indexPathsForVisibleRows ?? [] {
            updateCellContent(at: path, for: tableView)
        }
        calcRefreshTimer()
    }

    func calcRefreshTimer() {
        nextUpdateAt = nil
        for cell in tableView.visibleCells {
            updateAndSetRefreshTimer(for: cell as? ChatListCell)
        }
    }

    func updateCellContent(at indexPath: IndexPath, for tableView: UITableView) {
        AssertIsOnMainThread()

        guard let cell = tableView.cellForRow(at: indexPath) as? ChatListCell else { return }
        guard let contentToken = buildCellContentToken(for: indexPath) else { return }

        let cellWasVisible = cell.isCellVisible
        cell.reset()
        // reduces flicker effects for already visible cells
        cell.configure(
            cellContentToken: contentToken,
            spoilerAnimationManager: viewState.spoilerAnimationManager,
            asyncAvatarLoadingAllowed: false,
        )
        cell.isCellVisible = cellWasVisible
    }

    // This method can be called from any thread.
    private static func buildCellConfiguration(
        threadViewModel: ThreadViewModel,
        lastReloadDate: Date?,
    ) -> ChatListCell.Configuration {
        owsAssertDebug(threadViewModel.chatListInfo != nil)
        let configuration = ChatListCell.Configuration(
            threadViewModel: threadViewModel,
            lastReloadDate: lastReloadDate,
        )
        return configuration
    }

    private func buildCellContentToken(for indexPath: IndexPath) -> CLVCellContentToken? {
        AssertIsOnMainThread()

        guard let threadViewModel = threadViewModel(forIndexPath: indexPath) else {
            owsFailDebug("Missing threadViewModel.")
            return nil
        }
        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return nil
        }
        let cellContentCache = viewController.cellContentCache
        let cellContentCacheKey = threadViewModel.threadRecord.uniqueId
        // If we have an existing CLVCellContentToken, use it. Cell
        // measurement/arrangement is expensive.
        if let cellContentToken = cellContentCache.get(key: cellContentCacheKey) {
            return cellContentToken
        }
        let lastReloadDate: Date? = {
            guard viewState.hasEverAppeared else {
                return nil
            }
            return self.lastReloadDate
        }()
        let configuration = Self.buildCellConfiguration(threadViewModel: threadViewModel, lastReloadDate: lastReloadDate)
        let cellContentToken = ChatListCell.buildCellContentToken(for: configuration)
        cellContentCache.set(key: cellContentCacheKey, value: cellContentToken)
        return cellContentToken
    }

    // TODO: It would be preferable to figure out some way to use ReverseDispatchQueue.
    private static let preloadSerialQueue = DispatchQueue(label: "org.signal.chat-list.preload")

    private func preloadCellIfNecessaryAsync(indexPath: IndexPath) {
        AssertIsOnMainThread()

        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return
        }
        // These caches should only be accessed on the main thread.
        // They are thread-safe, but we don't want to race with a reset.
        let cellContentCache = viewController.cellContentCache
        let threadViewModelCache = viewController.threadViewModelCache
        // Take note of the cache reset counts. If either cache is reset
        // before we complete, discard the outcome of the preload.
        let cellContentCacheResetCount = cellContentCache.resetCount
        let threadViewModelCacheResetCount = threadViewModelCache.resetCount

        guard let threadUniqueId = renderState.threadUniqueId(forIndexPath: indexPath) else {
            owsFailDebug("Missing thread.")
            return
        }
        let cacheKey = threadUniqueId
        guard nil == cellContentCache.get(key: cacheKey) else {
            // If we already have an existing CLVCellContentToken, abort.
            return
        }

        let lastReloadDate: Date? = {
            guard viewState.hasEverAppeared else {
                return nil
            }
            return self.lastReloadDate
        }()

        // We use a serial queue to ensure we don't race and preload the same cell
        // twice at the same time.
        firstly(on: Self.preloadSerialQueue) { () -> (ThreadViewModel, CLVCellContentToken) in
            guard nil == cellContentCache.get(key: cacheKey) else {
                // If we already have an existing CLVCellContentToken, abort.
                throw CLVPreloadError.alreadyLoaded
            }
            // This is the expensive work we do off the main thread.
            let threadViewModel = SSKEnvironment.shared.databaseStorageRef.read { transaction in
                return ThreadViewModel(
                    threadUniqueId: threadUniqueId,
                    forChatList: true,
                    transaction: transaction,
                )
            }
            let configuration = Self.buildCellConfiguration(
                threadViewModel: threadViewModel,
                lastReloadDate: lastReloadDate,
            )
            let contentToken = ChatListCell.buildCellContentToken(for: configuration)
            return (threadViewModel, contentToken)
        }.done(on: DispatchQueue.main) { (threadViewModel: ThreadViewModel, contentToken: CLVCellContentToken) in
            // Commit the preloaded values to their respective caches.
            guard cellContentCacheResetCount == cellContentCache.resetCount else {
                return
            }
            guard threadViewModelCacheResetCount == threadViewModelCache.resetCount else {
                return
            }
            if nil == threadViewModelCache.get(key: cacheKey) {
                threadViewModelCache.set(key: cacheKey, value: threadViewModel)
            }
            if nil == cellContentCache.get(key: cacheKey) {
                cellContentCache.set(key: cacheKey, value: contentToken)
            }
        }.catch(on: DispatchQueue.global()) { error in
            if case CLVPreloadError.alreadyLoaded = error {
                return
            }
            owsFailDebugUnlessNetworkFailure(error)
        }
    }

    private enum CLVPreloadError: Error {
        case alreadyLoaded
    }
}

// MARK: -

public class CLVTableView: UITableView {
    fileprivate var lastReloadDate: Date?

    // A `tableFooterView` that always expands to fill available contentSize
    // when the table view contents otherwise wouldn't fill the space. This
    // supports Filter by Unread by helping to make transitions between very
    // large and very small chat lists more consistent. What this does in
    // practice is to prevent a glitch where the search bar would momentarily
    // disappears and then animates back in with the adjusted content insets.
    //
    // It also allows the user to swipe up to dismiss the search bar (if the
    // content height is too small, the search bar otherwise becomes un-hideable).
    private let footerView = UIView()

    public init() {
        super.init(frame: .zero, style: .grouped)
        tableFooterView = footerView
    }

    @available(*, unavailable, message: "use other constructor instead.")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func reloadData() {
        AssertIsOnMainThread()

        lastReloadDate = Date()
        super.reloadData()
        (dataSource as? CLVTableDataSource)?.calcRefreshTimer()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        updateFooterHeight()
    }

    override public func adjustedContentInsetDidChange() {
        super.adjustedContentInsetDidChange()
        updateFooterHeight()
    }

    private func updateFooterHeight() {
        let visibleRect = frame.inset(by: adjustedContentInset)
        let headerHeight = tableHeaderView?.frame.height ?? 0

        // Compute whether the total height content height (excluding the footer)
        // fits in the available space.
        var availableHeight = visibleRect.height - headerHeight
        for section in 0..<numberOfSections where availableHeight > 0 {
            let newValue = availableHeight - rect(forSection: section).height
            availableHeight = max(0, newValue)
        }

        // Add one pixel to the final height of the footer to ensure the content
        // height is always slightly larger than the available space and thus
        // remains scrollable.
        //
        // What this code *doesn't* do is cause scroll indicators to appear when
        // they shouldn't, because this value is smaller than the amount the
        // adjusted content insets can change by (i.e., the height of the expanded
        // search bar).
        let displayScale = (window?.windowScene?.screen ?? .main).scale
        let finalHeight = availableHeight + 1 / displayScale

        if footerView.frame.height != finalHeight {
            footerView.frame.height = finalHeight
        }
    }
}
