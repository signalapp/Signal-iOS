//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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
        let (shouldChange, changedString) = TextHelper.shouldChangeCharactersInRange(
            with: textField.text,
            editingRange: editingRange,
            replacementString: replacementString,
            maxByteCount: maxByteCount,
            maxGlyphCount: maxGlyphCount
        )

        if let changedString = changedString {
            owsAssertDebug(!shouldChange)
            textField.text = changedString
        }

        return shouldChange
    }
}

@objc
public class TextViewHelper: NSObject {

    // Used to implement the UITextViewDelegate method: `textView:shouldChangeTextIn:replacementText`
    // Takes advantage of Swift's superior unicode handling to append partial pasted text without splitting multi-byte characters.
    @objc
    public class func textView(_ textView: UITextView,
                               shouldChangeTextIn range: NSRange,
                               replacementText: String,
                               maxByteCount: Int) -> Bool {
        self.textView(textView,
                      shouldChangeTextIn: range,
                      replacementText: replacementText,
                      maxByteCount: maxByteCount,
                      maxGlyphCount: nil)
    }

    public class func textView(_ textView: UITextView,
                               shouldChangeTextIn range: NSRange,
                               replacementText: String,
                               maxByteCount: Int? = nil,
                               maxGlyphCount: Int? = nil) -> Bool {
        let (shouldChange, changedString) = TextHelper.shouldChangeCharactersInRange(
            with: textView.text,
            editingRange: range,
            replacementString: replacementText,
            maxByteCount: maxByteCount,
            maxGlyphCount: maxGlyphCount
        )

        if let changedString = changedString {
            owsAssertDebug(!shouldChange)
            textView.text = changedString
            textView.delegate?.textViewDidChange?(textView)
        }

        return shouldChange
    }
}

public enum TextHelper {
    public static func shouldChangeCharactersInRange(
        with existingString: String?,
        editingRange: NSRange,
        replacementString: String,
        maxByteCount: Int? = nil,
        maxGlyphCount: Int? = nil
    ) -> (shouldChange: Bool, changedString: String?) {
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

        let existingString = existingString ?? ""

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
            return (shouldChange: true, changedString: nil)
        }

        // Don't allow any change if inserting a single char is already over the limit (typically this means typing)
        if replacementString.count < 2 {
            return (shouldChange: false, changedString: nil)
        }

        // However if pasting, accept as much of the string as possible.
        var acceptableSubstring = ""

        for char in replacementString {
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

        let changedString = (existingString as NSString).replacingCharacters(in: editingRange, with: acceptableSubstring)

        // We've already handled any valid editing manually, so prevent further changes.
        return (shouldChange: false, changedString: changedString)
    }
}
