//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

// A trivial layout that places each item in a horizontal line.
// Each item has uniform size.
class LinearHorizontalLayout: UICollectionViewLayout {

    private let itemSize: CGSize
    private let inset: CGFloat
    private let spacing: CGFloat

    private var itemAttributesMap = [UInt: UICollectionViewLayoutAttributes]()

    private var contentSize = CGSize.zero

    // MARK: Initializers and Factory Methods

    @available(*, unavailable, message:"use other constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    required init(itemSize: CGSize, inset: CGFloat = 0, spacing: CGFloat = 0) {
        self.itemSize = itemSize
        self.inset = inset
        self.spacing = spacing

        super.init()
    }

    // MARK: Methods

    override func invalidateLayout() {
        super.invalidateLayout()

        itemAttributesMap.removeAll()
    }

    override func invalidateLayout(with context: UICollectionViewLayoutInvalidationContext) {
        super.invalidateLayout(with: context)

        itemAttributesMap.removeAll()
    }

    override func prepare() {
        super.prepare()

        guard let collectionView = collectionView else {
            return
        }
        guard collectionView.numberOfSections == 1 else {
            owsFailDebug("This layout only support a single section.")
            return
        }
        let itemCount = collectionView.numberOfItems(inSection: 0)

        let vInset: CGFloat = inset
        let hInset: CGFloat = inset

        guard itemCount > 0 else {
            contentSize = .zero
            return
        }

        for row in 0..<itemCount {
            let itemX: CGFloat = hInset + CGFloat(row) * (itemSize.width + spacing)
            let itemY: CGFloat = vInset
            let itemFrame = CGRect(x: itemX, y: itemY, width: itemSize.width, height: itemSize.height)

            let indexPath = NSIndexPath(row: row, section: 0)
            let itemAttributes = UICollectionViewLayoutAttributes(forCellWith: indexPath as IndexPath)
            itemAttributes.frame = itemFrame
            itemAttributesMap[UInt(row)] = itemAttributes
        }

        contentSize = CGSize(width: hInset * 2 + CGFloat(itemCount) * itemSize.width + CGFloat(itemCount - 1) * spacing,
                             height: vInset * 2 + itemSize.height)
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        return itemAttributesMap.values.filter { itemAttributes in
            return itemAttributes.frame.intersects(rect)
        }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        let result = itemAttributesMap[UInt(indexPath.row)]
        return result
    }

    override var collectionViewContentSize: CGSize {
        return contentSize
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView = collectionView else {
            return false
        }
        return collectionView.width() != newBounds.size.width
    }
}
