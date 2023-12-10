//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalRingRTC
import SignalServiceKit

protocol GroupCallVideoGridLayoutDelegate: AnyObject {
    var maxColumns: Int { get }
    var maxRows: Int { get }
    var maxItems: Int { get }
}

class GroupCallVideoGridLayout: UICollectionViewLayout {

    public weak var delegate: GroupCallVideoGridLayoutDelegate?

    private var itemAttributesMap = [Int: UICollectionViewLayoutAttributes]()

    private var contentSize = CGSize.zero

    // MARK: Initializers and Factory Methods

    @available(*, unavailable, message: "use other constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

        guard let collectionView = collectionView else { return }
        guard let delegate = delegate else { return }

        let vInset: CGFloat = 6
        let hInset: CGFloat = 6
        let vSpacing: CGFloat = 6
        let hSpacing: CGFloat = 6

        let maxColumns = delegate.maxColumns
        let maxRows = delegate.maxRows

        let numberOfItems = min(collectionView.numberOfItems(inSection: 0), delegate.maxItems)

        guard numberOfItems > 0 else { return }

        // We evenly distribute items across rows, up to the max
        // column count. If an item is alone on a row, it should
        // expand across all columns.

        let possibleGrids = (1...maxColumns).reduce(
            into: [(rows: Int, columns: Int)]()
        ) { result, columns in
            let rows = Int(ceil(CGFloat(numberOfItems) / CGFloat(columns)))
            if let previousRows = result.last?.rows, previousRows == rows { return }
            result.append((rows, columns))
        }.filter { $0.columns <= maxColumns && $0.rows <= maxRows }
        .sorted { lhs, rhs in
            // We prefer to render square grids (e.g. 2x2, 3x3, etc.) but it's
            // not always possible depending on how many items we have available.
            // If a square aspect ratio is not possible, we'll defer to having more
            // rows than columns.
            let lhsDistanceFromSquare = CGFloat(lhs.rows) / CGFloat(lhs.columns) - 1
            let rhsDistanceFromSquare = CGFloat(rhs.rows) / CGFloat(rhs.columns) - 1

            if lhsDistanceFromSquare >= 0 && rhsDistanceFromSquare >= 0 {
                return lhsDistanceFromSquare < rhsDistanceFromSquare
            } else {
                return lhsDistanceFromSquare > rhsDistanceFromSquare
            }
        }

        guard let (numberOfRows, numberOfColumns) = possibleGrids.first else { return owsFailDebug("missing grid") }

        let totalViewWidth = collectionView.width
        let totalViewHeight = collectionView.height

        let verticalSpacersWidth = (2 * vInset) + (vSpacing * (CGFloat(numberOfRows) - 1))
        let verticalCellSpace = totalViewHeight - verticalSpacersWidth

        let rowHeight = verticalCellSpace / CGFloat(numberOfRows)

        // The last row may have less columns than the previous rows,
        // if there is an odd number of videos. Each row should always
        // expand the full width of the collection view.
        var columnWidthPerRow = [CGFloat]()
        for row in 1...numberOfRows {
            let numberOfColumnsForRow: Int
            if row == numberOfRows {
                numberOfColumnsForRow = numberOfItems - ((row - 1) * numberOfColumns)
            } else {
                numberOfColumnsForRow = numberOfColumns
            }

            let horizontalSpacersWidth = (2 * hInset) + (hSpacing * (CGFloat(numberOfColumnsForRow) - 1))
            let horizontalCellSpace = totalViewWidth - horizontalSpacersWidth
            let columnWidth = horizontalCellSpace / CGFloat(numberOfColumnsForRow)

            columnWidthPerRow.append(columnWidth)
        }

        for index in 0..<numberOfItems {
            let indexPath = NSIndexPath(item: index, section: 0)
            let itemAttributes = UICollectionViewLayoutAttributes(forCellWith: indexPath as IndexPath)

            let row = ceil(CGFloat(index + 1) / CGFloat(numberOfColumns)) - 1
            let yPosition = (row * rowHeight) + vInset + (CGFloat(row) * vSpacing)

            let columnWidth = columnWidthPerRow[Int(row)]

            let column = CGFloat(index % numberOfColumns)
            let xPosition = (column * columnWidth) + vInset + (CGFloat(column) * vSpacing)

            itemAttributes.frame = CGRect(x: xPosition, y: yPosition, width: columnWidth, height: rowHeight)
            itemAttributesMap[index] = itemAttributes
        }

        contentSize = collectionView.frame.size
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        return itemAttributesMap.values.filter { itemAttributes in
            return itemAttributes.frame.intersects(rect)
        }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        return itemAttributesMap[indexPath.row]
    }

    override var collectionViewContentSize: CGSize {
        return contentSize
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        return true
    }
}
