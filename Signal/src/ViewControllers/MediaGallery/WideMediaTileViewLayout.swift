//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

// Accommodates remaining scrolled to the same "apparent" position when new content is inserted
// into the top of a collectionView. There are multiple ways to solve this problem, but this
// is the only one which avoided a perceptible flicker.
protocol ScrollPositionPreserving: AnyObject {
    func recordContentSizeBeforeInsertingToTop()
}

class WideMediaTileViewLayout: UICollectionViewFlowLayout, ScrollPositionPreserving {

    private var contentSizeBeforeInsertingToTop: CGSize?

    let contentCardVerticalInset: CGFloat

    func recordContentSizeBeforeInsertingToTop() {
        contentSizeBeforeInsertingToTop = collectionViewContentSize
    }

    override public func prepare() {
        super.prepare()

        if let collectionView = collectionView, let oldContentSize = contentSizeBeforeInsertingToTop {
            let newContentSize = collectionViewContentSize
            collectionView.contentOffset.y += newContentSize.height - oldContentSize.height
            contentSizeBeforeInsertingToTop = nil
        }
    }

    init(contentCardVerticalInset inset: CGFloat) {
        contentCardVerticalInset = inset

        super.init()

        scrollDirection = .vertical
        minimumInteritemSpacing = 0
        minimumLineSpacing = 0
    }

    required init?(coder: NSCoder) {
        owsFail("init(coder:) has not been implemented")
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        return true
    }
}
