//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

public extension UIViewPropertyAnimator {

    convenience init (
        duration: TimeInterval,
        springDamping: CGFloat,
        springResponse: CGFloat,
        initialVelocity velocity: CGVector = .zero
    ) {
        let stiffness = pow(2 * .pi / springResponse, 2)
        let damping = 4 * .pi * springDamping / springResponse
        let timingParameters = UISpringTimingParameters(
            mass: 1,
            stiffness: stiffness,
            damping: damping,
            initialVelocity: velocity
        )
        self.init(duration: duration, timingParameters: timingParameters)
        isUserInteractionEnabled = true
    }
}
