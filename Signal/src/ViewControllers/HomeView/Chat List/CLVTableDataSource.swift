//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI

class CLVTableDataSource: NSObject {
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
                updateTimer = Timer.scheduledTimer(withTimeInterval: max(1, interval), repeats: false) { [weak self] (_) in
                    if let self = self {
                        for path in self.tableView.indexPathsForVisibleRows ?? [] {
                            self.updateVisibleCellContent(at: path, for: self.tableView)
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
        tableView.separatorColor = Theme.cellSeparatorColor
        tableView.register(ChatListCell.self)
        tableView.register(ArchivedConversationsCell.self)
        tableView.register(ChatListFilterFooterCell.self)
        tableView.tableFooterView = UIView()
    }

    func threadViewModel(forThread thread: TSThread) -> ThreadViewModel {
        let threadViewModelCache = viewState.threadViewModelCache
        if let value = threadViewModelCache.get(key: thread.uniqueId) {
            return value
        }
        let threadViewModel = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            ThreadViewModel(thread: thread, forChatList: true, transaction: transaction)
        }
        threadViewModelCache.set(key: thread.uniqueId, value: threadViewModel)
        return threadViewModel
    }

    func threadViewModel(forIndexPath indexPath: IndexPath) -> ThreadViewModel? {
        renderState.thread(forIndexPath: indexPath).map(threadViewModel(forThread:))
    }

    func selectedThreads(in tableView: UITableView) -> [TSThread]? {
        tableView.indexPathsForSelectedRows?.compactMap(renderState.thread(forIndexPath:))
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
        guard let oldContentOffset = oldContentOffset else {
            return
        }
        let deltaY = (newContentOffset - oldContentOffset).y
        guard deltaY != 0 else {
            return
        }
        let isScrollingDownward = deltaY > 0

        // Debounce.
        let maxPreloadFrequency: TimeInterval = kSecondInterval / 100
        if let lastPreloadCellDate = self.lastPreloadCellDate,
           abs(lastPreloadCellDate.timeIntervalSinceNow) < maxPreloadFrequency {
            return
        }
        lastPreloadCellDate = Date()

        guard let visibleIndexPaths = tableView.indexPathsForVisibleRows else {
            owsFailDebug("Missing visibleIndexPaths.")
            return
        }
        let conversationIndexPaths = visibleIndexPaths.compactMap { indexPath -> IndexPath? in
            switch renderState.sections[indexPath.section].type {
            case .reminders, .archiveButton, .inboxFilterFooter:
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
            guard indexPath.row >= 0,
                  indexPath.row < rowCount else {
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
                tryToEnqueue(IndexPath(row: lastIndexPath.row + offset,
                                       section: lastIndexPath.section))
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
                tryToEnqueue(IndexPath(row: firstIndexPath.row + offset,
                                       section: firstIndexPath.section))
            }
        }

        for indexPath in indexPathsToPreload {
            preloadCellIfNecessaryAsync(indexPath: indexPath)
        }
    }
}

// MARK: -

public enum ChatListMode: Int, CaseIterable {
    case archive
    case inbox
}

// MARK: -

public enum ChatListSectionType: String, CaseIterable {
    case reminders
    case pinned
    case unpinned
    case archiveButton
    case inboxFilterFooter
}

// MARK: -

extension CLVTableDataSource: UITableViewDelegate {
    public func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        return UITableViewCell.EditingStyle.none
    }

    public func tableView(_ tableView: UITableView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        return !viewState.multiSelectState.locked
    }

    public func tableView(_ tableView: UITableView, willBeginEditingRowAt indexPath: IndexPath) {
        // editing a single row (by swiping to the left or right) calls this method
        // we have to disable the two-finger gesture for entering the multi-select mode
        viewState.multiSelectState.locked = true
    }

    public func tableView(_ tableView: UITableView, didEndEditingRowAt indexPath: IndexPath?) {
        // this method is called if the current single row edit has ended (even without
        // explicit user-interaction eg. due to table reload).
        // we can to enable the two-finger gesture for entering the multi-select mode again
        viewState.multiSelectState.locked = false
    }

    public func tableView(_ tableView: UITableView, didBeginMultipleSelectionInteractionAt indexPath: IndexPath) {
        guard let viewController = self.viewController, !viewState.multiSelectState.isActive, !viewState.multiSelectState.locked else {
            return
        }

        // the tableView has be switch to edit mode already (by the OS), we don't want to
        // change this, because otherwise the selection swipe gesture is cancelled.
        viewController.willEnterMultiselectMode(cancelCurrentEditAction: false)
    }

    public func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        return false
    }

    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let section = renderState.sections[section]

        // Without returning a header with a non-zero height, Grouped
        // table view will use a default spacing between sections. We
        // do not want that spacing so we use the smallest possible height.
        return section.title == nil ? .leastNormalMagnitude : UITableView.automaticDimension
    }

    public func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        // Without returning a footer with a non-zero height, Grouped
        // table view will use a default spacing between sections. We
        // do not want that spacing so we use the smallest possible height.
        return .leastNormalMagnitude
    }

    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let title = renderState.sections[section].title else { return UIView() }

        let container = UIView()
        container.backgroundColor = Theme.backgroundColor
        container.layoutMargins = UIEdgeInsets(top: 14, leading: 16, bottom: 8, trailing: 16)

        let label = UILabel()
        container.addSubview(label)
        label.autoPinEdgesToSuperviewMargins()
        label.font = UIFont.dynamicTypeBody.semibold()
        label.textColor = Theme.primaryTextColor
        label.text = title

        return container
    }

    public func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        UIView()
    }

    public func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        switch renderState.sections[indexPath.section].type {
        case .reminders, .inboxFilterFooter:
            return nil

        case .archiveButton:
            return indexPath

        case .pinned, .unpinned:
            guard let thread = renderState.thread(forIndexPath: indexPath) else {
                owsFailDebug("Missing thread at index path: \(indexPath)")
                return nil
            }
            threadIdBeingSelected = thread.uniqueId
            return indexPath
        }
    }

    public func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
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

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
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

        case .pinned, .unpinned:
            guard let thread = renderState.thread(forIndexPath: indexPath) else {
                owsFailDebug("Missing thread.")
                return
            }
            owsAssertDebug(thread.uniqueId == threadIdBeingSelected)
            threadIdBeingSelected = nil
            viewState.lastSelectedThreadId = thread.uniqueId

            if viewState.multiSelectState.isActive {
                viewController.updateCaptions()
            } else {
                viewController.presentThread(thread, animated: true)
            }

        case .archiveButton:
            owsAssertDebug(!viewState.multiSelectState.isActive)
            viewController.showArchivedConversations()
        }
    }

    public func tableView(_ tableView: UITableView,
                          contextMenuConfigurationForRowAt indexPath: IndexPath,
                          point: CGPoint) -> UIContextMenuConfiguration? {
        AssertIsOnMainThread()

        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return nil
        }
        guard viewController.canPresentPreview(fromIndexPath: indexPath) else {
            return nil
        }
        guard let thread = renderState.thread(forIndexPath: indexPath) else {
            return nil
        }

        return UIContextMenuConfiguration(
            identifier: thread.uniqueId as NSString,
            previewProvider: { [weak viewController] in
                viewController?.createPreviewController(atIndexPath: indexPath)
            },
            actionProvider: { _ in
                // nil for now. But we may want to add options like "Pin" or "Mute" in the future
                return nil
            }
        )
    }

    public func tableView(
        _ tableView: UITableView,
        previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        AssertIsOnMainThread()

        guard let threadId = configuration.identifier as? String else {
            owsFailDebug("Unexpected context menu configuration identifier")
            return nil
        }
        guard let indexPath = renderState.indexPath(forUniqueId: threadId) else {
            Logger.warn("No index path for threadId: \(threadId).")
            return nil
        }
        guard tableView.window != nil else {
            Logger.warn("Dismissing tableView not in view hierarchy")
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

    public func tableView(
        _ tableView: UITableView,
        willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionCommitAnimating
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

    public func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        AssertIsOnMainThread()

        guard let cell = cell as? ChatListCell else {
            return
        }
        viewController?.updateCellVisibility(cell: cell, isCellVisible: true)

        preloadCellsIfNecessary()
    }

    public func tableView(
        _ tableView: UITableView,
        didEndDisplaying cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        AssertIsOnMainThread()

        guard let cell = cell as? ChatListCell else {
            return
        }
        viewController?.updateCellVisibility(cell: cell, isCellVisible: false)
    }
}

// MARK: -

extension CLVTableDataSource: UITableViewDataSource {
    public func numberOfSections(in tableView: UITableView) -> Int {
        renderState.sections.count
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        renderState.numberOfRows(in: renderState.sections[section])
    }

    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch renderState.sections[indexPath.section].type {
        case .reminders, .archiveButton, .inboxFilterFooter:
            return UITableView.automaticDimension
        case .pinned, .unpinned:
            return measureConversationCell(tableView: tableView, indexPath: indexPath)
        }
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return UITableViewCell()
        }

        let cell: UITableViewCell
        let section = renderState.sections[indexPath.section]

        switch section.type {
        case .reminders:
            cell = viewController.reminderViewCell
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

        if isConversationActive(threadUniqueId: contentToken.thread.uniqueId) {
            tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
        } else if !viewState.multiSelectState.isActive {
            tableView.deselectRow(at: indexPath, animated: false)
        }

        updateAndSetRefreshTimer(for: cell)
        return cell
    }

    private func isConversationActive(threadUniqueId: String) -> Bool {
        AssertIsOnMainThread()

        guard let conversationSplitViewController = splitViewController as? ConversationSplitViewController else {
            owsFailDebug("Missing conversationSplitViewController.")
            return false
        }
        return conversationSplitViewController.selectedThread?.uniqueId == threadUniqueId
    }

    private func buildArchivedConversationsButtonCell(tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        AssertIsOnMainThread()
        let cell = tableView.dequeueReusableCell(ArchivedConversationsCell.self, for: indexPath)
        cell.configure(enabled: !viewState.multiSelectState.isActive)
        return cell
    }

    // MARK: - Edit Actions

    public func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        // TODO: Is this method necessary?
    }

    public func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        switch renderState.sections[indexPath.section].type {
        case .reminders, .archiveButton, .inboxFilterFooter:
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

            let threadUniqueId = threadViewModel.threadRecord.uniqueId
            return viewController.trailingSwipeActionsConfiguration(for: threadViewModel, closeConversationBlock: { [weak self] in
                guard let self else { return }
                if self.isConversationActive(threadUniqueId: threadUniqueId) {
                    viewController.conversationSplitViewController?.closeSelectedConversation(animated: true)
                }
            })
        }
    }

    public func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        switch renderState.sections[indexPath.section].type {
        case .reminders, .archiveButton, .inboxFilterFooter:
            return false
        case .pinned, .unpinned:
            return true
        }
    }

    public func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        switch renderState.sections[indexPath.section].type {
        case .reminders, .archiveButton, .inboxFilterFooter:
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

            return viewController.leadingSwipeActionsConfiguration(for: threadViewModel)
        }
    }
}

// MARK: -

extension CLVTableDataSource {
    func updateAndSetRefreshTimer(for cell: ChatListCell?) {
        if let cell = cell, let timestamp = cell.nextUpdateTimestamp {
            if nextUpdateAt == nil || timestamp.isBefore(nextUpdateAt!) {
                nextUpdateAt = timestamp
            }
        }
    }

    public func stopRefreshTimer() {
        nextUpdateAt = nil
    }

    public func updateAndSetRefreshTimer() {
        for path in tableView.indexPathsForVisibleRows ?? [] {
            updateVisibleCellContent(at: path, for: tableView)
        }
        calcRefreshTimer()
    }

    func calcRefreshTimer() {
        nextUpdateAt = nil
        for cell in tableView.visibleCells {
            updateAndSetRefreshTimer(for: cell as? ChatListCell)
        }
    }

    @discardableResult
    public func updateVisibleCellContent(at indexPath: IndexPath, for tableView: UITableView) -> Bool {
        AssertIsOnMainThread()

        guard tableView.indexPathsForVisibleRows?.contains(indexPath) == true else { return false }
        guard let cell = tableView.cellForRow(at: indexPath) as? ChatListCell else { return false }
        guard let contentToken = buildCellContentToken(for: indexPath) else { return false }

        let cellWasVisible = cell.isCellVisible
        cell.reset()
        // reduces flicker effects for already visible cells
        cell.configure(
            cellContentToken: contentToken,
            spoilerAnimationManager: viewState.spoilerAnimationManager,
            asyncAvatarLoadingAllowed: false
        )
        cell.isCellVisible = cellWasVisible
        return true
    }

    // This method can be called from any thread.
    private static func buildCellConfiguration(
        threadViewModel: ThreadViewModel,
        lastReloadDate: Date?
    ) -> ChatListCell.Configuration {
        owsAssertDebug(threadViewModel.chatListInfo != nil)
        let configuration = ChatListCell.Configuration(
            threadViewModel: threadViewModel,
            lastReloadDate: lastReloadDate
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

    fileprivate func preloadCellIfNecessaryAsync(indexPath: IndexPath) {
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

        guard let thread = renderState.thread(forIndexPath: indexPath) else {
            owsFailDebug("Missing thread.")
            return
        }
        let cacheKey = thread.uniqueId
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
                ThreadViewModel(thread: thread, forChatList: true, transaction: transaction)
            }
            let configuration = Self.buildCellConfiguration(threadViewModel: threadViewModel,
                                                            lastReloadDate: lastReloadDate)
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

    public override func reloadData() {
        AssertIsOnMainThread()

        lastReloadDate = Date()
        super.reloadData()
        (dataSource as? CLVTableDataSource)?.calcRefreshTimer()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateFooterHeight()
    }

    public override func adjustedContentInsetDidChange() {
        super.adjustedContentInsetDidChange()
        updateFooterHeight()
    }

    private func updateFooterHeight() {
        let visibleRect = frame.inset(by: adjustedContentInset)
        let headerHeight = tableHeaderView?.frame.height ?? 0

        // Compute whether the total height content height (excluding the footer)
        // fits in the available space.
        var availableHeight = visibleRect.height - headerHeight
        for section in 0 ..< numberOfSections where availableHeight > 0 {
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
