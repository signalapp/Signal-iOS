//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

class PhotoCaptureInteractiveDismiss: UIPercentDrivenInteractiveTransition {
    var interactionInProgress = false

    weak var interactiveDismissDelegate: InteractiveDismissDelegate?
    let handlesAnimation : Bool

    init(viewController: UIViewController, handlesAnimation: Bool = true) {
        self.viewController = viewController
        self.handlesAnimation = handlesAnimation
        super.init()
    }

    public func addGestureRecognizer(to view: UIView) {
        let gesture = DirectionalPanGestureRecognizer(direction: .vertical,
                                                      target: self,
                                                      action: #selector(handleGesture(_:)))
        view.addGestureRecognizer(gesture)
    }

    // MARK: - Private

    private var initialDimissFrame : CGRect?
    private weak var viewController: UIViewController?
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
            initialDimissFrame = self.viewController?.view.frame
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

            interactiveDismissDelegate?.interactiveDismissUpdate(self, didChangeTouchOffset: offset)
            if handlesAnimation {
                guard let frame = initialDimissFrame else {return}
                // Only allow swipe down to dismiss
                var y = offset.y
                if y < 0 {
                    y = 0
                }
                viewController?.view.center = frame.offsetBy(dx: 0, dy: y).center
            }

        case .cancelled:
            cancel()
            interactiveDismissDelegate?.interactiveDismissDidCancel(self)

            initialDimissFrame = nil
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
                if handlesAnimation {
                    guard let frame = initialDimissFrame else {return}
                    UIView.animate(withDuration: 0.1, animations: {
                        self.viewController?.view.frame = frame
                    })
                }
            }

            initialDimissFrame = nil
            interactionInProgress = false
            farEnoughToCompleteTransition = false
            fastEnoughToCompleteTransition = false

        default:
            break
        }
    }
}
