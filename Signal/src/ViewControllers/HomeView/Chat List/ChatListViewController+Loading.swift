//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

extension ChatListViewController {

    public var isViewVisible: Bool {
        get { viewState.isViewVisible }
        set {
            viewState.isViewVisible = newValue

            updateShouldBeUpdatingView()
            updateCellVisibility()
        }
    }

    fileprivate var shouldBeUpdatingView: Bool {
        get { viewState.shouldBeUpdatingView }
        set {
            guard viewState.shouldBeUpdatingView != newValue else {
                // Ignore redundant changes.
                return
            }
            viewState.shouldBeUpdatingView = newValue

            if newValue {
                loadCoordinator.loadIfNecessary(suppressAnimations: true)
            }
        }
    }

    public var hasVisibleReminders: Bool {
        renderState.hasVisibleReminders
    }

    public var hasArchivedThreadsRow: Bool {
        renderState.hasArchivedThreadsRow
    }

    // MARK: -

    public func loadIfNecessary() {
        loadCoordinator.loadIfNecessary()
    }

    func updateShouldBeUpdatingView() {
        AssertIsOnMainThread()

        let isAppForegroundAndActive = CurrentAppContext().isAppForegroundAndActive()

        self.shouldBeUpdatingView = self.isViewVisible && isAppForegroundAndActive
    }

    // MARK: -

    fileprivate func loadRenderStateForReset(viewInfo: CLVViewInfo,
                                             transaction: SDSAnyReadTransaction) -> CLVLoadResult {
        AssertIsOnMainThread()

        return Bench(title: "loadNewRenderState") {
            CLVLoader.loadRenderStateForReset(viewInfo: viewInfo, transaction: transaction)
        }
    }

    fileprivate func loadNewRenderStateWithDiff(viewInfo: CLVViewInfo,
                                                updatedThreadIds: Set<String>,
                                                transaction: SDSAnyReadTransaction) -> CLVLoadResult {
        AssertIsOnMainThread()

        guard !updatedThreadIds.isEmpty else {
            owsFailDebug("Empty updatedThreadIds.")
            // Ignoring irrelevant update.
            return .noChanges
        }

        return CLVLoader.loadRenderStateAndDiff(viewInfo: viewInfo,
                                               updatedItemIds: updatedThreadIds,
                                               lastRenderState: renderState,
                                               transaction: transaction)
    }

    fileprivate func applyLoadResult(_ loadResult: CLVLoadResult,
                                     isAnimated: Bool) {
        AssertIsOnMainThread()

        switch loadResult {
        case .renderStateForReset(renderState: let renderState):
            tableDataSource.renderState = renderState

            threadViewModelCache.clear()
            cellContentCache.clear()
            conversationCellHeightCache = nil

            reloadTableData()
        case .renderStateWithRowChanges(renderState: let renderState, let rowChanges):
            tableDataSource.renderState = renderState
            applyPartialLoadResult(rowChanges: rowChanges,
                                   isAnimated: isAnimated)
        case .renderStateWithoutRowChanges(let renderState):
            tableDataSource.renderState = renderState
        case .reloadTable:
            reloadTableData()
        case .noChanges:
            break
        }

        tableDataSource.calcRefreshTimer()
        // We need to perform this regardless of the load result type.
        updateViewState()
        updateBarButtonItems()
    }

    fileprivate func applyPartialLoadResult(rowChanges: [CLVRowChange],
                                            isAnimated: Bool) {
        AssertIsOnMainThread()

        guard !rowChanges.isEmpty else {
            owsFailDebug("Empty rowChanges.")
            return
        }

        let tableView = self.tableView
        let threadViewModelCache = self.threadViewModelCache
        let cellContentCache = self.cellContentCache
        let rowAnimation: UITableView.RowAnimation = isAnimated ? .automatic : .none

        // only perform a beginUpdates/endUpdates block if really necessary, otherwise
        // strange scroll animations may occur
        var tableUpdatesPerformed = false
        let checkAndSetTableUpdates = { [weak self] in
            if !tableUpdatesPerformed, let self = self {
                tableView.beginUpdates()
                // animate all UI changes within the same transaction
                if tableView.isEditing && !self.viewState.multiSelectState.isActive {
                    tableView.setEditing(false, animated: true)
                }
                tableUpdatesPerformed = true
            }
        }

        // Ss soon as structural changes are applied to the table we can not use our optimized update implementation
        // anymore. All indexPaths are based on the old model (before any change was applied) and if we
        // animate move, insert and delete changes the indexPaths of the to be updated rows will differ.
        var useFallBackUpdateMechanism = false
        for rowChange in rowChanges {

            threadViewModelCache.removeObject(forKey: rowChange.threadUniqueId)
            cellContentCache.removeObject(forKey: rowChange.threadUniqueId)

            if !DebugFlags.reduceLogChatter {
                Logger.verbose("----- \(rowChange.logSafeDescription)")
            }
            switch rowChange.type {
            case .delete(let oldIndexPath):
                checkAndSetTableUpdates()
                tableView.deleteRows(at: [oldIndexPath], with: rowAnimation)
                useFallBackUpdateMechanism = true
            case .insert(let newIndexPath):
                checkAndSetTableUpdates()
                tableView.insertRows(at: [newIndexPath], with: rowAnimation)
                useFallBackUpdateMechanism = true
            case .move(let oldIndexPath, let newIndexPath):
                // NOTE: if we're moving within the same section, we perform
                //       moves using a "delete" and "insert" rather than a "move".
                //       This ensures that moved items are also reloaded. This is
                //       how UICollectionView performs reloads internally. We can't
                //       do this when changing sections, because it results in a weird
                //       animation. This should generally be safe, because you'll only
                //       move between sections when pinning / unpinning which doesn't
                //       require the moved item to be reloaded.
                checkAndSetTableUpdates()
                if oldIndexPath.section != newIndexPath.section {
                    tableView.moveRow(at: oldIndexPath, to: newIndexPath)
                } else {
                    tableView.deleteRows(at: [oldIndexPath], with: rowAnimation)
                    tableView.insertRows(at: [newIndexPath], with: rowAnimation)
                }
                useFallBackUpdateMechanism = true
            case .update(let oldIndexPath):
                if tableView.isEditing && !viewState.multiSelectState.isActive {
                    checkAndSetTableUpdates()
                }
                if !useFallBackUpdateMechanism, let tds = tableView.dataSource as? CLVTableDataSource {
                    useFallBackUpdateMechanism = !tds.updateVisibleCellContent(at: oldIndexPath, for: tableView)
                }
                if useFallBackUpdateMechanism {
                    checkAndSetTableUpdates()
                    tableView.reloadRows(at: [oldIndexPath], with: .none)
                }
            }
        }
        if tableUpdatesPerformed {
            tableView.endUpdates()
        }
        BenchManager.completeEvent(eventId: "uiDatabaseUpdate")
    }
}

// MARK: -

private enum CLVLoadType {
    case resetAll
    case incrementalDiff(updatedThreadIds: Set<String>)
    case reloadTableOnly
    case none
}

// MARK: -

public class CLVLoadCoordinator: Dependencies {

    public weak var viewController: ChatListViewController?

    private struct CLVLoadInfo {
        let viewInfo: CLVViewInfo
        let loadType: CLVLoadType
    }
    private class CLVLoadInfoBuilder {
        var shouldResetAll = false
        var updatedThreadIds = Set<String>()

        func build(chatListMode: ChatListMode,
                   hasVisibleReminders: Bool,
                   canApplyRowChanges: Bool,
                   lastViewInfo: CLVViewInfo,
                   transaction: SDSAnyReadTransaction) -> CLVLoadInfo {
            let viewInfo = CLVViewInfo.build(chatListMode: chatListMode,
                                            hasVisibleReminders: hasVisibleReminders,
                                            transaction: transaction)
            if shouldResetAll ||
                viewInfo.hasArchivedThreadsRow != lastViewInfo.hasArchivedThreadsRow ||
                viewInfo.hasVisibleReminders != lastViewInfo.hasVisibleReminders {
                return CLVLoadInfo(viewInfo: viewInfo, loadType: .resetAll)
            } else if !updatedThreadIds.isEmpty {
                if canApplyRowChanges {
                    return CLVLoadInfo(viewInfo: viewInfo, loadType: .incrementalDiff(updatedThreadIds: updatedThreadIds))
                } else {
                    return CLVLoadInfo(viewInfo: viewInfo, loadType: .resetAll)
                }
            } else if viewInfo != lastViewInfo {
                return CLVLoadInfo(viewInfo: viewInfo, loadType: .reloadTableOnly)
            } else {
                return CLVLoadInfo(viewInfo: viewInfo, loadType: .none)
            }
        }
    }
    private var loadInfoBuilder = CLVLoadInfoBuilder()

    public required init() {
        loadInfoBuilder.shouldResetAll = true
    }

    public func scheduleHardReset() {
        AssertIsOnMainThread()

        loadInfoBuilder.shouldResetAll = true

        loadIfNecessary()
    }

    public func scheduleLoad(updatedThreadIds: Set<String>) {
        AssertIsOnMainThread()
        owsAssertDebug(!updatedThreadIds.isEmpty)

        if DebugFlags.internalLogging {
            Logger.info("[Scroll Perf Debug] 'Other' updateThreadIds to make union with (count \(loadInfoBuilder.updatedThreadIds.count)): \(loadInfoBuilder.updatedThreadIds)")
        }
        loadInfoBuilder.updatedThreadIds.formUnion(updatedThreadIds)

        loadIfNecessary()
    }

    public func ensureFirstLoad() {
        AssertIsOnMainThread()

        guard let viewController else {
            owsFailDebug("Missing viewController.")
            return
        }

        // During main app launch, the chat list becomes visible _before_
        // app is foreground and active.  Therefore we need to make an
        // exception and update the view contents; otherwise, the home
        // view will briefly appear empty after launch.
        let shouldForceLoad = (!viewController.hasEverAppeared &&
                                viewController.tableDataSource.renderState.visibleThreadCount == 0)

        loadIfNecessary(suppressAnimations: true, shouldForceLoad: shouldForceLoad)
    }

    @objc
    public func applicationWillEnterForeground() {
        AssertIsOnMainThread()

        guard let viewController = viewController else {
            owsFailDebug("Missing viewController.")
            return
        }

        if viewController.isViewVisible {
            // When app returns from background, it should perform one load
            // immediately (before entering the foreground) without animations.
            // Otherwise, the user sees the changes that occurred in the
            // background animate in.
            loadIfNecessary(suppressAnimations: true, shouldForceLoad: true)
        } else {
            viewController.updateViewState()
        }
    }

    public func loadIfNecessary(suppressAnimations: Bool = false,
                                shouldForceLoad: Bool = false) {
        AssertIsOnMainThread()

        guard let viewController else {
            owsFailDebug("Missing viewController.")
            return
        }

        guard viewController.shouldBeUpdatingView || shouldForceLoad else { return }

        // Copy the "current" load info, reset "next" load info.

        let reminderViews = viewController.viewState.reminderViews
        let hasVisibleReminders = reminderViews.hasVisibleReminders

        let loadResult: CLVLoadResult = databaseStorage.read { transaction in
            // Decide what kind of load we prefer.
            let canApplyRowChanges = viewController.tableDataSource.renderState.visibleThreadCount > 0
            let loadInfo = loadInfoBuilder.build(chatListMode: viewController.chatListMode,
                                                 hasVisibleReminders: hasVisibleReminders,
                                                 canApplyRowChanges: canApplyRowChanges,
                                                 lastViewInfo: viewController.renderState.viewInfo,
                                                 transaction: transaction)
            // Reset the builder.
            loadInfoBuilder = CLVLoadInfoBuilder()

            // Perform the load.
            //
            // NOTE: we might not receive the kind of load that we requested.
            switch loadInfo.loadType {
            case .resetAll:
                if DebugFlags.internalLogging {
                    Logger.info("[Scroll Perf Debug] About to do resetAll load")
                }
                return viewController.loadRenderStateForReset(viewInfo: loadInfo.viewInfo,
                                                              transaction: transaction)
            case .incrementalDiff(let updatedThreadIds):
                owsAssertDebug(!updatedThreadIds.isEmpty)
                if DebugFlags.internalLogging {
                    Logger.info("[Scroll Perf Debug] About to do incrementalDiff load")
                }
                return viewController.loadNewRenderStateWithDiff(viewInfo: loadInfo.viewInfo,
                                                                 updatedThreadIds: updatedThreadIds,
                                                                 transaction: transaction)
            case .reloadTableOnly:
                return .reloadTable
            case .none:
                return .noChanges
            }
        }

        // Apply the load to the view.
        let wasViewEmpty = viewController.tableDataSource.renderState.visibleThreadCount == 0
        let isAnimated = !suppressAnimations && !wasViewEmpty && viewController.hasEverAppeared
        if isAnimated {
            viewController.applyLoadResult(loadResult, isAnimated: isAnimated)
        } else {
            // Suppress animations.
            UIView.animate(withDuration: 0) {
                viewController.applyLoadResult(loadResult, isAnimated: isAnimated)
            }
        }
    }
}
