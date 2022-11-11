//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

// This GR:
//
// * Tries to fail quickly to avoid conflicts with other GRs, especially pans/swipes.
// * Captures a bunch of useful "pan state" that makes using this GR much easier
//   than UIPanGestureRecognizer.
class ImageEditorPanGestureRecognizer: UIPanGestureRecognizer {

    weak var referenceView: UIView?

    // Capture the location history of this gesture.
    var locationHistory = [CGPoint]()

    var locationFirst: CGPoint? {
        return locationHistory.first
    }

    // MARK: - Touch Handling

    @objc
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        updateLocationHistory(event: event)

        super.touchesBegan(touches, with: event)
    }

    @objc
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        updateLocationHistory(event: event)

        super.touchesMoved(touches, with: event)
    }

    @objc
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        updateLocationHistory(event: event)

        super.touchesEnded(touches, with: event)
    }

    private func updateLocationHistory(event: UIEvent) {
        guard let touches = event.allTouches,
            touches.count > 0 else {
                owsFailDebug("no touches.")
                return
        }
        guard let referenceView = referenceView else {
            owsFailDebug("Missing view")
            return
        }
        // Find the centroid.
        var location = CGPoint.zero
        for touch in touches {
            location = location.plus(touch.location(in: referenceView))
        }
        location = location.times(CGFloat(1) / CGFloat(touches.count))
        locationHistory.append(location)
    }

    override func reset() {
        super.reset()

        locationHistory.removeAll()
    }
}
