//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol ConversationViewLayoutItem {

    var cellSize: CGSize { get }

    func vSpacing(previousLayoutItem: ConversationViewLayoutItem) -> CGFloat

}

// MARK: -

@objc
public protocol ConversationViewLayoutDelegate {

    var layoutItems: [ConversationViewLayoutItem] { get }

    var layoutHeaderHeight: CGFloat { get }
    var layoutFooterHeight: CGFloat { get }
}

// MARK: -

@objc
public class ConversationViewLayout: UICollectionViewLayout {

    @objc
    public weak var delegate: ConversationViewLayoutDelegate?

    // This dirty flag may be redundant with logic in UICollectionViewLayout,
    // but it can't hurt and it ensures that we can safely & cheaply call
    // prepareLayout from view logic to ensure that we always have a¸valid
    // layout without incurring any of the (great) expense of performing an
    // unnecessary layout pass.
    private var hasLayout = false {
        didSet {
            AssertIsOnMainThread()

            if hasLayout {
                hasEverHadLayout = true
            }
        }
    }
    private var hasEverHadLayout = false

    private var lastViewWidth: CGFloat = 0
    private var contentSize: CGSize = .zero

    private var conversationStyle: ConversationStyle

    private var itemAttributesMap = [Int: UICollectionViewLayoutAttributes]()
    private var headerLayoutAttributes: UICollectionViewLayoutAttributes?
    private var footerLayoutAttributes: UICollectionViewLayoutAttributes?

    @objc
    public required init(conversationStyle: ConversationStyle) {
        self.conversationStyle = conversationStyle

        super.init()
    }

    @available(*, unavailable, message:"Use other constructor instead.")
    @objc
    public required init(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @objc
    public func update(conversationStyle: ConversationStyle) {
        AssertIsOnMainThread()

        self.conversationStyle = conversationStyle

        invalidateLayout()
    }

    @objc
    public override func invalidateLayout() {
        super.invalidateLayout()

        clearState()
    }

    @objc
    public override func invalidateLayout(with context: UICollectionViewLayoutInvalidationContext) {
        super.invalidateLayout(with: context)

        clearState()
    }

    private func clearState() {
        contentSize = .zero
        itemAttributesMap.removeAll()
        headerLayoutAttributes = nil
        footerLayoutAttributes = nil
        hasLayout = false
        lastViewWidth = 0
    }

    @objc
    public override func prepare() {
        super.prepare()

        guard let delegate = delegate else {
            owsFailDebug("Missing delegate")
            clearState()
            return
        }
        guard let collectionView = collectionView else {
            owsFailDebug("Missing collectionView")
            clearState()
            return
        }
        guard collectionView.width > 0, collectionView.height > 0 else {
            owsFailDebug("Collection view has invalid size: \(collectionView.bounds)")
            clearState()
            return
        }
        guard !hasLayout else {
            return
        }

        clearState()
        hasLayout = true

        prepareLayoutOfItems(delegate: delegate)
    }

    // TODO: We need to eventually audit this and make sure we're not
    //       invalidating our layout unnecessarily.  Having said that,
    //       doing layout should be pretty cheap now.
    private func prepareLayoutOfItems(delegate: ConversationViewLayoutDelegate) {
        let viewWidth: CGFloat = conversationStyle.viewWidth
        let layoutItems = delegate.layoutItems

        var y: CGFloat = 0

        let layoutHeaderHeight = delegate.layoutHeaderHeight
        if layoutItems.isEmpty || layoutHeaderHeight <= 0 {
            headerLayoutAttributes = nil
        } else {
            let headerIndexPath = IndexPath(row: 0, section: 0)
            let headerLayoutAttributes = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                                                          with: headerIndexPath)

            headerLayoutAttributes.frame = CGRect(x: 0, y: y, width: viewWidth, height: layoutHeaderHeight)
            self.headerLayoutAttributes = headerLayoutAttributes

            y += layoutHeaderHeight
        }

        y += conversationStyle.contentMarginTop
        var contentBottom: CGFloat = y

        var row: Int = 0
        var previousLayoutItem: ConversationViewLayoutItem?
        for layoutItem in layoutItems {
            if let previousLayoutItem = previousLayoutItem {
                y += layoutItem.vSpacing(previousLayoutItem: previousLayoutItem)
            }

            var layoutSize = layoutItem.cellSize.ceil

            // Ensure cell fits within view.
            if layoutSize.width > viewWidth {
                // This can happen due to safe area insets, orientation changes, etc.
                Logger.warn("Oversize cell layout: \(layoutSize.width) <= viewWidth: \(viewWidth)")
            }
            layoutSize.width = min(viewWidth, layoutSize.width)

            // All cells are "full width" and are responsible for aligning their own content.
            let itemFrame = CGRect(x: 0, y: y, width: viewWidth, height: layoutSize.height)

            let indexPath = IndexPath(row: row, section: 0)
            let itemAttributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
            itemAttributes.frame = itemFrame
            self.itemAttributesMap[row] = itemAttributes

            contentBottom = itemFrame.origin.y + itemFrame.size.height
            y = contentBottom
            row += 1
            previousLayoutItem = layoutItem
        }

        contentBottom += self.conversationStyle.contentMarginBottom

        let layoutFooterHeight = delegate.layoutFooterHeight
        let footerIndexPath = IndexPath(row: row, section: 0)
        if layoutItems.isEmpty || layoutFooterHeight <= 0 || headerLayoutAttributes?.indexPath == footerIndexPath {
            footerLayoutAttributes = nil
        } else {
            let footerLayoutAttributes = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter,
                                                                          with: footerIndexPath)

            footerLayoutAttributes.frame = CGRect(x: 0, y: contentBottom, width: viewWidth, height: layoutFooterHeight)
            self.footerLayoutAttributes = footerLayoutAttributes
            contentBottom += layoutFooterHeight
        }

        self.contentSize = CGSize(width: viewWidth, height: contentBottom)
        self.lastViewWidth = viewWidth
    }

    @objc
    public override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var result = [UICollectionViewLayoutAttributes]()

        if let headerLayoutAttributes = headerLayoutAttributes {
            result.append(headerLayoutAttributes)
        }
        result += itemAttributesMap.values
        if let footerLayoutAttributes = footerLayoutAttributes {
            result.append(footerLayoutAttributes)
        }
        return result.filter { $0.frame.intersects(rect) }
    }

    @objc
    public override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let attributes = itemAttributesMap[indexPath.row] else {
            Logger.verbose("Missing attributes: \(itemAttributesMap.keys)")
            return nil
        }
        return attributes
    }

    @objc
    public override func layoutAttributesForSupplementaryView(ofKind elementKind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        if elementKind == UICollectionView.elementKindSectionHeader {
            return headerLayoutAttributes
        } else if elementKind == UICollectionView.elementKindSectionFooter {
            return footerLayoutAttributes
        } else {
            return nil
        }
    }

    @objc
    public override var collectionViewContentSize: CGSize {
        contentSize
    }

    @objc
    public override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        lastViewWidth != newBounds.width
    }

    @objc
    public override var debugDescription: String {
        var result = "["
        for item in itemAttributesMap.keys.sorted() {
            guard let itemAttributes = itemAttributesMap[item] else {
                owsFailDebug("Missing attributes for item: \(item)")
                continue
            }
            result += "item: \(itemAttributes.indexPath), "
        }
        if let headerLayoutAttributes = headerLayoutAttributes {
            result += "header: \(headerLayoutAttributes.indexPath), "
        }
        if let footerLayoutAttributes = footerLayoutAttributes {
            result += "footer: \(footerLayoutAttributes.indexPath), "
        }
        result += "]"
        return result
    }
}
