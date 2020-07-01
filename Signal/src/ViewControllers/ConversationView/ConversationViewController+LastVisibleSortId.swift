//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

extension ConversationViewController {

    /// The visble content rect in the collection view's coordinate space
    /// This rect does not include displayed cells occluded by content inset
    @objc var visibleContentRect: CGRect {
        let collectionViewBounds = collectionView.bounds
        let insetBounds = collectionViewBounds.inset(by: collectionView.adjustedContentInset)
        return insetBounds
    }

    /// The index path of the last item in the collection view's visible rect
    @objc var lastVisibleIndexPath: IndexPath? {
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
            assert(percentOfIndexPathVisibleAboveBottom(lastVisibleIndexPath) > 0)
        }
        return lastVisibleIndexPath
    }

    @objc
    var lastVisibleSortId: UInt64 {
        guard let lastVisibleIndexPath = lastVisibleIndexPath else { return 0 }
        return firstIndexPathWithSortId(atOrBeforeIndexPath: lastVisibleIndexPath)?.sortId ?? 0
    }

    @objc
    var lastIndexPathInLoadedWindow: IndexPath? {
        guard !viewItems.isEmpty else { return nil }
        return IndexPath(row: viewItems.count - 1, section: 0)
    }

    @objc
    var lastSortIdInLoadedWindow: UInt64 {
        guard let lastIndexPath = lastIndexPathInLoadedWindow else { return 0 }
        return firstIndexPathWithSortId(atOrBeforeIndexPath: lastIndexPath)?.sortId ?? 0
    }

    @objc
    func saveLastVisibleSortIdAndOnScreenPercentage() {
        AssertIsOnMainThread()

        let sortIdToSave: UInt64
        let onScreenPercentageToSave: Double

        if let lastVisibleIndexPath = lastVisibleIndexPath,
            let (indexPath, sortId) = firstIndexPathWithSortId(atOrBeforeIndexPath: lastVisibleIndexPath) {

            sortIdToSave = sortId
            onScreenPercentageToSave = Double(percentOfIndexPathVisibleAboveBottom(indexPath))
        } else {
            sortIdToSave = 0
            onScreenPercentageToSave = 0
        }

        guard thread.lastVisibleSortId != sortIdToSave
            || !thread.lastVisibleSortIdOnScreenPercentage.isEqual(to: onScreenPercentageToSave) else {
                return
        }

        databaseStorage.asyncWrite { transaction in
            self.thread.update(
                withLastVisibleSortId: sortIdToSave,
                onScreenPercentage: onScreenPercentageToSave,
                transaction: transaction
            )
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
        return CGFloatClamp01(heightAboveBottom / cellFrameInPrimaryCoordinateSpace.height)
    }

    private func firstIndexPathWithSortId(atOrBeforeIndexPath indexPath: IndexPath) -> (indexPath: IndexPath, sortId: UInt64)? {
        AssertIsOnMainThread()

        var matchingIndexPath = indexPath

        while let viewItem = viewItem(forIndex: matchingIndexPath.row), matchingIndexPath.row > 0 {
            guard !viewItem.interaction.isDynamicInteraction() else {
                matchingIndexPath.row -= 1
                continue
            }

            return (matchingIndexPath, viewItem.interaction.sortId)
        }

        return nil
    }
}
