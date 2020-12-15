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

    func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint
}

// MARK: -

@objc
public class ConversationViewLayout: UICollectionViewLayout {

    @objc
    public weak var delegate: ConversationViewLayoutDelegate?

    private var conversationStyle: ConversationStyle

    private class LayoutInfo {

        let viewWidth: CGFloat
        let contentSize: CGSize
        let itemAttributesMap: [Int: UICollectionViewLayoutAttributes]
        let headerLayoutAttributes: UICollectionViewLayoutAttributes?
        let footerLayoutAttributes: UICollectionViewLayoutAttributes?

        required init(viewWidth: CGFloat,
                      contentSize: CGSize,
                      itemAttributesMap: [Int: UICollectionViewLayoutAttributes],
                      headerLayoutAttributes: UICollectionViewLayoutAttributes?,
                      footerLayoutAttributes: UICollectionViewLayoutAttributes?) {
            self.viewWidth = viewWidth
            self.contentSize = contentSize
            self.itemAttributesMap = itemAttributesMap
            self.headerLayoutAttributes = headerLayoutAttributes
            self.footerLayoutAttributes = footerLayoutAttributes
        }

        func layoutAttributesForItem(at indexPath: IndexPath, assertIfMissing: Bool) -> UICollectionViewLayoutAttributes? {
            if assertIfMissing {
                owsAssertDebug(indexPath.row >= 0 && indexPath.row < itemAttributesMap.count)
            }
            return itemAttributesMap[indexPath.row]
        }

        func layoutAttributesForSupplementaryElement(ofKind elementKind: String,
                                                     at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {

            if elementKind == UICollectionView.elementKindSectionHeader,
               let headerLayoutAttributes = headerLayoutAttributes,
               headerLayoutAttributes.indexPath == indexPath {
                return headerLayoutAttributes
            }
            if elementKind == UICollectionView.elementKindSectionFooter,
               let footerLayoutAttributes = footerLayoutAttributes,
               footerLayoutAttributes.indexPath == indexPath {
                return footerLayoutAttributes
            }
            return nil
        }

        var debugDescription: String {
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

    private var hasEverHadLayout = false

    private var currentLayoutInfo: LayoutInfo?

    private func ensureCurrentLayoutInfo() -> LayoutInfo {
        AssertIsOnMainThread()

        if let layoutInfo = currentLayoutInfo {
            return layoutInfo
        }

        let layoutInfo = Self.buildLayoutInfo(delegate: delegate, conversationStyle: conversationStyle)
        currentLayoutInfo = layoutInfo
        hasEverHadLayout = true
        return layoutInfo
    }

    // This is used during performBatchUpdates() to determine
    // the initial (last) layout state for items.
    private var lastLayoutInfo: LayoutInfo?

    private var isPerformingBatchUpdates = false
    private var hasInvalidatedDataSourceCounts = false

    @objc
    public func willPerformBatchUpdates() {
        AssertIsOnMainThread()
        owsAssertDebug(currentLayoutInfo != nil)
        owsAssertDebug(lastLayoutInfo == nil)

        isPerformingBatchUpdates = true
        lastLayoutInfo = ensureCurrentLayoutInfo()
        hasInvalidatedDataSourceCounts = false
        invalidateLayout()
    }

    @objc
    public func didPerformBatchUpdates() {
        AssertIsOnMainThread()
        owsAssertDebug(lastLayoutInfo != nil)

        isPerformingBatchUpdates = false
        lastLayoutInfo = nil
        hasInvalidatedDataSourceCounts = false
    }

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

        if context.invalidateDataSourceCounts {
            hasInvalidatedDataSourceCounts = true
        }

        super.invalidateLayout(with: context)

        clearState()
    }

    private func clearState() {
        AssertIsOnMainThread()

        currentLayoutInfo = nil
    }

    @objc
    public override func prepare() {
        super.prepare()

        _ = ensureCurrentLayoutInfo()
    }

    // TODO: We need to eventually audit this and make sure we're not
    //       invalidating our layout unnecessarily.  Having said that,
    //       doing layout should be pretty cheap now.
    private static func buildLayoutInfo(delegate: ConversationViewLayoutDelegate?,
                                        conversationStyle: ConversationStyle) -> LayoutInfo {

        func buildEmptyLayoutInfo() -> LayoutInfo {
            return LayoutInfo(viewWidth: 0,
                              contentSize: .zero,
                              itemAttributesMap: [:],
                              headerLayoutAttributes: nil,
                              footerLayoutAttributes: nil)
        }

        guard let delegate = delegate else {
            owsFailDebug("Missing delegate")
            return buildEmptyLayoutInfo()
        }

        let viewWidth: CGFloat = conversationStyle.viewWidth
        guard viewWidth > 0 else {
            return buildEmptyLayoutInfo()
        }
        let layoutItems = delegate.layoutItems

        var y: CGFloat = 0

        var itemAttributesMap = [Int: UICollectionViewLayoutAttributes]()
        var headerLayoutAttributes: UICollectionViewLayoutAttributes?
        var footerLayoutAttributes: UICollectionViewLayoutAttributes?

        let layoutHeaderHeight = delegate.layoutHeaderHeight
        if layoutItems.isEmpty || layoutHeaderHeight <= 0 {
            // Do nothing.
        } else {
            let headerIndexPath = IndexPath(row: 0, section: 0)
            let layoutAttributes = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                                                    with: headerIndexPath)

            layoutAttributes.frame = CGRect(x: 0, y: y, width: viewWidth, height: layoutHeaderHeight)
            headerLayoutAttributes = layoutAttributes

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
            itemAttributesMap[row] = itemAttributes

            contentBottom = itemFrame.origin.y + itemFrame.size.height
            y = contentBottom
            row += 1
            previousLayoutItem = layoutItem
        }

        contentBottom += conversationStyle.contentMarginBottom

        let layoutFooterHeight = delegate.layoutFooterHeight
        let footerIndexPath = IndexPath(row: row, section: 0)
        if layoutItems.isEmpty || layoutFooterHeight <= 0 || headerLayoutAttributes?.indexPath == footerIndexPath {
            // Do nothing.
        } else {
            let layoutAttributes = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter,
                                                                    with: footerIndexPath)

            layoutAttributes.frame = CGRect(x: 0, y: contentBottom, width: viewWidth, height: layoutFooterHeight)
            footerLayoutAttributes = layoutAttributes
            contentBottom += layoutFooterHeight
        }

        let contentSize = CGSize(width: viewWidth, height: contentBottom)

        return LayoutInfo(viewWidth: viewWidth,
                          contentSize: contentSize,
                          itemAttributesMap: itemAttributesMap,
                          headerLayoutAttributes: headerLayoutAttributes,
                          footerLayoutAttributes: footerLayoutAttributes)
    }

    @objc
    public override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        let layoutInfo = effectiveLayoutInfo
        var result = [UICollectionViewLayoutAttributes]()
        if let headerLayoutAttributes = layoutInfo.headerLayoutAttributes {
            result.append(headerLayoutAttributes)
        }
        result += layoutInfo.itemAttributesMap.values
        if let footerLayoutAttributes = layoutInfo.footerLayoutAttributes {
            result.append(footerLayoutAttributes)
        }
        return result.filter { $0.frame.intersects(rect) }
    }

    @objc
    public override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        layoutAttributesForItem(at: indexPath, alwaysUseLatestLayout: false)
    }

    @objc
    public func layoutAttributesForItem(at indexPath: IndexPath,
                                        alwaysUseLatestLayout: Bool) -> UICollectionViewLayoutAttributes? {
        AssertIsOnMainThread()

        let layoutInfo = alwaysUseLatestLayout ? ensureCurrentLayoutInfo() : effectiveLayoutInfo

        return layoutInfo.layoutAttributesForItem(at: indexPath, assertIfMissing: true)
    }

    @objc
    public override func layoutAttributesForSupplementaryView(ofKind elementKind: String,
                                                              at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        AssertIsOnMainThread()

        return effectiveLayoutInfo.layoutAttributesForSupplementaryElement(ofKind: elementKind,
                                                                           at: indexPath)
    }

    @objc
    public override var collectionViewContentSize: CGSize {
        ensureCurrentLayoutInfo().contentSize
    }

    @objc
    public override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        let lastViewWidth = currentLayoutInfo?.viewWidth
        return lastViewWidth != newBounds.width
    }

    private var effectiveLayoutInfo: LayoutInfo {
        if isPerformingBatchUpdates, !hasInvalidatedDataSourceCounts {
            if let lastLayoutInfo = self.lastLayoutInfo {
                return lastLayoutInfo
            } else {
                owsFailDebug("Missing lastLayoutInfo.")
            }
        }

        return ensureCurrentLayoutInfo()
//        }
    }

    // This method is called when there is an update with deletes/inserts to the collection view.
    //
    // It will be called prior to calling the initial/final layout attribute methods below to give
    // the layout an opportunity to do batch computations for the insertion and deletion layout attributes.
    //
    // The updateItems parameter is an array of UICollectionViewUpdateItem instances for each
    // element that is moving to a new index path.
    public override func prepare(forCollectionViewUpdates updateItems: [UICollectionViewUpdateItem]) {
        super.prepare(forCollectionViewUpdates: updateItems)
    }

    // Called inside an animation block after the update.
    public override func finalizeCollectionViewUpdates() {
        super.finalizeCollectionViewUpdates()
    }

    // UICollectionView calls this when its bounds have changed inside an
    // animation block before displaying cells in its new bounds.
    public override func prepare(forAnimatedBoundsChange oldBounds: CGRect) {
        super.prepare(forAnimatedBoundsChange: oldBounds)
    }

    // also called inside the animation block
    public override func finalizeAnimatedBoundsChange() {
        super.finalizeAnimatedBoundsChange()
    }

    // UICollectionView calls this when prior the layout transition animation
    // on the incoming and outgoing layout.
    public override func prepareForTransition(to newLayout: UICollectionViewLayout) {
        super.prepareForTransition(to: newLayout)
    }

    public override func prepareForTransition(from oldLayout: UICollectionViewLayout) {
        super.prepareForTransition(from: oldLayout)
    }

    // called inside an animation block after the transition
    public override func finalizeLayoutTransition() {
        super.finalizeLayoutTransition()
    }

    // A layout can return the content offset to be applied during transition or update animations.
    public override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint,
                                             withScrollingVelocity velocity: CGPoint) -> CGPoint {
        return proposedContentOffset
    }

    // A layout can return the content offset to be applied during transition or update animations.
    public override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {
        return proposedContentOffset
    }

    private var initialLayoutInfo: LayoutInfo? {
        lastLayoutInfo
    }

    private var finalLayoutInfo: LayoutInfo {
        ensureCurrentLayoutInfo()
    }

    // This set of methods is called when the collection view undergoes an animated
    // transition such as a batch update block or an animated bounds change.
    //
    // For each element on screen before the invalidation, finalLayoutAttributesForDisappearingXXX
    // will be called and an animation setup from what is on screen to those final attributes.
    //
    // For each element on screen after the invalidation, initialLayoutAttributesForAppearingXXX
    // will be called and an animation setup from those initial attributes to what ends up on screen.
    public override func initialLayoutAttributesForAppearingItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        owsAssertDebug(lastLayoutInfo != nil)
        return lastLayoutInfo?.layoutAttributesForItem(at: indexPath,
                                                       assertIfMissing: false)
    }

    public override func finalLayoutAttributesForDisappearingItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        finalLayoutInfo.layoutAttributesForItem(at: indexPath,
                                                assertIfMissing: false)
    }

    public override func initialLayoutAttributesForAppearingSupplementaryElement(ofKind elementKind: String,
                                                                                 at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        owsAssertDebug(lastLayoutInfo != nil)
        return lastLayoutInfo?.layoutAttributesForSupplementaryElement(ofKind: elementKind,
                                                                       at: indexPath)
    }

    public override func finalLayoutAttributesForDisappearingSupplementaryElement(ofKind elementKind: String,
                                                                                  at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        finalLayoutInfo.layoutAttributesForSupplementaryElement(ofKind: elementKind,
                                                                at: indexPath)
    }

    @objc
    public override var debugDescription: String {
        ensureCurrentLayoutInfo().debugDescription
    }
}
