//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

public extension UIView {
    @discardableResult
    static func animate(_: PromiseNamespace, duration: TimeInterval, delay: TimeInterval = 0, options: UIView.AnimationOptions = [], animations: @escaping () -> Void) -> Guarantee<Bool> {
        return Guarantee { animate(withDuration: duration, delay: delay, options: options, animations: animations, completion: $0) }
    }

    @discardableResult
    static func animate(_: PromiseNamespace, duration: TimeInterval, delay: TimeInterval, usingSpringWithDamping damping: CGFloat, initialSpringVelocity: CGFloat, options: UIView.AnimationOptions = [], animations: @escaping () -> Void) -> Guarantee<Bool> {
        return Guarantee { animate(withDuration: duration, delay: delay, usingSpringWithDamping: damping, initialSpringVelocity: initialSpringVelocity, options: options, animations: animations, completion: $0) }
    }
}
