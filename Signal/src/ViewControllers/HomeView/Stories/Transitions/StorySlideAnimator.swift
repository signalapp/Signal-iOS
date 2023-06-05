//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

class StorySlideAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    weak var coordinator: StoryInteractiveTransitionCoordinator!
    init(coordinator: StoryInteractiveTransitionCoordinator) {
        self.coordinator = coordinator
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.2
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let containerView = transitionContext.containerView

        guard let fromVC = transitionContext.viewController(forKey: .from) as? StoryPageViewController,
              let toVC = transitionContext.viewController(forKey: .to) else {
            owsFailDebug("Missing vcs")
            transitionContext.completeTransition(false)
            return
        }

        containerView.addSubview(toVC.view)
        containerView.addSubview(fromVC.view)

        let completion = {
            if transitionContext.transitionWasCancelled {
                toVC.view.removeFromSuperview()
            } else {
                fromVC.view.removeFromSuperview()
            }

            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }

        if coordinator.interactionInProgress {
            coordinator.finishAnimations = {
                let velocity = self.coordinator.panGestureRecognizer.velocity(in: fromVC.view)
                var interactiveEndFrame: CGRect = fromVC.currentContextViewController.view.frame

                // Follow a straight line to the nearest edge
                // based on the velocity at time of release.

                let distanceToHorizontalEdge = CurrentAppContext().isRTL ? -interactiveEndFrame.maxX : fromVC.view.frame.width - interactiveEndFrame.minX
                let distanceToVerticalEdge = velocity.y < 1 ? -interactiveEndFrame.maxY : fromVC.view.frame.height - interactiveEndFrame.minY

                let timeToHorizontalEdge = self.timeToEdge(velocity: velocity.x, distance: distanceToHorizontalEdge)
                let timeToVerticalEdge = self.timeToEdge(velocity: velocity.y, distance: distanceToVerticalEdge)

                if timeToHorizontalEdge < timeToVerticalEdge {
                    interactiveEndFrame.origin.x += distanceToHorizontalEdge
                    interactiveEndFrame.origin.y += timeToHorizontalEdge * velocity.y
                } else {
                    interactiveEndFrame.origin.x += timeToVerticalEdge * velocity.x
                    interactiveEndFrame.origin.y += distanceToVerticalEdge
                }

                fromVC.currentContextViewController.view.frame = interactiveEndFrame
            }
            coordinator.completionHandler = completion
        } else {
            let endFrame: CGRect
            switch coordinator.interactiveEdge {
            case .leading:
                endFrame = fromVC.view.frame.offsetBy(dx: (CurrentAppContext().isRTL ? -1 : 1) * fromVC.view.width, dy: 0)
            case .trailing:
                endFrame = fromVC.view.frame.offsetBy(dx: (CurrentAppContext().isRTL ? 1 : -1) * fromVC.view.width, dy: 0)
            case .top, .none:
                endFrame = fromVC.view.frame.offsetBy(dx: 0, dy: fromVC.view.height)
            case .bottom:
                endFrame = fromVC.view.frame.offsetBy(dx: 0, dy: -fromVC.view.height)
            }

            UIView.animate(withDuration: transitionDuration(using: transitionContext), animations: {
                fromVC.currentContextViewController.view.frame = endFrame
                fromVC.view.backgroundColor = .clear
            }, completion: { _ in completion()})
        }
    }

    private func timeToEdge(velocity: CGFloat, distance: CGFloat) -> TimeInterval {
        guard (velocity < 0 && distance < 0) || (velocity > 0 && distance > 0) else {
            return .greatestFiniteMagnitude
        }
        return distance / velocity
    }
}
