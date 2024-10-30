//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

@MainActor
protocol ChatListFilterControlDelegate: AnyObject {
    func filterControlWillStartFiltering()
}

final class ChatListFilterControl: UIView, UIScrollViewDelegate {
    private struct AnimationFrame: CaseIterable {
        static let allCases = [
            AnimationFrame(step: 0, relativeStartTime: 0.01, relativeDuration: 0, isFiltering: false),
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

        /// Control was tracking scroll view dragging, but dragging stopped
        /// before the threshold.
        case stopping

        /// Control is appearing, tracking scroll position.
        case tracking

        /// Control enters this state while interactively dragging the scroll
        /// view, indicating that filtering will begin when the user lifts
        /// their finger and dragging ends. Can't return to `tracking` after
        /// entering this state.
        case willStartFiltering

        /// `isFiltering == true` where `state >= .filterPending`. Started
        /// filtering but haven't finished animating into the "docked" position.
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

    private func animationDuration(_ defaultDuration: @autoclosure () -> CGFloat = CATransaction.animationDuration()) -> CGFloat {
        UIView.inheritedAnimationDuration == 0 ? defaultDuration() : UIView.inheritedAnimationDuration
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
            if state < .filterPending {
                scrollView?.contentInset.top = -preferredContentHeight
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
        imageContainer.translatesAutoresizingMaskIntoConstraints = false
        clearButton = ChatListFilterButton()
        clearButton.alpha = 0
        clearButton.configuration?.title = OWSLocalizedString("CHAT_LIST_FILTERED_BY_UNREAD_CLEAR_BUTTON", comment: "Button at top of chat list indicating the active filter is 'Filtered by Unread' and tapping will clear the filter")
        clearButton.isUserInteractionEnabled = false
        clearButton.showsClearIcon = true
        super.init(frame: frame)

        autoresizesSubviews = false
        maximumContentSizeCategory = .extraExtraExtraLarge
        preservesSuperviewLayoutMargins = true
        setContentHuggingPriority(.required, for: .vertical)
        ensureContentHeight()

        addSubview(clippingView)
        clippingView.addSubview(contentView)
        contentView.addSubview(imageContainer)
        contentView.insertSubview(clearButton, aboveSubview: imageContainer)

        NSLayoutConstraint.activate([
            imageContainer.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            imageContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])

        for imageView in imageViews {
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageContainer.addSubview(imageView)
            imageView.autoPinEdgesToSuperviewEdges()

            let image = imageView.image!
            let imageRect = CGRect(origin: .zero, size: image.size)
                .inset(by: image.alignmentRectInsets)
            let alignmentWidthAdjustment = imageRect.width - imageRect.height

            let variableImageHeight = imageView.heightAnchor.constraint(equalTo: clearButton.heightAnchor)
            variableImageHeight.priority = .defaultHigh
            NSLayoutConstraint.activate([
                variableImageHeight,
                imageView.heightAnchor.constraint(greaterThanOrEqualToConstant: 38),
                imageView.widthAnchor.constraint(equalTo: imageView.heightAnchor, multiplier: 1, constant: alignmentWidthAdjustment),
            ])
        }

        reconfigureFilterIconImageViews()

        // Animations are removed when the app enters the background or the owning
        // view controller disappears, so we need to properly clean up our
        // UIViewPropertyAnimator or the UI will be in an invalid state even if the
        // animator is recreated.
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

    override func didMoveToWindow() {
        super.didMoveToWindow()

        updateContentInset()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // clippingView's position is logically relative to the scroll view's
        // frame, not its bounds (i.e., it's docked near the top of the scroll
        // view regardless of scroll position). This means we should ignore the
        // default hit testing that's relative to scroll position and just
        // consult clippingView directly.
        let point = convert(point, to: clippingView)
        return clippingView.hitTest(point, with: event)
    }

    @objc private func cancelFilterIconAnimator() {
        guard let filterIconAnimator, filterIconAnimator.state == .active else { return }
        filterIconAnimator.stopAnimation(false)
        filterIconAnimator.finishAnimation(at: .start)
    }

    private func reconfigureFilterIconImageViews() {
        UIView.performWithoutAnimation {
            for (imageView, frame) in zip(imageViews, animationFrames) {
                frame.configure(imageView)
            }
        }
    }

    private func setUpFilterIconAnimatorIfNecessary() {
        guard UIView.areAnimationsEnabled, filterIconAnimator == nil else { return }

        let filterIconAnimator = UIViewPropertyAnimator(duration: 1, timingParameters: UICubicTimingParameters())
        self.filterIconAnimator = filterIconAnimator

        reconfigureFilterIconImageViews()

        filterIconAnimator.addAnimations { [imageViews, animationFrames] in
            UIView.animateKeyframes(withDuration: UIView.inheritedAnimationDuration, delay: 0) {
                for (imageView, frame) in zip(imageViews, animationFrames) {
                    UIView.addKeyframe(withRelativeStartTime: frame.relativeStartTime, relativeDuration: frame.relativeDuration) {
                        frame.animate(imageView)
                    }
                }
            }
        }

        filterIconAnimator.addCompletion { [weak self] _ in
            guard let self else { return }
            self.filterIconAnimator = nil
            self.reconfigureFilterIconImageViews()
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

        updateContentOrigin()

        let horizontalMargins = UIEdgeInsets(top: 0, left: layoutMargins.left, bottom: 0, right: layoutMargins.right)
        let fullBleedRect = contentView.bounds.inset(by: horizontalMargins)

        UIView.performWithoutAnimation {
            clearButton.frame = fullBleedRect
            clearButton.sizeToFit()
            clearButton.center = contentView.bounds.center
        }
    }

    func updateContentOrigin() {
        do {
            var scrollIndicatorInset = max(0, -adjustedContentOffset.y)

            if state >= .filterPending {
                scrollIndicatorInset += contentHeight
            }

            scrollView?.verticalScrollIndicatorInsets.top = scrollIndicatorInset

            // clippingView is offset so that its Y position is always at a
            // logical content offset of 0, never behind the top bar. This
            // prevents the contentView from blending with the navigation bar
            // background material.
            if let scrollView, let container = scrollView.superview {
                let safeAreaRect = scrollView.frame.inset(by: scrollView.safeAreaInsets)
                let contentOrigin = container.convert(safeAreaRect.origin, to: self)
                clippingView.frame.origin = contentOrigin
            }
        }

        // clippingView's height is adjusted so that it's only >0 in the
        // overscroll area where the pull-to-filter gesture is occuring.
        clippingView.frame.size.height = if state >= .willStartFiltering {
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
    }

    // Setting `UIScrollView.contentInset` triggers implicit changes to both
    // `contentOffset` and `adjustedContentInset`, and also synchronously calls
    // the associated `UIScrollViewDelegate` methods (`scrollViewDidScroll(_:)`
    // and `scrollViewDidChangeAdjustedContentInset(_:)`, respectively). Without
    // a careful explicit adjustment to the content offset, this tends to break
    // scroll view animations, causing content to snap to a new scroll position
    // abruptly.
    //
    // This method:
    //     a) avoids changing the content inset if unchanged, in order to avoid
    //        triggering unwanted delegate callbacks, and
    //     b) after changing the contentInset, explicitly adjusts the content
    //        *offset* by a complementary amount, preventing unwanted animation.
    func updateContentInset() {
        let newValue = state >= .filterPending ? 0 : -preferredContentHeight
        guard let scrollView, scrollView.contentInset.top != newValue else { return }
        let difference = newValue - scrollView.contentInset.top
        var targetOffset = scrollView.contentOffset
        targetOffset.y -= difference
        scrollView.contentInset.top = newValue
        scrollView.setContentOffset(targetOffset, animated: false)
    }

    func startFiltering(animated: Bool) {
        if animated {
            animateScrollViewTransition(withDuration: animationDuration()) { [self] in
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
            updateContentInset()
        }
    }

    func stopFiltering(animated: Bool) {
        func cleanUp() {
            clearButton.alpha = 0
            imageContainer.alpha = 1
            state = .inactive
            cancelFilterIconAnimator()
        }

        if animated {
            animateScrollViewTransition(withDuration: animationDuration()) { [self] in
                clearButton.isUserInteractionEnabled = false
                scrollView?.contentInset.top = -contentHeight

                UIView.animate(withDuration: UIView.inheritedAnimationDuration) { [self] in
                    clippingView.frame = CGRect(x: 0, y: bounds.maxY, width: bounds.width, height: 0)
                }

                UIView.animate(withDuration: UIView.inheritedAnimationDuration) { [self] in
                    contentView.frame = CGRect(x: 0, y: -contentHeight, width: bounds.width, height: contentHeight)
                }
            } completion: {
                cleanUp()
            }
        } else {
            clearButton.isUserInteractionEnabled = false
            cleanUp()
        }
    }

    func updateScrollPosition(in scrollView: UIScrollView) {
        do {
            var contentOffset = scrollView.contentOffset
            contentOffset.y += scrollView.adjustedContentInset.top
            adjustedContentOffset = contentOffset
        }

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
            setUpFilterIconAnimatorIfNecessary()
        }

        if feedback == nil {
            let feedback = UIImpactFeedbackGenerator(style: .heavy)
            feedback.prepare()
            self.feedback = feedback
        }
    }

    func draggingWillEnd(in scrollView: UIScrollView) {
        switch state {
        case .tracking:
            feedback = nil
            state = .stopping
        case .willStartFiltering:
            delegate?.filterControlWillStartFiltering()
            state = .filterPending
        default:
            break
        }
    }

    func draggingDidEnd(in scrollView: UIScrollView) {
        if state == .filterPending {
            updateContentInset()
            showClearButton(animated: true)
        }
    }

    func scrollingDidStop(in scrollView: UIScrollView) {
        if state <= .tracking {
            feedback = nil
            state = .inactive
            cancelFilterIconAnimator()
        } else if state == .filterPending {
            state = .filtering
        }
    }

    private func animateScrollViewTransition(withDuration duration: CGFloat, _ animations: @escaping () -> Void, completion: (() -> Void)? = nil) {
        guard !isTransitioning else {
            owsFailDebug("already transitioning; falling back to default animation")

            UIView.animate(withDuration: duration, delay: 0, options: .beginFromCurrentState) {
                animations()
            } completion: { _ in
                completion?()
            }

            return
        }

        isTransitioning = true

        if let scrollView {
            UIView.transition(with: scrollView, duration: duration, options: .allowAnimatedContent) {
                animations()
            } completion: { [self] _ in
                isTransitioning = false
                completion?()
            }
        } else {
            UIView.animate(withDuration: duration) {
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

        let filterIconImageView = UIImageView(image: animationFrames.last!.image.withConfiguration(.filterIconDisappearing))
        let transitionView = TransitionEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        let endFrame = clearButton.frame

        // Ensure that if clearButton.height < imageContainer.height, we don't
        // shrink the image container down.
        let startFrame = imageContainer.frame
            .union(endFrame)
            .intersection(imageContainer.frame)

        let oldBackground = clearButton.configuration?.background
        clearButton.configuration?.background = .clear()

        UIView.performWithoutAnimation {
            imageContainer.alpha = 0

            transitionView.contentView.backgroundColor = .filterIconActiveBackground
            transitionView.frame = startFrame
            transitionView.contentView.addSubview(filterIconImageView)
            contentView.insertSubview(transitionView, belowSubview: imageContainer)
            filterIconImageView.frame = transitionView.contentView.convert(imageViews.last!.frame, from: imageContainer)
        }

        let transitionAnimator = UIViewPropertyAnimator(duration: animationDuration(0.7), dampingRatio: 0.75)

        transitionAnimator.addAnimations(withDurationFactor: 0.1) {
            filterIconImageView.alpha = 0
        }

        transitionAnimator.addAnimations({ [clearButton] in
            clearButton.alpha = 1
        }, delayFactor: 0.33)

        transitionAnimator.addAnimations {
            transitionView.contentView.backgroundColor = .clear
            transitionView.frame = endFrame
            filterIconImageView.center = transitionView.contentView.bounds.center
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
        filterIconBase.applying(UIImage.SymbolConfiguration(paletteColors: [.filterIconActiveForeground, .filterIconActiveBackground]))
    }

    static var filterIconDisappearing: UIImage.SymbolConfiguration {
        filterIconBase.applying(UIImage.SymbolConfiguration(paletteColors: [.filterIconActiveForeground, .clear]))
    }
}

private extension UIColor {
    static var filterIconActiveForeground: UIColor {
        UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                .Signal.label
            } else {
                .Signal.ultramarine
            }
        }
    }

    static var filterIconActiveBackground: UIColor {
        UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                .Signal.ultramarine
            } else {
                .Signal.secondaryUltramarineBackground
            }
        }
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

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            updateMask()
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
