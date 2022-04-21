//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

class StorySlideAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let interactiveEdge: StoryInteractiveTransitionCoordinator.Edge
    init(interactiveEdge: StoryInteractiveTransitionCoordinator.Edge) {
        self.interactiveEdge = interactiveEdge
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
        fromVC.view.frame = transitionContext.initialFrame(for: fromVC)

        let endFrame: CGRect
        switch interactiveEdge {
        case .leading:
            endFrame = fromVC.view.frame.offsetBy(dx: (CurrentAppContext().isRTL ? -1 : 1) * fromVC.view.width, dy: 0)
        case .trailing:
            endFrame = fromVC.view.frame.offsetBy(dx: (CurrentAppContext().isRTL ? 1 : -1) * fromVC.view.width, dy: 0)
        case .top, .none:
            endFrame = fromVC.view.frame.offsetBy(dx: 0, dy: fromVC.view.height)
        case .bottom:
            endFrame = fromVC.view.frame.offsetBy(dx: 0, dy: -fromVC.view.height)
        }

        UIView.animate(
            withDuration: transitionDuration(using: transitionContext),
            delay: 0,
            options: interactiveEdge != .none ? .curveLinear : .curveEaseInOut
        ) {
            fromVC.currentContextViewController.view.frame = endFrame
            fromVC.view.backgroundColor = .clear
        } completion: { _ in
            if transitionContext.transitionWasCancelled {
                toVC.view.removeFromSuperview()
            } else {
                fromVC.view.removeFromSuperview()
            }

            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }
    }
}
