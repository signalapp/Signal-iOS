//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

extension ConversationViewController {

    /// The visible content rect in the collection view's coordinate space
    /// This rect does not include displayed cells occluded by content inset
    var visibleContentRect: CGRect {
        let collectionViewBounds = collectionView.bounds
        let insetBounds = collectionViewBounds.inset(by: collectionView.adjustedContentInset)
        return insetBounds
    }

    /// The index path of the last item in the collection view's visible rect
    public var firstVisibleIndexPath: IndexPath? {
        // For people looking at this in the future, UICollectionView has a very similar looking
        // property: -indexPathsForVisibleItems. Why aren't we using that?
        //
        // That property *almost* gives us what we want, but UIKit ordering isn't favorable. That property
        // gets updated after -scrollViewDidScroll: returns. But sometimes we want to know what cells are visible
        // with the updated -contentOffset in -scrollViewDidScroll:. So instead, we'll just see what layoutAttributes
        // are now in the collection view's visible content rect. This should be safe, since it's computed from the
        // already updated -contentOffset.
        let visibleLayoutAttributes = layout.layoutAttributesForElements(in: visibleContentRect) ?? []

        let firstVisibleIndexPath = visibleLayoutAttributes
            .map { $0.indexPath }
            .min { $0.row < $1.row }

        if let firstVisibleIndexPath = firstVisibleIndexPath {
            owsAssertDebug(percentOfIndexPathVisibleAboveBottom(firstVisibleIndexPath) > 0)
        }
        return firstVisibleIndexPath
    }

    /// The index path of the last item in the collection view's visible rect
    public var lastVisibleIndexPath: IndexPath? {
        // For people looking at this in the future, UICollectionView has a very similar looking
        // property: -indexPathsForVisibleItems. Why aren't we using that?
        //
        // That property *almost* gives us what we want, but UIKit ordering isn't favorable. That property
        // gets updated after -scrollViewDidScroll: returns. But sometimes we want to know what cells are visible
        // with the updated -contentOffset in -scrollViewDidScroll:. So instead, we'll just see what layoutAttributes
        // are now in the collection view's visible content rect. This should be safe, since it's computed from the
        // already updated -contentOffset.
        let visibleLayoutAttributes = layout.layoutAttributesForElements(in: visibleContentRect) ?? []

        let lastVisibleIndexPath = visibleLayoutAttributes
            .map { $0.indexPath }
            .max { $0.row < $1.row }

        if let lastVisibleIndexPath = lastVisibleIndexPath {
            owsAssertDebug(percentOfIndexPathVisibleAboveBottom(lastVisibleIndexPath) > 0)
        }
        return lastVisibleIndexPath
    }

    var lastVisibleSortId: UInt64 {
        guard let lastVisibleIndexPath = lastVisibleIndexPath else { return 0 }
        return firstRenderItemReferenceWithSortId(atOrBeforeIndexPath: lastVisibleIndexPath)?.sortId ?? 0
    }

    var lastIndexPathInLoadedWindow: IndexPath? {
        guard !renderItems.isEmpty else { return nil }
        return IndexPath(row: renderItems.count - 1, section: 0)
    }

    var lastSortIdInLoadedWindow: UInt64 {
        guard let lastIndexPath = lastIndexPathInLoadedWindow else { return 0 }
        return firstRenderItemReferenceWithSortId(atOrBeforeIndexPath: lastIndexPath)?.sortId ?? 0
    }

    func saveLastVisibleSortIdAndOnScreenPercentage(async: Bool = false) {
        AssertIsOnMainThread()

        guard hasAppearedAndHasAppliedFirstLoad else {
            return
        }
        guard !isMeasuringKeyboardHeight else {
            return
        }

        let newValue: TSThread.LastVisibleInteraction? = {
            guard
                let lastVisibleIndexPath,
                let reference = firstRenderItemReferenceWithSortId(atOrBeforeIndexPath: lastVisibleIndexPath)
            else {
                return nil
            }
            let onScreenPercentage = percentOfIndexPathVisibleAboveBottom(reference.indexPath)
            return TSThread.LastVisibleInteraction(sortId: reference.sortId, onScreenPercentage: onScreenPercentage)
        }()

        let updateBlock: () -> Void = { [thread] in
            let oldValue = DependenciesBridge.shared.db.read { tx in
                DependenciesBridge.shared.lastVisibleInteractionStore.lastVisibleInteraction(for: thread, tx: tx)
            }

            guard oldValue != newValue else {
                return
            }

            DependenciesBridge.shared.db.asyncWrite { tx in
                DependenciesBridge.shared.lastVisibleInteractionStore.setLastVisibleInteraction(
                    newValue,
                    for: thread,
                    tx: tx
                )
            }
        }
        if async {
            DispatchQueue.sharedUserInitiated.async { updateBlock() }
        } else {
            updateBlock()
        }
    }

    private func percentOfIndexPathVisibleAboveBottom(_ indexPath: IndexPath) -> CGFloat {

        // If we don't have layout attributes, it's not visible
        guard let attributes = layout.layoutAttributesForItem(at: indexPath) else { return 0.0 }

        // Map everything to view controller's coordinate space
        let cellFrameInPrimaryCoordinateSpace = view.convert(attributes.frame, from: collectionView)
        let contentFrameInPrimaryCoordinateSpace = view.convert(visibleContentRect, from: collectionView)

        // Distance between top edge of cell's frame and the bottom of the content frame
        let heightAboveBottom = contentFrameInPrimaryCoordinateSpace.maxY - cellFrameInPrimaryCoordinateSpace.minY
        return CGFloat.clamp01(heightAboveBottom / cellFrameInPrimaryCoordinateSpace.height)
    }

    struct RenderItemReference {
        let renderItem: CVRenderItem
        let indexPath: IndexPath

        var interaction: TSInteraction { renderItem.interaction }
        var sortId: UInt64 { interaction.sortId }
    }

    private func firstRenderItemReferenceWithSortId(atOrBeforeIndexPath indexPath: IndexPath) -> RenderItemReference? {
        AssertIsOnMainThread()

        var matchingIndexPath = indexPath

        while matchingIndexPath.row >= 0,
              matchingIndexPath.row < renderItems.count,
              let renderItem = renderItem(forIndex: matchingIndexPath.row) {
            guard !renderItem.interaction.isDynamicInteraction else {
                guard matchingIndexPath.row > 0 else {
                    return nil
                }
                matchingIndexPath.row -= 1
                continue
            }

            return RenderItemReference(renderItem: renderItem, indexPath: matchingIndexPath)
        }

        return nil
    }
}
