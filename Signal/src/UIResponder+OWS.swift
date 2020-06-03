//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc extension UIResponder {
    private static weak var _currentFirstResponder: UIResponder?
    static var currentFirstResponder: UIResponder? {
        _currentFirstResponder = nil
        // Passing `nil` to the to paramter of `sendAction` calls it on the firstResponder.
        UIApplication.shared.sendAction(#selector(findFirstResponder), to: nil, from: nil, for: nil)
        return _currentFirstResponder
    }

    private func findFirstResponder() {
        UIResponder._currentFirstResponder = self
    }
}
