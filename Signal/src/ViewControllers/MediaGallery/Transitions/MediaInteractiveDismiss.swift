//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import SignalUI

protocol InteractivelyDismissableViewController: UIViewController {
    func performInteractiveDismissal(animated: Bool)
}

protocol InteractiveDismissDelegate: AnyObject {
    func interactiveDismissDidBegin(_ interactiveDismiss: UIPercentDrivenInteractiveTransition)
    func interactiveDismiss(_ interactiveDismiss: UIPercentDrivenInteractiveTransition,
                            didChangeProgress: CGFloat,
                            touchOffset: CGPoint)
    func interactiveDismissDidFinish(_ interactiveDismiss: UIPercentDrivenInteractiveTransition)
    func interactiveDismissDidCancel(_ interactiveDismiss: UIPercentDrivenInteractiveTransition)
}

extension InteractiveDismissDelegate {
    func interactiveDismissDidBegin(_ interactiveDismiss: UIPercentDrivenInteractiveTransition) {

    }
    func interactiveDismiss(_ interactiveDismiss: UIPercentDrivenInteractiveTransition,
                            didChangeProgress: CGFloat,
                            touchOffset: CGPoint
    ) { }
    func interactiveDismissDidFinish(_ interactiveDismiss: UIPercentDrivenInteractiveTransition) {

    }
    func interactiveDismissDidCancel(_ interactiveDismiss: UIPercentDrivenInteractiveTransition) {

    }
}

class MediaInteractiveDismiss: UIPercentDrivenInteractiveTransition {
    var interactionInProgress = false

    weak var interactiveDismissDelegate: InteractiveDismissDelegate?
    private weak var targetViewController: InteractivelyDismissableViewController?

    init(targetViewController: InteractivelyDismissableViewController) {
        super.init()
        self.targetViewController = targetViewController
    }

    public func addGestureRecognizer(to view: UIView) {
        let gesture = DirectionalPanGestureRecognizer(direction: .vertical,
                                                      target: self,
                                                      action: #selector(handleGesture(_:)))
        // Allow panning with trackpad
        if #available(iOS 13.4, *) { gesture.allowedScrollTypesMask = .continuous }
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

        let distanceToCompletion: CGFloat = 88
        let velocityThreshold: CGFloat = 500

        switch gestureRecognizer.state {
        case .began:
            interactionInProgress = true
            targetViewController?.performInteractiveDismissal(animated: true)

        case .changed:
            let velocity = abs(gestureRecognizer.velocity(in: coordinateSpace).y)
            if velocity > velocityThreshold {
                fastEnoughToCompleteTransition = true
            }

            let offset = gestureRecognizer.translation(in: coordinateSpace)
            let progress = CGFloatClamp01(offset.length / distanceToCompletion)
            // `farEnoughToCompleteTransition` is cancelable if the user reverses direction
            farEnoughToCompleteTransition = progress == 1

            update(progress)

            interactiveDismissDelegate?.interactiveDismiss(self, didChangeProgress: progress, touchOffset: offset)

        case .cancelled:
            interactiveDismissDelegate?.interactiveDismissDidFinish(self)
            cancel()

            interactionInProgress = false
            farEnoughToCompleteTransition = false
            fastEnoughToCompleteTransition = false

        case .ended:
            if shouldCompleteTransition {
                finish()
            } else {
                cancel()
            }

            interactiveDismissDelegate?.interactiveDismissDidFinish(self)

            interactionInProgress = false
            farEnoughToCompleteTransition = false
            fastEnoughToCompleteTransition = false

        default:
            break
        }
    }
}
