//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

extension UIViewPropertyAnimator {
    /// Helper for adding animations to a property animator that end earlier
    /// than the inherited duration and respect the inherited timing curve.
    ///
    /// Internally sets up a keyframe animation with a keyframe ending at the
    /// relative duration specified by `durationFactor`.
    public func addAnimations(withDurationFactor durationFactor: CGFloat, _ animations: @escaping () -> Void) {
        addAnimations {
            UIView.animateKeyframes(withDuration: UIView.inheritedAnimationDuration, delay: 0) {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: durationFactor) {
                    animations()
                }
            }
        }
    }
}
