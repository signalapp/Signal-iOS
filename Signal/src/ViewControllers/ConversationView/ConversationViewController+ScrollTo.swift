//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

extension ConversationViewController {
    @objc
    var indexPathOfUnreadMessagesIndicator: IndexPath? {
        guard let unreadIndicatorIndex = conversationViewModel.viewState.unreadIndicatorIndex else { return nil }
        return IndexPath(row: unreadIndicatorIndex.intValue, section: 0)
    }

    @objc
    var indexPathOfFocusMessage: IndexPath? {
        guard let focusItemIndex = conversationViewModel.viewState.focusItemIndex else { return nil }
        return IndexPath(row: focusItemIndex.intValue, section: 0)
    }

    @objc(scrollToDefaultPositionAnimated:)
    func scrollToDefaultPosition(animated: Bool) {
        if let focusMessageIdOnOpen = conversationViewModel.focusMessageIdOnOpen,
            focusMessageIdOnOpen == threadViewModel.lastVisibleInteraction?.uniqueId {
            scrollToLastVisibleInteraction(animated: animated)
        } else if let indexPathOfFocusMessage = indexPathOfFocusMessage {
            scrollToInteraction(
                indexPath: indexPathOfFocusMessage,
                position: .top,
                animated: animated
            )
        } else if let indexPathOfUnreadMessagesIndicator = indexPathOfUnreadMessagesIndicator {
            scrollToInteraction(
                indexPath: indexPathOfUnreadMessagesIndicator,
                position: .top,
                animated: animated
            )
        } else {
            scrollToLastVisibleInteraction(animated: animated)
        }
    }

    @objc(scrollToBottomAnimated:)
    func scrollToBottom(animated: Bool) {
        if conversationViewModel.canLoadNewerItems() {
            databaseStorage.uiRead { transaction in
                self.conversationViewModel.ensureLoadWindowContainsNewestItems(with: transaction)
            }
        }

        guard let lastIndexPath = self.lastIndexPathInLoadedWindow else { return }
        scrollToInteraction(indexPath: lastIndexPath, position: .bottom, animated: animated)
    }

    @objc(scrollToLastVisibleInteractionAnimated:)
    func scrollToLastVisibleInteraction(animated: Bool) {
        guard let lastVisibleInteraction = threadViewModel.lastVisibleInteraction else {
            return scrollToBottom(animated: animated)
        }

        // IFF the lastVisibleInteraction is the last non-dynamic interaction in the thread,
        // we want to scroll to the bottom to also show any active typing indicators.
        if lastVisibleInteraction.sortId == lastSortIdInLoadedWindow,
            SSKEnvironment.shared.typingIndicators.typingAddress(forThread: thread) != nil {
            return scrollToBottom(animated: animated)
        }

        scrollToInteraction(
            uniqueId: lastVisibleInteraction.uniqueId,
            onScreenPercentage: CGFloat(thread.lastVisibleSortIdOnScreenPercentage),
            position: .bottom,
            animated: animated
        )
    }

    @objc
    func scrollToInteraction(
        uniqueId: String,
        onScreenPercentage: CGFloat = 1,
        position: ScrollTo,
        animated: Bool
    ) {
        guard let indexPath = databaseStorage.uiRead(block: { transaction in
            self.conversationViewModel.ensureLoadWindowContainsInteractionId(uniqueId, transaction: transaction)
        }) else {
            owsFailDebug("No index path for interaction, scrolling to bottom")
            scrollToBottom(animated: animated)
            return
        }

        scrollToInteraction(
            indexPath: indexPath,
            onScreenPercentage: onScreenPercentage,
            position: position,
            animated: animated
        )
    }

    @objc
    func scrollToInteraction(
        indexPath: IndexPath,
        onScreenPercentage: CGFloat = 1,
        position: ScrollTo = .bottom,
        animated: Bool = true
    ) {
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
        guard !position.scrollsOnlyIfNotEntirelyOnScreen || !rowIsEntirelyOnScreen else { return }

        guard indexPath != lastIndexPathInLoadedWindow || !onScreenPercentage.isEqual(to: 1) else {
            // If we're scrolling to the last index AND we want it entirely on screen,
            // scroll directly to the bottom regardless of the requested destination.
            return collectionView.setContentOffset(CGPoint(x: 0, y: bottomDestinationY), animated: animated)
        }

        var destinationY: CGFloat

        switch position {
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

        collectionView.setContentOffset(CGPoint(x: 0, y: destinationY), animated: animated)
    }

    @objc
    enum ScrollTo: Int {
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
}
