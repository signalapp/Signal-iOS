//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
class SlideOffAnimatedTransition: NSObject, UIViewControllerAnimatedTransitioning {

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {

        let containerView = transitionContext.containerView
        guard let fromView = transitionContext.viewController(forKey: UITransitionContextViewControllerKey.from)?.view else {
            owsFail("No fromView")
            return
        }
        guard let toView = transitionContext.viewController(forKey: UITransitionContextViewControllerKey.to)?.view else {
            owsFail("No toView")
            return
        }

        let width = containerView.frame.width
        let offsetLeft = fromView.frame.offsetBy(dx: -width, dy: 0)
        toView.frame = fromView.frame

        fromView.layer.shadowRadius = 15.0
        fromView.layer.shadowOpacity = 1.0
        toView.layer.opacity = 0.9

        containerView.insertSubview(toView, belowSubview: fromView)
        UIView.animate(withDuration: transitionDuration(using: transitionContext), delay:0, options: .curveLinear, animations: {
            fromView.frame = offsetLeft

            toView.layer.opacity = 1.0
            fromView.layer.shadowOpacity = 0.1
        }, completion: { _ in
            toView.layer.opacity = 1.0
            toView.layer.shadowOpacity = 0

            fromView.layer.opacity = 1.0
            fromView.layer.shadowOpacity = 0

            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        })
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.3
    }

}
