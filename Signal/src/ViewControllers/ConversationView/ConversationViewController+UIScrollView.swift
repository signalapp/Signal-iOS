//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

extension ConversationViewController {

    fileprivate var scrollDownButton: ConversationScrollButton { viewState.scrollDownButton }
    fileprivate var scrollToNextMentionButton: ConversationScrollButton { viewState.scrollToNextMentionButton }
    fileprivate var isHidingScrollDownButton: Bool {
        get { viewState.isHidingScrollDownButton }
        set { viewState.isHidingScrollDownButton = newValue }
    }
    fileprivate var isHidingScrollToNextMentionButton: Bool {
        get { viewState.isHidingScrollToNextMentionButton }
        set { viewState.isHidingScrollToNextMentionButton = newValue }
    }
    public var scrollUpdateTimer: Timer? {
        get { viewState.scrollUpdateTimer }
        set { viewState.scrollUpdateTimer = newValue }
    }
    public var isWaitingForDeceleration: Bool {
        get { viewState.isWaitingForDeceleration }
        set { viewState.isWaitingForDeceleration = newValue }
    }
    public var userHasScrolled: Bool {
        get { viewState.userHasScrolled }
        set {
            guard viewState.userHasScrolled != newValue else {
                return
            }
            viewState.userHasScrolled = newValue
            ensureBannerState()
        }
    }

    // MARK: -

    public func configureScrollDownButtons() {
        AssertIsOnMainThread()

        guard hasAppearedAndHasAppliedFirstLoad else {
            scrollDownButton.isHidden = true
            scrollToNextMentionButton.isHidden = true
            return
        }

        let scrollSpaceToBottom = (safeContentHeight + collectionView.contentInset.bottom
                                    - (collectionView.contentOffset.y + collectionView.frame.height))
        let pageHeight = (collectionView.frame.height
                            - (collectionView.contentInset.top + collectionView.contentInset.bottom))
        let isScrolledUpOnePage = scrollSpaceToBottom > pageHeight * 1.0

        let hasLaterMessageOffscreen = (lastSortIdInLoadedWindow > lastVisibleSortId) || canLoadNewerItems

        let scrollDownWasHidden = isHidingScrollDownButton || scrollDownButton.isHidden
        var scrollDownIsHidden = scrollDownWasHidden

        let scrollToNextMentionWasHidden = isHidingScrollToNextMentionButton || scrollToNextMentionButton.isHidden
        var scrollToNextMentionIsHidden = scrollToNextMentionWasHidden

        if viewState.inProgressVoiceMessage?.isRecording == true {
            scrollDownIsHidden = true
            scrollToNextMentionIsHidden = true
        } else if isInPreviewPlatter {
            scrollDownIsHidden = true
            scrollToNextMentionIsHidden = true
        } else {
            let shouldScrollDownAppear = isScrolledUpOnePage || hasLaterMessageOffscreen
            scrollDownIsHidden = !shouldScrollDownAppear

            let shouldScrollToMentionAppear = shouldScrollDownAppear && unreadMentionMessages.count > 0
            scrollToNextMentionIsHidden = !shouldScrollToMentionAppear
        }

        self.scrollDownButton.unreadCount = threadViewModel.unreadCount
        self.scrollToNextMentionButton.unreadCount = UInt(self.unreadMentionMessages.count)

        let scrollDownVisibilityDidChange = scrollDownIsHidden != scrollDownWasHidden
        let scrollToNextMentionVisibilityDidChange = scrollToNextMentionIsHidden != scrollToNextMentionWasHidden
        let shouldAnimateChanges = self.hasAppearedAndHasAppliedFirstLoad

        guard scrollDownVisibilityDidChange || scrollToNextMentionVisibilityDidChange else {
            return
        }

        if scrollDownVisibilityDidChange {
            self.scrollDownButton.isHidden = false
            self.isHidingScrollDownButton = scrollDownIsHidden
            scrollDownButton.layer.removeAllAnimations()
        }
        if scrollToNextMentionVisibilityDidChange {
            self.scrollToNextMentionButton.isHidden = false
            self.isHidingScrollToNextMentionButton = scrollToNextMentionIsHidden
            scrollToNextMentionButton.layer.removeAllAnimations()
        }

        let alphaBlock = {
            if scrollDownVisibilityDidChange {
                self.scrollDownButton.alpha = scrollDownIsHidden ? 0 : 1
            }
            if scrollToNextMentionVisibilityDidChange {
                self.scrollToNextMentionButton.alpha = scrollToNextMentionIsHidden ? 0 : 1
            }
        }
        let completionBlock = {
            if scrollDownVisibilityDidChange {
                self.scrollDownButton.isHidden = scrollDownIsHidden
                self.isHidingScrollDownButton = false
            }
            if scrollToNextMentionVisibilityDidChange {
                self.scrollToNextMentionButton.isHidden = scrollToNextMentionIsHidden
                self.isHidingScrollToNextMentionButton = false
            }
        }

        scrollDownButton.layer.removeAllAnimations()
        scrollToNextMentionButton.layer.removeAllAnimations()

        if shouldAnimateChanges {
            UIView.animate(withDuration: 0.2,
                           animations: alphaBlock) { finished in
                if finished {
                    completionBlock()
                }
            }
        } else {
            alphaBlock()
            completionBlock()
        }
    }
}

// MARK: -

extension ConversationViewController: UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        AssertIsOnMainThread()

        // Constantly try to update the lastKnownDistanceFromBottom.
        updateLastKnownDistanceFromBottom()

        configureScrollDownButtons()

        scheduleScrollUpdateTimer()

        updateScrollingContent()

        updateContextMenuInteractionIfNeeded()
    }

    private func scheduleScrollUpdateTimer() {
        AssertIsOnMainThread()

        guard self.scrollUpdateTimer == nil else {
            return
        }

        Logger.verbose("")

        // We need to manually schedule this timer using NSRunLoopCommonModes
        // or it won't fire during scrolling.
        let scrollUpdateTimer = Timer.weakTimer(
            withTimeInterval: 0.1,
            target: self,
            selector: #selector(scrollUpdateTimerDidFire),
            userInfo: nil,
            repeats: false
        )
        self.scrollUpdateTimer = scrollUpdateTimer
        RunLoop.main.add(scrollUpdateTimer, forMode: .common)
    }

    private func updateContextMenuInteractionIfNeeded() {
        if let contextMenuInteraction = collectionViewActiveContextMenuInteraction {
            contextMenuInteraction.cancelPresentationGesture()
        }
    }

    @objc
    private func scrollUpdateTimerDidFire() {
        AssertIsOnMainThread()

        scrollUpdateTimer?.invalidate()
        scrollUpdateTimer = nil

        guard viewHasEverAppeared else {
            return
        }

        _ = autoLoadMoreIfNecessary()

        if !isUserScrolling, !isWaitingForDeceleration {
            saveLastVisibleSortIdAndOnScreenPercentage()
        }
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        AssertIsOnMainThread()

        self.userHasScrolled = true
        self.isUserScrolling = true
        scrollingAnimationDidStart()
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate: Bool) {
        AssertIsOnMainThread()

        if !willDecelerate {
            scrollingAnimationDidComplete()
        }

        if !isUserScrolling {
            return
        }

        self.isUserScrolling = false

        if willDecelerate {
            self.isWaitingForDeceleration = willDecelerate
        } else {
            scheduleScrollUpdateTimer()
        }
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        AssertIsOnMainThread()

        scrollingAnimationDidComplete()

        if !isWaitingForDeceleration {
            return
        }

        self.isWaitingForDeceleration = false

        scheduleScrollUpdateTimer()
    }

    public func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        AssertIsOnMainThread()

        // If the user taps on the status bar, the UIScrollView tries to perform
        // a "scroll to top" animation that swings _past_ the top of the scroll
        // view content, then bounces back to settle at zero.  This is likely
        // to trigger a "load older" load which can land before the animation
        // settles.  If so, the animation will overwrite the contentOffset,
        // breaking scroll continuity and probably triggering another "load older"
        // load.  So there's also a risk of a load loop.
        //
        // To avoid this, we use a simple animation to "scroll to top" unless
        // we know its safe to use the default animation, e.g. when there's no
        // older content to load.
        if canLoadOlderItems {
            let newContentOffset = CGPoint(x: 0, y: 0)
            collectionView.setContentOffset(newContentOffset, animated: true)
            return false
        } else {
            scrollingAnimationDidStart()

            return true
        }
    }

    public func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
        AssertIsOnMainThread()

        scrollingAnimationDidComplete()
    }

    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        AssertIsOnMainThread()

        scrollingAnimationDidComplete()
    }
}

// MARK: - Scroll Down Button

extension ConversationViewController {
    public func createConversationScrollButtons() {
        AssertIsOnMainThread()

        scrollDownButton.addTarget(self, action: #selector(scrollDownButtonTapped), for: .touchUpInside)
        scrollDownButton.isHidden = true
        scrollDownButton.alpha = 0
        view.addSubview(scrollDownButton)
        scrollDownButton.autoSetDimension(.width, toSize: ConversationScrollButton.buttonSize)
        scrollDownButton.accessibilityIdentifier = "scrollDownButton"

        scrollDownButton.autoPinEdge(.bottom, to: .top, of: bottomBar, withOffset: -16)
        scrollDownButton.autoPinEdge(toSuperviewSafeArea: .trailing)

        scrollToNextMentionButton.addTarget(self, action: #selector(scrollToNextMentionButtonTapped), for: .touchUpInside)
        scrollToNextMentionButton.isHidden = true
        scrollToNextMentionButton.alpha = 0
        view.addSubview(scrollToNextMentionButton)
        scrollToNextMentionButton.autoSetDimension(.width, toSize: ConversationScrollButton.buttonSize)
        scrollToNextMentionButton.accessibilityIdentifier = "scrollToNextMentionButton"

        scrollToNextMentionButton.autoPinEdge(.bottom, to: .top, of: scrollDownButton, withOffset: -10)
        scrollToNextMentionButton.autoPinEdge(toSuperviewSafeArea: .trailing)
    }
}
