//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

// This GR:
//
// * Tries to fail quickly to avoid conflicts with other GRs, especially pans/swipes.
// * Captures a bunch of useful "pan state" that makes using this GR much easier
//   than UIPanGestureRecognizer.
public class ImageEditorPanGestureRecognizer: UIPanGestureRecognizer {

    public weak var referenceView: UIView?

    // Capture the location history of this gesture.
    public var locationHistory = [CGPoint]()

    public var locationFirst: CGPoint? {
        return locationHistory.first
    }

    // MARK: - Touch Handling

    @objc
    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        updateLocationHistory(event: event)

        super.touchesBegan(touches, with: event)
    }

    @objc
    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        updateLocationHistory(event: event)

        super.touchesMoved(touches, with: event)
    }

    @objc
    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
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

    public override func reset() {
        super.reset()

        locationHistory.removeAll()
    }
}
