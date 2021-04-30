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
                if !(indexPath.row >= 0 && indexPath.row < itemAttributesMap.count) {
                    Logger.verbose("indexPath: \(indexPath.row) / \(itemAttributesMap.count)")
                }
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

        self.conversationStyle = conversationStyle

        invalidateLayout()
    }

    @objc
    public override func invalidateLayout() {
        super.invalidateLayout()

        ensureState()
    }

    @objc
    public override func invalidateLayout(with context: UICollectionViewLayoutInvalidationContext) {
        super.invalidateLayout(with: context)

        ensureState()
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

    // MARK: - performBatchUpdates()

    private struct UpdateScrollContinuity {
        let layoutInfo: LayoutInfo
        let contentOffset: CGPoint

        private static let idCounter = AtomicUInt(0)
        public let id: UInt = UpdateScrollContinuity.idCounter.increment()
    }
    private var updateScrollContinuity: UpdateScrollContinuity?

    private var isAnimatingBoundsChange = false {
        didSet {
            if !isAnimatingBoundsChange {
                updateScrollContinuity = nil
            }
        }
    }

    @objc
    public var isUpdating: Bool {
        isPerformingBatchUpdates || isReloadingData
    }

    @objc
    public var isApplyingUpdate: Bool {
        updateScrollContinuity != nil
    }

    private var isPerformingBatchUpdates = false

    @objc
    public func willPerformBatchUpdates(animated: Bool, isLoadAdjacent: Bool) {
        AssertIsOnMainThread()
        owsAssertDebug(currentLayoutInfo != nil)

        isPerformingBatchUpdates = true
        if isLoadAdjacent {
            captureUpdateScrollContinuity()
        }
    }

    @objc
    public func didPerformBatchUpdates(animated: Bool) {
        AssertIsOnMainThread()

        isPerformingBatchUpdates = false
    }

    @objc
    public func didCompleteBatchUpdates() {
        AssertIsOnMainThread()
    }

    private var isReloadingData = false

    @objc
    public func willReloadData() {
        AssertIsOnMainThread()

        isReloadingData = true
    }

    @objc
    public func didReloadData() {
        AssertIsOnMainThread()

        isReloadingData = false
    }

    private func captureUpdateScrollContinuity() {
        AssertIsOnMainThread()

        if let collectionView = collectionView {
            let updateScrollContinuity = UpdateScrollContinuity(layoutInfo: ensureCurrentLayoutInfo(),
                                                                contentOffset: collectionView.contentOffset)
            self.updateScrollContinuity = updateScrollContinuity

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                if let currentContinuity = self.updateScrollContinuity,
                   currentContinuity.id == updateScrollContinuity.id {
                    Logger.warn("UpdateScrollContinuity did not get cleaned up in a timely way.")
                    self.updateScrollContinuity = nil
                }
            }
        } else {
            owsFailDebug("Missing collectionView.")
            updateScrollContinuity = nil
        }
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

        isAnimatingBoundsChange = true
    }

    // also called inside the animation block
    public override func finalizeAnimatedBoundsChange() {
        super.finalizeAnimatedBoundsChange()

        isAnimatingBoundsChange = false
    }

    private var debugInfo: String {
        guard let delegate = delegate else {
            owsFailDebug("Missing delegate.")
            return "Missing delegate"
        }
        return "isUserScrolling: \(delegate.isUserScrolling), hasScrollingAnimation: \(delegate.hasScrollingAnimation), scrollContinuity: \(delegate.scrollContinuity), isPerformingBatchUpdates: \(isPerformingBatchUpdates), isReloadingData: \(isReloadingData), updateScrollContinuity: \(updateScrollContinuity != nil)"
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

        if let updateScrollContinuity = updateScrollContinuity {
            let layoutInfoCurrent = ensureCurrentLayoutInfo()
            if let targetContentOffset = Self.targetContentOffsetForUpdate(delegate: delegate,
                                                                           updateScrollContinuity: updateScrollContinuity,
                                                                           layoutInfoCurrent: layoutInfoCurrent) {
                return targetContentOffset
            } else {
                Logger.warn("Could not ensure scroll continuity.")
            }
        }

        if isUpdating {
            let targetContentOffset = delegate.targetContentOffset(forProposedContentOffset: proposedContentOffset)
            return targetContentOffset
        } else {
            return proposedContentOffset
        }
    }

    // We use this hook to ensure scroll state continuity.  As the collection
    // view's content size changes, we want to keep the same cells in view.
    private static func targetContentOffsetForUpdate(delegate: ConversationViewLayoutDelegate,
                                                     updateScrollContinuity: UpdateScrollContinuity,
                                                     layoutInfoCurrent layoutInfoAfterUpdate: LayoutInfo) -> CGPoint? {
        let layoutInfoBeforeUpdate = updateScrollContinuity.layoutInfo
        let contentOffsetBeforeUpdate = updateScrollContinuity.contentOffset

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
            let updatedContentOffset = CGPoint(x: 0,
                                               y: (contentOffsetBeforeUpdate + offset).y)
            return updatedContentOffset
        }

        Logger.verbose("No continuity match.")

        return nil
    }

    @objc
    public override var debugDescription: String {
        ensureCurrentLayoutInfo().debugDescription
    }
}
