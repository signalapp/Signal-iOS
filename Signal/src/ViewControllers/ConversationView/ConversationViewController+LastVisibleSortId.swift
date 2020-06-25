//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

extension ConversationViewController {

    /// The visble content rect in the collection view's coordinate space
    /// This rect does not include displayed cells occluded by content inset
    @objc var visibleContentRect: CGRect {
        let collectionViewBounds = self.collectionView.bounds
        let insetBounds = collectionViewBounds.inset(by: self.collectionView.adjustedContentInset)
        return insetBounds
    }

    /// The index path of the last item in the collection view's visible rect
    @objc var lastVisibleIndexPath: IndexPath? {
        let visibleLayoutAttributes = self.layout.layoutAttributesForElements(in: self.visibleContentRect) ?? []

        let lastVisibleIndexPath = visibleLayoutAttributes
            .map { $0.indexPath }
            .max { $0.row < $1.row }

        assert(lastVisibleIndexPath == nil || percentOfIndexPathVisibleAboveBottom(lastVisibleIndexPath!) > 0)
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
            let (indexPath, sortId) = firstIndexPathWithSortId(atOrBeforeIndexPath: lastVisibleIndexPath),
            self.layout.layoutAttributesForItem(at: indexPath) != nil {

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
        guard let attributes = self.layout.layoutAttributesForItem(at: indexPath) else { return 0.0 }

        // Map everything to view controller's coordinate space
        let cellFrame_vcView = self.view.convert(attributes.frame, from: self.collectionView)
        let visibleRect_vcView = self.view.convert(self.visibleContentRect, from: self.collectionView)

        let intersectionRect = visibleRect_vcView.intersection(cellFrame_vcView)
        return CGFloatClamp01(intersectionRect.height / cellFrame_vcView.height)
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
