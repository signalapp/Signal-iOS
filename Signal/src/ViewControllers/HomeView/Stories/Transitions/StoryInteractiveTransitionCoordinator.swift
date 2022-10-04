//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
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
    func handlePan(_ gestureRecognizer: UIPanGestureRecognizer) {
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
            let progress = calculateProgress(gestureRecognizer)
            switch mode {
            case .reply:
                if progress >= 1 {
                    pageViewController.currentContextViewController.presentRepliesAndViewsSheet()
                    // Cancel the gesture.
                    self.interactionInProgress = false
                    gestureRecognizer.isEnabled = false
                    gestureRecognizer.isEnabled = true
                    finish()
                } else {
                    let newMinX: CGFloat
                    if CurrentAppContext().isRTL {
                        newMinX = progress * Self.replyGestureMaxTranslation
                    } else {
                        newMinX = -progress * Self.replyGestureMaxTranslation
                    }
                    self.pageViewController.currentContextViewController.view.frame.origin.x = newMinX
                    update(progress)
                }
            case .zoom, .slide:
                update(progress)
            }
        case .cancelled:
            switch mode {
            case .reply:
                finishRepliesGestureAnimation(gestureRecognizer)
                guard !self.interactionInProgress else {
                    fallthrough
                }
                // Cancel happens naturally as part of presentation.
                interactiveEdge = .none
                return
            case .slide, .zoom:
                pageViewController.currentContextViewController.play()
            }
            cancel()
            interactionInProgress = false
            interactiveEdge = .none
        case .ended:
            let progress = calculateProgress(gestureRecognizer)

            switch mode {
            case .reply:
                finishRepliesGestureAnimation(gestureRecognizer)
                pageViewController.currentContextViewController.play()
                cancel()
            case .zoom, .slide:
                if progress >= 0.5 || hasExceededVelocityThreshold(gestureRecognizer) {
                    finish()
                } else {
                    pageViewController.currentContextViewController.play()
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

    static let replyGestureMaxTranslation: CGFloat = 150

    func calculateProgress(_ gestureRecognizer: UIPanGestureRecognizer) -> CGFloat {
        let offset = gestureRecognizer.translation(in: pageViewController.view)
        let totalDistance: CGFloat

        switch mode {
        case .zoom, .reply: totalDistance = Self.replyGestureMaxTranslation
        case .slide:
            switch interactiveEdge {
            case .top, .bottom: totalDistance = pageViewController.view.height
            case .leading, .trailing, .none: totalDistance = pageViewController.view.width
            }
        }

        switch interactiveEdge {
        case .top:
            return offset.y / totalDistance
        case .leading:
            return ((CurrentAppContext().isRTL ? -1 : 1) * offset.x) / totalDistance
        case .trailing:
            return ((CurrentAppContext().isRTL ? 1 : -1) * offset.x) / totalDistance
        case .bottom:
            return -offset.y / totalDistance
        case .none:
            return 0
        }
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

    func finishRepliesGestureAnimation(_ gestureRecognizer: UIPanGestureRecognizer) {
        let view = self.pageViewController.currentContextViewController.view

        let percentCompletion = calculateProgress(gestureRecognizer)

        UIView.animate(
            withDuration: 0.3 * percentCompletion,
            delay: 0,
            options: .curveEaseOut,
            animations: {
                self.pageViewController.currentContextViewController.view.frame.origin.x = 0
            }
        )
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
}
