//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

protocol ChatListFilterControlDelegate: AnyObject {
    func filterControlDidStartFiltering()
}

final class ChatListFilterControl: UIView, UIScrollViewDelegate {
    private struct AnimationFrame: CaseIterable {
        static let allCases = [
            AnimationFrame(step: 0, relativeStartTime: 0, relativeDuration: 0, isFiltering: false),
            AnimationFrame(step: 1, relativeStartTime: 0.36, relativeDuration: 0.2, isFiltering: false),
            AnimationFrame(step: 2, relativeStartTime: 0.56, relativeDuration: 0.2, isFiltering: false),
            AnimationFrame(step: 3, relativeStartTime: 0.76, relativeDuration: 0.2, isFiltering: false),
            AnimationFrame(step: 3, relativeStartTime: 0.99, relativeDuration: 0, isFiltering: true),
        ]

        var step: Int
        var relativeStartTime: Double
        var relativeDuration: Double
        var isFiltering: Bool

        var image: UIImage {
            let resource = ImageResource(name: "filter.increment.\(step)", bundle: .main)

            let configuration: UIImage.SymbolConfiguration =
                switch (step, isFiltering) {
                case (0, false): .filterIconBackground
                case (_, false): .filterIconIncrementing
                case (_, true): .filterIconFiltering
                }

            return UIImage(resource: resource)
                .withAlignmentRectInsets(.zero)
                .withConfiguration(configuration)
        }

        func configure(_ imageView: UIView) {
            imageView.alpha = 0
        }

        func animate(_ imageView: UIImageView) {
            imageView.alpha = 1
        }
    }

    private enum State: Comparable {
        /// Control is not visible, filtering is disabled.
        case inactive

        /// Control is appearing, tracking scroll position.
        case tracking

        /// Control enters this state while interactively dragging the scroll
        /// view, indicating that filtering will begin when the user lifts
        /// their finger and dragging ends. Can't return to `tracking` after
        /// entering this state.
        case willStartFiltering

        /// `isFiltering == true` where `state >= .filterPending`. Started
        /// filtering (i.e., called `delegate.filterControlDidStartFiltering()`),
        /// but haven't finished animating into the "docked" position.
        case filterPending

        /// Actively filtering and control is docked to the top of the scroll view.
        case filtering
    }

    private let clearButton: ChatListFilterButton
    private let clippingView: UIView
    private let contentView: UIView
    private let imageContainer: UIView
    private let imageViews: [UIImageView]
    private let animationFrames: [AnimationFrame]
    private var feedback: UIImpactFeedbackGenerator?
    private var filterIconAnimator: UIViewPropertyAnimator?

    weak var delegate: (any ChatListFilterControlDelegate)?

    private var adjustedContentOffset: CGPoint = .zero {
        didSet {
            if adjustedContentOffset != oldValue {
                let position = max(0, -adjustedContentOffset.y)
                let limit = contentHeight * 2
                fractionComplete = min(1, position / limit)
                setNeedsLayout()
            }
        }
    }

    private var animationDuration: CGFloat {
        UIView.inheritedAnimationDuration == 0 ? CATransaction.animationDuration() : UIView.inheritedAnimationDuration
    }

    private var contentHeight: CGFloat {
        get { frame.size.height }
        set { frame.size.height = newValue }
    }

    private var fractionComplete: CGFloat = 0.0

    // When set to `true`, disables all layout for the duration of an animated
    // transition. This is automatically set by the `animateScrollViewTransition(_:completion:)`
    // helper method.
    private var isTransitioning = false {
        didSet {
            if !isTransitioning && oldValue {
                setNeedsLayout()
            }
        }
    }

    private var scrollView: UIScrollView? {
        superview as? UIScrollView
    }

    private var state = State.inactive {
        didSet {
            if state != oldValue {
                setNeedsLayout()
            }
        }
    }

    /// An action to perform when the clear button is triggered while in the filtering state.
    var clearAction: UIAction? {
        didSet {
            if let oldValue {
                clearButton.removeAction(oldValue, for: .primaryActionTriggered)
            }
            if let clearAction {
                clearButton.addAction(clearAction, for: .primaryActionTriggered)
            }
        }
    }

    /// Whether the control is in the filtering state or transitioning into it (i.e., pending).
    var isFiltering: Bool {
        state >= .filterPending
    }

    var preferredContentHeight: CGFloat = 52.0 {
        didSet {
            if state < .filterPending, let scrollView {
                scrollView.contentInset.top = preferredContentHeight
            }
            setNeedsLayout()
        }
    }

    override init(frame: CGRect) {
        let bounds = CGRect(origin: .zero, size: frame.size)
        clippingView = UIView(frame: bounds)
        clippingView.autoresizesSubviews = false
        clippingView.clipsToBounds = true
        contentView = UIView(frame: bounds)
        contentView.autoresizesSubviews = false
        animationFrames = AnimationFrame.allCases
        imageViews = animationFrames.map { UIImageView(image: $0.image) }
        imageContainer = UIView()
        clearButton = ChatListFilterButton()
        clearButton.alpha = 0
        clearButton.configuration?.title = OWSLocalizedString("CHAT_LIST_FILTERED_BY_UNREAD_CLEAR_BUTTON", comment: "Button at top of chat list indicating the active filter is 'Filtered by Unread' and tapping will clear the filter")
        clearButton.isUserInteractionEnabled = false
        clearButton.showsClearIcon = true
        super.init(frame: frame)

        autoresizesSubviews = false
        maximumContentSizeCategory = .extraExtraLarge
        preservesSuperviewLayoutMargins = true
        setContentHuggingPriority(.required, for: .vertical)
        ensureContentHeight()

        addSubview(clippingView)
        clippingView.addSubview(contentView)
        contentView.addSubview(imageContainer)
        contentView.insertSubview(clearButton, aboveSubview: imageContainer)

        for imageView in imageViews {
            imageContainer.addSubview(imageView)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(cancelFilterIconAnimator), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("unimplemented")
    }

    private func ensureContentHeight() {
        frame.size.height = preferredContentHeight
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: preferredContentHeight)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: preferredContentHeight)
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)

        if newWindow == nil {
            cancelFilterIconAnimator()
        }
    }

    // Animations are removed when the app enters the background or the owning
    // view controller disappears, so we need to properly clean up our
    // UIViewPropertyAnimator or the UI will be in an invalid state even if the
    // animator is recreated.
    @objc private func cancelFilterIconAnimator() {
        guard let filterIconAnimator, filterIconAnimator.state == .active else { return }
        self.filterIconAnimator = nil
        filterIconAnimator.stopAnimation(false)
        filterIconAnimator.finishAnimation(at: .start)
    }

    // Because animations are removed when the view disappears or the app moves
    // to the background, the animator needs to be lazily recreated whenever the
    // animation is about to begin or interactively change.
    private func resetAnimatorIfNecessary() {
        guard UIView.areAnimationsEnabled, filterIconAnimator == nil else { return }

        let filterIconAnimator = UIViewPropertyAnimator(duration: 1, timingParameters: UICubicTimingParameters())
        self.filterIconAnimator = filterIconAnimator

        for (imageView, frame) in zip(imageViews, animationFrames) {
            frame.configure(imageView)
        }

        filterIconAnimator.addAnimations { [imageViews, animationFrames] in
            UIView.animateKeyframes(withDuration: UIView.inheritedAnimationDuration, delay: 0) {
                for (imageView, frame) in zip(imageViews, animationFrames) {
                    UIView.addKeyframe(withRelativeStartTime: frame.relativeStartTime, relativeDuration: frame.relativeDuration) {
                        frame.animate(imageView)
                    }
                }
            }
        }

        // Activate the animation but leave it paused to advance it manually.
        filterIconAnimator.pauseAnimation()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // When synchronizing layout with scroll view content inset changes,
        // we need to disable normal layout until the transition completes. This
        // makes animation code easier to understand because all layout changes
        // happen explicitly.
        guard !isTransitioning else { return }

        ensureContentHeight()
        clippingView.frame.size = bounds.size
        contentView.frame.size = bounds.size
        contentView.layoutMargins = layoutMargins

        if let scrollView {
            var contentInset = -contentHeight
            var scrollIndicatorInset = max(0, -adjustedContentOffset.y)

            if state >= .filterPending {
                contentInset = 0
                scrollIndicatorInset += contentHeight
            }

            scrollView.contentInset.top = contentInset
            scrollView.verticalScrollIndicatorInsets.top = scrollIndicatorInset

            // clippingView is offset so that its Y position is always at a
            // logical content offset of 0, never behind the top bar. This
            // prevents the contentView from blending with the navigation bar
            // background material.
            var clippingOrigin = adjustedContentOffset
            clippingOrigin.y -= contentInset
            clippingView.frame.origin = clippingOrigin
        }

        // clippingView's height is adjusted so that it's only >0 in the
        // overscroll area where the pull-to-filter gesture is occuring.
        clippingView.frame.size.height = if state >= .filterPending {
            contentHeight
        } else {
            max(0, min(contentHeight, -adjustedContentOffset.y))
        }

        // contentView is a subview of clippingView so that it is clipped
        // appropriately, but its position is first calculated in this view's
        // coordinate space before being converted to clippingView. The effect
        // is that clippingView acts as a sliding window over contentView and
        // its children.
        //
        // An additional content translation factor is also applied to
        // contentView so that it effectively scrolls at half the speed of the
        // scroll gesture. Because the threshold for the gesture is
        // `contentHeight * 2`, the result is that the gesture triggers at the
        // moment that the content reaches its final scroll position
        // (even though you've physically scrolled twice as far).
        if state >= .willStartFiltering {
            contentView.frame.origin = CGPoint(x: 0, y: clippingView.bounds.maxY - contentHeight)
        } else {
            let contentTranslation = fractionComplete * -contentHeight
            var contentOrigin = CGPoint(x: 0, y: contentTranslation)
            contentOrigin = convert(contentOrigin, to: clippingView)
            contentOrigin.y = min(contentOrigin.y, 0)
            contentView.frame.origin = contentOrigin
        }

        let horizontalMargins = UIEdgeInsets(top: 0, left: layoutMargins.left, bottom: 0, right: layoutMargins.right)
        let fullBleedRect = contentView.bounds.inset(by: horizontalMargins)

        clearButton.frame = fullBleedRect
        clearButton.sizeToFit()
        clearButton.center = contentView.bounds.center

        let imageHeight = clearButton.frame.height
        let imageSize = CGSize(width: imageHeight, height: imageHeight)
        for imageView in imageViews {
            imageView.frame.size = imageSize
        }
        imageContainer.frame.size = imageSize
        imageContainer.center = contentView.bounds.center
    }

    func startFiltering(animated: Bool) {
        if animated {
            animateScrollViewTransition { [self] in
                UIView.performWithoutAnimation {
                    clippingView.frame = CGRect(x: 0, y: bounds.maxY, width: bounds.width, height: 0)
                    contentView.frame = CGRect(x: 0, y: -contentHeight, width: 0, height: contentHeight)
                    showClearButton(animated: false)
                }

                // The way UIScrollView converts contentInset changes into
                // complementary contentOffset changes is for some reason
                // different depending on whether the `contentSize` is big
                // enough for the content to be scrollable.
                //
                // The following adjustment ensures that the new `contentOffset`
                // is correct when the chat list is scrollable, and the change
                // animates smoothly. However, if `contentSize` is small both
                // before and after the this change (i.e., the chat list has a
                // very small number of chats), this happens:
                //
                //   - The scroll view doesn't call `scrollViewDidScroll(_:)`
                //   - `adjustedContentOffset` thus has a stale value
                //   - Until the user next interacts with the scroll view, the
                //     filter control will be rendered behind the search bar.
                //
                // The workaround is to manually call `updateScrollPosition(in:)`
                // below so that we have a consistent content offset before
                // `layoutSubviews()`.
                if let scrollView {
                    let previousInset = scrollView.adjustedContentInset.top
                    scrollView.contentInset.top = 0
                    let insetDifference = scrollView.adjustedContentInset.top - previousInset
                    scrollView.contentOffset.y -= insetDifference
                }

                UIView.animate(withDuration: UIView.inheritedAnimationDuration) { [self] in
                    clippingView.frame = bounds
                }

                UIView.animate(withDuration: UIView.inheritedAnimationDuration) { [self] in
                    contentView.frame = clippingView.bounds
                }
            } completion: { [self] in
                state = .filtering

                // See comment in the animation block above explaining why it's
                // necessary to manually call `updateScrollPosition(in:)`.
                if let scrollView {
                    updateScrollPosition(in: scrollView)
                }
            }
        } else {
            showClearButton(animated: false)
            state = .filtering
        }
    }

    func stopFiltering(animated: Bool) {
        if animated {
            animateScrollViewTransition { [self] in
                clearButton.isUserInteractionEnabled = false
                scrollView?.contentInset.top = -contentHeight

                UIView.animate(withDuration: UIView.inheritedAnimationDuration) { [self] in
                    clippingView.frame = CGRect(x: 0, y: bounds.maxY, width: bounds.width, height: 0)
                }

                UIView.animate(withDuration: UIView.inheritedAnimationDuration) { [self] in
                    contentView.frame = CGRect(x: 0, y: -contentHeight, width: bounds.width, height: contentHeight)
                }
            } completion: { [self] in
                clearButton.alpha = 0
                imageContainer.alpha = 1
                state = .inactive
            }
        } else {
            clearButton.alpha = 0
            clearButton.isUserInteractionEnabled = false
            imageContainer.alpha = 1
            state = .inactive
        }
    }

    func updateScrollPosition(in scrollView: UIScrollView) {
        do {
            var contentOffset = scrollView.contentOffset
            contentOffset.y += scrollView.adjustedContentInset.top
            adjustedContentOffset = contentOffset
        }

        resetAnimatorIfNecessary()

        if state == .tracking {
            filterIconAnimator?.fractionComplete = fractionComplete

            if fractionComplete == 1 {
                feedback?.impactOccurred()
                feedback = nil
                state = .willStartFiltering
            }
        }
    }

    func draggingWillBegin(in scrollView: UIScrollView) {
        if state < .tracking {
            state = .tracking
        }

        if feedback == nil {
            let feedback = UIImpactFeedbackGenerator(style: .medium)
            feedback.prepare()
            self.feedback = feedback
        }
    }

    func draggingWillEnd(in scrollView: UIScrollView) {
        if state == .willStartFiltering {
            scrollView.contentInset.top = 0
            showClearButton(animated: true)
            state = .filterPending
            delegate?.filterControlDidStartFiltering()
        }
    }

    func scrollingDidStop(in scrollView: UIScrollView) {
        if state == .tracking {
            feedback = nil
            state = .inactive
        } else if state == .filterPending {
            state = .filtering
        }
    }

    private func animateScrollViewTransition(_ animations: @escaping () -> Void, completion: (() -> Void)? = nil) {
        guard !isTransitioning else {
            owsFailDebug("already transitioning; falling back to default animation")

            UIView.animate(withDuration: animationDuration, delay: 0, options: .beginFromCurrentState) {
                animations()
            } completion: { _ in
                completion?()
            }

            return
        }

        isTransitioning = true

        if let scrollView {
            UIView.transition(with: scrollView, duration: animationDuration, options: .allowAnimatedContent) {
                animations()
            } completion: { [self] _ in
                isTransitioning = false
                completion?()
            }
        } else {
            UIView.animate(withDuration: animationDuration) {
                animations()
            } completion: { [self] _ in
                isTransitioning = false
                completion?()
            }
        }
    }

    private func showClearButton(animated: Bool) {
        guard animated else {
            clearButton.alpha = 1
            clearButton.isUserInteractionEnabled = true
            imageContainer.alpha = 0
            return
        }

        let startFrame = imageContainer.frame.intersection(clearButton.frame)
        let transitionView = TransitionEffectView(frame: startFrame)
        transitionView.effect = UIBlurEffect(style: .systemUltraThinMaterial)
        contentView.insertSubview(transitionView, belowSubview: imageContainer)
        let endFrame = clearButton.frame
        let oldBackground = clearButton.configuration?.background
        clearButton.configuration?.background = .clear()

        let transitionAnimator = UIViewPropertyAnimator(duration: 0.7, dampingRatio: 0.75) { [clearButton, imageContainer] in
            let duration = UIView.inheritedAnimationDuration

            UIView.animate(withDuration: 0.1 * duration, delay: 0) {
                imageContainer.alpha = 0
            }

            UIView.animate(withDuration: duration, delay: 0) {
                transitionView.frame = endFrame
            }

            UIView.animate(withDuration: 0.67 * duration, delay: 0.33 * duration) {
                clearButton.alpha = 1
            }
        }

        transitionAnimator.addCompletion { [self] _ in
            if let oldBackground {
                clearButton.configuration?.background = oldBackground
            }
            clearButton.isUserInteractionEnabled = true
            transitionView.removeFromSuperview()
        }

        transitionAnimator.startAnimation()
    }
}

private extension UIImage.Configuration {
    static var filterIconBase: UIImage.SymbolConfiguration {
        UIImage.SymbolConfiguration(scale: .large)
    }

    static var filterIconBackground: UIImage.SymbolConfiguration {
        filterIconBase.applying(UIImage.SymbolConfiguration(paletteColors: [.Signal.secondaryBackground]))
    }

    static var filterIconIncrementing: UIImage.SymbolConfiguration {
        filterIconBase.applying(UIImage.SymbolConfiguration(paletteColors: [.Signal.label, .Signal.secondaryBackground]))
    }

    static var filterIconFiltering: UIImage.SymbolConfiguration {
        filterIconBase.applying(UIImage.SymbolConfiguration(paletteColors: [.Signal.ultramarine, .Signal.secondaryBackground]))
    }
}

private extension ChatListFilterControl {
    final class TransitionEffectView: UIVisualEffectView {
        private let capsule: UIView

        override init(effect: UIVisualEffect?) {
            capsule = UIView()
            capsule.backgroundColor = UIColor(white: 1, alpha: 1) // only alpha channel is used
            super.init(effect: effect)
            mask = capsule
        }

        convenience init(frame: CGRect) {
            self.init(effect: nil)
            self.frame = frame
            updateMask()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            updateMask()
        }

        private func updateMask() {
            capsule.frame = bounds
            capsule.layer.cornerRadius = min(bounds.width, bounds.height) / 2
        }
    }
}
