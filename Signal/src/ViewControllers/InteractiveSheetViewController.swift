//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

public class InteractiveSheetViewController: OWSViewController {
    public let contentView = UIView()

    public var interactiveScrollViews: [UIScrollView] { [] }

    public weak var externalBackdropView: UIView?
    private lazy var _internalBackdropView = UIView()
    public var backdropView: UIView? { externalBackdropView ?? _internalBackdropView }

    public var maxWidth: CGFloat { 512 }
    public var minHeight: CGFloat { 346 }

    public var allowsInteractiveDismisssal: Bool { true }

    public var renderExternalHandle: Bool { true }
    private lazy var handle = UIView()

    public required override init() {
        super.init()
        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    public func willDismissInteractively() {}

    // MARK: -

    public override func loadView() {
        view = UIView()
        view.backgroundColor = .clear

        view.addSubview(contentView)
        contentView.autoPinEdge(toSuperviewEdge: .bottom)
        contentView.autoHCenterInSuperview()
        contentView.autoMatch(.height, to: .height, of: view, withOffset: 0, relation: .lessThanOrEqual)
        contentView.backgroundColor = Theme.actionSheetBackgroundColor

        // Prefer to be full width, but don't exceed the maximum width
        contentView.autoSetDimension(.width, toSize: maxWidth, relation: .lessThanOrEqual)
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            contentView.autoPinWidthToSuperview()
        }

        contentView.layer.cornerRadius = 16
        contentView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        contentView.layer.masksToBounds = true

        // Support tapping the backdrop to cancel the sheet.
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapBackdrop(_:)))
        tapGestureRecognizer.delegate = self
        view.addGestureRecognizer(tapGestureRecognizer)

        // Setup handle for interactive dismissal / resizing
        setupInteractiveSizing()
    }

    @objc func didTapBackdrop(_ sender: UITapGestureRecognizer) {
        guard allowsInteractiveDismisssal else { return }
        willDismissInteractively()
        dismiss(animated: true)
    }

    // MARK: - Resize / Interactive Dismiss

    var heightConstraint: NSLayoutConstraint?
    var minimizedHeight: CGFloat {
        return min(maximizedHeight, minHeight)
    }
    var maximizedHeight: CGFloat {
        return CurrentAppContext().frame.height - (view.safeAreaInsets.top + 32)
    }

    let maxAnimationDuration: TimeInterval = 0.2
    private var startingHeight: CGFloat?
    private var startingTranslation: CGFloat?

    private func setupInteractiveSizing() {
        heightConstraint = contentView.autoSetDimension(.height, toSize: minimizedHeight)

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

        if renderExternalHandle {
            handle.backgroundColor = .ows_whiteAlpha80
            handle.autoSetDimensions(to: CGSize(width: 56, height: 5))
            handle.layer.cornerRadius = 5 / 2
            view.addSubview(handle)
            handle.autoHCenterInSuperview()
            handle.autoPinEdge(.bottom, to: .top, of: contentView, withOffset: -8)
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
            if newHeight > maximizedHeight {
                newHeight = maximizedHeight
            }

            // If the height is decreasing, adjust the relevant view's proporitionally
            if newHeight < startingHeight {
                backdropView?.alpha = 1 - (startingHeight - newHeight) / startingHeight
            }

            // Update our height to reflect the new position
            heightConstraint?.constant = newHeight
            view.layoutIfNeeded()
        case .ended, .cancelled, .failed:
            guard let startingHeight = startingHeight else { break }

            let dismissThreshold = startingHeight * 0.5
            let growThreshold = startingHeight * 1.5
            let velocityThreshold: CGFloat = 500

            let currentHeight = contentView.height
            let currentVelocity = sender.velocity(in: view).y

            enum CompletionState { case growing, dismissing, cancelling }
            let completionState: CompletionState

            if abs(currentVelocity) >= velocityThreshold {
                if currentVelocity < 0 {
                    completionState = .growing
                } else {
                    completionState = allowsInteractiveDismisssal ? .dismissing : .cancelling
                }
            } else if currentHeight >= growThreshold {
                completionState = .growing
            } else if currentHeight <= dismissThreshold, allowsInteractiveDismisssal {
                completionState = .dismissing
            } else {
                completionState = .cancelling
            }

            let finalHeight: CGFloat
            switch completionState {
            case .dismissing:
                finalHeight = 0
            case .growing:
                finalHeight = maximizedHeight
            case .cancelling:
                finalHeight = startingHeight
            }

            let remainingDistance = finalHeight - currentHeight

            // Calculate the time to complete the animation if we want to preserve
            // the user's velocity. If this time is too slow (e.g. the user was scrolling
            // very slowly) we'll default to `maxAnimationDuration`
            let remainingTime = TimeInterval(abs(remainingDistance / currentVelocity))

            UIView.animate(withDuration: min(remainingTime, maxAnimationDuration), delay: 0, options: .curveEaseOut, animations: {
                if remainingDistance < 0 {
                    self.contentView.frame.origin.y -= remainingDistance
                    self.handle.frame.origin.y -= remainingDistance
                } else {
                    self.heightConstraint?.constant = finalHeight
                    self.view.layoutIfNeeded()
                }

                self.backdropView?.alpha = completionState == .dismissing ? 0 : 1
            }) { _ in
                owsAssertDebug(completionState != .dismissing || self.allowsInteractiveDismisssal)

                self.heightConstraint?.constant = finalHeight
                self.view.layoutIfNeeded()

                if completionState == .dismissing {
                    self.willDismissInteractively()
                    self.dismiss(animated: true, completion: nil)
                }
            }

            resetInteractiveTransition(panningScrollView: panningScrollView)
        default:
            resetInteractiveTransition(panningScrollView: panningScrollView)

            backdropView?.alpha = 1

            guard let startingHeight = startingHeight else { break }
            heightConstraint?.constant = startingHeight
        }
    }

    private func beginInteractiveTransitionIfNecessary(_ sender: UIPanGestureRecognizer) -> Bool {
        let panningScrollView = interactiveScrollViews.first { $0.panGestureRecognizer == sender }

        // If we're at the top of the scrollView, the the view is not
        // currently maximized, or we're panning outside of the scroll
        // view we want to do an interactive transition.
        guard (panningScrollView != nil && panningScrollView!.contentOffset.y <= 0)
            || contentView.height < maximizedHeight
            || panningScrollView == nil else { return false }

        if startingTranslation == nil {
            startingTranslation = sender.translation(in: view).y
        }

        if startingHeight == nil {
            startingHeight = contentView.height
        }

        return true
    }

    private func resetInteractiveTransition(panningScrollView: UIScrollView?) {
        startingTranslation = nil
        startingHeight = nil
        panningScrollView?.showsVerticalScrollIndicator = true
    }
}

// MARK: -
extension InteractiveSheetViewController: UIGestureRecognizerDelegate {
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        switch gestureRecognizer {
        case is UITapGestureRecognizer:
            let point = gestureRecognizer.location(in: view)
            guard !contentView.frame.contains(point) else { return false }
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

    override init(presentedViewController: UIViewController, presenting presentingViewController: UIViewController?) {
        super.init(presentedViewController: presentedViewController, presenting: presentingViewController)
        backdropView?.backgroundColor = Theme.backdropColor
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
    public func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        return InteractiveSheetAnimationController(presentedViewController: presented, presenting: presenting)
    }
}
