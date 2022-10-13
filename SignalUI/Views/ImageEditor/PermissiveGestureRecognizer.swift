//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

// The most permissive GR possible.
//
// * Accepts any number of touches in any locations.
// * Isn't blocked by any other GR.
// * Blocks all other GRs.
class PermissiveGestureRecognizer: UIGestureRecognizer {

    @objc
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    @objc
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    @objc
    override func shouldRequireFailure(of otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    @objc
    override func shouldBeRequiredToFail(by otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    @objc
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        handle(event: event)
    }

    @objc
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        handle(event: event)
    }

    @objc
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        handle(event: event)
    }

    @objc
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        handle(event: event)
    }

    private func handle(event: UIEvent) {
        var hasValidTouch = false
        if let allTouches = event.allTouches {
            for touch in allTouches {
                switch touch.phase {
                case .began, .moved, .stationary:
                    hasValidTouch = true
                default:
                    break
                }
            }
        }

        if hasValidTouch {
            switch self.state {
            case .possible:
                self.state = .began
            case .began, .changed:
                self.state = .changed
            default:
                self.state = .failed
            }
        } else {
            switch self.state {
            case .began, .changed:
                self.state = .ended
            default:
                self.state = .failed
            }
        }
    }
}
