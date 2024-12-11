//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public class TextFieldFormatting {

    private init() {}

    // Performs cursory validation and change handling for phone number text field edits
    // Allows UIKit to apply the majority of edits (unlike +phoneNumberTextField:changeCharacters...")
    // which applies the edit manually.
    // Useful when +phoneNumberTextField:changeCharactersInRange:... can't be used
    // because it applies changes manually and requires failing any change request from UIKit.
    public static func phoneNumberTextField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString insertionText: String,
        plusPrefixedCallingCode: String
    ) -> Bool {

        let isDeletion = insertionText.isEmpty
        guard !isDeletion else { return true }

        // If we're deleting text, we're going to want to ignore
        // parens and spaces when finding a character to delete.

        // Let's tell UIKit to not apply the edit and just apply it ourselves.
        phoneNumberTextField(textField, changeCharactersIn: range, replacementString: insertionText, plusPrefixedCallingCode: plusPrefixedCallingCode)
        return false
    }

    // Reformats the text in a UITextField to apply phone number formatting
    public static func reformatPhoneNumberTextField(_ textField: UITextField, plusPrefixedCallingCode: String) {

        let originalCursorOffset: Int
        if let selectedTextRange = textField.selectedTextRange {
            originalCursorOffset = textField.offset(from: textField.beginningOfDocument, to: selectedTextRange.start)
        } else {
            originalCursorOffset = 0
        }

        let originalText = textField.text ?? ""
        let trimmedText = originalText.digitsOnly().phoneNumberTrimmedToMaxLength
        let updatedText = PhoneNumber.bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber(trimmedText, plusPrefixedCallingCode: plusPrefixedCallingCode)

        let updatedCursorOffset = PhoneNumberUtil.translateCursorPosition(
            UInt(originalCursorOffset),
            from: originalText,
            to: updatedText,
            stickingRightward: false
        )
        textField.text = updatedText
        if let position = textField.position(from: textField.beginningOfDocument, offset: Int(updatedCursorOffset)) {
            textField.selectedTextRange = textField.textRange(from: position, to: position)
        }
    }

    // This convenience function can be used to reformat the contents of
    // a phone number text field as the user modifies its text by typing,
    // pasting, etc. Applies the incoming edit directly. The text field delegate
    // should return NO from -textField:shouldChangeCharactersInRange:...
    //
    // "callingCode" should be of the form: "+1".
    public static func phoneNumberTextField(
        _ textField: UITextField,
        changeCharactersIn range: NSRange,
        replacementString insertionText: String,
        plusPrefixedCallingCode: String
    ) {
        // Phone numbers takes many forms.
        //
        // * We only want to let the user enter decimal digits.
        // * The user shouldn't have to enter hyphen, parentheses or whitespace;
        //   the phone number should be formatted automatically.
        // * The user should be able to copy and paste freely.
        // * Invalid input should be simply ignored.
        //
        // We accomplish this by being permissive and trying to "take as much of the user
        // input as possible".
        //
        // * Always accept deletes.
        // * Ignore invalid input.
        // * Take partial input if possible.

        let oldText = textField.text ?? ""

        // Construct the new contents of the text field by:
        // 1. Determining the "left" substring: the contents of the old text _before_ the deletion range.
        //    Filtering will remove non-decimal digit characters like hyphen "-".
        var left = (oldText as NSString).substring(to: range.location).digitsOnly()
        // 2. Determining the "right" substring: the contents of the old text _after_ the deletion range.
        let right = (oldText as NSString).substring(from: range.location + range.length).digitsOnly()
        // 3. Determining the "center" substring: the contents of the new insertion text.
        let center = insertionText.digitsOnly()

        // 3a. If user hits backspace, they should always delete a _digit_ to the
        //     left of the cursor, even if the text _immediately_ to the left of
        //     cursor is "formatting text" (e.g. whitespace, a hyphen or a
        //     parentheses).
        let isJustDeletion = insertionText.isEmpty
        if isJustDeletion {
            let deletedText = (oldText as NSString).substring(with: range)
            let didDeleteFormatting = deletedText.count == 1 && deletedText.digitsOnly().isEmpty
            if didDeleteFormatting && !left.isEmpty {
                left = String(left.dropLast())
            }
        }

        // 4. Construct the "raw" new text by concatenating left, center and right.
        //    Ensure we don't exceed the maximum length for a e164 phone number
        let textAfterChange = left.appending(center).appending(right).phoneNumberTrimmedToMaxLength

        // 5. Construct the "formatted" new text by inserting a hyphen if necessary.
        // reformat the phone number, trying to keep the cursor beside the inserted or deleted digit
        let cursorPositionAfterChange = min(left.utf16.count + center.utf16.count, textAfterChange.utf16.count)

        let formattedText = PhoneNumber.bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber(textAfterChange, plusPrefixedCallingCode: plusPrefixedCallingCode)
        let cursorPositionAfterReformat = PhoneNumberUtil.translateCursorPosition(
            UInt(cursorPositionAfterChange),
            from: textAfterChange,
            to: formattedText,
            stickingRightward: isJustDeletion
        )

        textField.text = formattedText

        if let position = textField.position(from: textField.beginningOfDocument, offset: Int(cursorPositionAfterReformat)) {
            textField.selectedTextRange = textField.textRange(from: position, to: position)
        }
    }

    public static func ows2FAPINTextField(
        _ textField: UITextField,
        changeCharactersIn range: NSRange,
        replacementString insertionText: String
    ) {
        // * We only want to let the user enter decimal digits.
        // * The user should be able to copy and paste freely.
        // * Invalid input should be simply ignored.
        //
        // We accomplish this by being permissive and trying to "take as much of the user
        // input as possible".
        //
        // * Always accept deletes.
        // * Ignore invalid input.
        // * Take partial input if possible.

        let oldText = textField.text ?? ""
        // Construct the new contents of the text field by:
        // 1. Determining the "left" substring: the contents of the old text _before_ the deletion range.
        //    Filtering will remove non-decimal digit characters.
        let left = (oldText as NSString).substring(to: range.location).digitsOnly()
        // 2. Determining the "right" substring: the contents of the old text _after_ the deletion range.
        let right = (oldText as NSString).substring(from: range.location + range.length).digitsOnly()
        // 3. Determining the "center" substring: the contents of the new insertion text.
        let center = insertionText.digitsOnly()
        // 4. Construct the "raw" new text by concatenating left, center and right.
        let textAfterChange = left.appending(center).appending(right)
        // 5. Ensure we don't exceed the maximum length for a PIN.
        // We explicitly no longer do this here. We don't want to truncate passwords.
        // Instead, we rely on the view to notify when the user's pin is too long.
        // 6. Construct the final text.
        textField.text = textAfterChange

        let cursorPositionAfterChange = min(left.utf16.count + center.utf16.count, textAfterChange.utf16.count)
        if let position = textField.position(from: textField.beginningOfDocument, offset: cursorPositionAfterChange) {
            textField.selectedTextRange = textField.textRange(from: position, to: position)
        }
    }

    // The purpose of the example phone number is to indicate to the user that they should enter
    // their phone number _without_ a country calling code (e.g. +1 or +44) but _with_ area code, etc.
    public static func exampleNationalNumber(forCountryCode countryCode: String, includeExampleLabel: Bool) -> String? {
        owsAssertDebug(!countryCode.isEmpty)

        let phoneNumberUtil = SSKEnvironment.shared.phoneNumberUtilRef
        let countryCodeForParsing = phoneNumberUtil.countryCodeForParsing(fromCountryCode: countryCode)
        guard let nationalNumber = phoneNumberUtil.exampleNationalNumber(forCountryCode: countryCodeForParsing) else {
            owsFailDebug("examplePhoneNumber == nil")
            return nil
        }

        guard includeExampleLabel else {
            return nationalNumber
        }

        let formatString = OWSLocalizedString(
            "PHONE_NUMBER_EXAMPLE_FORMAT",
            comment: "A format for a label showing an example phone number. Embeds {{the example phone number}}."
        )
        return String(format: formatString, nationalNumber)
    }
}

private extension String {

    private static let kMaxPhoneNumberLength: Int = 18

    var phoneNumberTrimmedToMaxLength: String {
        // Ensure we don't exceed the maximum length for a e164 phone number,
        // 15 digits, per: https://en.wikipedia.org/wiki/E.164
        //
        // NOTE: The actual limit is 18, not 15, because of certain invalid phone numbers in Germany.
        //       https://github.com/googlei18n/libphonenumber/blob/master/FALSEHOODS.md
        if self.count > Self.kMaxPhoneNumberLength {
            return String(self.prefix(Self.kMaxPhoneNumberLength))
        }
        return self
    }
}
