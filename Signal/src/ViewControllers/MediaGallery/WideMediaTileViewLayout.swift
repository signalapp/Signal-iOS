//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// Accommodates remaining scrolled to the same "apparent" position when new content is inserted
// into the top of a collectionView. There are multiple ways to solve this problem, but this
// is the only one which avoided a perceptible flicker.
protocol ScrollPositionPreserving: AnyObject {
    func recordContentSizeBeforeInsertingToTop()
}

class WideMediaTileViewLayout: UICollectionViewFlowLayout, ScrollPositionPreserving {
    private var contentSizeBeforeInsertingToTop: CGSize?

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

    private var sectionSpacing: CGFloat = 20.0

    init(sectionSpacing: CGFloat) {
        self.sectionSpacing = sectionSpacing
        super.init()
        self.scrollDirection = .vertical
        minimumLineSpacing = 0.0
        minimumInteritemSpacing = 0.0
    }

    required init?(coder: NSCoder) {
        owsFail("init(coder:) has not been implemented")
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        let layoutAttributes = super.layoutAttributesForElements(in: rect)

        layoutAttributes?.forEach { attributes in
            if attributes.representedElementKind == UICollectionView.elementKindSectionHeader {
                guard let collectionView = collectionView else { return }
                let contentInset = collectionView.contentInset
                let bounds = collectionView.bounds

                let width = bounds.width - contentInset.left - contentInset.right
                let height = attributes.frame.height

                attributes.frame = CGRect(x: contentInset.left, y: attributes.frame.origin.y, width: width, height: height)
            }
        }

        return layoutAttributes
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        return true
    }
}
