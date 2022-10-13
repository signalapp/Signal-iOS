//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
extension UIResponder {
    private static weak var _currentFirstResponder: UIResponder?
    static var currentFirstResponder: UIResponder? {
        _currentFirstResponder = nil
        // Passing `nil` to the to parameter of `sendAction` calls it on the firstResponder.
        UIApplication.shared.sendAction(#selector(findFirstResponder), to: nil, from: nil, for: nil)
        return _currentFirstResponder
    }

    private func findFirstResponder() {
        UIResponder._currentFirstResponder = self
    }
}
