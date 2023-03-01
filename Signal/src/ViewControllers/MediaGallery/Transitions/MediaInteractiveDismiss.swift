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
    func interactiveDismiss(_ interactiveDismiss: UIPercentDrivenInteractiveTransition,
                            didFinishWithVelocity: CGVector?)
    func interactiveDismissDidCancel(_ interactiveDismiss: UIPercentDrivenInteractiveTransition)
}

extension InteractiveDismissDelegate {
    func interactiveDismissDidBegin(_ interactiveDismiss: UIPercentDrivenInteractiveTransition) {

    }
    func interactiveDismiss(_ interactiveDismiss: UIPercentDrivenInteractiveTransition,
                            didChangeProgress: CGFloat,
                            touchOffset: CGPoint
    ) { }
    func interactiveDismiss(_ interactiveDismiss: UIPercentDrivenInteractiveTransition,
                            didFinishWithVelocity: CGVector?) { }
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

    private static let distanceToCompletion: CGFloat = 88

    // Copy-pasted from SDK documentation.
    private func initialAnimationVelocity(for gestureVelocity: CGPoint, from currentPosition: CGPoint, to finalPosition: CGPoint) -> CGVector {
        var animationVelocity = CGVector.zero
        let xDistance = finalPosition.x - currentPosition.x
        let yDistance = finalPosition.y - currentPosition.y
        if xDistance != 0 {
            animationVelocity.dx = gestureVelocity.x / xDistance
        }
        if yDistance != 0 {
            animationVelocity.dy = gestureVelocity.y / yDistance
        }
        return animationVelocity
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

        switch gestureRecognizer.state {
        case .began:
            interactionInProgress = true
            targetViewController?.performInteractiveDismissal(animated: true)

        case .changed:
            let offset = gestureRecognizer.translation(in: coordinateSpace)
            let progress = CGFloatClamp01(offset.length / Self.distanceToCompletion)
            update(progress)

            interactiveDismissDelegate?.interactiveDismiss(self, didChangeProgress: progress, touchOffset: offset)

        case .cancelled:
            cancel()
            interactiveDismissDelegate?.interactiveDismissDidCancel(self)

            interactionInProgress = false

            targetViewController?.setNeedsStatusBarAppearanceUpdate()

        case .ended:
            let finishTransition = percentComplete == 1
            if finishTransition {
                finish()
            } else {
                cancel()
            }

            let gestureVelocity = gestureRecognizer.velocity(in: coordinateSpace)
            let animationVelocity = initialAnimationVelocity(
                for: gestureVelocity,
                from: .zero,
                to: gestureRecognizer.translation(in: coordinateSpace)
            )
            // Call `interactiveDismiss(_:, didFinishWithVelocity:) even when transition is canceled
            // to restore initial state with a proper spring animation.
            interactiveDismissDelegate?.interactiveDismiss(self, didFinishWithVelocity: animationVelocity)

            // This logic is necessary to ensure correct status bar state
            // both when transition is finished or canceled.
            if finishTransition {
                targetViewController?.setNeedsStatusBarAppearanceUpdate()
            }

            interactionInProgress = false

            if !finishTransition {
                targetViewController?.setNeedsStatusBarAppearanceUpdate()
            }

        default:
            break
        }
    }
}
