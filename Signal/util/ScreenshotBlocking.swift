//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

enum ScreenshotBlocking {
    /// Prevent screenshots (or the App Switcher) from capturing the content of
    /// the given view.
    ///
    /// This works by taking advantage of `UITextField` internals, which has
    /// built in content redaction when `isSecureTextEntry = true`, and tricking
    /// it into applying that redaction to the given view's layer.
    static func blockScreenshots(of view: UIView) {
        let textField = UITextField()

        guard
            let screenshotBlockingView = textField.subviews.first,
            String(describing: type(of: screenshotBlockingView)).contains("TextLayoutCanvasView")
        else {
            owsFailDebug("Missing expected screenshotBlockingView!")
            return
        }

        // Swap in the input view's layer for the "canvas view"'s layer, then
        // toggle isSecureTextEntry. That causes the UITextField to apply the
        // "redact content" flag to the input view's layer, at which point we're
        // all set.
        screenshotBlockingView.setValue(view.layer, forKey: "layer")
        textField.isSecureTextEntry = false
        textField.isSecureTextEntry = true
    }
}
