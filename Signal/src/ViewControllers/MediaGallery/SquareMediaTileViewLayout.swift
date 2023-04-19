//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

class SquareMediaTileViewLayout: UICollectionViewFlowLayout, ScrollPositionPreserving {
    private var contentSizeBeforeInsertingToTop: CGSize?

    override init() {
        super.init()

        let interItemSpacing = 2.0
        minimumInteritemSpacing = interItemSpacing
        minimumLineSpacing = interItemSpacing
    }

    required init?(coder: NSCoder) {
        owsFail("init(coder:) has not been implemented")
    }

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
}
