//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

@objc public class TextFieldHelper: NSObject {

    // Used to implement the UITextFieldDelegate method: `textField:shouldChangeCharactersInRange:replacementString`
    // Takes advantage of Swift's superior unicode handling to append partial pasted text without splitting multi-byte characters.
    @objc public class func textField(_ textField: UITextField, shouldChangeCharactersInRange editingRange: NSRange, replacementString: String, byteLimit: UInt) -> Bool {

        let byteLength = { (string: String) -> UInt in
            return UInt(string.utf8.count)
        }

        let existingString = textField.text ?? ""

        // Given an NSRange, we need to interact with the NS flavor of substring

        // Filtering the string for display may insert some new characters. We need
        // to verify that after insertion the string is still within our byte bounds.
        let filteredForDisplay = (existingString as NSString)
            .replacingCharacters(in: editingRange, with: replacementString)
            .filterStringForDisplay()

        let newLength = byteLength(filteredForDisplay)

        if (newLength <= byteLimit) {
            return true
        }

        // Don't allow any change if inserting a single char is already over the limit (typically this means typing)
        if (replacementString.count < 2) {
            return false
        }

        // However if pasting, accept as much of the string as possible.
        var acceptableSubstring = ""

        for (_, char) in replacementString.enumerated() {
            var maybeAcceptableSubstring = acceptableSubstring
            maybeAcceptableSubstring.append(char)

            let newFilteredString = (existingString as NSString)
                .replacingCharacters(in: editingRange, with: maybeAcceptableSubstring)
                .filterStringForDisplay()

            if (byteLength(newFilteredString) <= byteLimit) {
                acceptableSubstring = maybeAcceptableSubstring
            } else {
                break
            }
        }

        textField.text = (existingString as NSString).replacingCharacters(in: editingRange, with: acceptableSubstring)

        // We've already handled any valid editing manually, so prevent further changes.
        return false
    }
}
