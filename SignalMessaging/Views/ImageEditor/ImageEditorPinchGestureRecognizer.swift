//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

public struct ImageEditorPinchState {
    public let centroid: CGPoint
    public let distance: CGFloat
    public let angleRadians: CGFloat

    init(centroid: CGPoint,
         distance: CGFloat,
         angleRadians: CGFloat) {
        self.centroid = centroid
        self.distance = distance
        self.angleRadians = angleRadians
    }

    static func empty() -> ImageEditorPinchState {
        return ImageEditorPinchState(centroid: .zero, distance: 1.0, angleRadians: 0)
    }
}

public class ImageEditorPinchGestureRecognizer: UIGestureRecognizer {

    public var pinchStateStart = ImageEditorPinchState.empty()

    public var pinchStateLast = ImageEditorPinchState.empty()

    // MARK: - Touch Handling

    private var gestureBeganLocation: CGPoint?

    private func failAndReset() {
        state = .failed
        gestureBeganLocation = nil
    }

    @objc
    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)

        if state == .possible {
            if gestureBeganLocation == nil {
                gestureBeganLocation = centroid(forTouches: event.allTouches)
            }

            switch touchState(for: event) {
            case .possible:
                // Do nothing
                break
            case .invalid:
                failAndReset()
            case .valid(let pinchState):
                state = .began
                pinchStateStart = pinchState
                pinchStateLast = pinchState
            }
        } else {
            failAndReset()
        }
    }

    @objc
    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)

        switch state {
        case .began, .changed:
            switch touchState(for: event) {
            case .possible:
                if let gestureBeganLocation = gestureBeganLocation {
                    let location = centroid(forTouches: event.allTouches)

                    // If the initial touch moves too much without a second touch,
                    // this GR needs to fail - the gesture looks like a pan/swipe/etc.,
                    // not a pinch.
                    let distance = CGPointDistance(location, gestureBeganLocation)
                    let maxDistance: CGFloat = 10.0
                    guard distance <= maxDistance else {
                        failAndReset()
                        return
                    }
                }

                // Do nothing
                break
            case .invalid:
                failAndReset()
            case .valid(let pinchState):
                state = .changed
                pinchStateLast = pinchState
            }
        default:
            failAndReset()
        }
    }

    @objc
    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)

        switch state {
        case .began, .changed:
            switch touchState(for: event) {
            case .possible:
                failAndReset()
            case .invalid:
                failAndReset()
            case .valid(let pinchState):
                state = .ended
                pinchStateLast = pinchState
            }
        default:
            failAndReset()
        }
    }

    @objc
    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)

        state = .cancelled
    }

    public enum TouchState {
        case possible
        case valid(pinchState : ImageEditorPinchState)
        case invalid
    }

    private func touchState(for event: UIEvent) -> TouchState {
        guard let allTouches = event.allTouches else {
            owsFailDebug("Missing allTouches")
            return .invalid
        }
        // Note that we use _all_ touches.
        if allTouches.count < 2 {
            return .possible
        }
        guard let pinchState = pinchState(for: allTouches) else {
            return .invalid
        }
        return .valid(pinchState:pinchState)
    }

    private func pinchState(for touches: Set<UITouch>) -> ImageEditorPinchState? {
        guard let view = self.view else {
            owsFailDebug("Missing view")
            return nil
        }
        guard touches.count == 2 else {
            return nil
        }
        let touchList = Array<UITouch>(touches).sorted { (left, right) -> Bool in
            // TODO: Will timestamp yield stable sort?
            left.timestamp < right.timestamp
        }
        guard let touch0 = touchList.first else {
            return nil
        }
        guard let touch1 = touchList.last else {
            return nil
        }
        let location0 = touch0.location(in: view)
        let location1 = touch1.location(in: view)

        let centroid = CGPointScale(CGPointAdd(location0, location1), 0.5)
        let distance = CGPointDistance(location0, location1)

        // The valence of the angle doesn't matter; we're only going to be using
        // changes to the angle.
        let delta = CGPointSubtract(location1, location0)
        let angleRadians = atan2(delta.y, delta.x)

        return ImageEditorPinchState(centroid: centroid,
                                     distance: distance,
                                     angleRadians: angleRadians)
    }

    private func centroid(forTouches touches: Set<UITouch>?) -> CGPoint {
        guard let view = self.view else {
            owsFailDebug("Missing view")
            return .zero
        }
        guard let touches = touches else {
            return .zero
        }
        guard touches.count > 0 else {
            return .zero
        }
        var sum = CGPoint.zero
        for touch in touches {
            let location = touch.location(in: view)
            sum = CGPointAdd(sum, location)
        }

        let centroid = CGPointScale(sum, 1 / CGFloat(touches.count))
        return centroid
    }
}
