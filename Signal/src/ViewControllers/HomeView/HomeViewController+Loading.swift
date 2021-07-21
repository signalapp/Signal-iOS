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

    public func updateShouldBeUpdatingView() {
        AssertIsOnMainThread()

        let isAppForegroundAndActive = CurrentAppContext().isAppForegroundAndActive()
        self.shouldBeUpdatingView = self.isViewVisible && isAppForegroundAndActive
    }

    // MARK: -

    @objc
    public func reloadTableViewData() {
        AssertIsOnMainThread()

        self.lastReloadDate = Date()
        tableView.reloadData()
    }

    // TODO: Make async.
    fileprivate func reloadEverythingAndReloadTable() {
        AssertIsOnMainThread()

        BenchManager.bench(title: "HomeViewController#reloadEverythingAndReloadTable") {
            guard let renderState = tryToLoadRenderState() else {
                owsFailDebug("Could not update renderState.")
                return
            }
            applyNewRenderState(renderState)
        }
    }

    private func tryToLoadRenderState() -> HVRenderState? {
        AssertIsOnMainThread()

        return Self.databaseStorage.read { transaction in
            HVLoader.loadRenderState(isViewingArchive: isViewingArchive,
                                     transaction: transaction)
        }
    }

    private func applyNewRenderState(_ renderState: HVRenderState) {
        AssertIsOnMainThread()

        tableDataSource.renderState = renderState
        threadViewModelCache.clear()
        _ = updateHasArchivedThreadsRow()
        reloadTableViewData()
        updateViewState()
    }

    private var isViewingArchive: Bool { self.homeViewMode == .archive }

    fileprivate func updateRenderStateWithDiff(updatedThreadIds updatedItemIds: Set<String>,
                                               isAnimated: Bool) {
        AssertIsOnMainThread()

        guard !updatedItemIds.isEmpty else {
            // Ignoring irrelevant update.
            updateViewState()
            return
        }

        let mappingDiff = Self.databaseStorage.read { transaction in
            HVLoader.loadRenderStateAndDiff(isViewingArchive: isViewingArchive,
                                            updatedItemIds: updatedItemIds,
                                            lastRenderState: renderState,
                                            transaction: transaction)
        }
        guard let mappingDiff = mappingDiff else {
            owsFailDebug("Could not update.")
            // Diffing failed, reload to get back to a known good state.
            reloadEverythingAndReloadTable()
            return
        }

        tableDataSource.renderState = mappingDiff.renderState

        // We want this regardless of if we're currently viewing the archive.
        // So we run it before the early return
        updateViewState()

        if mappingDiff.rowChanges.isEmpty {
            return
        }

        if updateHasArchivedThreadsRow() {
            reloadTableViewData()
            return
        }

        let tableView = self.tableView
        let threadViewModelCache = self.threadViewModelCache
        let rowAnimation: UITableView.RowAnimation = isAnimated ? .automatic : .none
        let applyChanges = {
            tableView.beginUpdates()
            for rowChange in mappingDiff.rowChanges {

                threadViewModelCache.removeObject(forKey: rowChange.threadUniqueId)

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

@objc
public class HVLoadCoordinator: NSObject {
    @objc
    public weak var viewController: HomeViewController?

    private class HVLoadInfo {
        // TODO: Review this state.
        var shouldResetAll = false
        var dirtyThreadUniqueIds = Set<String>()
    }
    private var nextLoadInfo = HVLoadInfo()

    @objc
    public override required init() {
        nextLoadInfo.shouldResetAll = true
    }

    public func scheduleHardReset() {
        AssertIsOnMainThread()

        nextLoadInfo.shouldResetAll = true

        loadIfNecessary()
    }

    public func scheduleLoad(updatedThreadIds: Set<String>) {
        AssertIsOnMainThread()
        owsAssertDebug(!updatedThreadIds.isEmpty)

        nextLoadInfo.dirtyThreadUniqueIds.formUnion(updatedThreadIds)

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
        let currentLoadInfo = self.nextLoadInfo
        self.nextLoadInfo = HVLoadInfo()

        if currentLoadInfo.shouldResetAll {
            viewController.reloadEverythingAndReloadTable()
        } else {
            viewController.updateRenderStateWithDiff(updatedThreadIds: currentLoadInfo.dirtyThreadUniqueIds,
                                                     isAnimated: !suppressAnimations)
        }
    }
}
