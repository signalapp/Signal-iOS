//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

extension HomeViewController {

    @objc
    public var isViewVisible: Bool {
        get { viewState.isViewVisible }
        set {
            viewState.isViewVisible = newValue

            updateShouldBeUpdatingView()
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

    @objc
    public var hasVisibleReminders: Bool {
        renderState.hasVisibleReminders
    }

    @objc
    public var hasArchivedThreadsRow: Bool {
        renderState.hasArchivedThreadsRow
    }

    // MARK: -

    @objc
    public func loadIfNecessary() {
        loadCoordinator.loadIfNecessary()
    }

    func updateShouldBeUpdatingView() {
        AssertIsOnMainThread()

        let isAppForegroundAndActive = CurrentAppContext().isAppForegroundAndActive()
        self.shouldBeUpdatingView = self.isViewVisible && isAppForegroundAndActive
    }

    // MARK: -

    fileprivate func loadRenderStateForReset(viewInfo: HVViewInfo,
                                             transaction: SDSAnyReadTransaction) -> HVLoadResult {
        AssertIsOnMainThread()

        return Bench(title: "loadNewRenderState") {
            HVLoader.loadRenderStateForReset(viewInfo: viewInfo, transaction: transaction)
        }
    }

    fileprivate func loadNewRenderStateWithDiff(viewInfo: HVViewInfo,
                                                updatedThreadIds: Set<String>,
                                                transaction: SDSAnyReadTransaction) -> HVLoadResult {
        AssertIsOnMainThread()

        guard !updatedThreadIds.isEmpty else {
            owsFailDebug("Empty updatedThreadIds.")
            // Ignoring irrelevant update.
            return .noChanges
        }

        return HVLoader.loadRenderStateAndDiff(viewInfo: viewInfo,
                                               updatedItemIds: updatedThreadIds,
                                               lastRenderState: renderState,
                                               transaction: transaction)
    }

    fileprivate func applyLoadResult(_ loadResult: HVLoadResult,
                                     isAnimated: Bool) {
        AssertIsOnMainThread()

        switch loadResult {
        case .renderStateForReset(renderState: let renderState):
            tableDataSource.renderState = renderState
            threadViewModelCache.clear()
            cellMeasurementCache.clear()
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

        // We need to perform this regardless of the load result type.
        updateViewState()
    }

    fileprivate func applyPartialLoadResult(rowChanges: [HVRowChange],
                                            isAnimated: Bool) {
        AssertIsOnMainThread()

        guard !rowChanges.isEmpty else {
            owsFailDebug("Empty rowChanges.")
            return
        }

        let tableView = self.tableView
        let threadViewModelCache = self.threadViewModelCache
        let cellMeasurementCache = self.cellMeasurementCache
        let rowAnimation: UITableView.RowAnimation = isAnimated ? .automatic : .none
        let applyChanges = {
            tableView.beginUpdates()
            for rowChange in rowChanges {

                threadViewModelCache.removeObject(forKey: rowChange.threadUniqueId)
                cellMeasurementCache.removeObject(forKey: rowChange.threadUniqueId)

                switch rowChange.type {
                case .delete(let oldIndexPath):
                    Logger.verbose("----- delete: \(oldIndexPath)")
                    tableView.deleteRows(at: [oldIndexPath], with: rowAnimation)
                case .insert(let newIndexPath):
                    Logger.verbose("----- insert: \(newIndexPath)")
                    tableView.insertRows(at: [newIndexPath], with: rowAnimation)
                case .move(let oldIndexPath, let newIndexPath):
                    // NOTE: if we're moving within the same section, we perform
                    //       moves using a "delete" and "insert" rather than a "move".
                    //       This ensures that moved items are also reloaded. This is
                    //       how UICollectionView performs reloads internally. We can't
                    //       do this when changing sections, because it results in a weird
                    //       animation. This should generally be safe, because you'll only
                    //       move between sections when pinning / unpinning which doesn't
                    //       require the moved item to be reloaded.
                    Logger.verbose("----- move: \(oldIndexPath) -> \(newIndexPath)")
                    if oldIndexPath.section != newIndexPath.section {
                        tableView.moveRow(at: oldIndexPath, to: newIndexPath)
                    } else {
                        tableView.deleteRows(at: [oldIndexPath], with: rowAnimation)
                        tableView.insertRows(at: [newIndexPath], with: rowAnimation)
                    }
                case .update(let oldIndexPath):
                    Logger.verbose("----- update: \(oldIndexPath)")
                    tableView.reloadRows(at: [oldIndexPath], with: .none)
                }
            }

            tableView.endUpdates()
        }
        if isAnimated {
            applyChanges()
        } else {
            // Suppress animations.
            UIView.animate(withDuration: 0, animations: applyChanges)
        }
        BenchManager.completeEvent(eventId: "uiDatabaseUpdate")
    }
}

// MARK: -

private enum HVLoadType {
    case resetAll
    case incrementalDiff(updatedThreadIds: Set<String>)
    case reloadTableOnly
    case none
}

// MARK: -

@objc
public class HVLoadCoordinator: NSObject {
    @objc
    public weak var viewController: HomeViewController?

    private struct HVLoadInfo {
        let viewInfo: HVViewInfo
        let loadType: HVLoadType
    }
    private class HVLoadInfoBuilder {
        var shouldResetAll = false
        var updatedThreadIds = Set<String>()

        func build(homeViewMode: HomeViewMode,
                   hasVisibleReminders: Bool,
                   lastViewInfo: HVViewInfo,
                   transaction: SDSAnyReadTransaction) -> HVLoadInfo {
            let viewInfo = HVViewInfo.build(homeViewMode: homeViewMode,
                                            hasVisibleReminders: hasVisibleReminders,
                                            transaction: transaction)
            if shouldResetAll ||
                viewInfo.hasArchivedThreadsRow != lastViewInfo.hasArchivedThreadsRow ||
                viewInfo.hasVisibleReminders != lastViewInfo.hasVisibleReminders {
                return HVLoadInfo(viewInfo: viewInfo, loadType: .resetAll)
            } else if !updatedThreadIds.isEmpty {
                return HVLoadInfo(viewInfo: viewInfo, loadType: .incrementalDiff(updatedThreadIds: updatedThreadIds))
            } else if viewInfo != lastViewInfo {
                return HVLoadInfo(viewInfo: viewInfo, loadType: .reloadTableOnly)
            } else {
                return HVLoadInfo(viewInfo: viewInfo, loadType: .none)
            }
        }
    }
    private var loadInfoBuilder = HVLoadInfoBuilder()

    @objc
    public override required init() {
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

        loadInfoBuilder.updatedThreadIds.formUnion(updatedThreadIds)

        loadIfNecessary()
    }

    public func loadIfNecessary(suppressAnimations: Bool = false) {
        AssertIsOnMainThread()

        guard let viewController = viewController else {
            owsFailDebug("Missing viewController.")
            return
        }
        guard viewController.shouldBeUpdatingView else {
            return
        }

        // Copy the "current" load info, reset "next" load info.

        let reminderViews = viewController.viewState.reminderViews
        let hasVisibleReminders = reminderViews.hasVisibleReminders

        let loadResult: HVLoadResult = databaseStorage.read { transaction in
            // Decide what kind of load we prefer.
            let loadInfo = loadInfoBuilder.build(homeViewMode: viewController.homeViewMode,
                                                 hasVisibleReminders: hasVisibleReminders,
                                                 lastViewInfo: viewController.renderState.viewInfo,
                                                 transaction: transaction)
            // Reset the builder.
            loadInfoBuilder = HVLoadInfoBuilder()

            // Perform the load.
            //
            // NOTE: we might not receive the kind of load that we requested.
            switch loadInfo.loadType {
            case .resetAll:
                return viewController.loadRenderStateForReset(viewInfo: loadInfo.viewInfo,
                                                              transaction: transaction)
            case .incrementalDiff(let updatedThreadIds):
                owsAssertDebug(!updatedThreadIds.isEmpty)
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
        let isAnimated = !suppressAnimations
        viewController.applyLoadResult(loadResult, isAnimated: isAnimated)
    }
}
