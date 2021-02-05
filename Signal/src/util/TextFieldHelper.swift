//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

@objc
public class TextFieldHelper: NSObject {

    // Used to implement the UITextFieldDelegate method: `textField:shouldChangeCharactersInRange:replacementString`
    // Takes advantage of Swift's superior unicode handling to append partial pasted text without splitting multi-byte characters.
    @objc
    public class func textField(_ textField: UITextField,
                                shouldChangeCharactersInRange editingRange: NSRange,
                                replacementString: String,
                                maxByteCount: Int) -> Bool {
        self.textField(textField,
                       shouldChangeCharactersInRange: editingRange,
                       replacementString: replacementString,
                       maxByteCount: maxByteCount,
                       maxGlyphCount: nil)
    }

    public class func textField(_ textField: UITextField,
                                shouldChangeCharactersInRange editingRange: NSRange,
                                replacementString: String,
                                maxByteCount: Int? = nil,
                                maxGlyphCount: Int? = nil) -> Bool {
        // At least one must be set.
        owsAssertDebug(maxByteCount != nil || maxGlyphCount != nil)

        func hasValidLength(_ string: String) -> Bool {
            if let maxByteCount = maxByteCount {
                let byteCount = string.utf8.count
                guard byteCount <= maxByteCount else {
                    return false
                }
            }
            if let maxGlyphCount = maxGlyphCount {
                let glyphCount = string.glyphCount
                guard glyphCount <= maxGlyphCount else {
                    return false
                }
            }
            return true
        }

        let existingString = textField.text ?? ""

        // Given an NSRange, we need to interact with the NS flavor of substring

        // Filtering the string for display may insert some new characters. We need
        // to verify that after insertion the string is still within our byte bounds.
        let notFilteredForDisplay = (existingString as NSString)
            .replacingCharacters(in: editingRange, with: replacementString)
        let filteredForDisplay = notFilteredForDisplay.filterStringForDisplay()

        if hasValidLength(notFilteredForDisplay),
           hasValidLength(filteredForDisplay) {

            // Only allow the textfield to insert the replacement
            // if _both_ it's filtered and unfiltered length are
            // valid.
            //
            // * We can't measure just the filtered length or we
            //   would allow unlimited whitespace to be appended
            //   to the end of the string.
            // * We can't measure just the unfiltered length, since
            //   filterStringForDisplay() can increase the length
            //   of the string (e.g. appending Bidi characters).
            // * We can't replace the textfield contents with the
            //   filtered string, or we would prevent users from
            //   (legitimately) appending whitespace to the tail of
            //   of the string.
            return true
        }

        // Don't allow any change if inserting a single char is already over the limit (typically this means typing)
        if replacementString.count < 2 {
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

            if hasValidLength(newFilteredString) {
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
