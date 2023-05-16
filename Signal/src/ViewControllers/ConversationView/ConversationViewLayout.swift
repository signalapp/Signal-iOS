//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

public enum ScrollContinuity: CustomStringConvertible {
    // Do not try to maintain scroll continuity.
    case none

    // Try to maintain scroll continuity by invalidating
    // the layout with a contentOffsetAdjustment.
    //
    // If isRelativeToTop is true, the top-most visible interaction
    // in the chat history should remain the same distance from the
    // top of the chat history (assuming content didn't change,
    // interactions didn't expire, etc.).
    //
    // If isRelativeToTop is false, the bottom-most visible interaction
    // in the chat history above the keyboard should remain the same
    // distance from the top of the keyboard (again, everything else
    // being equal).
    case contentRelativeToViewport(token: CVScrollContinuityToken, isRelativeToTop: Bool)

    // Try to maintain scroll continuity using the delegate method:
    //
    // CVC.targetContentOffset(forProposedContentOffset().
    //
    // This delegate method handles cases like view size transitions,
    // orientation changes, message actions, etc.
    case delegateScrollContinuity

    // MARK: - CustomStringConvertible

    public var description: String {
        switch self {
        case .none:
            return "none"
        case .contentRelativeToViewport(_, let isRelativeToTop):
            return "contentRelativeToViewport(isRelativeToTop: \(isRelativeToTop))"
        case .delegateScrollContinuity:
            return "delegateScrollContinuity"
        }
    }
}

// MARK: -

public protocol ConversationViewLayoutItem {

    var interactionUniqueId: String { get }

    var cellSize: CGSize { get }

    func vSpacing(previousLayoutItem: ConversationViewLayoutItem) -> CGFloat

    var canBeUsedForContinuity: Bool { get }

    var isDateHeader: Bool { get }
}

// MARK: -

public protocol ConversationViewLayoutDelegate: AnyObject {

    var layoutItems: [ConversationViewLayoutItem] { get }
    var renderStateId: UInt { get }

    var layoutHeaderHeight: CGFloat { get }
    var layoutFooterHeight: CGFloat { get }

    var conversationViewController: ConversationViewController? { get }
}

// MARK: -

public class ConversationViewLayout: UICollectionViewLayout {

    public weak var delegate: ConversationViewLayoutDelegate?

    private var conversationStyle: ConversationStyle

    fileprivate struct ItemLayout {
        let interactionUniqueId: String
        let indexPath: IndexPath
        let layoutAttributes: UICollectionViewLayoutAttributes
        let canBeUsedForContinuity: Bool
        let isStickyHeader: Bool

        var frame: CGRect { layoutAttributes.frame }
    }

    fileprivate class LayoutInfo {

        let viewWidth: CGFloat
        let contentSize: CGSize
        let layoutAttributesMap: [Int: UICollectionViewLayoutAttributes]
        let headerLayoutAttributes: UICollectionViewLayoutAttributes?
        let footerLayoutAttributes: UICollectionViewLayoutAttributes?
        let itemLayouts: [ItemLayout]
        let renderStateId: UInt

        required init(viewWidth: CGFloat,
                      contentSize: CGSize,
                      layoutAttributesMap: [Int: UICollectionViewLayoutAttributes],
                      headerLayoutAttributes: UICollectionViewLayoutAttributes?,
                      footerLayoutAttributes: UICollectionViewLayoutAttributes?,
                      itemLayouts: [ItemLayout],
                      renderStateId: UInt) {
            self.viewWidth = viewWidth
            self.contentSize = contentSize
            self.layoutAttributesMap = layoutAttributesMap
            self.headerLayoutAttributes = headerLayoutAttributes
            self.footerLayoutAttributes = footerLayoutAttributes
            self.itemLayouts = itemLayouts
            self.renderStateId = renderStateId
        }

        func layoutAttributesForItem(at indexPath: IndexPath, assertIfMissing: Bool) -> UICollectionViewLayoutAttributes? {
            if assertIfMissing {
                owsAssertDebug(indexPath.row >= 0 && indexPath.row < layoutAttributesMap.count)
            }
            return layoutAttributesMap[indexPath.row]
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
            for item in layoutAttributesMap.keys.sorted() {
                guard let layoutAttributes = layoutAttributesMap[item] else {
                    owsFailDebug("Missing attributes for item: \(item)")
                    continue
                }
                result += "item: \(layoutAttributes.indexPath), "
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

    // * currentLayoutInfo is the "at rest" layout.
    // * translatedLayoutInfo is the same layout, with ephemeral changes
    //   for sticky date headers.
    private var currentLayoutInfo: LayoutInfo? {
        didSet {
            // We need to clear our "translated" layout info cache if the
            // "default" layout info changes, since the "translated" state
            // is derived from the "default" state.
            translatedLayoutInfo = nil
        }
    }

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

    private class TranslatedLayoutInfo {
        let layoutInfo: LayoutInfo
        let collectionViewSize: CGSize
        let contentOffset: CGPoint
        let contentInset: UIEdgeInsets

        init(layoutInfo: LayoutInfo,
             collectionViewSize: CGSize,
             contentOffset: CGPoint,
             contentInset: UIEdgeInsets) {

            self.layoutInfo = layoutInfo
            self.collectionViewSize = collectionViewSize
            self.contentOffset = contentOffset
            self.contentInset = contentInset
        }
    }
    // * currentLayoutInfo is the "at rest" layout.
    // * translatedLayoutInfo is the same layout, with ephemeral changes
    //   for sticky date headers.
    private var translatedLayoutInfo: TranslatedLayoutInfo?

    private func clearTranslatedLayoutInfoIfNecessary() {
        guard let collectionView = self.collectionView,
              let translatedLayoutInfo = self.translatedLayoutInfo else {
            return
        }
        let collectionViewSize = collectionView.bounds.size
        let contentOffset = collectionView.contentOffset
        let contentInset = collectionView.contentInset
        let didChange = (translatedLayoutInfo.collectionViewSize != collectionViewSize ||
                            translatedLayoutInfo.contentOffset != contentOffset ||
                            translatedLayoutInfo.contentInset != contentInset)
        guard didChange else {
            return
        }
        // We need to clear our "translated" layout info cache if any of
        // the collection view state changes.
        self.translatedLayoutInfo = nil
    }

    private func ensureTranslatedLayoutInfo() -> LayoutInfo {
        AssertIsOnMainThread()

        // Use cached value if possible.
        if let translatedLayoutInfo = self.translatedLayoutInfo {
            return translatedLayoutInfo.layoutInfo
        }

        let layoutInfo = ensureCurrentLayoutInfo()

        guard let collectionView = self.collectionView else {
            owsFailDebug("Missing view.")
            return layoutInfo
        }
        let collectionViewSize = collectionView.bounds.size
        let contentOffset = collectionView.contentOffset
        let contentInset = collectionView.adjustedContentInset
        // The spacing between the sticky header and the navbar.
        let navBarSpacing: CGFloat = 12
        // We want the sticky headers to stick just below the navbar,
        // with a small spacing.
        let topInset = contentInset.top + navBarSpacing
        let topOfViewportY = contentOffset.y + topInset
        // The minimum spacing between the sticky header and the next header.
        let minDateHeaderSpacing: CGFloat = 5

        func isDateHeaderInOrBelowViewport(itemLayout: ItemLayout) -> Bool {
            let frame = itemLayout.layoutAttributes.frame
            return frame.y >= topOfViewportY
        }

        // Find all date headers.
        var dateHeaderItemLayouts = [ItemLayout]()
        for itemLayout in layoutInfo.itemLayouts {
            guard itemLayout.isStickyHeader else {
                continue
            }
            dateHeaderItemLayouts.append(itemLayout)
        }
        // Sort the date headers.
        dateHeaderItemLayouts.sort { (left, right) in
            left.frame.y < right.frame.y
        }
        // The sticky date header is either:
        //
        // * The last date header if no date headers are in or below the viewport.
        //
        // DH                   DH
        // DH                   DH
        // DH                   ↓
        //    -                 DH - <- Stick to top of viewport
        //    |                    |
        //    | ViewPort   ->      | ViewPort
        //    |                    |
        //    -                    -
        //
        // * The date header just above the last date header in or below the viewport.
        //
        // DH                   DH
        // DH                   DH
        // DH                   ↓
        //    -                 DH - <- Stick to top of viewport
        //    |                    |
        //    | ViewPort   ->      | ViewPort
        //    |                    |
        // DH |                 DH | <- Last Header in or below the viewport.
        //    -                    -
        // DH                   DH
        // DH                   DH
        //
        // Therefore we trim the (ordered) list of date headers until there is
        // _at most_ one date header in or below the viewport (it will be last if
        // present).
        while true {
            let lastTwoDateHeaders = dateHeaderItemLayouts.suffix(2)
            guard lastTwoDateHeaders.count == 2,
               let lastDateHeader = lastTwoDateHeaders.last,
               let penultimateDateHeader = lastTwoDateHeaders.first else {
                // Not enough date headers to continue trimming.
                break
            }
            if isDateHeaderInOrBelowViewport(itemLayout: lastDateHeader),
               isDateHeaderInOrBelowViewport(itemLayout: penultimateDateHeader) {
                _ = dateHeaderItemLayouts.popLast()
                continue
            } else {
                // No need to continue trimming.
                break
            }
        }
        struct StickyDateHeader {
            let prevDateHeader: ItemLayout?
            let dateHeaderToStick: ItemLayout
            let nextDateHeader: ItemLayout?
        }
        func findDateHeaderToStick() -> StickyDateHeader? {
            // This might contain item layouts for 0, 1 or 2 date headers.
            guard let lastDateHeader = dateHeaderItemLayouts[back: 0] else {
                // No date headers, nothing to stick.
                return nil
            }
            guard let penultimateDateHeader = dateHeaderItemLayouts[back: 1] else {
                if isDateHeaderInOrBelowViewport(itemLayout: lastDateHeader) {
                    // All date headers are in or below viewport, nothing to stick.
                    return nil
                } else {
                    // There's only one date header and it's above the viewport;
                    // it should stick.
                    return StickyDateHeader(prevDateHeader: nil,
                                            dateHeaderToStick: lastDateHeader,
                                            nextDateHeader: nil)
                }
            }
            let prevDateHeader: ItemLayout? = dateHeaderItemLayouts[back: 2]
            if isDateHeaderInOrBelowViewport(itemLayout: lastDateHeader) {
                owsAssertDebug(!isDateHeaderInOrBelowViewport(itemLayout: penultimateDateHeader))
                // We found the last date header just above the first date header that
                // is in or below the viewport; it should stick.
                return StickyDateHeader(prevDateHeader: prevDateHeader,
                                        dateHeaderToStick: penultimateDateHeader,
                                        nextDateHeader: lastDateHeader)
            } else {
                // There's last date header is above the viewport;
                // it should stick.
                return StickyDateHeader(prevDateHeader: prevDateHeader,
                                        dateHeaderToStick: lastDateHeader,
                                        nextDateHeader: nil)
            }
        }
        guard let dateHeaderToStick = findDateHeaderToStick() else {
            // No date header to stick; no translation is needed.
            return layoutInfo
        }
        let stickyDateHeader = dateHeaderToStick.dateHeaderToStick

        var layoutAttributesMap = layoutInfo.layoutAttributesMap
        var itemLayouts = layoutInfo.itemLayouts

        func updateItemLayout(_ newItemLayout: ItemLayout) {
            // Update layoutAttributesMap.
            layoutAttributesMap[newItemLayout.indexPath.row] = newItemLayout.layoutAttributes

            // Update itemLayouts.
            itemLayouts = itemLayouts.map { (itemLayout: ItemLayout) -> ItemLayout in
                if itemLayout.indexPath == newItemLayout.indexPath {
                    // Replace this itemLayout with the stickyItemLayout
                    return newItemLayout
                } else {
                    return itemLayout
                }
            }
        }

        // "At rest", the sticky header should be aligned with the top of the viewport,
        // with a small spacing.
        let stickyHeaderY_normal = stickyDateHeader.frame.y
        var stickyHeaderY_stuck = topOfViewportY
        if let nextDateHeader = dateHeaderToStick.nextDateHeader {
            let maxStickyY = nextDateHeader.frame.y - (stickyDateHeader.frame.height + minDateHeaderSpacing)
            stickyHeaderY_stuck = min(stickyHeaderY_stuck, maxStickyY)
        }

        // Update the ItemLayout for the "stuck" sticky header.
        do {
            let stickyItemLayout: ItemLayout = {
                let indexPath = stickyDateHeader.indexPath
                let layoutAttributes = CVCollectionViewLayoutAttributes(forCellWith: indexPath)
                var frame = stickyDateHeader.frame
                frame.y = stickyHeaderY_stuck
                layoutAttributes.frame = frame
                layoutAttributes.zIndex = Self.zIndexStickyHeader
                layoutAttributes.isStickyHeader = true

                return ItemLayout(interactionUniqueId: stickyDateHeader.interactionUniqueId,
                                  indexPath: indexPath,
                                  layoutAttributes: layoutAttributes,
                                  canBeUsedForContinuity: stickyDateHeader.canBeUsedForContinuity,
                                  isStickyHeader: stickyDateHeader.isStickyHeader)
            }()
            updateItemLayout(stickyItemLayout)
        }

        // Update the ItemLayout for the previous date header.
        // This ensures an orderly transition out after it has become
        // "unstuck"
        if let prevDateHeader = dateHeaderToStick.prevDateHeader {

            let prevItemLayout: ItemLayout = {
                let indexPath = prevDateHeader.indexPath
                let layoutAttributes = CVCollectionViewLayoutAttributes(forCellWith: indexPath)
                var frame = prevDateHeader.frame
                frame.y = stickyHeaderY_normal - (frame.height + minDateHeaderSpacing)
                layoutAttributes.frame = frame
                layoutAttributes.zIndex = Self.zIndexStickyHeader
                layoutAttributes.isStickyHeader = true

                return ItemLayout(interactionUniqueId: prevDateHeader.interactionUniqueId,
                                  indexPath: indexPath,
                                  layoutAttributes: layoutAttributes,
                                  canBeUsedForContinuity: prevDateHeader.canBeUsedForContinuity,
                                  isStickyHeader: prevDateHeader.isStickyHeader)
            }()
            updateItemLayout(prevItemLayout)
        }

        let adjustedLayoutInfo = LayoutInfo(viewWidth: layoutInfo.viewWidth,
                                            contentSize: layoutInfo.contentSize,
                                            layoutAttributesMap: layoutAttributesMap,
                                            headerLayoutAttributes: layoutInfo.headerLayoutAttributes,
                                            footerLayoutAttributes: layoutInfo.footerLayoutAttributes,
                                            itemLayouts: itemLayouts,
                                            renderStateId: layoutInfo.renderStateId)
        // Update the cache.
        self.translatedLayoutInfo = TranslatedLayoutInfo(layoutInfo: adjustedLayoutInfo,
                                                         collectionViewSize: collectionViewSize,
                                                         contentOffset: contentOffset,
                                                         contentInset: contentInset)
        return adjustedLayoutInfo
    }

    public override class var layoutAttributesClass: AnyClass {
        CVCollectionViewLayoutAttributes.self
    }

    public required init(conversationStyle: ConversationStyle) {
        self.conversationStyle = conversationStyle

        super.init()
    }

    @available(*, unavailable, message: "Use other constructor instead.")
    public required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(conversationStyle: ConversationStyle) {
        AssertIsOnMainThread()

        guard !self.conversationStyle.isEqualForCellRendering(conversationStyle) else {
            return
        }

        self.conversationStyle = conversationStyle

        invalidateLayout()
    }

    public override func invalidateLayout() {
        AssertIsOnMainThread()

        super.invalidateLayout()

        // This method will call invalidateLayout(with:).
        // We don't want to assume that, so we call ensureState() to be safe.
        ensureState()
    }

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

    public override func prepare() {
        super.prepare()

        _ = ensureCurrentLayoutInfo()
        clearTranslatedLayoutInfoIfNecessary()
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
                              layoutAttributesMap: [:],
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

        var layoutAttributesMap = [Int: UICollectionViewLayoutAttributes]()
        var headerLayoutAttributes: UICollectionViewLayoutAttributes?
        var footerLayoutAttributes: UICollectionViewLayoutAttributes?

        if layoutItems.isEmpty || layoutHeaderHeight <= 0 {
            // Do nothing.
        } else {
            let headerIndexPath = IndexPath(row: 0, section: 0)
            let layoutAttributes = CVCollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
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
            let layoutAttributes = CVCollectionViewLayoutAttributes(forCellWith: indexPath)
            layoutAttributes.frame = itemFrame
            if layoutItem.isDateHeader {
                layoutAttributes.zIndex = Self.zIndexStickyHeader
            } else {
                layoutAttributes.zIndex = Self.zIndexDefault
            }
            layoutAttributesMap[row] = layoutAttributes

            contentBottom = itemFrame.origin.y + itemFrame.size.height
            y = contentBottom
            row += 1
            previousLayoutItem = layoutItem

            itemLayouts.append(ItemLayout(interactionUniqueId: layoutItem.interactionUniqueId,
                                          indexPath: indexPath,
                                          layoutAttributes: layoutAttributes,
                                          canBeUsedForContinuity: layoutItem.canBeUsedForContinuity,
                                          isStickyHeader: layoutItem.isDateHeader))
        }

        contentBottom += conversationStyle.contentMarginBottom

        if row > 0 {
            let footerIndexPath = IndexPath(row: row - 1, section: 0)
            if layoutItems.isEmpty || layoutFooterHeight <= 0 || headerLayoutAttributes?.indexPath == footerIndexPath {
                // Do nothing.
            } else {
                let layoutAttributes = CVCollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter,
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
                          layoutAttributesMap: layoutAttributesMap,
                          headerLayoutAttributes: headerLayoutAttributes,
                          footerLayoutAttributes: footerLayoutAttributes,
                          itemLayouts: itemLayouts,
                          renderStateId: renderStateId)
    }

    private static let zIndexDefault: Int = 1
    private static let zIndexStickyHeader: Int = 2

    // MARK: - UICollectionViewLayout Impl.

    public override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        AssertIsOnMainThread()

        // Return values from the "translated" layout info.
        let layoutInfo = ensureTranslatedLayoutInfo()

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

    public override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        AssertIsOnMainThread()

        // Return values from the "translated" layout info.
        let layoutInfo = ensureTranslatedLayoutInfo()
        return layoutInfo.layoutAttributesForItem(at: indexPath, assertIfMissing: true)
    }

    public override func layoutAttributesForSupplementaryView(ofKind elementKind: String,
                                                              at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        AssertIsOnMainThread()

        // Return values from the "translated" layout info.
        let layoutInfo = ensureTranslatedLayoutInfo()
        return layoutInfo.layoutAttributesForSupplementaryElement(ofKind: elementKind,
                                                                  at: indexPath)
    }

    public override var collectionViewContentSize: CGSize {
        AssertIsOnMainThread()

        return ensureCurrentLayoutInfo().contentSize
    }

    public override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        return true
    }

    // MARK: - performBatchUpdates() & reloadData()

    // Flag set before reloadData() and cleared after it _completes_.
    private var isReloadingData = false

    // Flag set before performBatchUpdates() and cleared after it _returns_.
    private var isPerformingBatchUpdates = false

    private enum DelegateScrollContinuityMode: Equatable {
        case disabled
        case enabled(lastKnownDistanceFromBottom: CGFloat?)
        case enabledIOS12(token: CVScrollContinuityToken,
                          isRelativeToTop: Bool,
                          lastKnownDistanceFromBottom: CGFloat?)
    }
    private var delegateScrollContinuityMode: DelegateScrollContinuityMode = .disabled

    // Returns true during performBatchUpdates() or reloadData().
    // Unlike isPerformBatchUpdatesOrReloadDataBeingAppliedOrSettling, this
    // returns true after performBatchUpdates() returns, before
    // its completion is called.
    public var isPerformBatchUpdatesOrReloadDataBeingApplied: Bool {
        isPerformingBatchUpdates || isReloadingData
    }

    private let updateCompletionCounter = AtomicUInt(0)

    // Returns true during performBatchUpdates() or reloadData().
    // Unlike isPerformBatchUpdatesOrReloadDataBeingApplied, this
    // returns true until the completion of performBatchUpdates().
    public var isPerformBatchUpdatesOrReloadDataBeingAppliedOrSettling: Bool {
        updateCompletionCounter.get() > 0
    }

    public func willPerformBatchUpdates(scrollContinuity: ScrollContinuity,
                                        lastKnownDistanceFromBottom: CGFloat?) {
        AssertIsOnMainThread()
        owsAssertDebug(!isReloadingData)
        owsAssertDebug(!isPerformingBatchUpdates)
        owsAssertDebug(delegateScrollContinuityMode == .disabled)

        isPerformingBatchUpdates = true
        updateCompletionCounter.increment()
        delegateScrollContinuityMode = .disabled

        switch scrollContinuity {
        case .none:
            break
        case .contentRelativeToViewport(let token, let isRelativeToTop):
        if #available(iOS 13, *) {
            if !applyContentOffsetAdjustmentIfNecessary(scrollContinuityToken: token,
                                                        isRelativeToTop: isRelativeToTop) {
                delegateScrollContinuityMode = .enabled(lastKnownDistanceFromBottom: lastKnownDistanceFromBottom)
            }
        } else {
            // On iOS 12, we can't safely invalidate the context before performBatchUpdates()
            // begins, so we use a special .delegateScrollContinuity mode.
            delegateScrollContinuityMode = .enabledIOS12(token: token,
                                                         isRelativeToTop: isRelativeToTop,
                                                         lastKnownDistanceFromBottom: lastKnownDistanceFromBottom)
        }
        case .delegateScrollContinuity:
            delegateScrollContinuityMode = .enabled(lastKnownDistanceFromBottom: lastKnownDistanceFromBottom)
        }
    }

    private func applyContentOffsetAdjustmentIfNecessary(scrollContinuityToken: CVScrollContinuityToken,
                                                         isRelativeToTop: Bool) -> Bool {

        // When landing some CVC loads, we maintain scroll continuity by setting a
        // `contentOffsetAdjustment` on the UICollectionViewLayoutInvalidationContext
        // pass to invalidateLayout().  The timing of this adjustment to the
        // `contentOffset` is delicate.  It must be done just before
        // UICollectionView.performBatchUpdates().
        ensureState()

        let layoutInfoAfterUpdate = ensureCurrentLayoutInfo()

        // TODO: Capture a CVScrollContinuityToken before view transition,
        // orientation changes, etc.
        guard let contentOffsetAdjustment = Self.invalidationContentOffsetAdjustment(scrollContinuityToken: scrollContinuityToken,
                                                                                     layoutInfoAfterUpdate: layoutInfoAfterUpdate,
                                                                                     isRelativeToTop: isRelativeToTop) else {
            return false
        }
        guard contentOffsetAdjustment != .zero else {
            // If no adjustment is necessary, consider that success but
            // do not bother calling invalidateLayout().
            return true
        }

        let context = UICollectionViewLayoutInvalidationContext()
        context.contentOffsetAdjustment = contentOffsetAdjustment
        self.invalidateLayout(with: context)
        return true
    }

    // Try to determine the correct adjustment to `content offset` that will
    // ensure scroll continuity.
    private static func invalidationContentOffsetAdjustment(scrollContinuityToken: CVScrollContinuityToken,
                                                            layoutInfoAfterUpdate: LayoutInfo,
                                                            isRelativeToTop: Bool) -> CGPoint? {

        let layoutInfoBeforeUpdate = scrollContinuityToken.layoutInfo

        func buildItemLayoutMap(layoutInfo: LayoutInfo) -> [String: ItemLayout] {
            var result = [String: ItemLayout]()
            for itemLayout in layoutInfo.itemLayouts {
                result[itemLayout.interactionUniqueId] = itemLayout
            }
            return result
        }

        let beforeItemLayoutMap = buildItemLayoutMap(layoutInfo: layoutInfoBeforeUpdate)
        let afterItemLayoutMap = buildItemLayoutMap(layoutInfo: layoutInfoAfterUpdate)

        func calculateAdjustment(beforeItemLayout: ItemLayout,
                                 afterItemLayout: ItemLayout) -> CGPoint {
            let frameBeforeUpdate = beforeItemLayout.frame
            let frameAfterUpdate = afterItemLayout.frame
            let offset = frameAfterUpdate.origin - frameBeforeUpdate.origin
            let contentOffsetAdjustment = CGPoint(x: 0, y: offset.y)
            return contentOffsetAdjustment
        }

        // Prefer to maintain continuity with visible interactions.
        //
        // Honor the scroll continuity bias. If we prefer continuity with regard
        // to the bottom of the viewport, start with the last items.
        let visibleUniqueIds = (isRelativeToTop
                                    ? scrollContinuityToken.visibleUniqueIds
                                    : scrollContinuityToken.visibleUniqueIds.reversed())
        for visibleUniqueId in visibleUniqueIds {
            guard let beforeItemLayout = beforeItemLayoutMap[visibleUniqueId],
                  let afterItemLayout = afterItemLayoutMap[visibleUniqueId] else {
                continue
            }
            return calculateAdjustment(beforeItemLayout: beforeItemLayout,
                                       afterItemLayout: afterItemLayout)
        }

        // Fail over to trying to use any interaction in the before & after
        // load windows.  Again, honor the scroll continuity bias.
        let afterItemLayouts = (isRelativeToTop
                                    ? layoutInfoAfterUpdate.itemLayouts
                                    : layoutInfoAfterUpdate.itemLayouts.reversed())

        for afterItemLayout in afterItemLayouts {
            guard let beforeItemLayout = beforeItemLayoutMap[afterItemLayout.interactionUniqueId] else {
                continue
            }
            return calculateAdjustment(beforeItemLayout: beforeItemLayout,
                                       afterItemLayout: afterItemLayout)
        }

        return nil
    }

    public func didPerformBatchUpdates() {
        AssertIsOnMainThread()
        owsAssertDebug(!isReloadingData)
        owsAssertDebug(isPerformingBatchUpdates)

        isPerformingBatchUpdates = false
        delegateScrollContinuityMode = .disabled

        if #unavailable(iOS 13) {
            // On iOS 12, we invalidate the layout immediately after performBatchUpdates()
            // to ensure that targetContentOffset(forProposedContentOffset:) is applied in a timely way.
            invalidateLayout()
        }
    }

    public func didCompleteBatchUpdates() {
        AssertIsOnMainThread()

        updateCompletionCounter.decrementOrZero()
    }

    public func willReloadData() {
        AssertIsOnMainThread()
        owsAssertDebug(!isReloadingData)
        owsAssertDebug(!isPerformingBatchUpdates)
        owsAssertDebug(delegateScrollContinuityMode == .disabled)

        isReloadingData = true
        updateCompletionCounter.increment()
        // TODO: We _could_ use the invalidation context for scroll
        // continuity here.
        let lastKnownDistanceFromBottom = delegate?.conversationViewController?.lastKnownDistanceFromBottom ?? 0
        delegateScrollContinuityMode = .enabled(lastKnownDistanceFromBottom: lastKnownDistanceFromBottom)
    }

    public func didReloadData() {
        AssertIsOnMainThread()
        owsAssertDebug(isReloadingData)
        owsAssertDebug(!isPerformingBatchUpdates)

        isReloadingData = false
        updateCompletionCounter.decrementOrZero()
        delegateScrollContinuityMode = .disabled
    }

    public func buildScrollContinuityToken() -> CVScrollContinuityToken {
        AssertIsOnMainThread()

        let layoutInfo = ensureCurrentLayoutInfo()
        let contentOffset = collectionView?.contentOffset ?? .zero
        let visibleUniqueIds: [String] = {
            guard let collectionView = self.collectionView else {
                Logger.warn("Missing collectionView.")
                return []
            }
            let visibleIndexPaths = collectionView.indexPathsForVisibleItems
            return visibleIndexPaths.compactMap { indexPath -> String? in
                guard let layoutInfo = layoutInfo.itemLayouts[safe: indexPath.row],
                      layoutInfo.canBeUsedForContinuity else {
                    return nil
                }
                return layoutInfo.interactionUniqueId
            }
        }()
        return CVScrollContinuityToken(layoutInfo: layoutInfo,
                                       contentOffset: contentOffset,
                                       visibleUniqueIds: visibleUniqueIds)
    }

    // Some interactions shift around and cannot be reliably used as
    // references for scroll continuity.
    public static func canInteractionBeUsedForScrollContinuity(_ interaction: TSInteraction) -> Bool {
        guard !interaction.isDynamicInteraction else {
            return false
        }

        switch interaction.interactionType {
        case .unknown, .unreadIndicator, .dateHeader, .typingIndicator:
            return false
        case .incomingMessage, .outgoingMessage, .error, .call, .info, .threadDetails, .unknownThreadWarning, .defaultDisappearingMessageTimer:
            return true
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
    }

    // also called inside the animation block
    public override func finalizeAnimatedBoundsChange() {
        super.finalizeAnimatedBoundsChange()
    }

    private var isUserScrolling: Bool {
        delegate?.conversationViewController?.isUserScrolling ?? false
    }

    private var hasScrollingAnimation: Bool {
        delegate?.conversationViewController?.hasScrollingAnimation ?? false
    }

    private var debugInfo: String {
        "isUserScrolling: \(isUserScrolling), hasScrollingAnimation: \(hasScrollingAnimation), " +
            "isPerformingBatchUpdates: \(isPerformingBatchUpdates), " +
            "isReloadingData: \(isReloadingData), " +
            "isPerformBatchUpdatesOrReloadDataBeingApplied: \(isPerformBatchUpdatesOrReloadDataBeingApplied), " +
            "isPerformBatchUpdatesOrReloadDataBeingAppliedOrSettling: \(isPerformBatchUpdatesOrReloadDataBeingAppliedOrSettling), "
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
        switch delegateScrollContinuityMode {
        case .disabled:
            break
        case .enabled(let lastKnownDistanceFromBottom):
            if let conversationViewController = delegate.conversationViewController {
                let targetContentOffset = conversationViewController.targetContentOffset(forProposedContentOffset: proposedContentOffset,
                                                                                         lastKnownDistanceFromBottom: lastKnownDistanceFromBottom)
                return targetContentOffset
            }
        case .enabledIOS12(let token,
                           let isRelativeToTop,
                           let lastKnownDistanceFromBottom):

            if let lastKnownDistanceFromBottom = lastKnownDistanceFromBottom,
               abs(lastKnownDistanceFromBottom) < 5 {
                // If the user was scrolled to the bottom, use the "delegate"
                // scroll continuity mechanism.
            } else {
                let layoutInfoCurrent = ensureCurrentLayoutInfo()
                if let targetContentOffset = Self.targetContentOffsetForUpdate(delegate: delegate,
                                                                               token: token,
                                                                               isRelativeToTop: isRelativeToTop,
                                                                               layoutInfoAfterUpdate: layoutInfoCurrent) {
                    return targetContentOffset
                }
            }
            if let conversationViewController = delegate.conversationViewController {
                let targetContentOffset = conversationViewController.targetContentOffset(forProposedContentOffset: proposedContentOffset,
                                                                                         lastKnownDistanceFromBottom: lastKnownDistanceFromBottom)
                return targetContentOffset
            }
        }

        return proposedContentOffset
    }

    private static func targetContentOffsetForUpdate(delegate: ConversationViewLayoutDelegate,
                                                     token: CVScrollContinuityToken,
                                                     isRelativeToTop: Bool,
                                                     layoutInfoAfterUpdate: LayoutInfo) -> CGPoint? {
        let layoutInfoBeforeUpdate = token.layoutInfo
        let contentOffsetBeforeUpdate = token.contentOffset

        var beforeItemLayoutMap = [String: ItemLayout]()
        for beforeItemLayout in layoutInfoBeforeUpdate.itemLayouts {
            guard beforeItemLayout.canBeUsedForContinuity else {
                continue
            }
            beforeItemLayoutMap[beforeItemLayout.interactionUniqueId] = beforeItemLayout
        }

        // Honor the scroll continuity bias.
        //
        // If we prefer continuity with regard to the bottom
        // of the conversation, start with the last items.
        let afterItemLayouts = (isRelativeToTop
                                    ? layoutInfoAfterUpdate.itemLayouts
                                    : layoutInfoAfterUpdate.itemLayouts.reversed())

        for afterItemLayout in afterItemLayouts {
            guard afterItemLayout.canBeUsedForContinuity,
                  let beforeItemLayout = beforeItemLayoutMap[afterItemLayout.interactionUniqueId] else {
                continue
            }
            let frameBeforeUpdate = beforeItemLayout.frame
            let frameAfterUpdate = afterItemLayout.frame
            let offset = frameAfterUpdate.origin - frameBeforeUpdate.origin
            let updatedContentOffset = CGPoint(x: 0,
                                               y: (contentOffsetBeforeUpdate + offset).y)
            return updatedContentOffset
        }

        Logger.verbose("No continuity match.")

        return nil
    }

    public override var debugDescription: String {
        ensureCurrentLayoutInfo().debugDescription
    }
}

// MARK: -

// TODO: This might not have to be @objc after the CVC port.
public class CVScrollContinuityToken: NSObject {
    fileprivate let layoutInfo: ConversationViewLayout.LayoutInfo
    fileprivate let contentOffset: CGPoint
    fileprivate let visibleUniqueIds: [String]

    fileprivate init(layoutInfo: ConversationViewLayout.LayoutInfo,
                     contentOffset: CGPoint,
                     visibleUniqueIds: [String]) {
        self.layoutInfo = layoutInfo
        self.contentOffset = contentOffset
        self.visibleUniqueIds = visibleUniqueIds
    }
}

// MARK: -

public class CVCollectionViewLayoutAttributes: UICollectionViewLayoutAttributes {
    public var isStickyHeader: Bool = false

    public override func copy(with zone: NSZone? = nil) -> Any {
        let copy = super.copy(with: zone) as! CVCollectionViewLayoutAttributes
        copy.isStickyHeader = isStickyHeader
        return copy
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? CVCollectionViewLayoutAttributes else {
            return false
        }
        guard object.isStickyHeader == self.isStickyHeader else {
            return false
        }
        return super.isEqual(object)
    }
}

// MARK: -

extension Array {
    subscript(back i: Int) -> Iterator.Element? {
        self[safe: index(endIndex, offsetBy: -(i + 1))]
    }
}
