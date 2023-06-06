//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalUI

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
        case bottomForNewMessage

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
            case .bottomForNewMessage:
                return "bottomForNewMessage"
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
        case .bottomOfLoadWindow, .bottomForNewMessage:
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

    func scrollToBottomOfLoadWindow(animated: Bool) {
        let newContentOffset = CGPoint(x: 0, y: maxContentOffsetY)
        collectionView.setContentOffset(newContentOffset, animated: animated)
    }

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
    func scrollToBottomOfConversation(animated: Bool) {
        if canLoadNewerItems {
            loadCoordinator.loadAndScrollToNewestItems(isAnimated: animated)
        } else {
            scrollToBottomOfLoadWindow(animated: animated)
        }
    }

    func scrollToLastVisibleInteraction(animated: Bool) {
        guard let lastVisibleInteraction = lastVisibleInteractionWithSneakyTransaction() else {
            return scrollToBottomOfConversation(animated: animated)
        }

        // IFF the lastVisibleInteraction is the last non-dynamic interaction in the thread,
        // we want to scroll to the bottom to also show any active typing indicators.
        if lastVisibleInteraction.sortId == lastSortIdInLoadedWindow,
           typingIndicatorsImpl.typingAddress(forThread: thread) != nil {
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

    func scrollToQuotedMessage(_ quotedReply: QuotedReplyModel, isAnimated: Bool) {
        if quotedReply.isRemotelySourced {
            presentRemotelySourcedQuotedReplyToast()
            return
        }
        let quotedMessage = databaseStorage.read { transaction in
            InteractionFinder.findMessage(withTimestamp: quotedReply.timestamp,
                                          threadId: self.thread.uniqueId,
                                          author: quotedReply.authorAddress,
                                          transaction: transaction)
        }
        if let quotedMessage {
            if quotedMessage.wasRemotelyDeleted {
                presentMissingQuotedReplyToast()
                return
            }

            let targetUniqueId: String
            switch quotedMessage.editState {
            case .latestRevision, .none:
                targetUniqueId = quotedMessage.uniqueId
            case .pastRevision:
                // If this is an older edit revision, find the current
                // edit and use that uniqueId instead of the old one.
                let currentEdit = databaseStorage.read { transaction in
                    EditMessageFinder.findMessage(
                        fromEdit: quotedMessage,
                        transaction: transaction
                    )
                }
                if let currentEdit {
                    targetUniqueId = currentEdit.uniqueId
                } else {
                    owsFailDebug("Couldn't find original edit")
                    return
                }
            }

            ensureInteractionLoadedThenScrollToInteraction(
                targetUniqueId,
                alignment: .centerIfNotEntirelyOnScreen,
                isAnimated: isAnimated
            )
        }
    }

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
               typingIndicatorsImpl.typingAddress(forThread: thread) != nil {
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

    public func recordInitialScrollState(_ focusMessageId: String?) {
        initialScrollState = CVInitialScrollState(focusMessageId: focusMessageId)
    }

    public func clearInitialScrollState() {
        initialScrollState = nil
    }

    @objc
    func scrollToNextMentionButtonTapped() {
        if let nextMessageId = conversationViewModel.unreadMentionMessageIds.first {
            ensureInteractionLoadedThenScrollToInteraction(
                nextMessageId,
                alignment: .bottomIfNotEntirelyOnScreen,
                isAnimated: true
            )
        }
    }

    @discardableResult
    func updateLastKnownDistanceFromBottom() -> CGFloat? {
        guard hasAppearedAndHasAppliedFirstLoad else {
            return nil
        }

        let lastKnownDistanceFromBottom = self.safeDistanceFromBottom
        self.lastKnownDistanceFromBottom = lastKnownDistanceFromBottom
        return lastKnownDistanceFromBottom
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

    var isScrolledToBottom: Bool {
        isScrolledToBottom(tolerancePoints: 5)
    }

    func isScrolledToBottom(tolerancePoints: CGFloat) -> Bool {
        safeDistanceFromBottom <= tolerancePoints
    }

    func isScrolledToTop(tolerancePoints: CGFloat) -> Bool {
        safeDistanceFromTop <= tolerancePoints
    }

    public var safeDistanceFromTop: CGFloat {
        collectionView.contentOffset.y - minContentOffsetY
    }

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
    internal var maxContentOffsetY: CGFloat {
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
    public func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint,
                                    lastKnownDistanceFromBottom: CGFloat?) -> CGPoint {

        // TODO: Remove logging in this method once scroll continuity
        // issues are resolved.
        if !DebugFlags.reduceLogChatter {
            Logger.verbose("---- proposedContentOffset: \(proposedContentOffset)")
        }

        // TODO: Consider handling these transitions using a scroll
        // continuity token.
        if let contentOffset = targetContentOffsetForSizeTransition() {
            if !DebugFlags.reduceLogChatter {
                Logger.verbose("---- targetContentOffsetForSizeTransition: \(contentOffset)")
            }
            return contentOffset
        }

        // TODO: Consider handling these transitions using a scroll
        // continuity token.
        if let contentOffset = targetContentOffsetForUpdate() {
            if !DebugFlags.reduceLogChatter {
                Logger.verbose("---- targetContentOffsetForUpdate: \(contentOffset)")
            }
            return contentOffset
        }

        // TODO: Can we improve this case?
        if let contentOffset = targetContentOffsetForBottom(lastKnownDistanceFromBottom: lastKnownDistanceFromBottom) {
            if !DebugFlags.reduceLogChatter {
                Logger.verbose("---- forLastKnownDistanceFromBottom: \(contentOffset)")
            }
            return contentOffset
        }

        if !DebugFlags.reduceLogChatter {
            Logger.verbose("---- ...: \(proposedContentOffset)")
        }
        return proposedContentOffset
    }

    var shouldUseDelegateScrollContinuity: Bool {
        if let scrollAction = viewState.scrollActionForSizeTransition,
           scrollAction != .none {
            return true
        }
        if let scrollAction = viewState.scrollActionForUpdate {
            switch scrollAction.action {
            case .bottomOfLoadWindow, .scrollTo:
                if !scrollAction.isAnimated {
                    return true
                }
            case .bottomForNewMessage:
                return true
            default:
                break
            }
        }
        return false
    }

    private func targetContentOffsetForBottom(lastKnownDistanceFromBottom: CGFloat?) -> CGPoint? {
        guard let lastKnownDistanceFromBottom = self.lastKnownDistanceFromBottom else {
            return nil
        }

        let contentOffset = self.contentOffset(forLastKnownDistanceFromBottom: lastKnownDistanceFromBottom)
        return contentOffset
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
        case .bottomOfLoadWindow, .bottomForNewMessage:
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

    // MARK: -

    private struct LastVisibleInteraction {
        public let interaction: TSInteraction
        public let onScreenPercentage: CGFloat

        public var sortId: UInt64 { interaction.sortId }
        public var uniqueId: String { interaction.uniqueId }
    }

    public static func lastVisibleInteractionId(for thread: TSThread, tx: SDSAnyReadTransaction) -> String? {
        return lastVisibleInteraction(for: thread, tx: tx)?.uniqueId
    }

    private func lastVisibleInteractionWithSneakyTransaction() -> LastVisibleInteraction? {
        return databaseStorage.read { tx in Self.lastVisibleInteraction(for: thread, tx: tx) }
    }

    private static func lastVisibleInteraction(for thread: TSThread, tx: SDSAnyReadTransaction) -> LastVisibleInteraction? {
        guard
            let lastVisibleInteraction = thread.lastVisibleInteraction(transaction: tx),
            let interaction = thread.firstInteraction(atOrAroundSortId: lastVisibleInteraction.sortId, transaction: tx)
        else {
            return nil
        }
        let onScreenPercentage = lastVisibleInteraction.onScreenPercentage
        return LastVisibleInteraction(interaction: interaction, onScreenPercentage: onScreenPercentage)
    }
}
