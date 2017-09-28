//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

protocol GifPickerLayoutDelegate: class {
    func imageInfosForLayout() -> [GiphyImageInfo]
}

class GifPickerLayout: UICollectionViewLayout {
    let TAG = "[GifPickerLayout]"

    public weak var delegate: GifPickerLayoutDelegate?

    private var itemAttributesMap = [UInt: UICollectionViewLayoutAttributes]()

    private var contentSize = CGSize.zero

    // MARK: Initializers and Factory Methods

    @available(*, unavailable, message:"use other constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        owsFail("\(self.TAG) invalid constructor")
    }

    override init() {
        super.init()
    }

    // MARK: Methods

    override func invalidateLayout() {
        super.invalidateLayout()

        itemAttributesMap.removeAll()
    }

    override func invalidateLayout(with context: UICollectionViewLayoutInvalidationContext) {
        super.invalidateLayout(with:context)

        itemAttributesMap.removeAll()
    }

    override func prepare() {
        super.prepare()

        guard let collectionView = collectionView else {
            return
        }
        guard let delegate = delegate else {
            return
        }

        let vMargin = UInt(5)
        let hMargin = UInt(5)
        let vSpacing = UInt(3)
        let hSpacing = UInt(3)
        // TODO:
        let columnCount = UInt(3)

        let totalViewWidth = UInt(collectionView.width())
        let hTotalWhitespace = (2 * hMargin) + (hSpacing * (columnCount - 1))
        let hRemainderSpace = totalViewWidth - hTotalWhitespace
        let columnWidth = UInt(hRemainderSpace / columnCount)
        // We want to unevenly distribute the hSpacing between the columns
        // so that the left and right margins are equal, which is non-trivial
        // due to rounding error.
        let totalHSpacing = totalViewWidth - ((2 * hMargin) + (columnCount * columnWidth))

        var columnXs = [UInt]()
        var columnYs = [UInt]()
        // Note that columnIndex is a one-based index, not a zero-based index.
        for columnIndex in 1...columnCount {
            var columnX = hMargin + (columnWidth * (columnIndex - 1))
            if columnCount > 1 {
                // We want to unevenly distribute the hSpacing between the columns
                // so that the left and right margins are equal, which is non-trivial
                // due to rounding error.
                columnX += ((totalHSpacing * (columnIndex - 1)) / (columnCount - 1))
            }
            columnXs.append(columnX)
            columnYs.append(vMargin)
        }

        // Always layout all items.
        let imageInfos = delegate.imageInfosForLayout()
        for (cellIndex, imageInfo) in imageInfos.enumerated() {
            // Select a column by finding the "highest, leftmost" column.
            var column = 0
            var cellY = columnYs[column]
            for (columnValue, columnYValue) in columnYs.enumerated() {
                if columnYValue < cellY {
                    column = columnValue
                    cellY = columnYValue
                }
            }
            let cellX = columnXs[column]
            let cellWidth = columnWidth
            let cellHeight = UInt(columnWidth * imageInfo.originalRendition.height / imageInfo.originalRendition.width)

            let indexPath = NSIndexPath(row: cellIndex, section: 0)
            let itemAttributes = UICollectionViewLayoutAttributes(forCellWith:indexPath as IndexPath)
            let itemFrame = CGRect(x:CGFloat(cellX), y:CGFloat(cellY), width:CGFloat(cellWidth), height:CGFloat(cellHeight))
            itemAttributes.frame = itemFrame
            itemAttributesMap[UInt(cellIndex)] = itemAttributes

            columnYs[column] = cellY + cellHeight + vSpacing
        }

        var contentHeight = vMargin
        for columnY in columnYs {
            contentHeight = max(contentHeight, columnY)
        }
        contentHeight += vMargin
        contentSize = CGSize(width:CGFloat(totalViewWidth), height:CGFloat(contentHeight))
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var result = [UICollectionViewLayoutAttributes]()
        for itemAttributes in itemAttributesMap.values {
            if itemAttributes.frame.intersects(rect) {
                result.append(itemAttributes)
            }
        }
        return result
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
