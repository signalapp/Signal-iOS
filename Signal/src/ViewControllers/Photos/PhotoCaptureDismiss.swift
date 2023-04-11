//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalUI

class PhotoCaptureInteractiveDismiss: UIPercentDrivenInteractiveTransition {
    var interactionInProgress = false

    weak var interactiveDismissDelegate: InteractiveDismissDelegate?
    let handlesAnimation: Bool

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

    private var initialDimissFrame: CGRect?
    private weak var viewController: UIViewController?
    private var farEnoughToCompleteTransition = false

    private var shouldCompleteTransition: Bool {
        if farEnoughToCompleteTransition {
            Logger.verbose("farEnoughToCompleteTransition")
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

        let distanceToTriggerDismiss: CGFloat = 200

        switch gestureRecognizer.state {
        case .began:
            interactionInProgress = true
            interactiveDismissDelegate?.interactiveDismissDidBegin(self)

        case .changed:
            let offset = gestureRecognizer.translation(in: coordinateSpace)
            let progress = offset.y / distanceToTriggerDismiss
            // `farEnoughToCompleteTransition` is cancelable if the user reverses direction
            farEnoughToCompleteTransition = progress >= 1
            update(progress)

            interactiveDismissDelegate?.interactiveDismiss(self, didChangeProgress: progress, touchOffset: offset)
            if handlesAnimation {
                guard let frame = initialDimissFrame else {return}
                let delta = self.constainSwipe(offset: offset)
                viewController?.view.center = frame.offsetBy(dx: delta.x, dy: delta.y).center
            }

        case .cancelled:
            cancel()
            interactiveDismissDelegate?.interactiveDismissDidCancel(self)

            initialDimissFrame = nil
            interactionInProgress = false
            farEnoughToCompleteTransition = false

        case .ended:
            if shouldCompleteTransition {
                finish()
                interactiveDismissDelegate?.interactiveDismiss(self, didFinishWithVelocity: nil)
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

        default:
            break
        }
    }

    private func constainSwipe(offset: CGPoint) -> CGPoint {
        // Don't allow the swipe to move the view upwards off the screen
        var y = offset.y
        if y < 0 {
            y = 0
        }
        return CGPoint(x: 0, y: y)
    }
}
