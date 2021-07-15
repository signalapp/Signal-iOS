//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

extension HomeViewController {

    @objc
    public func reloadTableViewData() {
        AssertIsOnMainThread()

        self.lastReloadDate = Date()
        tableView.reloadData()
    }

    // TODO: Make async.
    @objc
    public func resetMappings() {
        AssertIsOnMainThread()

        BenchManager.bench(title: "HomeViewController#resetMappings") {
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

    func updateRenderStateWithDiff(updatedThreadIds updatedItemIds: Set<String>) {
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
            resetMappings()
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

        tableView.beginUpdates()

        for rowChange in mappingDiff.rowChanges {

            threadViewModelCache.removeObject(forKey: rowChange.threadUniqueId)

            switch rowChange.type {
            case .delete:
                guard let oldIndexPath = rowChange.oldIndexPath else {
                    owsFailDebug("Missing rowChange.oldIndexPath.")
                    continue
                }
                Logger.verbose("----- delete: \(oldIndexPath)")
                tableView.deleteRows(at: [oldIndexPath], with: .automatic)
            case .insert:
                guard let newIndexPath = rowChange.newIndexPath else {
                    owsFailDebug("Missing rowChange.newIndexPath.")
                    continue
                }
                Logger.verbose("----- insert: \(newIndexPath)")
                tableView.insertRows(at: [newIndexPath], with: .automatic)
            case .move:
                guard let oldIndexPath = rowChange.oldIndexPath else {
                    owsFailDebug("Missing rowChange.oldIndexPath.")
                    continue
                }
                guard let newIndexPath = rowChange.newIndexPath else {
                    owsFailDebug("Missing rowChange.newIndexPath.")
                    continue
                }
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
                    tableView.deleteRows(at: [oldIndexPath], with: .automatic)
                    tableView.insertRows(at: [newIndexPath], with: .automatic)
                }
            case .update:
                guard let oldIndexPath = rowChange.oldIndexPath else {
                    owsFailDebug("Missing rowChange.oldIndexPath.")
                    continue
                }
                Logger.verbose("----- update: \(oldIndexPath)")
                tableView.reloadRows(at: [oldIndexPath], with: .none)
            }
        }

        tableView.endUpdates()
        BenchManager.completeEvent(eventId: "uiDatabaseUpdate")
    }
}
