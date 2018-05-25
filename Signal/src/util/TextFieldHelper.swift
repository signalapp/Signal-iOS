//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
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
        let removedString = (existingString as NSString).substring(with: editingRange)

        let lengthOfRemainingExistingString = byteLength(existingString) - byteLength(removedString)

        let newLength = lengthOfRemainingExistingString + byteLength(replacementString)

        if (newLength <= byteLimit) {
            return true
        }

        // Don't allow any change if inserting a single char is already over the limit (typically this means typing)
        if (replacementString.count < 2) {
            return false
        }

        // However if pasting, accept as much of the string as possible.
        let availableSpace = byteLimit - lengthOfRemainingExistingString

        var acceptableSubstring = ""

        for (_, char) in replacementString.enumerated() {
            var maybeAcceptableSubstring = acceptableSubstring
            maybeAcceptableSubstring.append(char)
            if (byteLength(maybeAcceptableSubstring) <= availableSpace) {
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
