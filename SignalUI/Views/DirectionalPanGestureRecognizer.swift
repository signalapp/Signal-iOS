//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit.UIGestureRecognizerSubclass

public struct PanDirection: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let left  = PanDirection(rawValue: 1 << 0)
    public static let right = PanDirection(rawValue: 1 << 1)
    public static let up    = PanDirection(rawValue: 1 << 2)
    public static let down  = PanDirection(rawValue: 1 << 3)

    public static let horizontal: PanDirection = [.left, .right]
    public static let vertical: PanDirection = [.up, .down]
    public static let any: PanDirection = [.left, .right, .up, .down]
}

public class DirectionalPanGestureRecognizer: UIPanGestureRecognizer {

    let direction: PanDirection

    public init(direction: PanDirection, target: AnyObject, action: Selector) {
        self.direction = direction

        super.init(target: target, action: action)
    }

    override public func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        // Only start gesture if it's initially in the specified direction.
        if state == .possible {
            guard let touch = touches.first else {
                return
            }

            let previousLocation = touch.previousLocation(in: view)
            let location = touch.location(in: view)
            let deltaY = previousLocation.y - location.y
            let deltaX = previousLocation.x - location.x

            let isSatisified: Bool = {
                if abs(deltaY) > abs(deltaX) {
                    if direction.contains(.up) && deltaY < 0 {
                        return true
                    }

                    if direction.contains(.down) && deltaY > 0 {
                        return true
                    }
                } else {
                    if direction.contains(.left) && deltaX < 0 {
                        return true
                    }

                    if direction.contains(.right) && deltaX > 0 {
                        return true
                    }
                }

                return false
            }()

            guard isSatisified else {
                return
            }
        }

        // Gesture was already started, or in the correct direction.
        super.touchesMoved(touches, with: event)

        if state == .began {
            let vel = velocity(in: view)
            switch direction {
            case .left, .right:
                if abs(vel.y) > abs(vel.x) {
                    state = .cancelled
                }
            case .up, .down:
                if abs(vel.x) > abs(vel.y) {
                    state = .cancelled
                }
            default:
                break
            }
        }
    }
}
