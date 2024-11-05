//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

extension UIView {
    @discardableResult
    public static func animate(duration: TimeInterval, delay: TimeInterval = 0, options: UIView.AnimationOptions = [], animations: @escaping () -> Void) async -> Bool {
        await withCheckedContinuation { continuation in
            animate(withDuration: duration, delay: delay, options: options, animations: animations) { isCompleted in
                continuation.resume(returning: isCompleted)
            }
        }
    }
}
