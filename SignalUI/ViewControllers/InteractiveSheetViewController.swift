//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

open class InteractiveSheetViewController: OWSViewController {

    public enum Constants {
        public static let handleSize = CGSize(width: 36, height: 5)
        public static let handleInsideMargin: CGFloat = 12
        public static let handleHeight = 2*handleInsideMargin + handleSize.height

        /// Max height of the sheet has its top this far from the safe area top of the screen.
        fileprivate static let extraTopPadding: CGFloat = 32

        public static let defaultMinHeight: CGFloat = 346

        /// Any absolute velocity below this amount counts as zero velocity, e.g. just releasing.
        fileprivate static let baseVelocityThreshold: CGFloat = 200
        /// Any upwards velocity greater this that amount maximizes the sheet.
        fileprivate static let maximizeVelocityThreshold: CGFloat = 500
        /// Any downwards velocity greater than this amount dismisses the sheet.
        fileprivate static let dismissVelocityThreshold: CGFloat = 1000
    }

    private lazy var sheetContainerView: UIView = {
        let view: UIView
        if let blurEffect = blurEffect {
            view = UIVisualEffectView(effect: blurEffect)
        } else {
            view = UIView()
        }
        view.layer.cornerRadius = 16
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.layer.masksToBounds = true
        return view
    }()

    private var sheetContainerContentView: UIView {
        return (sheetContainerView as? UIVisualEffectView)?.contentView ?? sheetContainerView
    }

    private let sheetStackView: UIStackView = {
        let view = UIStackView()
        view.axis = .vertical
        return view
    }()

    public let contentView = UIView()

    open var interactiveScrollViews: [UIScrollView] { [] }

    open var dismissesWithHighVelocitySwipe: Bool { false }
    open var shrinksWithHighVelocitySwipe: Bool { true }
    open var canBeDismissed: Bool { true }
    /// Allows taps above the sheet to pass through to the parent.
    open var canInteractWithParent: Bool { false }

    open var sheetBackgroundColor: UIColor { Theme.actionSheetBackgroundColor }
    open var handleBackgroundColor: UIColor { Theme.tableView2PresentedSeparatorColor }

    public weak var externalBackdropView: UIView?
    private lazy var _internalBackdropView = UIView()
    public var backdropView: UIView? { externalBackdropView ?? _internalBackdropView }
    public var backdropColor = Theme.backdropColor

    public var maxWidth: CGFloat { 512 }

    private let handle = UIView()
    private lazy var handleContainer = UIView()

    private let blurEffect: UIBlurEffect?

    public weak var sheetPanDelegate: SheetPanDelegate?
    public weak var dismissalDelegate: (any SheetDismissalDelegate)?

    public init(blurEffect: UIBlurEffect? = nil) {
        self.blurEffect = blurEffect
        super.init()
        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    open func willDismissInteractively() {}

    // MARK: -

    public class SheetView: UIView {
        weak var interactiveSheetViewController: InteractiveSheetViewController?

        private let canInteractWithParent: Bool

        init(
            canInteractWithParent: Bool,
            interactiveSheetViewController: InteractiveSheetViewController
        ) {
            self.canInteractWithParent = canInteractWithParent
            self.interactiveSheetViewController = interactiveSheetViewController
            super.init(frame: .zero)
        }

        public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard self.canInteractWithParent else {
                return super.hitTest(point, with: event)
            }

            guard
                let interactiveSheetViewController,
                let presentingView = interactiveSheetViewController.presentingViewController?.view
            else {
                owsFailDebug("A parent view controller is missing")
                return super.hitTest(point, with: event)
            }

            let sheetContent = interactiveSheetViewController.sheetContainerView
            let pointInSheet = self.convert(point, to: sheetContent)
            if sheetContent.bounds.contains(pointInSheet) {
                // Hit in sheet
                return super.hitTest(point, with: event)
            }

            // Hit in parent
            return presentingView.hitTest(point, with: event)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    private var maxWidthConstraint: NSLayoutConstraint?
    open override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        maxWidthConstraint?.autoRemove()
        let minScreenDimension = min(CurrentAppContext().frame.width, CurrentAppContext().frame.height)
        if minScreenDimension <= maxWidth {
            maxWidthConstraint = sheetContainerView.autoSetDimension(.width, toSize: minScreenDimension)
        }
    }

    public override func loadView() {
        let sheetView = SheetView(
            canInteractWithParent: self.canInteractWithParent,
            interactiveSheetViewController: self
        )
        view = sheetView
        view.backgroundColor = .clear

        view.addSubview(sheetContainerView)
        sheetCurrentOffsetConstraint = sheetContainerView.autoPinEdge(toSuperviewEdge: .bottom)
        sheetContainerView.autoHCenterInSuperview()
        sheetContainerView.backgroundColor = sheetBackgroundColor

        // Prefer to be full width, but don't exceed the maximum width
        sheetContainerView.autoSetDimension(.width, toSize: maxWidth, relation: .lessThanOrEqual)
        sheetContainerView.autoPinWidthToSuperview(relation: .lessThanOrEqual)

        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            sheetContainerView.autoPinWidthToSuperview()
        }

        sheetContainerContentView.addSubview(sheetStackView)
        sheetStackView.autoPinEdgesToSuperviewEdges()

        sheetStackView.addArrangedSubview(contentView)
        contentView.autoPinWidthToSuperview()

        handle.autoSetDimensions(to: Constants.handleSize)
        handle.layer.cornerRadius = Constants.handleSize.height / 2
        sheetStackView.insertArrangedSubview(handleContainer, at: 0)
        handleContainer.autoPinWidthToSuperview()
        handleContainer.addSubview(handle)
        handle.backgroundColor = handleBackgroundColor
        handle.autoPinHeightToSuperview(withMargin: Constants.handleInsideMargin)
        handle.autoHCenterInSuperview()

        // Support tapping the backdrop to cancel the sheet.
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapBackdrop(_:)))
        tapGestureRecognizer.delegate = self
        view.addGestureRecognizer(tapGestureRecognizer)

        // Setup handle for interactive dismissal / resizing
        setupInteractiveSizing()
    }

    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        dismissalDelegate?.didDismissPresentedSheet()
    }

    open override func themeDidChange() {
        super.themeDidChange()

        handle.backgroundColor = handleBackgroundColor
        sheetContainerView.backgroundColor = sheetBackgroundColor
    }

    @objc
    private func didTapBackdrop(_ sender: UITapGestureRecognizer) {
        guard canBeDismissed else {
            return
        }
        willDismissInteractively()
        dismiss(animated: true)
    }

    // MARK: - Resize / Interactive Dismiss

    private func updateMaxHeight() {
        if allowsExpansion {
            maxHeight = maximumPreferredHeight()
        } else {
            maxHeight = minHeight
        }
    }

    public final var allowsExpansion: Bool = true {
        didSet {
            self.updateMaxHeight()
            guard isViewLoaded else {
                return
            }
            if
                !isInInteractiveTransition,
                !isDismissingFromPanGesture,
                sheetCurrentHeightConstraint.constant > minHeight
            {
                sheetCurrentHeightConstraint.constant = minHeight
            }
        }
    }

    private var minHeight: CGFloat = Constants.defaultMinHeight {
        didSet {
            if !allowsExpansion {
                maxHeight = minHeight
            }
            guard isViewLoaded else {
                return
            }
            sheetHeightMinConstraint.constant = minHeight
            if
                !isInInteractiveTransition,
                !isDismissingFromPanGesture,
                sheetCurrentHeightConstraint.constant == oldValue
                    || sheetCurrentHeightConstraint.constant < minHeight
            {
                sheetCurrentHeightConstraint.constant = minHeight
            }
        }
    }

    private var externalMinHeight: CGFloat?

    public final var minimizedHeight: CGFloat {
        get {
            return minHeight
        }
        set {
            externalMinHeight = newValue
            self.minHeight = min(newValue, maximumPreferredHeight())
        }
    }

    public private(set) lazy final var maxHeight = maximumPreferredHeight()

    private lazy var sheetHeightMinConstraint = sheetContainerView.autoSetDimension(
        .height,
        toSize: minHeight,
        relation: .greaterThanOrEqual
    )

    private lazy var sheetHeightMaxConstraint = sheetContainerView.autoSetDimension(
        .height,
        toSize: maxHeight,
        relation: .lessThanOrEqual
    )

    private lazy var sheetCurrentHeightConstraint = sheetContainerView.autoSetDimension(.height, toSize: minHeight)

    private var sheetCurrentOffsetConstraint: NSLayoutConstraint?

    private var currentVisibleHeight: CGFloat {
        sheetCurrentHeightConstraint.constant - (sheetCurrentOffsetConstraint?.constant ?? 0)
    }

    public func minimizeHeight(animated: Bool = true) {
        self.cancelAnimationAndUpdateConstraints()

        sheetCurrentHeightConstraint.constant = minHeight
        guard animated else {
            view.layoutIfNeeded()
            self.heightDidChange(to: .min)
            return
        }

        view.setNeedsUpdateConstraints()
        self.animate {
            self.view.layoutIfNeeded()
            self.heightDidChange(to: .min)
        }
    }

    public func maximizeHeight(animated: Bool = true, completion: (() -> Void)? = nil) {
        self.cancelAnimationAndUpdateConstraints()

        sheetCurrentHeightConstraint.constant = maxHeight
        guard animated else {
            view.layoutIfNeeded()
            self.heightDidChange(to: .max)
            completion?()
            return
        }

        view.setNeedsUpdateConstraints()
        self.animate(
            animations: {
                self.view.layoutIfNeeded()
                self.heightDidChange(to: .max)
            },
            completion: completion
        )
    }

    /// When `true`, uses a slower, smoother, interruptible animation curve for
    /// height changes using a UIViewPropertyAnimator. This can have unintended
    /// side effects, however, such as reloading table content in an animation
    /// block resulting is strange behavior, so it is disabled by default.
    public var animationsShouldBeInterruptible = false

    private var animator: UIViewPropertyAnimator?

    public func animate(
        animations: @escaping () -> Void,
        completion: (() -> Void)? = nil
    ) {
        if animationsShouldBeInterruptible {
            let animator = UIViewPropertyAnimator(
                duration: 0.5,
                controlPoint1: .init(x: 0.25, y: 1),
                controlPoint2: .init(x: 0.25, y: 1)
            )
            animator.addAnimations(animations)
            animator.addCompletion { [weak self] _ in
                self?.animator = nil
                completion?()
            }
            animator.startAnimation()
            self.animator = animator
        } else {
            UIView.animate(
                withDuration: 0.3,
                delay: 0,
                usingSpringWithDamping: 4 * .pi / 0.3,
                initialSpringVelocity: 0,
                animations: animations,
                completion: completion.map { closure in { _ in closure() } }
            )
        }
    }

    // If either of these are set, min/max height changes will not take immediate effect.
    private var isInInteractiveTransition = false
    private var isDismissingFromPanGesture = false

    private var startingHeight: CGFloat?
    private var startingOffset: CGFloat?
    private var startingTranslation: CGFloat?

    private func setupInteractiveSizing() {
        view.addConstraints([sheetCurrentHeightConstraint, sheetHeightMinConstraint, sheetHeightMaxConstraint])

        // Create a pan gesture to handle when the user interacts with the
        // view outside of any scroll views we want to follow.
        let panGestureRecognizer = DirectionalPanGestureRecognizer(direction: .vertical, target: self, action: #selector(handlePan))
        view.addGestureRecognizer(panGestureRecognizer)
        panGestureRecognizer.delegate = self

        // We also want to handle the pan gesture for all of the scroll
        // views, so we can do a nice scroll to dismiss gesture, and
        // so we can transfer any initial scrolling into maximizing
        // the view.
        interactiveScrollViews.forEach { $0.panGestureRecognizer.addTarget(self, action: #selector(handlePan)) }
    }

    /// The maximum height the sheet wants to be. It can be "sprung" past this
    /// point up until `maximumAllowedHeight`, if that is higher than this.
    ///
    /// By default, it returns `maximumAllowedHeight()`.
    open func maximumPreferredHeight() -> CGFloat {
        self.maximumAllowedHeight()
    }

    /// The maximum height the sheet can ever get.
    open func maximumAllowedHeight() -> CGFloat {
        return CurrentAppContext().frame.height - (view.safeAreaInsets.top + Constants.extraTopPadding)
    }

    open override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        let oldMaxHeight = maxHeight
        let newMaxHeight = maximumPreferredHeight()
        if allowsExpansion {
            maxHeight = newMaxHeight
        }
        if minHeight > maxHeight {
            minHeight = maxHeight
        } else if minHeight == oldMaxHeight, let externalMinHeight = externalMinHeight {
            minimizedHeight = externalMinHeight
        }

        guard isViewLoaded else {
            return
        }
        sheetHeightMaxConstraint.constant = maxHeight
        if
            !isInInteractiveTransition,
            !isDismissingFromPanGesture,
            (
                sheetCurrentHeightConstraint.constant == oldMaxHeight
                && sheetCurrentHeightConstraint.constant != minHeight
            )
                || sheetCurrentHeightConstraint.constant > maxHeight
        {
            sheetCurrentHeightConstraint.constant = maxHeight
        }
    }

    @objc
    private func handlePan(_ sender: UIPanGestureRecognizer) {
        let panningScrollView = interactiveScrollViews.first { $0.panGestureRecognizer == sender }

        switch sender.state {
        case .began:
            self.cancelAnimationAndUpdateConstraints()
            sheetPanDelegate?.sheetPanDidBegin()
            fallthrough
        case .changed:
            guard
                beginInteractiveTransitionIfNecessary(sender),
                var startingHeight,
                let startingOffset,
                let startingTranslation
            else {
                return resetInteractiveTransition(panningScrollView: panningScrollView)
            }

            // We're in an interactive transition, so don't let the scrollView scroll.
            if let panningScrollView = panningScrollView {
                panningScrollView.contentOffset.y = -panningScrollView.contentInset.top
                panningScrollView.showsVerticalScrollIndicator = false
            }

            // We may have panned some distance if we were scrolling before we started
            // this interactive transition. Offset the translation we use to move the
            // view by whatever the translation was when we started the interactive
            // portion of the gesture.
            let translation = sender.translation(in: view).y - startingTranslation

            startingHeight -= startingOffset

            let resistanceDivisor: CGFloat = 3
            func adjustStartingHeightForBeingOutOfBounds(bound: CGFloat) {
                let distanceOutOfBounds = startingHeight - bound
                startingHeight = bound + distanceOutOfBounds * resistanceDivisor
            }

            if startingHeight > self.maxHeight {
                adjustStartingHeightForBeingOutOfBounds(bound: self.maxHeight)
            } else if !canBeDismissed && startingHeight < self.minHeight {
                adjustStartingHeightForBeingOutOfBounds(bound: self.minHeight)
            }

            var newOffset = 0 as CGFloat
            var newHeight = startingHeight - translation

            // Add resistance above the max preferred height
            if newHeight > maxHeight {
                newHeight = maxHeight + (newHeight - maxHeight) / resistanceDivisor
            }

            // Don't go past the max allowed height
            let maxAllowedHeight = self.maximumAllowedHeight()
            if newHeight > maxAllowedHeight {
                newHeight = maxAllowedHeight
            }

            // Don't shrink below minHeight and instead offset down
            if newHeight < minHeight {
                newOffset = minHeight - newHeight
                newHeight = minHeight
            }

            // Add resistance below the min height
            if !canBeDismissed {
                newOffset /= resistanceDivisor
            }

            let newVisibleHeight = newHeight - newOffset

            if newVisibleHeight != startingHeight {
                heightDidChange(to: .height(newHeight))
            }

            // If the height is decreasing, adjust the relevant view's proportionally
            if newHeight < startingHeight {
                backdropView?.alpha = 1 - (startingHeight - newVisibleHeight) / startingHeight
            }

            // Update our offset/height to reflect the new position
            sheetCurrentOffsetConstraint?.constant = newOffset
            sheetCurrentHeightConstraint.constant = newHeight
            view.layoutIfNeeded()
        case .ended, .cancelled, .failed:
            sheetPanDelegate?.sheetPanDidEnd()
            let currentVisibleHeight = self.currentVisibleHeight
            let currentVelocity = sender.velocity(in: view).y

            enum CompletionState { case growing, shrinking, dismissing }
            let completionState: CompletionState

            if currentVelocity <= -Constants.maximizeVelocityThreshold {
                completionState = .growing
            } else if
                canBeDismissed,
                currentVelocity >= Constants.dismissVelocityThreshold,
                (dismissesWithHighVelocitySwipe || isInInteractiveTransition)
            {
                completionState = .dismissing
            } else if currentVisibleHeight >= minHeight {
                if
                    currentVelocity > Constants.baseVelocityThreshold,
                    shrinksWithHighVelocitySwipe,
                    panningScrollView.map({ $0.contentOffset.y <= -$0.contentInset.top }) ?? true
                {
                    completionState = .shrinking
                } else if currentVelocity < -Constants.baseVelocityThreshold {
                    completionState = .growing
                } else {
                    completionState =
                        currentVisibleHeight < (maxHeight + minHeight) / 2
                        ? .shrinking : .growing
                }
            } else {
                if abs(currentVelocity) > Constants.baseVelocityThreshold {
                    completionState = currentVelocity > 0 && canBeDismissed ? .dismissing : .shrinking
                } else {
                    completionState =
                        currentVisibleHeight < minHeight / 2 && canBeDismissed
                        ? .dismissing : .shrinking
                }
            }

            self.updateMaxHeight()

            let finalOffset: CGFloat
            let finalHeight: CGFloat
            switch completionState {
            case .dismissing:
                isDismissingFromPanGesture = true
                finalOffset = minHeight
                finalHeight = minHeight
            case .growing:
                finalOffset = 0
                finalHeight = maxHeight
            case .shrinking:
                finalOffset = 0
                finalHeight = minHeight
            }

            sheetPanDelegate?.sheetPanDecelerationDidBegin()
            self.animate {
                self.sheetCurrentOffsetConstraint?.constant = finalOffset
                self.sheetCurrentHeightConstraint.constant = finalHeight
                self.view.layoutIfNeeded()

                switch completionState {
                case .growing:
                    self.heightDidChange(to: .max)
                case .shrinking, .dismissing:
                    self.heightDidChange(to: .min)
                }

                self.backdropView?.alpha = completionState == .dismissing ? 0 : 1
            } completion: {
                self.sheetPanDelegate?.sheetPanDecelerationDidEnd()
                self.heightDidChange(to: .height(finalHeight))
                if completionState == .dismissing && self.canBeDismissed {
                    self.willDismissInteractively()
                    self.dismiss(animated: true, completion: { [weak self] in
                        self?.isDismissingFromPanGesture = false
                    })
                }
            }

            resetInteractiveTransition(panningScrollView: panningScrollView)
        default:
            resetInteractiveTransition(panningScrollView: panningScrollView)

            backdropView?.alpha = 1

            guard let startingHeight = startingHeight else { break }
            sheetCurrentOffsetConstraint?.constant = 0
            sheetCurrentHeightConstraint.constant = startingHeight
            heightDidChange(to: .height(startingHeight))
        }
    }

    public func cancelAnimationAndUpdateConstraints() {
        guard let animator else { return }
        animator.stopAnimation(false)
        animator.finishAnimation(at: .current)
        self.updateConstraintsAfterCanceledAnimation()
    }

    private func updateConstraintsAfterCanceledAnimation() {
        let sheetBottom = self.view.convert(sheetContainerView.frame, from: self.view).maxY
        let offset = sheetBottom - self.view.frame.maxY
        sheetCurrentOffsetConstraint?.constant = offset

        sheetCurrentHeightConstraint.constant = sheetContainerView.height

        self.view.layoutIfNeeded()
    }

    public final func refreshMaxHeight() {
        guard !isInInteractiveTransition else { return }

        let oldMaxHeight = self.maxHeight
        self.maxHeight = maximumPreferredHeight()
        self.sheetHeightMaxConstraint.constant = self.maxHeight
        if self.sheetCurrentHeightConstraint.constant == oldMaxHeight {
            self.cancelAnimationAndUpdateConstraints()
            self.sheetCurrentOffsetConstraint?.constant = 0
            self.sheetCurrentHeightConstraint.constant = self.maxHeight
            self.animate {
                self.view.setNeedsLayout()
                self.view.layoutIfNeeded()
                self.heightDidChange(to: .max)
            }
        }
    }

    public enum SheetHeight {
        case min
        case height(CGFloat)
        case max
    }

    open func heightDidChange(to height: SheetHeight) {}

    private func beginInteractiveTransitionIfNecessary(_ sender: UIPanGestureRecognizer) -> Bool {
        let panningScrollView = interactiveScrollViews.first { $0.panGestureRecognizer == sender }

        // If we're at the top of the scrollView, the view is not
        // currently maximized, or we're panning outside of the scroll
        // view we want to do an interactive transition.

        var isScrollingPastTop: Bool {
            guard let panningScrollView else { return false }
            return panningScrollView.contentOffset.y <= 0
        }

        var isScrollingPastBottom: Bool {
            guard let panningScrollView else { return false }
            let hasScrollableContent = panningScrollView.contentSize.height <= panningScrollView.height
            let contentIsPastBottom = panningScrollView.contentOffset.y + panningScrollView.height > panningScrollView.contentSize.height
            return hasScrollableContent && contentIsPastBottom
        }

        guard
            isScrollingPastTop
            || isScrollingPastBottom
            || currentVisibleHeight < maxHeight
            || panningScrollView == nil
        else {
            return false
        }

        if !isInInteractiveTransition {
            self.updateMaxHeight()
        }

        if startingTranslation == nil {
            startingTranslation = sender.translation(in: view).y
        }

        if startingHeight == nil {
            startingHeight = sheetContainerView.height
        }
        if startingOffset == nil {
            startingOffset = sheetCurrentOffsetConstraint?.constant ?? 0
        }
        isInInteractiveTransition = true
        return true
    }

    private func resetInteractiveTransition(panningScrollView: UIScrollView?) {
        startingTranslation = nil
        startingHeight = nil
        startingOffset = nil
        isInInteractiveTransition = false
        panningScrollView?.showsVerticalScrollIndicator = true
    }
}

// MARK: -
extension InteractiveSheetViewController: UIGestureRecognizerDelegate {
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        switch gestureRecognizer {
        case is UITapGestureRecognizer:
            let point = gestureRecognizer.location(in: view)
            return !sheetContainerView.frame.contains(point)
        default:
            return true
        }
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        switch gestureRecognizer {
        case is UIPanGestureRecognizer:
            return interactiveScrollViews.map { $0.panGestureRecognizer }.contains(otherGestureRecognizer)
        default:
            return false
        }
    }
}

// MARK: -

private class InteractiveSheetAnimationController: UIPresentationController {

    var backdropView: UIView? {
        guard let vc = presentedViewController as? InteractiveSheetViewController else { return nil }
        return vc.backdropView
    }

    var isUsingExternalBackdropView: Bool {
        guard let vc = presentedViewController as? InteractiveSheetViewController else { return false }
        return vc.externalBackdropView != nil
    }

    init(presentedViewController: UIViewController, presenting presentingViewController: UIViewController?, backdropColor: UIColor? = Theme.backdropColor) {
        super.init(presentedViewController: presentedViewController, presenting: presentingViewController)
        backdropView?.backgroundColor = backdropColor
    }

    override func presentationTransitionWillBegin() {
        if !isUsingExternalBackdropView, let containerView = containerView, let backdropView = backdropView {
            backdropView.alpha = 0
            containerView.addSubview(backdropView)
            backdropView.autoPinEdgesToSuperviewEdges()
            containerView.layoutIfNeeded()
        }

        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.backdropView?.alpha = 1
        }, completion: nil)
    }

    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.backdropView?.alpha = 0
        }, completion: { _ in
            self.backdropView?.removeFromSuperview()
        })
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard let presentedView = presentedView else { return }
        coordinator.animate(alongsideTransition: { _ in
            presentedView.frame = self.frameOfPresentedViewInContainerView
            presentedView.layoutIfNeeded()
        }, completion: nil)
    }
}

extension InteractiveSheetViewController: UIViewControllerTransitioningDelegate {
    open func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        let controller = InteractiveSheetAnimationController(presentedViewController: presented, presenting: presenting, backdropColor: self.backdropColor)
        return controller
    }
}

public protocol SheetPanDelegate: AnyObject {
    func sheetPanDidBegin()
    func sheetPanDidEnd()
    func sheetPanDecelerationDidBegin()
    func sheetPanDecelerationDidEnd()
}
