//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

protocol GifPickerLayoutDelegate: class {
    func imageInfosForLayout() -> [GiphyImageInfo]
}

// A Pinterest-style waterfall layout.
class GifPickerLayout: UICollectionViewLayout {

    public weak var delegate: GifPickerLayoutDelegate?

    private var itemAttributesMap = [UInt: UICollectionViewLayoutAttributes]()

    private var contentSize = CGSize.zero

    // MARK: Initializers and Factory Methods

    @available(*, unavailable, message:"use other constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        notImplemented()
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
        super.invalidateLayout(with: context)

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

        let vInset = UInt(5)
        let hInset = UInt(5)
        let vSpacing = UInt(3)
        let hSpacing = UInt(3)

        // We  use 2 or 3 columns, depending on the device.
        // 2 columns will show fewer GIFs at a time,
        // but use less network & be a more responsive experience.
        let screenSize = UIScreen.main.bounds.size
        let screenWidth = min(screenSize.width, screenSize.height)
        let columnCount = UInt(max(2, screenWidth / 130))

        let totalViewWidth = UInt(collectionView.width())
        let hTotalWhitespace = (2 * hInset) + (hSpacing * (columnCount - 1))
        let hRemainderSpace = totalViewWidth - hTotalWhitespace
        let columnWidth = UInt(hRemainderSpace / columnCount)
        // We want to unevenly distribute the hSpacing between the columns
        // so that the left and right margins are equal, which is non-trivial
        // due to rounding error.
        let totalHSpacing = totalViewWidth - ((2 * hInset) + (columnCount * columnWidth))

        // columnXs are the left edge of each column.
        var columnXs = [UInt]()
        // columnYs are the top edge of the next cell in each column.
        var columnYs = [UInt]()
        for columnIndex in 0...columnCount-1 {
            var columnX = hInset + (columnWidth * columnIndex)
            if columnCount > 1 {
                // We want to unevenly distribute the hSpacing between the columns
                // so that the left and right margins are equal, which is non-trivial
                // due to rounding error.
                columnX += ((totalHSpacing * columnIndex) / (columnCount - 1))
            }
            columnXs.append(columnX)
            columnYs.append(vInset)
        }

        // Always layout all items.
        let imageInfos = delegate.imageInfosForLayout()
        var contentBottom = vInset
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
            let itemAttributes = UICollectionViewLayoutAttributes(forCellWith: indexPath as IndexPath)
            let itemFrame = CGRect(x: CGFloat(cellX), y: CGFloat(cellY), width: CGFloat(cellWidth), height: CGFloat(cellHeight))
            itemAttributes.frame = itemFrame
            itemAttributesMap[UInt(cellIndex)] = itemAttributes

            columnYs[column] = cellY + cellHeight + vSpacing
            contentBottom = max(contentBottom, cellY + cellHeight)
        }

        // Add bottom margin.
        let contentHeight = contentBottom + vInset
        contentSize = CGSize(width: CGFloat(totalViewWidth), height: CGFloat(contentHeight))
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
