//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

open class InteractiveSheetViewController: OWSViewController {

    public enum Constants {
        fileprivate static let handleSize = CGSize(width: 36, height: 5)
        fileprivate static let handleInsideMargin: CGFloat = 12

        /// Max height of the sheet has its top this far from the safe area top of the screen.
        fileprivate static let extraTopPadding: CGFloat = 32

        public static let defaultMinHeight: CGFloat = 346

        fileprivate static let maxAnimationDuration: TimeInterval = 0.3

        /// Any absolute velocity below this amount counts as zero velocity, e.g. just releasing.
        fileprivate static let baseVelocityThreshhold: CGFloat = 200
        /// Any upwards velocity greater this that amount maximizes the sheet.
        fileprivate static let maximizeVelocityThreshold: CGFloat = 500
        /// Any downwards velocity greater than this amount dismisses the sheet.
        fileprivate static let dismissVelocityThreshold: CGFloat = 1000
    }

    private let sheetContainerView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 16
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.layer.masksToBounds = true
        return view
    }()

    private let sheetStackView: UIStackView = {
        let view = UIStackView()
        view.axis = .vertical
        return view
    }()

    public let contentView = UIView()

    open var interactiveScrollViews: [UIScrollView] { [] }

    open var sheetBackgroundColor: UIColor { Theme.actionSheetBackgroundColor }

    public weak var externalBackdropView: UIView?
    private lazy var _internalBackdropView = UIView()
    public var backdropView: UIView? { externalBackdropView ?? _internalBackdropView }
    public var backdropColor = Theme.backdropColor

    public var maxWidth: CGFloat { 512 }

    private let handle = UIView()
    private lazy var handleContainer = UIView()

    public required override init() {
        super.init()
        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    open func willDismissInteractively() {}

    // MARK: -

    public override func loadView() {
        view = UIView()
        view.backgroundColor = .clear

        view.addSubview(sheetContainerView)
        sheetContainerView.autoPinEdge(toSuperviewEdge: .bottom)
        sheetContainerView.autoHCenterInSuperview()
        sheetContainerView.backgroundColor = sheetBackgroundColor

        // Prefer to be full width, but don't exceed the maximum width
        sheetContainerView.autoSetDimension(.width, toSize: maxWidth, relation: .lessThanOrEqual)
        sheetContainerView.autoPinWidthToSuperview(relation: .lessThanOrEqual)
        let minScreenDimension = min(CurrentAppContext().frame.width, CurrentAppContext().frame.height)
        if minScreenDimension <= maxWidth {
            sheetContainerView.autoSetDimension(.width, toSize: minScreenDimension)
        }
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            sheetContainerView.autoPinWidthToSuperview()
        }

        sheetContainerView.addSubview(sheetStackView)
        sheetStackView.autoPinEdgesToSuperviewEdges()

        sheetStackView.addArrangedSubview(contentView)
        contentView.autoPinWidthToSuperview()

        handle.autoSetDimensions(to: Constants.handleSize)
        handle.layer.cornerRadius = Constants.handleSize.height / 2
        sheetStackView.insertArrangedSubview(handleContainer, at: 0)
        handleContainer.autoPinWidthToSuperview()
        handleContainer.addSubview(handle)
        handle.backgroundColor = Theme.tableView2PresentedSeparatorColor
        handle.autoPinHeightToSuperview(withMargin: Constants.handleInsideMargin)
        handle.autoHCenterInSuperview()

        // Support tapping the backdrop to cancel the sheet.
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapBackdrop(_:)))
        tapGestureRecognizer.delegate = self
        view.addGestureRecognizer(tapGestureRecognizer)

        // Setup handle for interactive dismissal / resizing
        setupInteractiveSizing()
    }

    open override func themeDidChange() {
        super.themeDidChange()

        handle.backgroundColor = Theme.tableView2PresentedSeparatorColor
        sheetContainerView.backgroundColor = sheetBackgroundColor
    }

    @objc
    func didTapBackdrop(_ sender: UITapGestureRecognizer) {
        willDismissInteractively()
        dismiss(animated: true)
    }

    // MARK: - Resize / Interactive Dismiss

    public final var allowsExpansion: Bool = true {
        didSet {
            if allowsExpansion {
                maxHeight = maximumAllowedHeight()
            } else {
                maxHeight = minHeight
            }
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
            self.minHeight = min(newValue, maximumAllowedHeight())
        }
    }

    public private(set) lazy final var maxHeight = maximumAllowedHeight()

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

    public func minimizeHeight(animated: Bool = true) {
        sheetCurrentHeightConstraint.constant = minHeight
        guard animated else {
            view.layoutIfNeeded()
            return
        }

        view.setNeedsUpdateConstraints()
        UIView.animate(
            withDuration: Constants.maxAnimationDuration,
            delay: 0,
            options: .curveEaseOut,
            animations: {
                self.view.layoutIfNeeded()
            }
        )
    }

    public func maximizeHeight(animated: Bool = true) {
        sheetCurrentHeightConstraint.constant = maxHeight
        guard animated else {
            view.layoutIfNeeded()
            return
        }

        view.setNeedsUpdateConstraints()
        UIView.animate(
            withDuration: Constants.maxAnimationDuration,
            delay: 0,
            options: .curveEaseOut,
            animations: {
                self.view.layoutIfNeeded()
            }
        )
    }

    // If either of these are set, min/max height changes will not take immediate effect.
    private var isInInteractiveTransition = false
    private var isDismissingFromPanGesture = false

    private var startingHeight: CGFloat?
    private var startingTranslation: CGFloat?

    private func setupInteractiveSizing() {
        view.addConstraints([sheetCurrentHeightConstraint, sheetHeightMinConstraint, sheetHeightMaxConstraint])

        sheetContainerView.autoSetDimension(.height, toSize: minimizedHeight, relation: .greaterThanOrEqual)

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

    private func maximumAllowedHeight() -> CGFloat {
        return CurrentAppContext().frame.height - (view.safeAreaInsets.top + Constants.extraTopPadding)
    }

    open override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        let oldMaxHeight = maxHeight
        let newMaxHeight = maximumAllowedHeight()
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
        case .began, .changed:
            guard beginInteractiveTransitionIfNecessary(sender),
                let startingHeight = startingHeight,
                let startingTranslation = startingTranslation else {
                    return resetInteractiveTransition(panningScrollView: panningScrollView)
            }

            // We're in an interactive transition, so don't let the scrollView scroll.
            if let panningScrollView = panningScrollView {
                panningScrollView.contentOffset.y = 0
                panningScrollView.showsVerticalScrollIndicator = false
            }

            // We may have panned some distance if we were scrolling before we started
            // this interactive transition. Offset the translation we use to move the
            // view by whatever the translation was when we started the interactive
            // portion of the gesture.
            let translation = sender.translation(in: view).y - startingTranslation

            var newHeight = startingHeight - translation
            if newHeight > maxHeight {
                newHeight = maxHeight
            }

            // If the height is decreasing, adjust the relevant view's proporitionally
            if newHeight < startingHeight {
                backdropView?.alpha = 1 - (startingHeight - newHeight) / startingHeight
            }

            // Update our height to reflect the new position
            sheetCurrentHeightConstraint.constant = newHeight
            view.layoutIfNeeded()
        case .ended, .cancelled, .failed:
            let currentHeight = sheetContainerView.height
            let currentVelocity = sender.velocity(in: view).y

            enum CompletionState { case growing, shrinking, dismissing }
            let completionState: CompletionState

            if currentVelocity <= -Constants.maximizeVelocityThreshold {
                completionState = .growing
            } else if currentVelocity >= Constants.dismissVelocityThreshold {
                completionState = .dismissing
            } else if currentHeight >= minHeight {
                if abs(currentVelocity) > Constants.baseVelocityThreshhold {
                    completionState = currentVelocity > 0 ? .shrinking : .growing
                } else {
                    completionState =
                        currentHeight < (maxHeight + minHeight) / 2
                        ? .shrinking : .growing
                }
            } else {
                if abs(currentVelocity) > Constants.baseVelocityThreshhold {
                    completionState = currentVelocity > 0 ? .dismissing : .shrinking
                } else {
                    completionState =
                        currentHeight < minHeight / 2
                        ? .dismissing : .shrinking
                }
            }

            let finalHeight: CGFloat
            switch completionState {
            case .dismissing:
                isDismissingFromPanGesture = true
                finalHeight = 0
            case .growing:
                finalHeight = maxHeight
            case .shrinking:
                finalHeight = minHeight
            }

            let remainingDistance = finalHeight - currentHeight

            // Calculate the time to complete the animation if we want to preserve
            // the user's velocity. If this time is too slow (e.g. the user was scrolling
            // very slowly) we'll default to `maxAnimationDuration`
            let remainingTime = TimeInterval(abs(remainingDistance / currentVelocity))

            UIView.animate(withDuration: min(remainingTime, Constants.maxAnimationDuration), delay: 0, options: .curveEaseOut, animations: {
                if remainingDistance < 0 {
                    self.sheetContainerView.frame.origin.y -= remainingDistance
                } else {
                    self.sheetCurrentHeightConstraint.constant = finalHeight
                    self.view.layoutIfNeeded()
                }

                self.backdropView?.alpha = completionState == .dismissing ? 0 : 1
            }) { _ in
                self.sheetCurrentHeightConstraint.constant = finalHeight
                self.view.layoutIfNeeded()

                if completionState == .dismissing {
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
            sheetCurrentHeightConstraint.constant = startingHeight
        }
    }

    private func beginInteractiveTransitionIfNecessary(_ sender: UIPanGestureRecognizer) -> Bool {
        let panningScrollView = interactiveScrollViews.first { $0.panGestureRecognizer == sender }

        // If we're at the top of the scrollView, the view is not
        // currently maximized, or we're panning outside of the scroll
        // view we want to do an interactive transition.
        guard
            (panningScrollView != nil && panningScrollView!.contentOffset.y <= 0)
            || sheetContainerView.height < maxHeight
            || panningScrollView == nil
        else {
            return false
        }

        if startingTranslation == nil {
            startingTranslation = sender.translation(in: view).y
        }

        if startingHeight == nil {
            startingHeight = sheetContainerView.height
        }
        isInInteractiveTransition = true
        return true
    }

    private func resetInteractiveTransition(panningScrollView: UIScrollView?) {
        startingTranslation = nil
        startingHeight = nil
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
            guard !sheetContainerView.frame.contains(point) else { return false }
            return true
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
