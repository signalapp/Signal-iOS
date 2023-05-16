//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

class StoryInteractiveTransitionCoordinator: UIPercentDrivenInteractiveTransition, UIGestureRecognizerDelegate {
    weak var pageViewController: StoryPageViewController!
    lazy var panGestureRecognizer = UIPanGestureRecognizer(
        target: self,
        action: #selector(handlePan(_:))
    )
    init(pageViewController: StoryPageViewController) {
        self.pageViewController = pageViewController
        super.init()
        pageViewController.view.addGestureRecognizer(panGestureRecognizer)
        panGestureRecognizer.delegate = self

        for subview in pageViewController.view.subviews {
            guard let scrollView = subview as? UIScrollView else { continue }
            scrollView.panGestureRecognizer.require(toFail: panGestureRecognizer)
            break
        }
    }

    private(set) var interactionInProgress: Bool = false

    enum Edge {
        case leading
        case trailing
        case top
        case bottom
        case none
    }
    var interactiveEdge: Edge = .none

    enum Mode {
        case zoom
        case slide
        case reply
    }
    var mode: Mode = .zoom

    @objc
    private func handlePan(_ gestureRecognizer: UIPanGestureRecognizer) {
        switch gestureRecognizer.state {
        case .began:
            interactionInProgress = true
            gestureRecognizer.setTranslation(.zero, in: pageViewController.view)

            pageViewController.currentContextViewController.pause(hideChrome: true)

            switch interactiveEdge {
            case .none:
                pageViewController.currentContextViewController.play()
                cancel()
                return
            case .leading, .top, .bottom:
                pageViewController.dismiss(animated: true)
            case .trailing:
                mode = .reply
            }
        case .changed:
            interactionInProgress = true
            update(calculateProgress(gestureRecognizer))
        case .cancelled:
            cancel()
            interactionInProgress = false
            interactiveEdge = .none
        case .ended:
            let progress = calculateProgress(gestureRecognizer)

            switch mode {
            case .reply:
                cancel()
            case .zoom, .slide:
                if progress >= 0.5 || hasExceededVelocityThreshold(gestureRecognizer) {
                    finish()
                } else {
                    cancel()
                }
            }

            interactionInProgress = false
            interactiveEdge = .none
        default:
            cancel()
            interactionInProgress = false
            interactiveEdge = .none
        }
    }

    static let maxTranslation: CGFloat = 150

    func calculateProgress(_ gestureRecognizer: UIPanGestureRecognizer) -> CGFloat {
        let translation = gestureRecognizer.translation(in: pageViewController.view)

        let progress: CGFloat
        switch interactiveEdge {
        case .top:
            progress = translation.y / Self.maxTranslation
        case .leading:
            progress = ((CurrentAppContext().isRTL ? -1 : 1) * translation.x) / Self.maxTranslation
        case .trailing:
            progress = ((CurrentAppContext().isRTL ? 1 : -1) * translation.x) / Self.maxTranslation
        case .bottom:
            progress = -translation.y / Self.maxTranslation
        case .none:
            progress = 0
        }
        return progress.clamp01()
    }

    func hasExceededVelocityThreshold(_ gestureRecognizer: UIPanGestureRecognizer) -> Bool {
        let velocity = gestureRecognizer.velocity(in: pageViewController.view)
        let velocityThreshold: CGFloat = 500

        switch interactiveEdge {
        case .top:
            return velocity.y > velocityThreshold
        case .leading:
            return ((CurrentAppContext().isRTL ? -1 : 1) * velocity.x) > velocityThreshold
        case .trailing:
            return -((CurrentAppContext().isRTL ? 1 : -1) * velocity.x) > velocityThreshold
        case .bottom:
            return -velocity.y > velocityThreshold
        case .none:
            return false
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer == panGestureRecognizer else { return false }
        guard gestureRecognizer.numberOfTouches == 1 else { return false }
        guard !pageViewController.currentContextViewController.willHandleInteractivePanGesture(panGestureRecognizer) else {
            return false
        }
        self.interactiveEdge = interactiveEdgeForCurrentGesture()
        return interactiveEdge != .none
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer == panGestureRecognizer
    }

    private func interactiveEdgeForCurrentGesture() -> Edge {
        let translation = panGestureRecognizer.translation(in: pageViewController.view)
        let normalizedTranslationX = (CurrentAppContext().isRTL ? -1 : 1) * translation.x

        if normalizedTranslationX > 0 {
            return .leading
        } else if normalizedTranslationX < 0, pageViewController.currentContextViewController.allowsReplies {
            return .trailing
        } else if pageViewController.previousStoryContext == nil, translation.y > 0 {
            return .top
        } else if pageViewController.nextStoryContext == nil, translation.y < 0 {
            return .bottom
        } else {
            return .none
        }
    }

    var completionHandler: (() -> Void)?
    var finishAnimations: (() -> Void)?
    var cancelAnimations: (() -> Void)?
    var updateHandler: ((CGFloat) -> Void)?

    func resetHandlers() {
        completionHandler = nil
        finishAnimations = nil
        cancelAnimations = nil
        updateHandler = nil
    }

    override func finish() {
        super.finish()

        switch mode {
        case .reply:
            pageViewController.currentContextViewController.presentRepliesAndViewsSheet()
        case .slide, .zoom:
            completionAnimation {
                self.pageViewController.view.backgroundColor = .clear
                self.finishAnimations?()
            } completion: { _ in
                self.completionHandler?()
                self.resetHandlers()
            }
        }
    }

    override func cancel() {
        super.cancel()

        if interactionInProgress {
            pageViewController.currentContextViewController.play()
        }

        completionAnimation {
            switch self.mode {
            case .reply:
                self.pageViewController.currentContextViewController.view.frame.origin.x = 0
            case .slide, .zoom:
                self.pageViewController.view.backgroundColor = .black
                self.pageViewController.currentContextViewController.currentItemMediaView?.transform = .identity
                self.pageViewController.currentContextViewController.view.frame = self.pageViewController.view.frame
            }

            self.cancelAnimations?()
        } completion: { _ in
            self.completionHandler?()
            self.resetHandlers()
        }
    }

    func completionAnimation(animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        let velocity = panGestureRecognizer.velocity(in: pageViewController.view)
        let averageVelocity = abs(velocity.x) + abs(velocity.y) / 2
        let translation = panGestureRecognizer.translation(in: pageViewController.view)
        let averageTranslation = abs(translation.x) + abs(translation.y) / 2
        let springVelocity = averageVelocity / averageTranslation

        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            usingSpringWithDamping: 0.98,
            initialSpringVelocity: springVelocity,
            options: .curveLinear,
            animations: animations,
            completion: completion
        )
    }

    override func update(_ percentComplete: CGFloat) {
        super.update(percentComplete)

        switch mode {
        case .reply:
            if percentComplete >= 1 {
                // Cancel the gesture.
                interactionInProgress = false
                panGestureRecognizer.isEnabled = false
                panGestureRecognizer.isEnabled = true
                finish()
            } else {
                let newMinX: CGFloat
                if CurrentAppContext().isRTL {
                    newMinX = percentComplete * Self.maxTranslation
                } else {
                    newMinX = -percentComplete * Self.maxTranslation
                }
                pageViewController.currentContextViewController.view.frame.origin.x = newMinX
            }
        case .slide, .zoom:
            let translation = panGestureRecognizer.translation(in: pageViewController.view)
            let translatedFrame = pageViewController.view.frame.offsetBy(dx: translation.x, dy: translation.y)
            pageViewController.currentContextViewController.view.frame = translatedFrame
            let scale = 1 - (0.1 * percentComplete)
            pageViewController.currentContextViewController.currentItemMediaView?.transform = .init(scaleX: scale, y: scale)
            pageViewController.view.backgroundColor = UIColor.black.withAlphaComponent(1 - (0.6 * percentComplete))
        }

        updateHandler?(percentComplete)
    }
}
