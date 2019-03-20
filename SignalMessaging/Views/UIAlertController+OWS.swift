//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

extension UIAlertController {
    @objc
    public func applyAccessibilityIdentifiers() {
        for action in actions {
            guard let view = action.value(forKey: "__representer") as? UIView else {
                owsFailDebug("Missing representer.")
                continue
            }
            view.accessibilityIdentifier = action.accessibilityIdentifier
        }
    }
}

// MARK: -

extension UIAlertAction {
    private struct AssociatedKeys {
        static var AccessibilityIdentifier = "ows_accessibilityIdentifier"
    }

    @objc
    public var accessibilityIdentifier: String? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.AccessibilityIdentifier) as? String
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.AccessibilityIdentifier, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)
        }
    }
}
