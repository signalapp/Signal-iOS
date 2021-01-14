//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public enum ScrollAlignment: Int {
    case top
    case bottom
    case center

    // These match the behavior of UICollectionView.ScrollPosition and
    // noop if the view is already entirely on screen.
    case topIfNotEntirelyOnScreen
    case bottomIfNotEntirelyOnScreen
    case centerIfNotEntirelyOnScreen

    var scrollsOnlyIfNotEntirelyOnScreen: Bool {
        switch self {
        case .top, .bottom, .center:
            return false
        case .topIfNotEntirelyOnScreen,
             .bottomIfNotEntirelyOnScreen,
             .centerIfNotEntirelyOnScreen:
            return true
        }
    }
}

// MARK: -

@objc
public enum ScrollContinuity: Int, CustomStringConvertible {
    case top
    case bottom

    // MARK: - CustomStringConvertible

    public var description: String {
        switch self {
        case .top:
            return "top"
        case .bottom:
            return "bottom"
        }
    }
}

// MARK: -

// TODO: Do we need to specify the load alignment (top, bottom, center)
// or that implicit in the value?
public struct CVScrollAction: Equatable, CustomStringConvertible {

    // TODO: Do we need to specify the load alignment (top, bottom, center)
    // or that implicit in the value?
    public enum Action: Equatable, CustomStringConvertible {
        case none
        case scrollTo(interactionId: String, onScreenPercentage: CGFloat, alignment: ScrollAlignment)
        case bottomOfLoadWindow
        case initialPosition

        // MARK: - CustomStringConvertible

        public var description: String {
            switch self {
            case .none:
                return "none"
            case .scrollTo(let interactionId, _, _):
                return "scrollTo(\(interactionId))"
            case .bottomOfLoadWindow:
                return "bottomOfLoadWindow"
            case .initialPosition:
                return "initialPosition"
            }
        }
    }

    let action: Action
    let isAnimated: Bool

    public static var none: CVScrollAction {
        CVScrollAction(action: .none, isAnimated: false)
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        "[scrollAction: \(action), isAnimated: \(isAnimated)]"
    }
}

// MARK: -

extension ConversationViewController {

    func perform(scrollAction: CVScrollAction) {
        AssertIsOnMainThread()

        switch scrollAction.action {
        case .none:
            break
        case .scrollTo(let interactionId, let onScreenPercentage, let alignment):
            if let indexPath = self.indexPath(forInteractionUniqueId: interactionId) {
                // TODO: Set position and animated.
                scrollToInteraction(
                    indexPath: indexPath,
                    onScreenPercentage: onScreenPercentage,
                    alignment: alignment,
                    animated: scrollAction.isAnimated
                )
            } else {
                owsFailDebug("Could not locate interaction.")
            }
        case .bottomOfLoadWindow:
            scrollToBottomOfLoadWindow(animated: scrollAction.isAnimated)
        case .initialPosition:
            scrollToInitialPosition(animated: scrollAction.isAnimated)
        }
    }

    func scrollToTopOfLoadWindow(animated: Bool) {
        guard let interactionId = renderItems.first?.interactionUniqueId else {
            return
        }
        scrollToInteraction(uniqueId: interactionId, alignment: .top, animated: animated)
    }

    @objc
    func scrollToBottomOfLoadWindow(animated: Bool) {
        let newContentOffset = CGPoint(x: 0, y: maxContentOffsetY)
        collectionView.setContentOffset(newContentOffset, animated: animated)
    }

    @objc(scrollToInitialPositionAnimated:)
    func scrollToInitialPosition(animated: Bool) {

        guard loadCoordinator.hasRenderState else {
            // TODO: We should scroll to default position after first load completes.
            return
        }

        guard let initialScrollState = initialScrollState else {
            owsAssertDebug(hasViewDidAppearEverBegun)
            return
        }

        // TODO: Should we load any of these interactions before we scroll?
        if let focusMessageId = initialScrollState.focusMessageId {
            if focusMessageId == lastVisibleInteractionWithSneakyTransaction()?.uniqueId {
                scrollToLastVisibleInteraction(animated: animated)
                return
            } else if let indexPath = indexPath(forInteractionUniqueId: focusMessageId) {
                scrollToInteraction(
                    indexPath: indexPath,
                    alignment: .top,
                    animated: animated
                )
                return
            } else if hasRenderState {
                owsFailDebug("focusMessageId not in the load window.")
            }
        }

        if let indexPath = indexPathOfUnreadMessagesIndicator {
            scrollToInteraction(
                indexPath: indexPath,
                alignment: .top,
                animated: animated
            )
        } else {
            scrollToLastVisibleInteraction(animated: animated)
        }
    }

    // This method scrolls to the bottom of the _conversation_,
    // not the load window.
    @objc(scrollToBottomOfConversationAnimated:)
    func scrollToBottomOfConversation(animated: Bool) {
        if canLoadNewerItems {
            loadCoordinator.loadAndScrollToNewestItems(isAnimated: animated)
        } else {
            scrollToBottomOfLoadWindow(animated: animated)
        }
    }

    @objc(scrollToLastVisibleInteractionAnimated:)
    func scrollToLastVisibleInteraction(animated: Bool) {
        guard let lastVisibleInteraction = lastVisibleInteractionWithSneakyTransaction() else {
            return scrollToBottomOfConversation(animated: animated)
        }

        // IFF the lastVisibleInteraction is the last non-dynamic interaction in the thread,
        // we want to scroll to the bottom to also show any active typing indicators.
        if lastVisibleInteraction.sortId == lastSortIdInLoadedWindow,
           SSKEnvironment.shared.typingIndicators.typingAddress(forThread: thread) != nil {
            return scrollToBottomOfConversation(animated: animated)
        }

        guard let indexPath = indexPath(forInteractionUniqueId: lastVisibleInteraction.uniqueId) else {
            owsFailDebug("No index path for interaction, scrolling to bottom")
            scrollToBottomOfConversation(animated: animated)
            return
        }

        scrollToInteraction(
            indexPath: indexPath,
            onScreenPercentage: CGFloat(lastVisibleInteraction.onScreenPercentage),
            alignment: .bottom,
            animated: animated
        )
    }

    func scrollToInteraction(uniqueId: String,
                             onScreenPercentage: CGFloat = 1,
                             alignment: ScrollAlignment,
                             animated: Bool) {
        guard let indexPath = indexPath(forInteractionUniqueId: uniqueId) else {
            owsFailDebug("No index path for interaction, scrolling to bottom")
            return
        }
        scrollToInteraction(indexPath: indexPath,
                            onScreenPercentage: onScreenPercentage,
                            alignment: alignment,
                            animated: animated)
    }

    @objc
    func scrollToInteraction(indexPath: IndexPath,
                             onScreenPercentage: CGFloat = 1,
                             alignment: ScrollAlignment,
                             animated: Bool = true) {
        guard !isUserScrolling else { return }

        view.layoutIfNeeded()

        guard let attributes = layout.layoutAttributesForItem(at: indexPath) else {
            return owsFailDebug("failed to get attributes for indexPath \(indexPath)")
        }

        let topInset = collectionView.adjustedContentInset.top
        let bottomInset = collectionView.adjustedContentInset.bottom
        let collectionViewHeightUnobscuredByBottomBar = collectionView.height - bottomInset

        let topDestinationY = topInset
        let bottomDestinationY = safeContentHeight - collectionViewHeightUnobscuredByBottomBar

        let currentMinimumVisibleOffset = collectionView.contentOffset.y + topInset
        let currentMaximumVisibleOffset = collectionView.contentOffset.y + collectionViewHeightUnobscuredByBottomBar

        let rowIsEntirelyOnScreen = attributes.frame.minY > currentMinimumVisibleOffset
            && attributes.frame.maxY < currentMaximumVisibleOffset

        // If the collection view contents aren't scrollable, do nothing.
        guard safeContentHeight > collectionViewHeightUnobscuredByBottomBar else { return }

        // If the destination row is entirely visible AND the desired position
        // is only valid for when the view is not on screen, do nothing.
        guard !alignment.scrollsOnlyIfNotEntirelyOnScreen || !rowIsEntirelyOnScreen else { return }

        guard indexPath != lastIndexPathInLoadedWindow || !onScreenPercentage.isEqual(to: 1) else {
            // If we're scrolling to the last index AND we want it entirely on screen,
            // scroll directly to the bottom regardless of the requested destination.
            let contentOffset = CGPoint(x: 0, y: bottomDestinationY)
            collectionView.setContentOffset(contentOffset, animated: animated)
            updateLastKnownDistanceFromBottom()
            return
        }

        var destinationY: CGFloat

        switch alignment {
        case .top, .topIfNotEntirelyOnScreen:
            destinationY = attributes.frame.minY - topInset
            destinationY += attributes.frame.height * (1 - onScreenPercentage)
        case .bottom, .bottomIfNotEntirelyOnScreen:
            destinationY = attributes.frame.minY
            destinationY -= collectionViewHeightUnobscuredByBottomBar
            destinationY += attributes.frame.height * onScreenPercentage
        case .center, .centerIfNotEntirelyOnScreen:
            assert(onScreenPercentage.isEqual(to: 1))
            destinationY = attributes.frame.midY
            destinationY -= collectionView.height / 2
        }

        // If the target destination would cause us to scroll beyond
        // the top of the collection view, scroll to top
        if destinationY < topDestinationY { destinationY = topDestinationY }

        // If the target destination would cause us to scroll beyond
        // the bottom of the collection view, scroll to bottom
        else if destinationY > bottomDestinationY { destinationY = bottomDestinationY }

        let contentOffset = CGPoint(x: 0, y: destinationY)
        collectionView.setContentOffset(contentOffset, animated: animated)
        updateLastKnownDistanceFromBottom()
    }

    @objc
    func scrollToQuotedMessage(_ quotedReply: OWSQuotedReplyModel,
                               isAnimated: Bool) {
        if quotedReply.isRemotelySourced {
            return
        }
        let quotedMessage = databaseStorage.uiRead { transaction in
            InteractionFinder.findMessage(withTimestamp: quotedReply.timestamp,
                                          threadId: self.thread.uniqueId,
                                          author: quotedReply.authorAddress,
                                          transaction: transaction)
        }
        guard let message = quotedMessage else {
            return
        }
        guard !message.wasRemotelyDeleted else {
            return
        }
        ensureInteractionLoadedThenScrollToInteraction(message.uniqueId,
                                                       alignment: .centerIfNotEntirelyOnScreen,
                                                       isAnimated: isAnimated)
    }

    @objc
    func ensureInteractionLoadedThenScrollToInteraction(_ interactionId: String,
                                                        onScreenPercentage: CGFloat = 1,
                                                        alignment: ScrollAlignment,
                                                        isAnimated: Bool = true) {
        if let indexPath = self.indexPath(forInteractionUniqueId: interactionId) {
            self.scrollToInteraction(indexPath: indexPath,
                                     onScreenPercentage: onScreenPercentage,
                                     alignment: alignment,
                                     animated: isAnimated)
        } else {
            loadCoordinator.enqueueLoadAndScrollToInteraction(interactionId: interactionId,
                                                              onScreenPercentage: onScreenPercentage,
                                                              alignment: alignment,
                                                              isAnimated: isAnimated)
        }
    }

    @objc
    func setScrollActionForSizeTransition() {
        AssertIsOnMainThread()

        owsAssertDebug(viewState.scrollActionForSizeTransition == nil)

        viewState.scrollActionForSizeTransition = {
            if self.isScrolledToBottom {
                return CVScrollAction(action: .bottomOfLoadWindow, isAnimated: false)
            }
            guard let lastVisibleInteraction = lastVisibleInteractionWithSneakyTransaction() else {
                return CVScrollAction(action: .bottomOfLoadWindow, isAnimated: false)
            }
            // IFF the lastVisibleInteraction is the last non-dynamic interaction in the thread,
            // we want to scroll to the bottom to also show any active typing indicators.
            if lastVisibleInteraction.sortId == lastSortIdInLoadedWindow,
               SSKEnvironment.shared.typingIndicators.typingAddress(forThread: thread) != nil {
                return CVScrollAction(action: .bottomOfLoadWindow, isAnimated: false)
            }
            if let lastKnownDistanceFromBottom = self.lastKnownDistanceFromBottom,
               lastKnownDistanceFromBottom < 50 {
                return CVScrollAction(action: .bottomOfLoadWindow, isAnimated: false)
            }

            return CVScrollAction(action: .scrollTo(interactionId: lastVisibleInteraction.uniqueId,
                                                    onScreenPercentage: lastVisibleInteraction.onScreenPercentage,
                                                    alignment: .bottom),
                                  isAnimated: false)
        }()
    }

    @objc
    func clearScrollActionForSizeTransition() {
        AssertIsOnMainThread()

        owsAssertDebug(viewState.scrollActionForSizeTransition != nil)
        if let scrollAction = viewState.scrollActionForSizeTransition {
            owsAssertDebug(!scrollAction.isAnimated)
            perform(scrollAction: scrollAction)
        }
        viewState.scrollActionForSizeTransition = nil
    }

    @objc
    func scrollDownButtonTapped() {
        AssertIsOnMainThread()

        // TODO: I'm not sure this will do the right thing if there's an unread indicator
        // below current scroll position but outside the load window, e.g. if we entered
        // the conversation view a search result.
        if let indexPathOfUnreadMessagesIndicator = self.indexPathOfUnreadMessagesIndicator {
            let unreadRow = indexPathOfUnreadMessagesIndicator.row

            var isScrolledAboveUnreadIndicator = true
            let visibleIndices = collectionView.indexPathsForVisibleItems
            for indexPath in visibleIndices {
                if indexPath.row > unreadRow {
                    isScrolledAboveUnreadIndicator = false
                    break
                }
            }

            if isScrolledAboveUnreadIndicator {
                // Only scroll as far as the unread indicator if we're scrolled above the unread indicator.
                scrollToInteraction(indexPath: indexPathOfUnreadMessagesIndicator,
                                    onScreenPercentage: 1,
                                    alignment: .top,
                                    animated: true)
                return
            }
        }

        scrollToBottomOfConversation(animated: true)
    }

    @objc
    public func recordInitialScrollState(_ focusMessageId: String?) {
        initialScrollState = CVInitialScrollState(focusMessageId: focusMessageId)
    }

    @objc
    public func clearInitialScrollState() {
        initialScrollState = nil
    }

    @objc
    func scrollToNextMentionButtonTapped() {
        if let nextMessage = unreadMentionMessages?.first {
            ensureInteractionLoadedThenScrollToInteraction(nextMessage.uniqueId,
                                                           alignment: .bottomIfNotEntirelyOnScreen,
                                                           isAnimated: true)
        }
    }

    @objc
    func updateLastKnownDistanceFromBottom() {
        guard hasAppearedAndHasAppliedFirstLoad else {
            return
        }

        // Never update the lastKnownDistanceFromBottom,
        // if we're presenting the message actions which
        // temporarily meddles with the content insets.
        if !isPresentingMessageActions {
            self.lastKnownDistanceFromBottom = self.safeDistanceFromBottom
        }
    }

    // We use this hook to ensure scroll state continuity.  As the collection
    // view's content size changes, we want to keep the same cells in view.
    func contentOffset(forLastKnownDistanceFromBottom distanceFromBottom: CGFloat) -> CGPoint {
        // Adjust the content offset to reflect the "last known" distance
        // from the bottom of the content.
        let contentOffsetYBottom = maxContentOffsetY
        var contentOffsetY = contentOffsetYBottom - max(0, distanceFromBottom)
        let minContentOffsetY = -collectionView.safeAreaInsets.top
        contentOffsetY = max(minContentOffsetY, contentOffsetY)
        return CGPoint(x: 0, y: contentOffsetY)
    }

    @objc
    var isScrolledToBottom: Bool {
        isScrolledToBottom(tolerancePoints: 5)
    }

    func isScrolledToBottom(tolerancePoints: CGFloat) -> Bool {
        safeDistanceFromBottom <= tolerancePoints
    }

    func isScrolledToTop(tolerancePoints: CGFloat) -> Bool {
        safeDistanceFromTop <= tolerancePoints
    }

    @objc
    public var safeDistanceFromTop: CGFloat {
        collectionView.contentOffset.y - minContentOffsetY
    }

    @objc
    public var safeDistanceFromBottom: CGFloat {
        // This is a bit subtle.
        //
        // The _wrong_ way to determine if we're scrolled to the bottom is to
        // measure whether the collection view's content is "near" the bottom edge
        // of the collection view.  This is wrong because the collection view
        // might not have enough content to fill the collection view's bounds
        // _under certain conditions_ (e.g. with the keyboard dismissed).
        //
        // What we're really interested in is something a bit more subtle:
        // "Is the scroll view scrolled down as far as it can, "at rest".
        //
        // To determine that, we find the appropriate "content offset y" if
        // the scroll view were scrolled down as far as possible.  IFF the
        // actual "content offset y" is "near" that value, we return YES.
        maxContentOffsetY - collectionView.contentOffset.y
    }

    // The lowest valid content offset when the view is at rest.
    private var minContentOffsetY: CGFloat {
        -collectionView.adjustedContentInset.top
    }

    // The highest valid content offset when the view is at rest.
    private var maxContentOffsetY: CGFloat {
        let contentHeight = self.safeContentHeight
        let adjustedContentInset = collectionView.adjustedContentInset
        let rawValue = contentHeight + adjustedContentInset.bottom - collectionView.bounds.size.height
        // Note the usage of MAX() to handle the case where there isn't enough
        // content to fill the collection view at its current size.
        let clampedValue = max(minContentOffsetY, rawValue)
        return clampedValue
    }

    // We use this hook to ensure scroll state continuity.  As the collection
    // view's content size changes, we want to keep the same cells in view.
    @objc
    public func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {

        Logger.verbose("---- proposedContentOffset: \(proposedContentOffset)")

        if isPresentingMessageActions,
           let contentOffset = targetContentOffsetForMessageActionInteraction {
            Logger.verbose("---- targetContentOffsetForMessageActionInteraction: \(contentOffset)")
            return contentOffset
        }

        if let contentOffset = targetContentOffsetForSizeTransition() {
            Logger.verbose("---- targetContentOffsetForSizeTransition: \(contentOffset)")
            return contentOffset
        }

        if let contentOffset = targetContentOffsetForUpdate() {
            Logger.verbose("---- targetContentOffsetForUpdate: \(contentOffset)")
            return contentOffset
        }

        if let contentOffset = targetContentOffsetForScrollContinuityMap() {
            Logger.verbose("---- targetContentOffsetForScrollContinuityMap: \(contentOffset)")
            return contentOffset
        }

        if scrollContinuity == .bottom,
           let contentOffset = targetContentOffsetForBottom() {
            Logger.verbose("---- forLastKnownDistanceFromBottom: \(contentOffset)")
            return contentOffset
        }

        Logger.verbose("---- ...: \(proposedContentOffset)")
        return proposedContentOffset
    }

    private func targetContentOffsetForBottom() -> CGPoint? {
        guard let lastKnownDistanceFromBottom = self.lastKnownDistanceFromBottom else {
            return nil
        }

        let contentOffset = self.contentOffset(forLastKnownDistanceFromBottom: lastKnownDistanceFromBottom)
        return contentOffset
    }

    func buildScrollContinuityMap(forRenderState renderState: CVRenderState) -> CVScrollContinuityMap {
        AssertIsOnMainThread()

        // We don't need to worry about scroll continuity when landing
        // the first load or if we're not yet displaying the collection
        // view content.
        if renderState.isFirstLoad || loadCoordinator.shouldHideCollectionViewContent {
            return CVScrollContinuityMap(renderStateId: renderState.renderStateId,
                                         items: [])
        }

        let contentOffset = collectionView.contentOffset

        var sortIdToIndexPathMap = [UInt64: IndexPath]()
        for (index, renderItem) in renderItems.enumerated() {
            let indexPath = IndexPath(row: index, section: Self.messageSection)
            let sortId = renderItem.interaction.sortId
            sortIdToIndexPathMap[sortId] = indexPath
        }

        var items = [CVScrollContinuityMap.Item]()
        for cell in collectionView.visibleCells {
            guard let cell = cell as? CVCell else {
                owsFailDebug("Invalid cell.")
                continue
            }
            guard let renderItem = cell.renderItem else {
                owsFailDebug("Missing renderItem.")
                continue
            }
            guard canInteractionBeUsedForScrollContinuity(renderItem.interaction) else {
                continue
            }
            let sortId = renderItem.interaction.sortId
            guard let indexPath = sortIdToIndexPathMap[sortId] else {
                owsFailDebug("Missing indexPath.")
                continue
            }
            guard let layoutAttributes = layout.layoutAttributesForItem(at: indexPath) else {
                owsFailDebug("Missing layoutAttributes.")
                continue
            }
            let distanceY = layoutAttributes.frame.topLeft.y - contentOffset.y

            items.append(CVScrollContinuityMap.Item(sortId: sortId,
                                                    distanceY: distanceY))
        }
        return CVScrollContinuityMap(renderStateId: renderState.renderStateId,
                                     items: items)
    }

    private func canInteractionBeUsedForScrollContinuity(_ interaction: TSInteraction) -> Bool {
        guard !interaction.isDynamicInteraction() else {
            return false
        }

        switch interaction.interactionType() {
        case .unknown, .unreadIndicator, .dateHeader, .typingIndicator:
            return false
        case .incomingMessage, .outgoingMessage, .error, .call, .info, .threadDetails:
            return true
        }
    }

    // We use this hook to ensure scroll state continuity.  As the collection
    // view's content size changes, we want to keep the same cells in view.
    private func targetContentOffsetForScrollContinuityMap() -> CGPoint? {
        guard let scrollContinuityMap = viewState.scrollContinuityMap else {
            return nil
        }

        var sortIdToIndexPathMap = [UInt64: IndexPath]()
        for (index, renderItem) in renderItems.enumerated() {
            let indexPath = IndexPath(row: index, section: Self.messageSection)
            let sortId = renderItem.interaction.sortId
            sortIdToIndexPathMap[sortId] = indexPath
        }

        // Honor the scroll continuity bias.
        //
        // If we prefer continuity with regard to the bottom
        // of the conversation, start with the last items.
        let items = (scrollContinuity == .bottom
                        ? scrollContinuityMap.items.reversed()
                        : scrollContinuityMap.items)

        for item in items {
            let sortId = item.sortId
            let oldDistanceY = item.distanceY

            guard let indexPath = sortIdToIndexPathMap[sortId] else {
                continue
            }
            guard let latestFrame = layout.latestFrame(forIndexPath: indexPath) else {
                owsFailDebug("Missing layoutAttributes.")
                continue
            }

            let newLocation = latestFrame.topLeft
            let contentOffsetY = newLocation.y - oldDistanceY
            let contentOffset = CGPoint(x: 0, y: contentOffsetY)
            return contentOffset
        }

        Logger.verbose("No continuity match.")

        return nil
    }

    private func targetContentOffsetForSizeTransition() -> CGPoint? {
        guard let scrollAction = viewState.scrollActionForSizeTransition else {
            return nil
        }
        owsAssertDebug(!scrollAction.isAnimated)
        return targetContentOffsetForScrollAction(scrollAction)
    }

    private func targetContentOffsetForUpdate() -> CGPoint? {
        guard let scrollAction = viewState.scrollActionForUpdate else {
            return nil
        }
        guard scrollAction.action != .none, !scrollAction.isAnimated else {
            return nil
        }
        return targetContentOffsetForScrollAction(scrollAction)
    }

    private func targetContentOffsetForScrollAction(_ scrollAction: CVScrollAction) -> CGPoint? {
        owsAssertDebug(!scrollAction.isAnimated)

        switch scrollAction.action {
        case .bottomOfLoadWindow:
            let minContentOffsetY = -collectionView.safeAreaInsets.top
            var contentOffset = self.contentOffset(forLastKnownDistanceFromBottom: 0)
            contentOffset.y = max(minContentOffsetY, contentOffset.y)
            return contentOffset
        case .scrollTo(let referenceUniqueId, let onScreenPercentage, _):

            // Start with a content offset for being scrolled to the bottom.
            var contentOffset = self.contentOffset(forLastKnownDistanceFromBottom: 0)

            guard let referenceIndexPath = indexPath(forInteractionUniqueId: referenceUniqueId) else {
                owsFailDebug("Missing referenceIndexPath.")
                return nil
            }
            guard let referenceLayoutAttributes = layout.layoutAttributesForItem(at: referenceIndexPath) else {
                owsFailDebug("Missing layoutAttributes.")
                return nil
            }

            // Adjust content offset to reflect onScreenPercentage.
            let onScreenAlpha = (1 - onScreenPercentage).clamp01()
            contentOffset.y -= referenceLayoutAttributes.frame.height * onScreenAlpha

            if let lastIndexPath = allIndexPaths.last,
               let lastLayoutAttributes = layout.layoutAttributesForItem(at: lastIndexPath) {
                // Only offset if the reference interaction is not last.
                if lastIndexPath != referenceIndexPath {
                    owsAssertDebug(lastLayoutAttributes.frame.maxY > referenceLayoutAttributes.frame.maxY)
                    let distanceToLastInteraction = (lastLayoutAttributes.frame.maxY -
                                                        referenceLayoutAttributes.frame.maxY)
                    contentOffset.y -= distanceToLastInteraction
                }
            } else {
                owsFailDebug("Missing lastIndexPath.")
            }

            let minContentOffsetY = -collectionView.safeAreaInsets.top
            contentOffset.y = max(minContentOffsetY, contentOffset.y)

            return contentOffset
        default:
            owsFailDebug("Invalid scroll action: \(scrollAction.description)")
            return nil
        }
    }

    private var targetContentOffsetForMessageActionInteraction: CGPoint? {
        guard isPresentingMessageActions,
              let messageActionsViewController = messageActionsViewController else {
            owsFailDebug("Not presenting message actions.")
            return nil
        }

        let messageActionInteractionId = messageActionsViewController.focusedInteraction.uniqueId

        guard let indexPath = indexPath(forInteractionUniqueId: messageActionInteractionId) else {
            // This is expected if the menu action interaction is being deleted.
            return nil
        }
        guard let layoutAttributes = layout.layoutAttributesForItem(at: indexPath) else {
            owsFailDebug("Missing layoutAttributes.")
            return nil
        }
        let cellFrame = layoutAttributes.frame
        return CGPoint(x: 0, y: cellFrame.origin.y - messageActionsOriginalFocusY)
    }

// MARK: -

    private struct LastVisibleInteraction {
        public let interaction: TSInteraction
        public let onScreenPercentage: CGFloat

        public var sortId: UInt64 { interaction.sortId }
        public var uniqueId: String { interaction.uniqueId }
    }

    @objc
    public func lastVisibleInteractionIdWithSneakyTransaction(_ threadViewModel: ThreadViewModel) -> String? {
        lastVisibleInteractionWithSneakyTransaction(thread: threadViewModel.threadRecord)?.uniqueId
    }

    private func lastVisibleInteractionWithSneakyTransaction() -> LastVisibleInteraction? {
        lastVisibleInteractionWithSneakyTransaction(thread: thread)
    }

    private func lastVisibleInteractionWithSneakyTransaction(thread: TSThread) -> LastVisibleInteraction? {
        databaseStorage.read { transaction in
            guard let lastVisibleInteraction = thread.lastVisibleInteraction(transaction: transaction),
               let interaction = thread.firstInteraction(atOrAroundSortId: lastVisibleInteraction.sortId,
                                                         transaction: transaction) else {

                return nil
            }

            let onScreenPercentage = lastVisibleInteraction.onScreenPercentage

            return LastVisibleInteraction(interaction: interaction,
                                          onScreenPercentage: onScreenPercentage)
        }
    }
}
