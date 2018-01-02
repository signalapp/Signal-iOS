//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import UIKit.UIGestureRecognizerSubclass

@objc
enum PanDirection: Int {
    case forward, backward, up, down, any
}

@objc
class PanDirectionGestureRecognizer: UIPanGestureRecognizer {

    let direction: PanDirection

    init(direction: PanDirection, target: AnyObject, action: Selector) {
        self.direction = direction

        super.init(target: target, action: action)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        // Only start gesture if it's initially in the specified direction.
        if state == .possible {
            guard let touch = touches.first else {
                return
            }

            let previousLocation = touch.previousLocation(in: view)
            let location = touch.location(in: view)
            let deltaY = previousLocation.y - location.y
            let deltaX = previousLocation.x - location.x

            switch direction {
            case .down where deltaY < 0:
                return
            case .up where deltaY > 0:
                return
            case .forward where deltaX < 0:
                return
            case .backward where deltaX > 0:
                return
            default:
                break
            }
        }

        // Gesture was already started, or in the correct direction.
        super.touchesMoved(touches, with: event)

        if state == .began {
            let vel = velocity(in: view)
            switch direction {
            case .forward, .backward:
                if fabs(vel.y) > fabs(vel.x) {
                    state = .cancelled
                }
            case .up, .down:
                if fabs(vel.x) > fabs(vel.y) {
                    state = .cancelled
                }
            default:
                break
            }
        }
    }
}
