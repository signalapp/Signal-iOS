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

    private enum State {
        /// Control is not visible, filtering is disabled.
        case inactive

        /// Control is appearing, but not interactively.
        case starting

        /// Control is appearing, tracking scroll position.
        case tracking

        /// Started filtering (i.e., called `delegate.filterControlDidStartFiltering()`),
        /// but still tracking scroll position.
        case pending

        /// Actively filtering and control is docked to the top of the scroll view.
        case filtering

        /// Control is disappearing.
        case stopping

        /// Whether the control is in the filtering state or transitioning into it (i.e., pending).
        var isFiltering: Bool {
            switch self {
            case .pending, .filtering:
                return true
            case .inactive, .starting, .tracking, .stopping:
                return false
            }
        }

        mutating func startOrContinueTracking() -> Bool {
            switch self {
            case .pending, .filtering, .starting:
                return false
            case .inactive:
                self = .tracking
                fallthrough
            case .tracking, .stopping:
                return true
            }
        }
    }

    static var minimumContentHeight: CGFloat {
        52
    }

    private let contentView: UIView
    private let clippingView: UIView
    private let imageContainer: UIView
    private let imageViews: [UIImageView]
    private let clearButton: ChatListFilterButton
    private let animationFrames: [AnimationFrame]
    private var feedback: UIImpactFeedbackGenerator?
    private var filterIconAnimator: UIViewPropertyAnimator?
    private var previousContentHeight = CGFloat(0)
    private var state = State.inactive

    weak var delegate: (any ChatListFilterControlDelegate)?

    private var adjustedContentOffset: CGPoint = .zero {
        didSet {
            let position = max(0, -adjustedContentOffset.y)
            let limit = contentHeight * 2
            fractionComplete = min(1, position / limit)
        }
    }

    private var fractionComplete: CGFloat = 0.0

    private var animationDuration: CGFloat {
        UIView.inheritedAnimationDuration == 0 ? CATransaction.animationDuration() : UIView.inheritedAnimationDuration
    }

    private var contentHeight: CGFloat {
        get { frame.size.height }
        set { frame.size.height = newValue }
    }

    private var scrollView: UIScrollView? {
        superview as? UIScrollView
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
        state.isFiltering
    }

    override init(frame: CGRect) {
        let bounds = CGRect(origin: .zero, size: frame.size)
        clippingView = UIView(frame: bounds)
        clippingView.autoresizesSubviews = false
        clippingView.clipsToBounds = true
        contentView = UIView(frame: bounds)
        contentView.autoresizesSubviews = false
        contentView.backgroundColor = .Signal.background
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
        ensureMinimumContentHeight()
        previousContentHeight = contentHeight

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

    private func ensureMinimumContentHeight() {
        if contentHeight < Self.minimumContentHeight {
            contentHeight = Self.minimumContentHeight
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.minimumContentHeight)
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

        ensureMinimumContentHeight()
        clippingView.frame.size = bounds.size
        contentView.frame.size = bounds.size
        contentView.layoutMargins = layoutMargins

        // clippingView is offset so that its Y position is always at a content
        // offset of 0, never behind the top bar. This prevents the contentView
        // from blending with the navigation bar background material.
        clippingView.frame.origin.y = if state == .filtering {
            adjustedContentOffset.y
        } else {
            adjustedContentOffset.y + contentHeight
        }

        // clippingView's height is adjusted so that it's only >0 in the overscroll
        // area where the pull-to-filter gesture is occuring.
        clippingView.frame.size.height = if state == .filtering {
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
        let contentTranslation: Double = if state == .filtering {
            0.0
        } else {
            fractionComplete * -contentHeight
        }
        var contentOrigin = CGPoint(x: 0, y: contentTranslation)
        contentOrigin = convert(contentOrigin, to: clippingView)
        contentOrigin.y = min(contentOrigin.y, 0)
        contentView.frame.origin = contentOrigin

        if let scrollView {
            var inset = max(0, -adjustedContentOffset.y)
            if state == .filtering {
                inset += contentHeight
            }
            scrollView.verticalScrollIndicatorInsets.top = inset

            // Ensure that the content inset stays in sync with the content height
            // whenever the frame changes (e.g., when dynamic type changes the size
            // of the search bar).
            if state != .filtering && abs(scrollView.contentInset.top) != contentHeight {
                scrollView.contentInset.top = -contentHeight
            }
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
        func startFiltering() {
            scrollView?.contentInset.top = 0
        }

        showClearButton(animated: false)

        if animated {
            resetAnimatorIfNecessary()
            UIView.animate(withDuration: animationDuration) { [self] in
                state = .starting
                startFiltering()
            } completion: { [self] _ in
                state = .filtering
            }
        } else {
            state = .filtering
            startFiltering()
            filterIconAnimator?.fractionComplete = 1
        }
    }

    func stopFiltering(animated: Bool) {
        func stopFiltering() {
            clearButton.alpha = 0
            clearButton.isUserInteractionEnabled = false
            scrollView?.contentInset.top = -contentHeight
        }

        func cleanUp() {
            filterIconAnimator?.fractionComplete = 0
            contentView.backgroundColor = .Signal.background
            imageContainer.alpha = 1
            state = .inactive
        }

        if animated {
            resetAnimatorIfNecessary()
            UIView.animate(withDuration: animationDuration) { [self] in
                state = .stopping
                stopFiltering()
            } completion: { _ in
                cleanUp()
            }
        } else {
            stopFiltering()
            cleanUp()
        }
    }

    func updateScrollPosition(in scrollView: UIScrollView) {
        adjustedContentOffset = scrollView.contentOffset
        adjustedContentOffset.y += scrollView.adjustedContentInset.top
        setNeedsLayout()

        guard state.startOrContinueTracking() else { return }

        if feedback == nil {
            let feedback = UIImpactFeedbackGenerator(style: .medium)
            feedback.prepare()
            self.feedback = feedback
        }

        var didStartFiltering = false

        if state == .stopping {
            self.feedback = nil
        } else if fractionComplete == 1 {
            state = .pending
            didStartFiltering = true
        }

        resetAnimatorIfNecessary()
        filterIconAnimator?.fractionComplete = fractionComplete

        if didStartFiltering {
            feedback?.impactOccurred()
            feedback = nil
            delegate?.filterControlDidStartFiltering()
        }
    }

    func draggingWillEnd(in scrollView: UIScrollView) {
        switch state {
        case .pending:
            state = .filtering
            scrollView.contentInset.top = 0
            showClearButton(animated: true)

        case .inactive, .filtering, .stopping, .starting:
            break

        case .tracking:
            state = .stopping
        }
    }

    func scrollingDidStop(in scrollView: UIScrollView) {
        if state == .stopping {
            state = .inactive
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
        let transitionView = UIView(frame: startFrame)
        transitionView.layer.cornerRadius = startFrame.height / 2
        contentView.insertSubview(transitionView, belowSubview: imageContainer)
        let backgroundColor = clearButton.configuration?.baseBackgroundColor
        transitionView.backgroundColor = backgroundColor
        let endFrame = clearButton.frame
        clearButton.configuration?.baseBackgroundColor = .clear

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

        transitionAnimator.addCompletion { [clearButton] _ in
            clearButton.configuration?.baseBackgroundColor = backgroundColor
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
