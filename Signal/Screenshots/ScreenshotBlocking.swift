//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

enum ScreenshotBlocking {
    /// Set whether screenshots (or the App Switcher) can capture the content
    /// of the given view.
    ///
    /// This works by taking advantage of `UITextField` internals, which has
    /// built in content redaction when `isSecureTextEntry = true`, and tricking
    /// it into applying that redaction to the given view's layer.
    static func setBlocksScreenshots(_ blocksScreenshots: Bool, of view: UIView) {
        let textField = UITextField()

        guard
            let screenshotBlockingView = textField.subviews.first,
            String(describing: type(of: screenshotBlockingView)).contains("TextLayoutCanvasView")
        else {
            owsFailDebug("Missing expected screenshotBlockingView!")
            return
        }

        // Swap in the given view's layer for the "canvas view"'s layer, then
        // move isSecureTextEntry to the value we want. That causes the
        // UITextField to set (or clear) the "redact content" flag on the given
        // view's layer, at which point we're all set.
        let canvasLayer = screenshotBlockingView.layer
        let layerDelegate = view.layer.delegate as AnyObject?

        screenshotBlockingView.setValue(view.layer, forKey: "layer")
        textField.isSecureTextEntry = !blocksScreenshots
        textField.isSecureTextEntry = blocksScreenshots

        // Hand the canvas view its own layer back before it deallocs, since
        // otherwise it'll tear down a layer it doesn't own.
        screenshotBlockingView.setValue(canvasLayer, forKey: "layer")

        // If the text field repointed the layer's delegate at the canvas view,
        // the given view will stop drawing and laying out once we're done here.
        owsAssertDebug(view.layer.delegate as AnyObject? === layerDelegate)
    }
}
