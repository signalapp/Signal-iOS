//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

public class ImageEditorGestureRecognizer: UIGestureRecognizer {

    @objc
    public var shouldAllowOutsideView = true

    @objc
    public weak var canvasView: UIView?

    @objc
    public var startLocationInView: CGPoint = .zero

    @objc
    public override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    @objc
    public override func canBePrevented(by: UIGestureRecognizer) -> Bool {
        return false
    }

    @objc
    public override func shouldRequireFailure(of: UIGestureRecognizer) -> Bool {
        return false
    }

    @objc
    public override func shouldBeRequiredToFail(by: UIGestureRecognizer) -> Bool {
        return true
    }

    // MARK: - Touch Handling

    @objc
    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)

        if state == .possible,
            touchType(for: touches, with: event) == .valid {
            // If a gesture starts with a valid touch, begin stroke.
            state = .began
            startLocationInView = .zero

            guard let view = view else {
                owsFailDebug("Missing view.")
                return
            }
            guard let touch = touches.randomElement() else {
                owsFailDebug("Missing touch.")
                return
            }
            startLocationInView = touch.location(in: view)
        } else {
            state = .failed
        }
    }

    @objc
    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)

        switch state {
        case .began, .changed:
            switch touchType(for: touches, with: event) {
            case .valid:
                // If a gesture continues with a valid touch, continue stroke.
                state = .changed
            case .invalid:
                state = .failed
            case .outside:
                // If a gesture continues with a valid touch _outside the canvas_,
                // end stroke.
                state = .ended
            }
        default:
            state = .failed
        }
    }

    @objc
    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)

        switch state {
        case .began, .changed:
            switch touchType(for: touches, with: event) {
            case .valid, .outside:
                // If a gesture ends with a valid touch, end stroke.
                state = .ended
            case .invalid:
                state = .failed
            }
        default:
            state = .failed
        }
    }

    @objc
    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)

        state = .cancelled
    }

    public enum TouchType {
        case invalid
        case valid
        case outside
    }

    private func touchType(for touches: Set<UITouch>, with event: UIEvent) -> TouchType {
        guard let gestureView = self.view else {
            owsFailDebug("Missing gestureView")
            return .invalid
        }
        guard let canvasView = canvasView else {
            owsFailDebug("Missing canvasView")
            return .invalid
        }
        guard let allTouches = event.allTouches else {
            owsFailDebug("Missing allTouches")
            return .invalid
        }
        guard allTouches.count <= 1 else {
            return .invalid
        }
        guard touches.count == 1 else {
            return .invalid
        }
        guard let firstTouch: UITouch = touches.first else {
            return .invalid
        }

        let isNewTouch = firstTouch.phase == .began
        if isNewTouch {
            // Reject new touches that are inside a control subview.
            if subviewControl(ofView: gestureView, contains: firstTouch) {
                return .invalid
            }
        }

        // Reject new touches outside this GR's view's bounds.
        let location = firstTouch.location(in: canvasView)
        if !canvasView.bounds.contains(location) {
            if shouldAllowOutsideView {
                // Do nothing
            } else if isNewTouch {
                return .invalid
            } else {
                return .outside
            }
        }

        if isNewTouch {
            // Ignore touches that start near the top or bottom edge of the screen;
            // they may be a system edge swipe gesture.
            let rootView = self.rootView(of: gestureView)
            let rootLocation = firstTouch.location(in: rootView)
            let distanceToTopEdge = max(0, rootLocation.y)
            let distanceToBottomEdge = max(0, rootView.bounds.size.height - rootLocation.y)
            let distanceToNearestEdge = min(distanceToTopEdge, distanceToBottomEdge)
            let kSystemEdgeSwipeTolerance: CGFloat = 50
            if (distanceToNearestEdge < kSystemEdgeSwipeTolerance) {
                return .invalid
            }
        }

        return .valid
    }

    private func subviewControl(ofView superview: UIView, contains touch: UITouch) -> Bool {
        for subview in superview.subviews {
            guard !subview.isHidden, subview.isUserInteractionEnabled else {
                continue
            }
            let location = touch.location(in: subview)
            guard subview.bounds.contains(location) else {
                continue
            }
            if subview as? UIControl != nil {
                return true
            }
            if subviewControl(ofView: subview, contains: touch) {
                return true
            }
        }
        return false
    }

    private func rootView(of view: UIView) -> UIView {
        var responder: UIResponder? = view
        var lastView: UIView = view
        while true {
            guard let currentResponder = responder else {
                return lastView
            }
            if let currentView = currentResponder as? UIView {
                lastView = currentView
            }
            responder = currentResponder.next
        }
    }
}
