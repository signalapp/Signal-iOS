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

final class ChatListFilterControl: UIView {
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

    enum State {
        /// Control is not visible, filtering is disabled.
        case inactive

        /// Control was tracking scroll view dragging, but dragging stopped
        /// before the threshold.
        case stopping

        /// Control is tracking scroll view offset, but gesture threshold has
        /// not been reached.
        case starting

        /// Control enters this state while interactively dragging the scroll
        /// view, indicating that filtering will begin when the user lifts
        /// their finger and dragging ends. Can't return to `starting` after
        /// entering this state.
        case triggered

        /// `isFiltering == true` where `state >= .filterPending`. Started
        /// filtering but haven't finished animating into the "docked" position.
        case filterPending

        /// Actively filtering and control is docked to the top of the scroll view.
        case filtering

        fileprivate var affectsContentInset: Bool {
            isFiltering
        }

        fileprivate var isFiltering: Bool {
            switch self {
            case .filterPending, .filtering:
                return true
            case .inactive, .starting, .stopping, .triggered:
                return false
            }
        }
    }

    private let animationFrames: [AnimationFrame]
    private let clearButton: ChatListFilterButton
    private let contentHeightConstraint: NSLayoutConstraint
    private let contentView: UIView
    private let imageContainer: UIView
    private let imageViews: [UIImageView]

    private var contentTranslationConstraint: NSLayoutConstraint!
    private var feedback: UIImpactFeedbackGenerator?
    private var filterIconAnimator: UIViewPropertyAnimator?
    private var fractionComplete: CGFloat = 0.0
    private var isTracking = false
    private var scrollViewTransitionAnimator: UIViewPropertyAnimator?

    private unowned let container: ChatListContainerView
    private weak var scrollView: UIScrollView?

    weak var delegate: (any ChatListFilterControlDelegate)?

    private var adjustedContentOffset: CGPoint = .zero {
        didSet {
            if adjustedContentOffset != oldValue {
                updateFractionComplete()
            }
        }
    }

    private func animationDuration(_ defaultDuration: @autoclosure () -> CGFloat = CATransaction.animationDuration()) -> CGFloat {
        UIView.inheritedAnimationDuration == 0 ? defaultDuration() : UIView.inheritedAnimationDuration
    }

    private func updateFractionComplete() {
        let position = max(0, -adjustedContentOffset.y)
        let limit = swipeGestureThreshold
        fractionComplete = min(1, position / limit)
        setNeedsLayout()
    }

    private(set) var state = State.inactive {
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

    var isAnimatingTransition: Bool {
        switch state {
        case .inactive, .triggered, .filterPending, .filtering:
            return false
        case .starting, .stopping:
            return !isTracking
        }
    }

    /// Whether the control is in the filtering state or transitioning into it (i.e., pending).
    var isFiltering: Bool {
        state.isFiltering
    }

    var preferredContentHeight: CGFloat = 52.0 {
        didSet {
            contentHeightConstraint.constant = preferredContentHeight
            updateContentInsetIfNecessary()
        }
    }

    var swipeGestureThreshold: CGFloat = 150.0 {
        didSet {
            swipeGestureThreshold = swipeGestureThreshold.clamp(75.0, 150.0)

            if swipeGestureThreshold != oldValue {
                updateFractionComplete()
            }
        }
    }

    init(container: ChatListContainerView, scrollView: UIScrollView) {
        self.container = container
        self.scrollView = scrollView

        contentView = UIView()
        contentView.autoresizesSubviews = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentHeightConstraint = contentView.heightAnchor.constraint(equalToConstant: preferredContentHeight)

        animationFrames = AnimationFrame.allCases
        imageViews = animationFrames.map { UIImageView(image: $0.image) }
        imageContainer = UIView()
        imageContainer.translatesAutoresizingMaskIntoConstraints = false

        clearButton = ChatListFilterButton()
        clearButton.alpha = 0
        clearButton.configuration?.title = OWSLocalizedString("CHAT_LIST_FILTERED_BY_UNREAD_CLEAR_BUTTON", comment: "Button at top of chat list indicating the active filter is 'Filtered by Unread' and tapping will clear the filter")
        clearButton.isUserInteractionEnabled = false
        clearButton.showsClearIcon = true

        super.init(frame: .zero)

        clipsToBounds = true
        maximumContentSizeCategory = .extraExtraExtraLarge
        preservesSuperviewLayoutMargins = true

        addSubview(contentView)
        contentTranslationConstraint = contentView.bottomAnchor.constraint(equalTo: topAnchor, constant: 0)

        contentView.addSubview(imageContainer)
        contentView.insertSubview(clearButton, aboveSubview: imageContainer)

        NSLayoutConstraint.activate([
            contentHeightConstraint,
            contentTranslationConstraint,
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
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

        updateContentInsetIfNecessary()
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

        let horizontalMargins = UIEdgeInsets(top: 0, left: layoutMargins.left, bottom: 0, right: layoutMargins.right)
        let fullBleedRect = contentView.bounds.inset(by: horizontalMargins)

        UIView.performWithoutAnimation {
            clearButton.frame = fullBleedRect
            clearButton.sizeToFit()
            clearButton.center = contentView.bounds.center
        }
    }

    func updateContentOrigin() {
        switch (state, isTracking) {
        case (.inactive, _), (.starting, false), (.stopping, false):
            contentTranslationConstraint.constant = 0
        case (.starting, true), (.stopping, true):
            contentTranslationConstraint.constant = fractionComplete * preferredContentHeight
        case (.triggered, _), (.filterPending, _), (.filtering, _):
            contentTranslationConstraint.constant = preferredContentHeight
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
    private func updateContentInsetIfNecessary() {
        let newValue = state.affectsContentInset ? preferredContentHeight : 0
        guard let scrollView, scrollView.contentInset.top != newValue else { return }
        let difference = newValue - scrollView.contentInset.top
        var targetOffset = scrollView.contentOffset
        targetOffset.y -= difference
        scrollView.contentInset.top = newValue
        scrollView.setContentOffset(targetOffset, animated: false)
    }

    func startFiltering(animated: Bool) {
        guard state != .filtering  else { return }

        isTracking = false
        state = .filtering
        showClearButton(animated: false)

        if animated {
            UIView.animate(withDuration: animationDuration()) { [self] in
                frame.height = preferredContentHeight
                updateContentInsetIfNecessary()
                updateContentOrigin()
                layoutIfNeeded()
            }
        } else {
            updateContentInsetIfNecessary()
            updateContentOrigin()
        }
    }

    func stopFiltering(animated: Bool) {
        func cleanUp() {
            clearButton.alpha = 0
            imageContainer.alpha = 1
            cancelFilterIconAnimator()
        }

        clearButton.isUserInteractionEnabled = false
        isTracking = false
        state = .inactive

        if animated {
            UIView.animate(withDuration: animationDuration()) { [self] in
                frame.height = 0
                updateContentInsetIfNecessary()
                updateContentOrigin()
                layoutIfNeeded()
            } completion: { _ in
                cleanUp()
            }
        } else {
            cleanUp()
        }
    }

    func setAdjustedContentOffset(_ adjustedContentOffset: CGPoint) {
        self.adjustedContentOffset = adjustedContentOffset
        guard isTracking else { return }

        updateContentOrigin()

        switch state {
        case .starting where fractionComplete == 1:
            feedback?.impactOccurred()
            feedback = nil
            isTracking = false
            state = .triggered
            filterIconAnimator?.fractionComplete = 1
        case .starting, .stopping:
            // Limiting to 99% means that even if a rapid swipe has enough velocity
            // to exceed the threshold, if the drag has stopped and we've moved to
            // the 'stopping' state, the filter icon won't turn blue.
            filterIconAnimator?.fractionComplete = min(fractionComplete, 0.99)
        default:
            break
        }
    }

    func draggingWillBegin(in scrollView: UIScrollView) {
        if state == .inactive || state == .stopping {
            isTracking = true
            state = .starting
            setUpFilterIconAnimatorIfNecessary()
        }

        if feedback == nil {
            let feedback = UIImpactFeedbackGenerator(style: .heavy)
            feedback.prepare()
            self.feedback = feedback
        }
    }

    func draggingWillEnd(in scrollView: UIScrollView) {
        if state == .triggered {
            delegate?.filterControlWillStartFiltering()
            state = .filterPending
        }
    }

    func draggingDidEnd(in scrollView: UIScrollView) {
        switch state {
        case .starting:
            feedback = nil
            if fractionComplete > 0 {
                state = .stopping
            } else {
                isTracking = false
                state = .inactive
            }
        case .filterPending:
            updateContentInsetIfNecessary()
            showClearButton(animated: true)
        default:
            break
        }
    }

    func scrollingDidStop(in scrollView: UIScrollView) {
        if state == .stopping {
            feedback = nil
            isTracking = false
            state = .inactive
            cancelFilterIconAnimator()
        } else if state == .filterPending {
            state = .filtering
        }
    }

    private func showClearButton(animated: Bool) {
        guard animated else {
            UIView.performWithoutAnimation {
                clearButton.alpha = 1
                clearButton.isUserInteractionEnabled = true
                imageContainer.alpha = 0
            }
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
