//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

extension ConversationViewController {
    @objc
    var lastVisibleIndexPath: IndexPath? {
        return collectionView.indexPathsForVisibleItems
            .lazy
            .sorted { $0.row > $1.row }
            .first { percentOfIndexPathVisibleAboveBottom($0) ?? 0 > 0 }
    }

    @objc
    var lastVisibleSortId: UInt64 {
        guard let lastVisibleIndexPath = lastVisibleIndexPath else { return 0 }
        return firstIndexPathWithSortId(atOrBeforeIndexPath: lastVisibleIndexPath)?.sortId ?? 0
    }

    @objc
    var lastIndexPath: IndexPath? {
        guard !viewItems.isEmpty else { return nil }
        return IndexPath(row: viewItems.count - 1, section: 0)
    }

    @objc
    var lastSortId: UInt64 {
        guard let lastIndexPath = lastIndexPath else { return 0 }
        return firstIndexPathWithSortId(atOrBeforeIndexPath: lastIndexPath)?.sortId ?? 0
    }

    @objc
    func saveLastVisibleSortIdAndOnScreenPercentage() {
        AssertIsOnMainThread()

        let sortIdToSave: UInt64
        let onScreenPercentageToSave: Double

        if let lastVisibleIndexPath = lastVisibleIndexPath,
            let (indexPath, sortId) = firstIndexPathWithSortId(atOrBeforeIndexPath: lastVisibleIndexPath),
            let onScreenPercentage = percentOfIndexPathVisibleAboveBottom(indexPath) {

            sortIdToSave = sortId
            onScreenPercentageToSave = Double(onScreenPercentage)
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

    private func percentOfIndexPathVisibleAboveBottom(_ indexPath: IndexPath) -> CGFloat? {
        guard let attributes = layout.layoutAttributesForItem(at: indexPath) else { return nil }
        let origin = view.convert(attributes.frame.origin, from: collectionView)
        let heightAboveBottom = collectionView.height - origin.y - collectionView.adjustedContentInset.bottom
        return CGFloatClamp01(heightAboveBottom / attributes.frame.height)
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
