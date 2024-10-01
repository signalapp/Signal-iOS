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
            AnimationFrame(step: 1, relativeStartTime: 0.2, relativeDuration: 0.2, isFiltering: false),
            AnimationFrame(step: 2, relativeStartTime: 0.4, relativeDuration: 0.2, isFiltering: false),
            AnimationFrame(step: 3, relativeStartTime: 0.6, relativeDuration: 0.2, isFiltering: false),
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
    private let overlayView: UIView
    private let imageContainer: UIView
    private let imageViews: [UIImageView]
    private let clearButton: ChatListFilterButton
    private let animationFrames: [AnimationFrame]
    private var filterIconAnimator: UIViewPropertyAnimator!
    private var feedback: UIImpactFeedbackGenerator?
    private var previousContentHeight = CGFloat(0)
    private var state = State.inactive

    weak var delegate: (any ChatListFilterControlDelegate)?

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
        contentView = UIView(frame: bounds)
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.backgroundColor = .Signal.background
        contentView.preservesSuperviewLayoutMargins = true
        overlayView = UIView(frame: bounds)
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlayView.backgroundColor = .Signal.background
        animationFrames = AnimationFrame.allCases
        imageViews = animationFrames.map { UIImageView(image: $0.image) }
        imageContainer = UIView()
        clearButton = ChatListFilterButton()
        clearButton.alpha = 0
        clearButton.configuration?.title = OWSLocalizedString("CHAT_LIST_FILTERED_BY_UNREAD_CLEAR_BUTTON", comment: "Button at top of chat list indicating the active filter is 'Filtered by Unread' and tapping will clear the filter")
        clearButton.isUserInteractionEnabled = false
        clearButton.showsClearIcon = true
        super.init(frame: frame)

        maximumContentSizeCategory = .extraExtraLarge
        preservesSuperviewLayoutMargins = true
        setContentHuggingPriority(.required, for: .vertical)
        ensureMinimumContentHeight()
        previousContentHeight = contentHeight

        addSubview(contentView)
        addSubview(overlayView)
        contentView.autoPinEdgesToSuperviewEdges()
        contentView.addSubview(imageContainer)
        contentView.insertSubview(clearButton, aboveSubview: imageContainer)

        for imageView in imageViews {
            imageContainer.addSubview(imageView)
        }

        resetFilterIconAnimator()

        NotificationCenter.default.addObserver(self, selector: #selector(cancelFilterIconAnimator), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resetFilterIconAnimator), name: UIApplication.didBecomeActiveNotification, object: nil)
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

    // Animations are removed when the app enters the background, so we need to
    // properly clean up our `UIViewPropertyAnimator` or the UI will be in an
    // invalid state even if the animator is recreated.
    @objc private func cancelFilterIconAnimator() {
        filterIconAnimator.stopAnimation(true)
        filterIconAnimator.finishAnimation(at: .start)
    }

    // The animator needs to be reset any time the app resumes from the background,
    // because long-running animations are removed when the app is backgrounded.
    @objc private func resetFilterIconAnimator() {
        assert(filterIconAnimator == nil || filterIconAnimator.state == .inactive, "Animator should be inactive before being reset")
        filterIconAnimator = UIViewPropertyAnimator(duration: 1, timingParameters: UICubicTimingParameters())

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

        if contentHeight != previousContentHeight {
            contentView.frame.size = bounds.size
            overlayView.frame.size = bounds.size

            // If the first layout is in the filtering state, we can't rely on
            // updateScrollPosition() to have been called in order to set the
            // position of the overlay view. Manually adjust the position so
            // it doesn't obscure the content before interactive scrolling occurs.
            if state == .filtering {
                overlayView.frame.origin.y = -contentHeight
            }

            previousContentHeight = contentHeight
        }

        // Ensure that the content inset stays in sync with the content height
        // whenever the frame changes (e.g., when dynamic type changes the size
        // of the search bar).
        if let scrollView, state != .filtering && abs(scrollView.contentInset.top) != contentHeight {
            scrollView.contentInset.top = -contentHeight
        }

        let layoutMargins = contentView.layoutMargins
        let horizontalMargins = UIEdgeInsets(top: 0, left: layoutMargins.left, bottom: 0, right: layoutMargins.right)
        let fullBleedRect = contentView.bounds.inset(by: horizontalMargins)

        clearButton.frame = fullBleedRect
        clearButton.sizeToFit()
        clearButton.center = contentView.center

        let imageHeight = clearButton.frame.height
        let imageSize = CGSize(width: imageHeight, height: imageHeight)
        for imageView in imageViews {
            imageView.frame.size = imageSize
        }
        imageContainer.frame.size = imageSize
        imageContainer.center = contentView.center
    }

    func startFiltering(animated: Bool) {
        func startFiltering() {
            scrollView?.contentInset.top = 0
        }

        showClearButton(animated: false)

        if animated {
            UIView.animate(withDuration: animationDuration) { [self] in
                state = .starting
                startFiltering()
            } completion: { [self] _ in
                state = .filtering
            }
        } else {
            state = .filtering
            startFiltering()
            filterIconAnimator.fractionComplete = 1
        }
    }

    func stopFiltering(animated: Bool) {
        func stopFiltering() {
            clearButton.alpha = 0
            clearButton.isUserInteractionEnabled = false
            scrollView?.contentInset.top = -contentHeight
        }

        func cleanUp() {
            filterIconAnimator.fractionComplete = 0
            contentView.backgroundColor = .Signal.background
            imageContainer.alpha = 1
            state = .inactive
        }

        if animated {
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
        let adjustedOffset = scrollView.adjustedContentInset.top + scrollView.contentOffset.y

        overlayView.frame.origin.y = if state == .filtering {
            // When filtering/"docked", contentView is part of the content area,
            // so make sure overlayView doesn't obscure it.
            adjustedOffset - overlayView.frame.height
        } else {
            // When not docked, contentView  can be obscured by overlayView.
            adjustedOffset
        }

        guard state.startOrContinueTracking() else { return }

        if feedback == nil {
            let feedback = UIImpactFeedbackGenerator(style: .medium)
            feedback.prepare()
            self.feedback = feedback
        }

        let position = max(0, -adjustedOffset)
        let limit = frame.height * 2
        let progress = min(1, position / limit)
        var didStartFiltering = false

        if state == .stopping {
            self.feedback = nil
        } else if progress == 1 {
            state = .pending
            didStartFiltering = true
        }

        filterIconAnimator.fractionComplete = progress

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
