//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalUI
import UIKit

public class InteractiveSheetViewController: OWSViewController {
    private let handleHeight: CGFloat = 5
    private let handleInsideMargin: CGFloat = 12

    public enum HandlePosition {
        case outside
        case inside
    }

    private let contentContainerView: UIStackView = {
        let view = UIStackView()
        view.axis = .vertical
        return view
    }()

    public let contentView = UIView()

    public var interactiveScrollViews: [UIScrollView] { [] }

    var sheetBackgroundColor: UIColor { Theme.actionSheetBackgroundColor }

    public weak var externalBackdropView: UIView?
    private lazy var _internalBackdropView = UIView()
    public var backdropView: UIView? { externalBackdropView ?? _internalBackdropView }
    public var backdropColor = Theme.backdropColor

    public var maxWidth: CGFloat { 512 }
    public var minHeight: CGFloat { 346 }

    public var allowsInteractiveDismisssal: Bool { true }

    var handlePosition: HandlePosition { .inside }
    private let handle = UIView()
    private lazy var handleContainer = UIView()

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

        view.addSubview(contentContainerView)
        contentContainerView.autoPinEdge(toSuperviewEdge: .bottom)
        contentContainerView.autoHCenterInSuperview()
        contentContainerView.backgroundColor = sheetBackgroundColor

        let autoMatchHeightOffset: CGFloat
        switch handlePosition {
        case .outside:
            autoMatchHeightOffset = 0
        case .inside:
            autoMatchHeightOffset = -2 * (handleHeight + handleInsideMargin + handleInsideMargin)
        }
        contentContainerView.autoMatch(.height, to: .height, of: view, withOffset: autoMatchHeightOffset, relation: .lessThanOrEqual)

        // Prefer to be full width, but don't exceed the maximum width
        contentContainerView.autoSetDimension(.width, toSize: maxWidth, relation: .lessThanOrEqual)
        contentContainerView.autoPinWidthToSuperview(relation: .lessThanOrEqual)
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            contentContainerView.autoPinWidthToSuperview()
        }

        contentContainerView.layer.cornerRadius = 16
        contentContainerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        contentContainerView.layer.masksToBounds = true

        contentContainerView.addArrangedSubview(contentView)
        contentView.autoPinWidthToSuperview()

        handle.autoSetDimensions(to: CGSize(width: 36, height: handleHeight))
        handle.layer.cornerRadius = handleHeight / 2
        switch handlePosition {
        case .outside:
            view.addSubview(handle)
            handle.backgroundColor = .ows_whiteAlpha80
            handle.autoPinEdge(.bottom, to: .top, of: contentContainerView, withOffset: -8)
        case .inside:
            contentContainerView.insertArrangedSubview(handleContainer, at: 0)
            handleContainer.autoPinWidthToSuperview()
            handleContainer.addSubview(handle)
            handleContainer.backgroundColor = contentContainerView.backgroundColor
            handleContainer.isOpaque = true
            handle.backgroundColor = Theme.tableView2PresentedSeparatorColor
            handle.autoPinHeightToSuperview(withMargin: handleInsideMargin)
        }
        handle.autoHCenterInSuperview()

        // Support tapping the backdrop to cancel the sheet.
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapBackdrop(_:)))
        tapGestureRecognizer.delegate = self
        view.addGestureRecognizer(tapGestureRecognizer)

        // Setup handle for interactive dismissal / resizing
        setupInteractiveSizing()
    }

    public override func themeDidChange() {
        super.themeDidChange()

        contentContainerView.backgroundColor = sheetBackgroundColor

        switch handlePosition {
        case .outside:
            break
        case .inside:
            handleContainer.backgroundColor = contentContainerView.backgroundColor
            handle.backgroundColor = Theme.tableView2PresentedSeparatorColor
        }
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

    public func maximizeHeight() {
        heightConstraint?.constant = maximizedHeight
        view.layoutIfNeeded()
    }

    let maxAnimationDuration: TimeInterval = 0.2
    private var startingHeight: CGFloat?
    private var startingTranslation: CGFloat?

    private func setupInteractiveSizing() {
        heightConstraint = contentContainerView.autoSetDimension(.height, toSize: minimizedHeight)

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

            let currentHeight = contentContainerView.height
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
                    self.contentContainerView.frame.origin.y -= remainingDistance
                    switch self.handlePosition {
                    case .outside:
                        self.handle.frame.origin.y -= remainingDistance
                    case .inside:
                        break
                    }
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

        // If we're at the top of the scrollView, the view is not
        // currently maximized, or we're panning outside of the scroll
        // view we want to do an interactive transition.
        guard (panningScrollView != nil && panningScrollView!.contentOffset.y <= 0)
            || contentContainerView.height < maximizedHeight
            || panningScrollView == nil else { return false }

        if startingTranslation == nil {
            startingTranslation = sender.translation(in: view).y
        }

        if startingHeight == nil {
            startingHeight = contentContainerView.height
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
            guard !contentContainerView.frame.contains(point) else { return false }
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
    public func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        let controller = InteractiveSheetAnimationController(presentedViewController: presented, presenting: presenting, backdropColor: self.backdropColor)
        return controller
    }
}
