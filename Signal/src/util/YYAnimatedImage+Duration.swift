//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import YYImage

public extension YYAnimatedImage {

    /// YYAnimatedImageView's duration sometimes returns 0 duration even when this extended method works.
    var duration: TimeInterval? {
        let frameCount = self.animatedImageFrameCount()
        guard frameCount > 0 else {
            return nil
        }
        return (0..<frameCount).reduce(0, { sum, frame in
            return sum + self.animatedImageDuration(at: frame)
        })
    }
}
