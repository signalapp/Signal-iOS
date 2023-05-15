//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalUI
import UIKit

@objc
public class CLVTableDataSource: NSObject {
    private var viewState: CLVViewState!

    public let tableView = CLVTableView()

    @objc
    public weak var viewController: ChatListViewController?

    fileprivate var splitViewController: UISplitViewController? { viewController?.splitViewController }

    @objc
    public var renderState: CLVRenderState = .empty

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

    public required override init() {
        super.init()
    }

    func configure(viewState: CLVViewState) {
        AssertIsOnMainThread()

        self.viewState = viewState

        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.separatorColor = Theme.cellSeparatorColor
        tableView.register(ChatListCell.self, forCellReuseIdentifier: ChatListCell.reuseIdentifier)
        tableView.register(ArchivedConversationsCell.self, forCellReuseIdentifier: ArchivedConversationsCell.reuseIdentifier)
        tableView.tableFooterView = UIView()
    }
}

// MARK: -

extension CLVTableDataSource {
    public func threadViewModel(forThread thread: TSThread) -> ThreadViewModel {
        let threadViewModelCache = viewState.threadViewModelCache
        if let value = threadViewModelCache.get(key: thread.uniqueId) {
            return value
        }
        let threadViewModel = databaseStorage.read { transaction in
            ThreadViewModel(thread: thread, forChatList: true, transaction: transaction)
        }
        threadViewModelCache.set(key: thread.uniqueId, value: threadViewModel)
        return threadViewModel
    }

    @objc
    func threadViewModel(forIndexPath indexPath: IndexPath, expectsSuccess: Bool = true) -> ThreadViewModel? {
        guard let thread = self.thread(forIndexPath: indexPath, expectsSuccess: expectsSuccess) else {
            return nil
        }
        return self.threadViewModel(forThread: thread)
    }

    func thread(forIndexPath indexPath: IndexPath, expectsSuccess: Bool = true) -> TSThread? {
        renderState.thread(forIndexPath: indexPath, expectsSuccess: expectsSuccess)
    }
}

// MARK: - UIScrollViewDelegate

extension CLVTableDataSource: UIScrollViewDelegate {

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
            guard let section = ChatListSection(rawValue: indexPath.section) else {
                owsFailDebug("Invalid section: \(indexPath.section).")
                return nil
            }

            switch section {
            case .reminders:
                return nil
            case .pinned, .unpinned:
                return indexPath
            case .archiveButton:
                return nil
            }
        }
        guard !conversationIndexPaths.isEmpty else {
            return
        }
        let sortedIndexPaths = conversationIndexPaths.sorted()
        var indexPathsToPreload = [IndexPath]()
        func tryToEnqueue(_ indexPath: IndexPath) {
            let rowCount = numberOfRows(inSection: indexPath.section)
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

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        AssertIsOnMainThread()

        guard let viewController = viewController else {
            owsFailDebug("Missing viewController.")
            return
        }

        viewController.dismissSearchKeyboard()
    }
}

// MARK: -

@objc
public enum ChatListMode: Int, CaseIterable {
    case archive
    case inbox
}

// MARK: -

@objc
public enum ChatListSection: Int, CaseIterable {
    case reminders
    case pinned
    case unpinned
    case archiveButton
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
        if #available(iOS 13, *) {
            return false
        } else {
            return true
        }
    }

    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        AssertIsOnMainThread()

        guard let section = ChatListSection(rawValue: section) else {
            owsFailDebug("Invalid section: \(section).")
            return 0
        }

        switch section {
        case .pinned, .unpinned:
            if !renderState.hasPinnedAndUnpinnedThreads {
                return CGFloat.epsilon
            }

            return UITableView.automaticDimension
        default:
            // Without returning a header with a non-zero height, Grouped
            // table view will use a default spacing between sections. We
            // do not want that spacing so we use the smallest possible height.
            return CGFloat.epsilon
        }
    }

    public func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        AssertIsOnMainThread()

        // Without returning a footer with a non-zero height, Grouped
        // table view will use a default spacing between sections. We
        // do not want that spacing so we use the smallest possible height.
        return CGFloat.epsilon
    }

    public func tableView(_ tableView: UITableView,
                          viewForHeaderInSection section: Int) -> UIView? {
        AssertIsOnMainThread()

        guard let section = ChatListSection(rawValue: section) else {
            owsFailDebug("Invalid section: \(section).")
            return nil
        }

        switch section {
        case .pinned, .unpinned:
            let container = UIView()
            container.layoutMargins = UIEdgeInsets(top: 14, leading: 16, bottom: 8, trailing: 16)

            let label = UILabel()
            container.addSubview(label)
            label.autoPinEdgesToSuperviewMargins()
            label.font = UIFont.dynamicTypeBody.semibold()
            label.textColor = Theme.primaryTextColor
            label.text = (section == .pinned
                            ? OWSLocalizedString("PINNED_SECTION_TITLE",
                                                comment: "The title for pinned conversation section on the conversation list")
                            : OWSLocalizedString("UNPINNED_SECTION_TITLE",
                                                comment: "The title for unpinned conversation section on the conversation list"))

            return container
        default:
            return UIView()
        }
    }

    public func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        AssertIsOnMainThread()

        return UIView()
    }

    public func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        AssertIsOnMainThread()

        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return
        }
        if viewState.multiSelectState.isActive {
            viewController.updateCaptions()
        }
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        AssertIsOnMainThread()

        Logger.info("\(indexPath)")

        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return
        }

        viewController.dismissSearchKeyboard()

        guard let section = ChatListSection(rawValue: indexPath.section) else {
            owsFailDebug("Invalid section: \(indexPath.section).")
            return
        }

        switch section {
        case .reminders:
            tableView.deselectRow(at: indexPath, animated: false)
        case .pinned, .unpinned:
            guard let threadViewModel = threadViewModel(forIndexPath: indexPath) else {
                owsFailDebug("Missing threadViewModel.")
                return
            }
            if viewState.multiSelectState.isActive {
                viewController.updateCaptions()
            } else {
                viewController.presentThread(threadViewModel.threadRecord, animated: true)
            }
        case .archiveButton:
            if viewState.multiSelectState.isActive {
                tableView.deselectRow(at: indexPath, animated: false)
            } else {
                viewController.showArchivedConversations()
            }
        }
    }

    @available(iOS 13.0, *)
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

        return UIContextMenuConfiguration(identifier: thread.uniqueId as NSString,
                                          previewProvider: { [weak viewController] in
                                            viewController?.createPreviewController(atIndexPath: indexPath)
                                          },
                                          actionProvider: { _ in
                                            // nil for now. But we may want to add options like "Pin" or "Mute" in the future
                                            return nil
                                          })
    }

    @available(iOS 13.0, *)
    public func tableView(_ tableView: UITableView,
                          previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
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

    @available(iOS 13.0, *)
    public func tableView(_ tableView: UITableView,
                          willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
                          animator: UIContextMenuInteractionCommitAnimating) {
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

    public func tableView(_ tableView: UITableView,
                          willDisplay cell: UITableViewCell,
                          forRowAt indexPath: IndexPath) {
        AssertIsOnMainThread()

        guard let cell = cell as? ChatListCell else {
            return
        }
        viewController?.updateCellVisibility(cell: cell, isCellVisible: true)

        preloadCellsIfNecessary()
    }

    public func tableView(_ tableView: UITableView,
                          didEndDisplaying cell: UITableViewCell,
                          forRowAt indexPath: IndexPath) {
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
        AssertIsOnMainThread()

        return ChatListSection.allCases.count
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        AssertIsOnMainThread()

        return numberOfRows(inSection: section)
    }

    fileprivate func numberOfRows(inSection section: Int) -> Int {
        AssertIsOnMainThread()

        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return 0
        }

        guard let section = ChatListSection(rawValue: section) else {
            owsFailDebug("Invalid section: \(section).")
            return 0
        }
        switch section {
        case .reminders:
            return viewController.hasVisibleReminders ? 1 : 0
        case .pinned:
            return renderState.pinnedThreads.count
        case .unpinned:
            return renderState.unpinnedThreads.count
        case .archiveButton:
            return viewController.hasArchivedThreadsRow ? 1 : 0
        }
    }

    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        AssertIsOnMainThread()
                guard let section = ChatListSection(rawValue: indexPath.section) else {
            owsFailDebug("Invalid section: \(indexPath.section).")
            return UITableView.automaticDimension
        }

        switch section {
        case .reminders:
            return UITableView.automaticDimension
        case .pinned, .unpinned:
            return measureConversationCell(tableView: tableView, indexPath: indexPath)
        case .archiveButton:
            return UITableView.automaticDimension
        }
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        AssertIsOnMainThread()

        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return UITableViewCell()
        }
        guard let section = ChatListSection(rawValue: indexPath.section) else {
            owsFailDebug("Invalid section: \(indexPath.section).")
            return UITableViewCell()
        }

        let cell: UITableViewCell = {
            switch section {
            case .reminders:
                return viewController.reminderViewCell
            case .pinned, .unpinned:
                return buildConversationCell(tableView: tableView, indexPath: indexPath)
            case .archiveButton:
                return buildArchivedConversationsButtonCell(tableView: tableView, indexPath: indexPath)
            }
        }()

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
        guard let cellConfigurationAndContentToken = buildCellConfigurationAndContentTokenSync(forIndexPath: indexPath) else {
            owsFailDebug("Missing cellConfigurationAndContentToken.")
            return UITableView.automaticDimension
        }
        let result = ChatListCell.measureCellHeight(cellContentToken: cellConfigurationAndContentToken.contentToken)
        viewController.conversationCellHeightCache = result
        return result
    }

    private func buildConversationCell(tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        AssertIsOnMainThread()

        guard let cell = tableView.dequeueReusableCell(withIdentifier: ChatListCell.reuseIdentifier) as? ChatListCell else {
            owsFailDebug("Invalid cell.")
            return UITableViewCell()
        }
        guard let cellConfigurationAndContentToken = buildCellConfigurationAndContentTokenSync(forIndexPath: indexPath) else {
            owsFailDebug("Missing cellConfigurationAndContentToken.")
            return UITableViewCell()
        }
        let configuration = cellConfigurationAndContentToken.configuration
        let contentToken = cellConfigurationAndContentToken.contentToken

        cell.configure(cellContentToken: contentToken)
        let thread = configuration.thread.threadRecord
        let cellName: String = {
            if let groupThread = thread as? TSGroupThread {
                return "cell-group-\(groupThread.groupModel.groupName ?? "unknown")"
            } else if let contactThread = thread as? TSContactThread {
                return "cell-contact-\(contactThread.contactAddress.stringForDisplay)"
            } else {
                owsFailDebug("invalid-thread-\(thread.uniqueId) ")
                return "Unknown"
            }
        }()
        cell.accessibilityIdentifier = cellName

        if isConversationActive(forThread: thread) {
            tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
        } else if !viewState.multiSelectState.isActive {
            tableView.deselectRow(at: indexPath, animated: false)
        }

        updateAndSetRefreshTimer(for: cell)
        return cell
    }

    private func isConversationActive(forThread thread: TSThread) -> Bool {
        AssertIsOnMainThread()

        guard let conversationSplitViewController = splitViewController as? ConversationSplitViewController else {
            owsFailDebug("Missing conversationSplitViewController.")
            return false
        }
        return conversationSplitViewController.selectedThread?.uniqueId == thread.uniqueId
    }

    private func buildArchivedConversationsButtonCell(tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        AssertIsOnMainThread()

        guard let cell = tableView.dequeueReusableCell(withIdentifier: ArchivedConversationsCell.reuseIdentifier) else {
            owsFailDebug("Invalid cell.")
            return UITableViewCell()
        }
        if let cell = cell as? ArchivedConversationsCell, let viewController = viewController {
            cell.configure(enabled: !viewState.multiSelectState.isActive)
        }
        return cell
    }

    // MARK: - Edit Actions

    public func tableView(_ tableView: UITableView,
                          commit editingStyle: UITableViewCell.EditingStyle,
                          forRowAt indexPath: IndexPath) {
        AssertIsOnMainThread()

        // TODO: Is this method necessary?
    }

    public func tableView(_ tableView: UITableView,
                          trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        AssertIsOnMainThread()

        guard let section = ChatListSection(rawValue: indexPath.section) else {
            owsFailDebug("Invalid section: \(indexPath.section).")
            return nil
        }

        switch section {
        case .reminders, .archiveButton:
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

            return viewController.trailingSwipeActionsConfiguration(for: threadViewModel,
                                                                       closeConversationBlock: { [weak self] in
                if let self = self, self.isConversationActive(forThread: threadViewModel.threadRecord) {
                    viewController.conversationSplitViewController?.closeSelectedConversation(animated: true)
                }
            })
        }
    }

    public func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        AssertIsOnMainThread()

        guard let section = ChatListSection(rawValue: indexPath.section) else {
            owsFailDebug("Invalid section: \(indexPath.section).")
            return false
        }

        switch section {
        case .reminders:
            return false
        case .pinned, .unpinned:
            return true
        case .archiveButton:
            return false
        }
    }

    public func tableView(_ tableView: UITableView,
                          leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        AssertIsOnMainThread()

        guard let section = ChatListSection(rawValue: indexPath.section) else {
            owsFailDebug("Invalid section: \(indexPath.section).")
            return nil
        }

        switch section {
        case .reminders:
            return nil
        case .archiveButton:
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

    @objc
    public func stopRefreshTimer() {
        nextUpdateAt = nil
    }

    @objc
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
        guard let homeCell = tableView.cellForRow(at: indexPath) as? ChatListCell else { return false }
        guard let configToken = buildCellConfigurationAndContentTokenSync(forIndexPath: indexPath)?.contentToken else { return false }

        let cellWasVisible = homeCell.isCellVisible
        homeCell.reset()
        // reduces flicker effects for already visible cells
        homeCell.configure(cellContentToken: configToken, asyncAvatarLoadingAllowed: false)
        homeCell.isCellVisible = cellWasVisible
        return true
    }

    fileprivate struct CLVCellConfigurationAndContentToken {
        let configuration: ChatListCell.Configuration
        let contentToken: CLVCellContentToken
    }

    // This method can be called from any thread.
    private static func buildCellConfiguration(threadViewModel: ThreadViewModel,
                                               lastReloadDate: Date?) -> ChatListCell.Configuration {
        owsAssertDebug(threadViewModel.chatListInfo != nil)
        let configuration = ChatListCell.Configuration(thread: threadViewModel,
                                                       lastReloadDate: lastReloadDate,
                                                       isBlocked: threadViewModel.isBlocked)
        return configuration
    }

    fileprivate func buildCellConfigurationAndContentTokenSync(forIndexPath indexPath: IndexPath) -> CLVCellConfigurationAndContentToken? {
        AssertIsOnMainThread()

        guard let threadViewModel = threadViewModel(forIndexPath: indexPath) else {
            owsFailDebug("Missing threadViewModel.")
            return nil
        }
        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return nil
        }
        let lastReloadDate: Date? = {
            guard viewState.hasEverAppeared else {
                return nil
            }
            return self.lastReloadDate
        }()
        let configuration = Self.buildCellConfiguration(threadViewModel: threadViewModel,
                                                        lastReloadDate: lastReloadDate)
        let cellContentCache = viewController.cellContentCache
        let contentToken = { () -> CLVCellContentToken in
            // If we have an existing CLVCellContentToken, use it.
            // Cell measurement/arrangement is expensive.
            let cacheKey = configuration.thread.threadRecord.uniqueId
            if let cellContentToken = cellContentCache.get(key: cacheKey) {
                return cellContentToken
            }

            let cellContentToken = ChatListCell.buildCellContentToken(forConfiguration: configuration)
            cellContentCache.set(key: cacheKey, value: cellContentToken)
            return cellContentToken
        }()
        return CLVCellConfigurationAndContentToken(configuration: configuration,
                                                  contentToken: contentToken)
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

        guard let thread = self.thread(forIndexPath: indexPath) else {
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
            let threadViewModel = Self.databaseStorage.read { transaction in
                ThreadViewModel(thread: thread, forChatList: true, transaction: transaction)
            }
            let configuration = Self.buildCellConfiguration(threadViewModel: threadViewModel,
                                                            lastReloadDate: lastReloadDate)
            let contentToken = ChatListCell.buildCellContentToken(forConfiguration: configuration)
            return (threadViewModel, contentToken)
        }.done(on: DispatchQueue.main) { (threadViewModel: ThreadViewModel, contentToken: CLVCellContentToken) in
            // Commit the preloaded values to their respective caches.
            guard cellContentCacheResetCount == cellContentCache.resetCount else {
                Logger.info("cellContentCache was reset.")
                return
            }
            guard threadViewModelCacheResetCount == threadViewModelCache.resetCount else {
                Logger.info("cellContentCache was reset.")
                return
            }
            if nil == threadViewModelCache.get(key: cacheKey) {
                threadViewModelCache.set(key: cacheKey, value: threadViewModel)
            } else {
                Logger.info("threadViewModel already loaded.")
            }
            if nil == cellContentCache.get(key: cacheKey) {
                cellContentCache.set(key: cacheKey, value: contentToken)
            } else {
                Logger.info("contentToken already loaded.")
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

    @objc
    public override func reloadData() {
        AssertIsOnMainThread()

        lastReloadDate = Date()
        super.reloadData()
        (dataSource as? CLVTableDataSource)?.calcRefreshTimer()
    }

    @objc
    public required init() {
        super.init(frame: .zero, style: .grouped)
    }

    @available(*, unavailable, message: "use other constructor instead.")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
