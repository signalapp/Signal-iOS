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

    public var locationStart: CGPoint?

    // MARK: - Touch Handling

    @objc
    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)

        guard let referenceView = referenceView else {
            owsFailDebug("Missing view")
            return
        }
        locationStart = self.location(in: referenceView)
    }

    public override func reset() {
        super.reset()

        locationStart = nil
    }
}
