//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

class PhotoCaptureInteractiveDismiss: UIPercentDrivenInteractiveTransition {
    var interactionInProgress = false

    weak var interactiveDismissDelegate: InteractiveDismissDelegate?
    private weak var viewController: UIViewController?

    init(viewController: UIViewController) {
        super.init()
        self.viewController = viewController
    }

    public func addGestureRecognizer(to view: UIView) {
        let gesture = DirectionalPanGestureRecognizer(direction: .vertical,
                                                      target: self,
                                                      action: #selector(handleGesture(_:)))
        view.addGestureRecognizer(gesture)
    }

    // MARK: - Private

    private var fastEnoughToCompleteTransition = false
    private var farEnoughToCompleteTransition = false

    private var shouldCompleteTransition: Bool {
        if farEnoughToCompleteTransition {
            Logger.verbose("farEnoughToCompleteTransition")
            return true
        }

        if fastEnoughToCompleteTransition {
            Logger.verbose("fastEnoughToCompleteTransition")
            return true
        }

        return false
    }

    @objc
    private func handleGesture(_ gestureRecognizer: UIScreenEdgePanGestureRecognizer) {
        guard let coordinateSpace = gestureRecognizer.view?.superview else {
            owsFailDebug("coordinateSpace was unexpectedly nil")
            return
        }

        if case .began = gestureRecognizer.state {
            gestureRecognizer.setTranslation(.zero, in: coordinateSpace)
        }

        let totalDistance: CGFloat = 100
        let velocityThreshold: CGFloat = 500

        switch gestureRecognizer.state {
        case .began:
            interactionInProgress = true
            interactiveDismissDelegate?.interactiveDismissDidBegin(self)

        case .changed:
            let velocity = abs(gestureRecognizer.velocity(in: coordinateSpace).y)
            if velocity > velocityThreshold {
                fastEnoughToCompleteTransition = true
            }

            let offset = gestureRecognizer.translation(in: coordinateSpace)
            let progress = abs(offset.y) / totalDistance
            // `farEnoughToCompleteTransition` is cancelable if the user reverses direction
            farEnoughToCompleteTransition = progress >= 0.5
            update(progress)

            interactiveDismissDelegate?.interactiveDismiss(self, didChangeTouchOffset: offset)

        case .cancelled:
            cancel()
            interactiveDismissDelegate?.interactiveDismissDidCancel(self)

            interactionInProgress = false
            farEnoughToCompleteTransition = false
            fastEnoughToCompleteTransition = false

        case .ended:
            if shouldCompleteTransition {
                finish()
                interactiveDismissDelegate?.interactiveDismissDidFinish(self)
            } else {
                cancel()
                interactiveDismissDelegate?.interactiveDismissDidCancel(self)
            }


            interactionInProgress = false
            farEnoughToCompleteTransition = false
            fastEnoughToCompleteTransition = false

        default:
            break
        }
    }
}

class PhotoDismissAnimationController: NSObject {
    public let interactionController: UIPercentDrivenInteractiveTransition?

    var transitionView: UIView?
    var fromMediaFrame: CGRect?

    init(interactionController: UIPercentDrivenInteractiveTransition? = nil) {
        self.interactionController = interactionController
    }
}

extension PhotoDismissAnimationController: UIViewControllerAnimatedTransitioning {
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 5
    }
    
    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        print(".")
    }
    
}

extension PhotoDismissAnimationController: InteractiveDismissDelegate {
    func interactiveDismissDidBegin(_ interactiveDismiss: UIPercentDrivenInteractiveTransition) {
    }

    func interactiveDismiss(_ interactiveDismiss: UIPercentDrivenInteractiveTransition, didChangeTouchOffset offset: CGPoint) {
        guard let transitionView = transitionView else {
            // transition hasn't started yet.
            return
        }

        guard let fromMediaFrame = fromMediaFrame else {
            owsFailDebug("fromMediaFrame was unexpectedly nil")
            return
        }

        transitionView.center = fromMediaFrame.offsetBy(dx: offset.x, dy: offset.y).center
    }

    func interactiveDismissDidFinish(_ interactiveDismiss: UIPercentDrivenInteractiveTransition) {
    }
    
    func interactiveDismissDidCancel(_ interactiveDismiss: UIPercentDrivenInteractiveTransition) {
    }
}
