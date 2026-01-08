//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol InteractivelyDismissableViewController: UIViewController {
    func performInteractiveDismissal(animated: Bool)
}

protocol InteractiveDismissDelegate: AnyObject {
    func interactiveDismissDidBegin(_ interactiveDismiss: UIPercentDrivenInteractiveTransition)
    func interactiveDismiss(
        _ interactiveDismiss: UIPercentDrivenInteractiveTransition,
        didChangeProgress: CGFloat,
        touchOffset: CGPoint,
    )
    func interactiveDismissDidFinish(_ interactiveDismiss: UIPercentDrivenInteractiveTransition)
    func interactiveDismissDidCancel(_ interactiveDismiss: UIPercentDrivenInteractiveTransition)
}

class MediaInteractiveDismiss: UIPercentDrivenInteractiveTransition {
    var interactionInProgress = false

    weak var interactiveDismissDelegate: InteractiveDismissDelegate?
    private weak var targetViewController: InteractivelyDismissableViewController?

    init(targetViewController: InteractivelyDismissableViewController) {
        super.init()
        self.targetViewController = targetViewController
    }

    func addGestureRecognizer(to view: UIView) {
        let gesture = DirectionalPanGestureRecognizer(
            direction: .vertical,
            target: self,
            action: #selector(handleGesture(_:)),
        )
        // Allow panning with trackpad
        gesture.allowedScrollTypesMask = .continuous
        view.addGestureRecognizer(gesture)
    }

    // MARK: - Private

    private static let distanceToCompletion: CGFloat = 88

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
            let progress = CGFloat.clamp01(offset.length / Self.distanceToCompletion)
            update(progress)

            interactiveDismissDelegate?.interactiveDismiss(self, didChangeProgress: progress, touchOffset: offset)

        case .cancelled:
            cancel()
            interactiveDismissDelegate?.interactiveDismissDidCancel(self)

            interactionInProgress = false

            targetViewController?.setNeedsStatusBarAppearanceUpdate()

        case .ended:
            let finishTransition = percentComplete > 0
            if finishTransition {
                finish()
            } else {
                cancel()
            }

            interactiveDismissDelegate?.interactiveDismissDidFinish(self)

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
