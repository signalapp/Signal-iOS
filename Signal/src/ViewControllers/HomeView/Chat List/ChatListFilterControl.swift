//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

@MainActor
protocol ChatListFilterControlDelegate: AnyObject {
    func filterControlWillChangeState(to state: ChatListFilterControl.FilterState)
}

final class ChatListFilterControl: UIView {
    private struct AnimationFrame: CaseIterable {
        static let allCases = [
            AnimationFrame(step: 0, relativeStartTime: 0.01, relativeDuration: 0, isFiltering: false),
            AnimationFrame(step: 1, relativeStartTime: 0.36, relativeDuration: 0.2, isFiltering: false),
            AnimationFrame(step: 2, relativeStartTime: 0.56, relativeDuration: 0.2, isFiltering: false),
            AnimationFrame(step: 3, relativeStartTime: 0.76, relativeDuration: 0.2, isFiltering: false),
            AnimationFrame(step: 3, relativeStartTime: 0.95, relativeDuration: 0.05, isFiltering: true),
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

    enum FilterState: Equatable {
        case on, off

        var isOn: Bool {
            switch self {
            case .on:
                return true
            case .off:
                return false
            }
        }
    }

    private enum ControlState: Equatable {
        /// Control is not visible, filtering is disabled.
        case off

        /// Actively filtering and control is docked to the top of the scroll view.
        case on

        /// Control is tracking scroll view offset, but gesture threshold has
        /// not been reached.
        case tracking(state: FilterState)

        case pending(newState: FilterState)

        case committed(newState: FilterState)

        case transitioning(newState: FilterState)

        fileprivate var affectsContentInset: Bool {
            filterState.isOn
        }

        fileprivate var filterState: FilterState {
            switch self {
            case .off, .tracking(state: .off), .pending(newState: .on), .committed(newState: .off), .transitioning(newState: .off):
                return .off
            case .on, .tracking(state: .on), .pending(newState: .off), .committed(newState: .on), .transitioning(newState: .on):
                return .on
            }
        }
    }

    private let animationFrames: [AnimationFrame]
    private let clearButton: ChatListFilterButton
    private let clearButtonContainer: UIView
    private let contentHeightConstraint: NSLayoutConstraint
    private let contentView: UIView
    private let imageContainer: UIView
    private let imageViews: [UIImageView]

    private var contentTranslationConstraint: NSLayoutConstraint!
    private var feedback: UIImpactFeedbackGenerator?
    private var filterIconAnimator: UIViewPropertyAnimator?
    private var previousClearButtonConfiguration: UIButton.Configuration?

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

    private(set) var fractionComplete: CGFloat = 0.0

    // For the forward phase of the gesture (pull to filter), `fractionComplete`
    // is in the range [0, 1]. For the reverse phase (pull to clear), the range
    // [1, 2] is used. This makes computing both content height (which defines
    // the clipping rect) and content translation very simple:
    //
    //     contentHeight = fractionComplete * preferredContentHeight
    //     contentTranslation: contentView.bottom = self.top + (fractionComplete * preferredContentHeight)
    private func updateFractionComplete() {
        var fraction: CGFloat {
            let position = max(0, -adjustedContentOffset.y)
            let limit = swipeGestureThreshold
            return min(1, position / limit)
        }

        switch state {
        case .off, .transitioning(newState: .off):
            fractionComplete = 0
        case .tracking(state: .off):
            fractionComplete = fraction
        case .on, .pending(newState: .on), .committed(newState: .on), .transitioning(newState: .on):
            fractionComplete = 1
        case .tracking(state: .on):
            fractionComplete = fraction + 1
        case .pending(newState: .off), .committed(newState: .off):
            fractionComplete = 2
        }
    }

    private var isDragging = false

    private var state = ControlState.off {
        didSet {
            if state != oldValue {
                updateFractionComplete()
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
        case .transitioning:
            return true
        case .off, .on, .tracking, .pending, .committed:
            return false
        }
    }

    /// Whether the control is in the filtering state or transitioning into it (i.e., pending).
    var isFiltering: Bool {
        state.filterState.isOn
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
        clearButton.configuration?.title = OWSLocalizedString("CHAT_LIST_FILTERED_BY_UNREAD_CLEAR_BUTTON", comment: "Button at top of chat list indicating the active filter is 'Filtered by Unread' and tapping will clear the filter")
        clearButton.isUserInteractionEnabled = false
        clearButton.setContentHuggingPriority(.required, for: .vertical)
        clearButton.showsClearIcon = true
        clearButton.translatesAutoresizingMaskIntoConstraints = false

        clearButtonContainer = UIView()
        clearButtonContainer.alpha = 0
        clearButtonContainer.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: .zero)

        clipsToBounds = true
        maximumContentSizeCategory = .extraExtraExtraLarge
        preservesSuperviewLayoutMargins = true

        addSubview(contentView)
        contentTranslationConstraint = contentView.bottomAnchor.constraint(equalTo: topAnchor, constant: 0)

        contentView.addSubview(imageContainer)
        contentView.insertSubview(clearButtonContainer, aboveSubview: imageContainer)

        clearButtonContainer.addSubview(clearButton)
        clearButton.autoPinEdgesToSuperviewEdges()

        NSLayoutConstraint.activate([
            contentHeightConstraint,
            contentTranslationConstraint,
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageContainer.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            imageContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            clearButtonContainer.topAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor),
            clearButtonContainer.bottomAnchor.constraint(lessThanOrEqualTo: contentView.layoutMarginsGuide.bottomAnchor),
            clearButtonContainer.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            clearButtonContainer.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor),
            clearButtonContainer.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
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

    func adjustedContentOffsetDidChange(_ adjustedContentOffset: CGPoint) {
        self.adjustedContentOffset = adjustedContentOffset
        guard !isAnimatingTransition else { return }

        updateContentOrigin()

        switch state {
        case .tracking(state: .off) where fractionComplete == 1 && isDragging:
            feedback?.impactOccurred()
            feedback = nil
            state = .pending(newState: .on)

            // Finish remaining 5% / 50 ms of animation
            filterIconAnimator?.pausesOnCompletion = true
            filterIconAnimator?.startAnimation()

            applyBounceEffect(to: imageContainer)

        case .tracking(state: .off):
            filterIconAnimator?.fractionComplete = min(fractionComplete, 0.95)

        case .tracking(state: .on) where fractionComplete == 2 && isDragging:
            feedback?.impactOccurred()
            feedback = nil
            state = .pending(newState: .off)

            previousClearButtonConfiguration = clearButton.configuration
            UIView.transition(with: clearButton, duration: 0.1, options: .transitionCrossDissolve) { [self] in
                var configuration = previousClearButtonConfiguration
                configuration?.baseForegroundColor = .Signal.label
                configuration?.baseBackgroundColor = .filterIconActiveBackground
                clearButton.configuration = configuration
            }

            applyBounceEffect(to: clearButtonContainer)

        default:
            break
        }
    }

    private func updateContentOrigin() {
        contentTranslationConstraint.constant = fractionComplete * preferredContentHeight
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
        guard state != .on else { return }

        showClearButton(animated: false)

        if animated {
            state = .transitioning(newState: .on)
            UIView.animate(withDuration: animationDuration()) { [self] in
                frame.height = preferredContentHeight
                updateContentInsetIfNecessary()
                updateContentOrigin()
                layoutIfNeeded()
            } completion: { [self] _ in
                state = .on
            }
        } else {
            state = .on
            updateContentInsetIfNecessary()
            updateContentOrigin()
        }
    }

    func stopFiltering(animated: Bool) {
        guard state != .off else { return }

        func cleanUp() {
            if let configuration = previousClearButtonConfiguration {
                previousClearButtonConfiguration = nil
                clearButton.configuration = configuration
            }
            imageContainer.alpha = 1
            cancelFilterIconAnimator()
        }

        clearButton.isUserInteractionEnabled = false

        if animated {
            state = .transitioning(newState: .off)
            UIView.animate(withDuration: animationDuration()) { [self] in
                clearButtonContainer.alpha = 0
                frame.height = 0
                updateContentInsetIfNecessary()
                updateContentOrigin()
                layoutIfNeeded()
            } completion: { [self] _ in
                state = .off
                cleanUp()
            }
        } else {
            clearButtonContainer.alpha = 0
            state = .off
            updateContentInsetIfNecessary()
            cleanUp()
        }
    }

    func draggingWillBegin(in scrollView: UIScrollView) {
        func prepareFeedback() {
            let feedback = UIImpactFeedbackGenerator(style: .heavy)
            feedback.prepare()
            self.feedback = feedback
        }

        switch state {
        case .off:
            state = .tracking(state: .off)
            setUpFilterIconAnimatorIfNecessary()
            prepareFeedback()
        case .on:
            state = .tracking(state: .on)
            prepareFeedback()
        default:
            break
        }
        isDragging = true
    }

    func draggingWillEnd(in scrollView: UIScrollView) {
        switch state {
        case let .pending(newState):
            delegate?.filterControlWillChangeState(to: newState)
            state = .committed(newState: newState)
        default:
            break
        }
    }

    func draggingDidEnd(in scrollView: UIScrollView) {
        switch state {
        case .tracking(state: .off):
            feedback = nil
            if fractionComplete <= 0 {
                cancelFilterIconAnimator()
                state = .off
            }
        case .committed(newState: .on):
            updateContentInsetIfNecessary()
            showClearButton(animated: true)
            state = .on
        case .tracking(state: .on):
            feedback = nil
            if fractionComplete <= 1 {
                state = .on
            }
        case .committed(newState: .off):
            stopFiltering(animated: true)
        default:
            break
        }
        isDragging = false
    }

    func scrollingDidStop(in scrollView: UIScrollView) {
        switch state {
        case .tracking(state: .off):
            cancelFilterIconAnimator()
            fallthrough
        case .committed(newState: .off):
            state = .off

        case .tracking(state: .on), .committed(newState: .on):
            state = .on

        default:
            break
        }
    }

    private func applyBounceEffect(to view: UIView) {
        UIView.animateKeyframes(withDuration: animationDuration(0.2), delay: 0) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.5) {
                let height = view.bounds.height
                let width = view.bounds.width
                view.transform = .init(scaleX: (width + 3) / width, y: (height + 3) / height)
            }

            UIView.addKeyframe(withRelativeStartTime: 0.5, relativeDuration: 0.5) {
                view.transform = .identity
            }
        }
    }

    private func showClearButton(animated: Bool) {
        guard animated else {
            UIView.performWithoutAnimation {
                clearButtonContainer.alpha = 1
                clearButton.isUserInteractionEnabled = true
                imageContainer.alpha = 0
            }
            return
        }

        let filterIconImageView = UIImageView(image: animationFrames.last!.image.withConfiguration(.filterIconDisappearing))
        let transitionView = TransitionEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        let endFrame = clearButtonContainer.frame

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

        transitionAnimator.addAnimations({ [clearButtonContainer] in
            clearButtonContainer.alpha = 1
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
