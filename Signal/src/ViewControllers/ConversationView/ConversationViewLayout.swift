//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol ConversationViewLayoutItem {

    var interactionUniqueId: String { get }

    var cellSize: CGSize { get }

    func vSpacing(previousLayoutItem: ConversationViewLayoutItem) -> CGFloat
}

// MARK: -

@objc
public protocol ConversationViewLayoutDelegate {

    var layoutItems: [ConversationViewLayoutItem] { get }
    var renderStateId: UInt { get }

    var layoutHeaderHeight: CGFloat { get }
    var layoutFooterHeight: CGFloat { get }

    func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint

    var isUserScrolling: Bool { get }
    var hasScrollingAnimation: Bool { get }
    var scrollContinuity: ScrollContinuity { get }
}

// MARK: -

@objc
public class ConversationViewLayout: UICollectionViewLayout {

    @objc
    public weak var delegate: ConversationViewLayoutDelegate?

    private var conversationStyle: ConversationStyle

    fileprivate struct ItemLayout {
        let interactionUniqueId: String
        let indexPath: IndexPath
        let layoutAttributes: UICollectionViewLayoutAttributes
    }

    fileprivate class LayoutInfo {

        let viewWidth: CGFloat
        let contentSize: CGSize
        let itemAttributesMap: [Int: UICollectionViewLayoutAttributes]
        let headerLayoutAttributes: UICollectionViewLayoutAttributes?
        let footerLayoutAttributes: UICollectionViewLayoutAttributes?
        let itemLayouts: [ItemLayout]
        let renderStateId: UInt

        required init(viewWidth: CGFloat,
                      contentSize: CGSize,
                      itemAttributesMap: [Int: UICollectionViewLayoutAttributes],
                      headerLayoutAttributes: UICollectionViewLayoutAttributes?,
                      footerLayoutAttributes: UICollectionViewLayoutAttributes?,
                      itemLayouts: [ItemLayout],
                      renderStateId: UInt) {
            self.viewWidth = viewWidth
            self.contentSize = contentSize
            self.itemAttributesMap = itemAttributesMap
            self.headerLayoutAttributes = headerLayoutAttributes
            self.footerLayoutAttributes = footerLayoutAttributes
            self.itemLayouts = itemLayouts
            self.renderStateId = renderStateId
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

        ensureState()

        let layoutInfo = Self.buildLayoutInfo(state: currentState)
        currentLayoutInfo = layoutInfo
        hasEverHadLayout = true
        return layoutInfo
    }

    @objc
    public required init(conversationStyle: ConversationStyle) {
        self.conversationStyle = conversationStyle

        super.init()
    }

    @available(*, unavailable, message: "Use other constructor instead.")
    @objc
    public required init(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @objc
    public func update(conversationStyle: ConversationStyle) {
        AssertIsOnMainThread()

        guard !self.conversationStyle.isEqualForCellRendering(conversationStyle) else {
            return
        }

        self.conversationStyle = conversationStyle

        invalidateLayout()
    }

    @objc
    public override func invalidateLayout() {
        AssertIsOnMainThread()

        super.invalidateLayout()

        // This method will call invalidateLayout(with:).
        // We don't want to assume that, so we call ensureState() to be safe.
        ensureState()
    }

    @objc
    public override func invalidateLayout(with context: UICollectionViewLayoutInvalidationContext) {
        AssertIsOnMainThread()

        ensureState()

        super.invalidateLayout(with: context)
    }

    private func ensureState() {
        AssertIsOnMainThread()

        let newState = State.build(delegate: delegate, conversationStyle: conversationStyle)
        guard newState != currentState else {
            return
        }

        currentState = newState

        currentLayoutInfo = nil
    }

    @objc
    public override func prepare() {
        super.prepare()

        _ = ensureCurrentLayoutInfo()
    }

    private var currentState: State?

    private struct State: Equatable {
        let conversationStyle: ConversationStyle

        let renderStateId: UInt
        let layoutItems: [ConversationViewLayoutItem]

        let layoutHeaderHeight: CGFloat
        let layoutFooterHeight: CGFloat

        static func build(delegate: ConversationViewLayoutDelegate?,
                          conversationStyle: ConversationStyle) -> State? {
            guard let delegate = delegate else {
                return nil
            }
            return State(conversationStyle: conversationStyle,
                         renderStateId: delegate.renderStateId,
                         layoutItems: delegate.layoutItems,
                         layoutHeaderHeight: delegate.layoutHeaderHeight,
                         layoutFooterHeight: delegate.layoutFooterHeight)
        }

        // MARK: Equatable

        static func == (lhs: State, rhs: State) -> Bool {
            // Comparing the layoutItems is expensive. We can avoid that by
            // comparing renderStateIds.
            (lhs.conversationStyle.isEqualForCellRendering(rhs.conversationStyle) &&
                lhs.renderStateId == rhs.renderStateId &&
                lhs.layoutHeaderHeight == rhs.layoutHeaderHeight &&
                lhs.layoutFooterHeight == rhs.layoutFooterHeight)
        }
    }

    private static func buildLayoutInfo(state: State?) -> LayoutInfo {
        AssertIsOnMainThread()

        func buildEmptyLayoutInfo() -> LayoutInfo {
            return LayoutInfo(viewWidth: 0,
                              contentSize: .zero,
                              itemAttributesMap: [:],
                              headerLayoutAttributes: nil,
                              footerLayoutAttributes: nil,
                              itemLayouts: [],
                              renderStateId: 0)
        }

        guard let state = state else {
            owsFailDebug("Missing state")
            return buildEmptyLayoutInfo()
        }

        let conversationStyle = state.conversationStyle
        let layoutItems = state.layoutItems
        let layoutHeaderHeight = state.layoutHeaderHeight
        let layoutFooterHeight = state.layoutFooterHeight

        let viewWidth: CGFloat = conversationStyle.viewWidth
        guard viewWidth > 0 else {
            return buildEmptyLayoutInfo()
        }

        var y: CGFloat = 0

        var itemAttributesMap = [Int: UICollectionViewLayoutAttributes]()
        var headerLayoutAttributes: UICollectionViewLayoutAttributes?
        var footerLayoutAttributes: UICollectionViewLayoutAttributes?

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
        var itemLayouts = [ItemLayout]()
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

            itemLayouts.append(ItemLayout(interactionUniqueId: layoutItem.interactionUniqueId,
                                          indexPath: indexPath,
                                          layoutAttributes: itemAttributes))
        }

        contentBottom += conversationStyle.contentMarginBottom

        if row > 0 {
            let footerIndexPath = IndexPath(row: row - 1, section: 0)
            if layoutItems.isEmpty || layoutFooterHeight <= 0 || headerLayoutAttributes?.indexPath == footerIndexPath {
                // Do nothing.
            } else {
                let layoutAttributes = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter,
                                                                        with: footerIndexPath)

                layoutAttributes.frame = CGRect(x: 0, y: contentBottom, width: viewWidth, height: layoutFooterHeight)
                footerLayoutAttributes = layoutAttributes
                contentBottom += layoutFooterHeight
            }
        }

        let contentSize = CGSize(width: viewWidth, height: contentBottom)
        let renderStateId = state.renderStateId

        return LayoutInfo(viewWidth: viewWidth,
                          contentSize: contentSize,
                          itemAttributesMap: itemAttributesMap,
                          headerLayoutAttributes: headerLayoutAttributes,
                          footerLayoutAttributes: footerLayoutAttributes,
                          itemLayouts: itemLayouts,
                          renderStateId: renderStateId)
    }

    // MARK: - UICollectionViewLayout Impl.

    @objc
    public override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        AssertIsOnMainThread()

        let layoutInfo = ensureCurrentLayoutInfo()

        var result = [UICollectionViewLayoutAttributes]()
        if let headerLayoutAttributes = layoutInfo.headerLayoutAttributes {
            result.append(headerLayoutAttributes)
        }
        for itemLayout in layoutInfo.itemLayouts {
            result.append(itemLayout.layoutAttributes)
        }
        if let footerLayoutAttributes = layoutInfo.footerLayoutAttributes {
            result.append(footerLayoutAttributes)
        }
        return result.filter { $0.frame.intersects(rect) }
    }

    @objc
    public override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        AssertIsOnMainThread()

        let layoutInfo = ensureCurrentLayoutInfo()
        return layoutInfo.layoutAttributesForItem(at: indexPath, assertIfMissing: true)
    }

    @objc
    public override func layoutAttributesForSupplementaryView(ofKind elementKind: String,
                                                              at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        AssertIsOnMainThread()

        let layoutInfo = ensureCurrentLayoutInfo()
        return layoutInfo.layoutAttributesForSupplementaryElement(ofKind: elementKind,
                                                                  at: indexPath)
    }

    @objc
    public override var collectionViewContentSize: CGSize {
        AssertIsOnMainThread()

        return ensureCurrentLayoutInfo().contentSize
    }

    @objc
    public override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        return true
    }

    // MARK: - performBatchUpdates() & reloadData()

    // Flag set before reloadData() and cleared after it _completes_.
    private var isReloadingData = false

    // Flag set before performBatchUpdates() and cleared after it _returns_.
    private var isPerformingBatchUpdates = false

    // Returns true during performBatchUpdates() or reloadData().
    // Unlike isPerformBatchUpdatesOrReloadDataBeingAppliedOrSettling, this
    // returns true after performBatchUpdates() returns, before
    // its completion is called.
    @objc
    public var isPerformBatchUpdatesOrReloadDataBeingApplied: Bool {
        isPerformingBatchUpdates || isReloadingData
    }

    private let updateCompletionCounter = AtomicUInt(0)

    // Returns true during performBatchUpdates() or reloadData().
    // Unlike isPerformBatchUpdatesOrReloadDataBeingApplied, this
    // returns true until the completion of performBatchUpdates().
    @objc
    public var isPerformBatchUpdatesOrReloadDataBeingAppliedOrSettling: Bool {
        updateCompletionCounter.get() > 0
    }

    @objc
    public func willPerformBatchUpdates(scrollContinuityToken: CVScrollContinuityToken?) {
        AssertIsOnMainThread()
        owsAssertDebug(currentLayoutInfo != nil)

        isPerformingBatchUpdates = true
        updateCompletionCounter.increment()

        // When landing some CVC loads, we maintain scroll continuity by setting a
        // `contentOffsetAdjustment` on the UICollectionViewLayoutInvalidationContext
        // pass to invalidateLayout().  The timing of this adjustment to the
        // `contentOffset` is delicate.  It must be done just before
        // UICollectionView.performBatchUpdates().
        if let delegate = self.delegate,
           let scrollContinuityToken = scrollContinuityToken {
            ensureState()
            let layoutInfoBeforeUpdate = scrollContinuityToken.layoutInfo
            let layoutInfoAfterUpdate = ensureCurrentLayoutInfo()

            if let contentOffsetAdjustment = Self.invalidationContentOffsetAdjustment(delegate: delegate,
                                                                                      layoutInfoBeforeUpdate: layoutInfoBeforeUpdate,
                                                                                      layoutInfoAfterUpdate: layoutInfoAfterUpdate),
               contentOffsetAdjustment != .zero {

                let context = UICollectionViewLayoutInvalidationContext()
                context.contentOffsetAdjustment = contentOffsetAdjustment
                self.invalidateLayout(with: context)
            }
        }
    }

    // Try to determine the correct adjustment to `content offset` that will
    // ensure scroll continuity.
    private static func invalidationContentOffsetAdjustment(delegate: ConversationViewLayoutDelegate,
                                                            layoutInfoBeforeUpdate: LayoutInfo,
                                                            layoutInfoAfterUpdate: LayoutInfo) -> CGPoint? {

        var beforeItemLayoutMap = [String: ItemLayout]()
        for itemLayout in layoutInfoBeforeUpdate.itemLayouts {
            beforeItemLayoutMap[itemLayout.interactionUniqueId] = itemLayout
        }

        // Honor the scroll continuity bias.
        //
        // If we prefer continuity with regard to the bottom
        // of the conversation, start with the last items.
        let afterItemLayouts = (delegate.scrollContinuity == .bottom
                                    ? layoutInfoAfterUpdate.itemLayouts.reversed()
                                    : layoutInfoAfterUpdate.itemLayouts)

        for afterItemLayout in afterItemLayouts {
            guard let beforeItemLayout = beforeItemLayoutMap[afterItemLayout.interactionUniqueId] else {
                continue
            }
            let frameBeforeUpdate = beforeItemLayout.layoutAttributes.frame
            let frameAfterUpdate = afterItemLayout.layoutAttributes.frame
            let offset = frameAfterUpdate.origin - frameBeforeUpdate.origin
            let contentOffsetAdjustment = CGPoint(x: 0, y: offset.y)
            return contentOffsetAdjustment
        }

        return nil
    }

    @objc
    public func didPerformBatchUpdates(scrollContinuityToken: CVScrollContinuityToken?) {
        AssertIsOnMainThread()

        isPerformingBatchUpdates = false
    }

    @objc
    public func didCompleteBatchUpdates() {
        AssertIsOnMainThread()

        updateCompletionCounter.decrementOrZero()
    }

    @objc
    public func willReloadData() {
        AssertIsOnMainThread()

        isReloadingData = true
        updateCompletionCounter.increment()
    }

    @objc
    public func didReloadData() {
        AssertIsOnMainThread()

        isReloadingData = false
        updateCompletionCounter.decrementOrZero()
    }

    public func buildScrollContinuityToken() -> CVScrollContinuityToken {
        AssertIsOnMainThread()

        let layoutInfo = ensureCurrentLayoutInfo()
        return CVScrollContinuityToken(layoutInfo: layoutInfo)
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

    private var debugInfo: String {
        guard let delegate = delegate else {
            owsFailDebug("Missing delegate.")
            return "Missing delegate"
        }
        return "isUserScrolling: \(delegate.isUserScrolling), hasScrollingAnimation: \(delegate.hasScrollingAnimation), scrollContinuity: \(delegate.scrollContinuity), isPerformingBatchUpdates: \(isPerformingBatchUpdates), isReloadingData: \(isReloadingData)"
    }

    // MARK: -

    // A layout can return the content offset to be applied during transition or update animations.
    public override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint,
                                             withScrollingVelocity velocity: CGPoint) -> CGPoint {

        targetContentOffset(proposedContentOffset: proposedContentOffset,
                            withScrollingVelocity: velocity)
    }

    // A layout can return the content offset to be applied during transition or update animations.
    public override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {

        targetContentOffset(proposedContentOffset: proposedContentOffset,
                            withScrollingVelocity: nil)
    }

    private func targetContentOffset(proposedContentOffset: CGPoint,
                                     withScrollingVelocity velocity: CGPoint?) -> CGPoint {

        guard let delegate = delegate else {
            owsFailDebug("Missing delegate.")
            if let velocity = velocity {
                return super.targetContentOffset(forProposedContentOffset: proposedContentOffset,
                                                 withScrollingVelocity: velocity)
            } else {
                return super.targetContentOffset(forProposedContentOffset: proposedContentOffset)
            }
        }

        guard velocity == nil else {
            return proposedContentOffset
        }

        // While applying reloadData() and performBatchUpdates(), allow CVC
        // to maintain scroll continuity.
        if isPerformBatchUpdatesOrReloadDataBeingApplied {
            let targetContentOffset = delegate.targetContentOffset(forProposedContentOffset: proposedContentOffset)
            return targetContentOffset
        } else {
            return proposedContentOffset
        }
    }

    @objc
    public override var debugDescription: String {
        ensureCurrentLayoutInfo().debugDescription
    }
}

// MARK: -

// TODO: This might not have to be @objc after the CVC port.
@objc
public class CVScrollContinuityToken: NSObject {
    fileprivate let layoutInfo: ConversationViewLayout.LayoutInfo

    fileprivate init(layoutInfo: ConversationViewLayout.LayoutInfo) {
        self.layoutInfo = layoutInfo
    }
}
