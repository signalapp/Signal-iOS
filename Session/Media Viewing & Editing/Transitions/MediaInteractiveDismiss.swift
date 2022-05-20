// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit

// MARK: - InteractivelyDismissableViewController

protocol InteractivelyDismissableViewController: UIViewController {
    func performInteractiveDismissal(animated: Bool)
}

// MARK: - InteractiveDismissDelegate

protocol InteractiveDismissDelegate: AnyObject {
    func interactiveDismissUpdate(_ interactiveDismiss: UIPercentDrivenInteractiveTransition, didChangeTouchOffset offset: CGPoint)
    func interactiveDismissDidFinish(_ interactiveDismiss: UIPercentDrivenInteractiveTransition)
}

// MARK: - MediaInteractiveDismiss

class MediaInteractiveDismiss: UIPercentDrivenInteractiveTransition {
    var interactionInProgress = false

    weak var interactiveDismissDelegate: InteractiveDismissDelegate?
    private weak var targetViewController: InteractivelyDismissableViewController?

    init(targetViewController: InteractivelyDismissableViewController) {
        super.init()

        self.targetViewController = targetViewController
    }

    public func addGestureRecognizer(to view: UIView) {
        let gesture: DirectionalPanGestureRecognizer = DirectionalPanGestureRecognizer(direction: .vertical, target: self, action: #selector(handleGesture(_:)))

        // Allow panning with trackpad
        if #available(iOS 13.4, *) { gesture.allowedScrollTypesMask = .continuous }

        view.addGestureRecognizer(gesture)
    }

    // MARK: - Private

    private var fastEnoughToCompleteTransition = false
    private var farEnoughToCompleteTransition = false
    private var lastProgress: CGFloat = 0
    private var lastIncreasedProgress: CGFloat = 0

    private var shouldCompleteTransition: Bool {
        if farEnoughToCompleteTransition { return true }
        if fastEnoughToCompleteTransition { return true }

        return false
    }

    @objc private func handleGesture(_ gestureRecognizer: UIScreenEdgePanGestureRecognizer) {
        guard let coordinateSpace = gestureRecognizer.view?.superview else { return }

        if case .began = gestureRecognizer.state {
            gestureRecognizer.setTranslation(.zero, in: coordinateSpace)
        }

        let totalDistance: CGFloat = 100
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
                let progress = abs(offset.y) / totalDistance
                
                // `farEnoughToCompleteTransition` is cancelable if the user reverses direction
                farEnoughToCompleteTransition = (progress >= 0.5)
                
                // If the user has reverted enough progress then we want to reset the velocity
                // flag (don't want the user to start quickly, slowly drag it back end end up
                // dismissing the screen)
                if (lastIncreasedProgress - progress) > 0.2 || progress < 0.05 {
                    fastEnoughToCompleteTransition = false
                }
                
                update(progress)
                
                lastIncreasedProgress = (progress > lastProgress ? progress : lastIncreasedProgress)
                lastProgress = progress

                interactiveDismissDelegate?.interactiveDismissUpdate(self, didChangeTouchOffset: offset)

            case .cancelled:
                interactiveDismissDelegate?.interactiveDismissDidFinish(self)
                cancel()

                interactionInProgress = false
                farEnoughToCompleteTransition = false
                fastEnoughToCompleteTransition = false
                lastIncreasedProgress = 0
                lastProgress = 0

            case .ended:
                if shouldCompleteTransition {
                    finish()
                }
                else {
                    cancel()
                }

                interactiveDismissDelegate?.interactiveDismissDidFinish(self)

                interactionInProgress = false
                farEnoughToCompleteTransition = false
                fastEnoughToCompleteTransition = false
                lastIncreasedProgress = 0
                lastProgress = 0

            default:
                break
        }
    }
}
