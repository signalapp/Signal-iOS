//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

class StoryReplySheetAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let isPresenting: Bool
    let isInteractive: Bool
    let backdropView: UIView?

    init(isPresenting: Bool, isInteractive: Bool, backdropView: UIView?) {
        self.isPresenting = isPresenting
        self.isInteractive = isInteractive
        self.backdropView = backdropView
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.25
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let containerView = transitionContext.containerView

        guard let toVC = transitionContext.viewController(forKey: .to),
                let fromVC = transitionContext.viewController(forKey: .from) else {
            transitionContext.completeTransition(false)
            return
        }

        let startFrame: CGRect
        let endFrame: CGRect
        let animatingView: UIView

        if let backdropView = backdropView {
            backdropView.frame = transitionContext.initialFrame(for: fromVC)
            backdropView.backgroundColor = Theme.backdropColor
            containerView.addSubview(backdropView)
        }

        if isPresenting {
            containerView.addSubview(toVC.view)

            backdropView?.alpha = 0

            endFrame = transitionContext.finalFrame(for: toVC)
            startFrame = endFrame.offsetBy(dx: 0, dy: endFrame.height)
            animatingView = toVC.view
        } else {
            containerView.addSubview(fromVC.view)

            backdropView?.alpha = 1

            startFrame = transitionContext.initialFrame(for: fromVC)
            endFrame = startFrame.offsetBy(dx: 0, dy: startFrame.height)
            animatingView = fromVC.view
        }

        animatingView.frame = startFrame

        UIView.animate(
            withDuration: transitionDuration(using: transitionContext),
            delay: 0,
            options: isInteractive ? .curveLinear : .curveEaseInOut
        ) {
            self.backdropView?.alpha = self.isPresenting ? 1 : 0
            animatingView.frame = endFrame
        } completion: { _ in
            if transitionContext.transitionWasCancelled || !self.isPresenting {
                animatingView.removeFromSuperview()
                self.backdropView?.removeFromSuperview()
            }

            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }
    }
}
