//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit
import SignalServiceKit

/// Attach this to a ``UITextField`` to auto-format it and restrict input to
/// ASCII digits.
///
/// For example, this can be used to format credit card numbers.
///
/// This could be made more generic (for example, supporting non-numbers or more
/// powerful formatting), but it works well enough for us.
///
/// You may wish to see the tests, which demonstrate how this behaves.
public enum FormattedNumberField {
    struct OperationResult {
        let formattedString: String
        let cursorPosition: Int
    }

    enum SingleDeletionDirection {
        case backward
        case forward
    }

    /// Call this from your [`UITextFieldDelegate#textField`][0] method.
    /// This will restrict inputs and format the text.
    ///
    /// - Parameter textField:
    /// The text field. Pass the value from your delegate method.
    /// - Parameter shouldChangeCharactersIn:
    /// The range to be replaced. Pass the value from your delegate method.
    /// - Parameter replacementString:
    /// The replacement string. Pass the value from your delegate method.
    /// - Parameter maxDigits:
    /// The maximum number of digits allowed. Trying to type more digits than
    /// this won't be allowed, but it's possible for the field to be longer
    /// than this if you set the value programmatically or change this value.
    /// - Parameter format:
    /// A function that turns an unformatted string (such as "42424242") into
    /// a formatted one (such as "4242 4242"). Must only include printable ASCII
    /// characters, and no numbers should be added, removed, or moved during
    /// formatting. (Printable ASCII characters are required because
    /// `UITextField` deals with UTF-16 code points and we don't want to handle
    /// any trickiness with conversion to UTF-8.)
    /// - Returns:
    /// `false`, which is what the caller should return.
    ///
    /// [0]: https://developer.apple.com/documentation/uikit/uitextfielddelegate/1619599-textfield
    public static func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString: String,
        maxDigits: Int,
        format: (String) -> String
    ) -> Bool {
        let operationResult: OperationResult? = {
            let oldFormattedString = textField.text ?? ""
            let isSingleDeletion = range.length == 1 && replacementString.isEmpty
            if isSingleDeletion {
                let cursorPosition = textField.offset(
                    from: textField.beginningOfDocument,
                    to: textField.selectedTextRange?.start ?? textField.beginningOfDocument
                )
                return singleDelete(
                    formattedString: oldFormattedString,
                    cursorPosition: cursorPosition,
                    direction: cursorPosition == range.location ? .forward : .backward,
                    format: format
                )
            } else {
                return insertOrReplace(
                    formattedString: oldFormattedString,
                    selectionStart: range.location,
                    selectionEnd: range.upperBound,
                    rawInsertion: replacementString,
                    maxDigits: maxDigits,
                    format: format
                )
            }
        }()

        if let operationResult {
            textField.text = operationResult.formattedString
            let newCursorPosition = textField.position(
                from: textField.beginningOfDocument,
                offset: operationResult.cursorPosition
            )
            guard let newCursorPosition else {
                owsFail("Could not get cursor position after formatting")
            }
            textField.selectedTextRange = textField.textRange(from: newCursorPosition, to: newCursorPosition)
        }

        return false
    }

    // MARK: - Abstract operation logic

    /// Turn a position inside a formatted string into the position in an
    /// unformatted version of the string.
    ///
    /// For example, imagine the formatter inserts a space between every pair
    /// of digits, so `1234567` becomes `12 34 56 7`, and that your cursor is
    /// just before the 7 (represented by the `|`):
    ///
    ///     12 34 56 |7
    ///
    /// The position in the unformatted string is also just before the 7, but
    /// numerically lower:
    ///
    ///     123456|7
    ///
    /// - Precondition:
    /// The position is actually in the string.
    /// - Parameter formattedString:
    /// The formatted string (`12 34 56 7` in the example above).
    /// - Parameter positionInFormattedString:
    /// The position in the formatted string (`9` in the example above).
    /// - Returns:
    /// The position in the unformatted string (`6` in the example above).
    private static func unformattedPosition(
        formattedString: String,
        positionInFormattedString: Int
    ) -> Int {
        formattedString
            .prefix(positionInFormattedString)
            .reduce(0) { $0 + ($1.isNumber ? 1 : 0) }
    }

    /// Turn the cursor position inside an unformatted string into the cursor
    /// position in a formatted version of the string.
    ///
    /// For example, imagine the formatter inserts a space between every pair
    /// of digits, so `1234567` becomes `12 34 56 7`, and that your cursor is
    /// just before the 7 (represented by the `|`):
    ///
    ///     123456|7
    ///
    /// The position in the formatted string is between the 6 and the 7. It
    /// could be in either of these two spots:
    ///
    ///     12 34 56| 7
    ///     12 34 56 |7
    ///
    /// Because it's ambiguous, we return the upper and lower bounds.
    ///
    /// - Precondition:
    /// The position is actually in the string.
    /// - Parameter formattedString:
    /// The formatted string (`12 34 56 7` in the example above).
    /// - Parameter unformattedString:
    /// The formatted string (`1234567` in the example above).
    /// - Parameter positionInUnformattedString:
    /// The position in the unformatted string (`6` in the example above).
    /// - Returns:
    /// The upper and lower bounds of the position in the formatted string
    /// (`8` or `9` in the example above). May be the same if the result can
    /// be determined unambiguously.
    private static func formattedPosition(
        unformattedString: String,
        positionInUnformattedString: Int,
        formattedString: String
    ) -> (lower: Int, upper: Int) {
        var lower: Int?
        var upper: Int?

        for i in (0...formattedString.count) {
            let unformattedCursorPosition = unformattedPosition(
                formattedString: formattedString,
                positionInFormattedString: i
            )
            if unformattedCursorPosition == positionInUnformattedString {
                lower = lower ?? i
                upper = i
            }
        }

        if let lower, let upper {
            return (lower: lower, upper: upper)
        } else {
            let end = formattedString.count
            return (lower: end, upper: end)
        }
    }

    /// Delete a single character (e.g., with Backspace).
    ///
    /// Most notably handles deletions across boundaries. For example, imagine
    /// the formatter inserts a space between every pair of digits, so `1234`
    /// becomes `12 34`. If your cursor is on either side of the space, the `2`
    /// should be removed if you delete backwards, and `3` if you delete
    /// forwards.
    ///
    /// - Parameter formattedString:
    /// The formatted string (`12 34` in the example above).
    /// - Parameter cursorPosition:
    /// The current cursor position (`2` or `3` in the example above).
    /// - Parameter direction:
    /// The direction to delete: forward or backward.
    /// - Parameter format:
    /// A function to format the string. See earlier comments for details.
    /// - Returns:
    /// The new formatted string and the new cursor position. If this deletion
    /// makes no change, `nil` is returned.
    static func singleDelete(
        formattedString: String,
        cursorPosition: Int,
        direction: SingleDeletionDirection,
        format: (String) -> String
    ) -> OperationResult? {
        let oldUnformattedString = formattedString.asciiDigitsOnly
        if oldUnformattedString.isEmpty {
            return nil
        }

        let cursorPositionInOldUnformattedString = Self.unformattedPosition(
            formattedString: formattedString,
            positionInFormattedString: cursorPosition
        )

        let cursorOffset: Int
        switch direction {
        case .backward: cursorOffset = -1
        case .forward: cursorOffset = 0
        }

        let offsetToRemove = cursorPositionInOldUnformattedString + cursorOffset
        guard (0..<oldUnformattedString.count).contains(offsetToRemove) else {
            return nil
        }

        var newUnformattedString = oldUnformattedString
        let indexToRemove = newUnformattedString.index(
            newUnformattedString.startIndex,
            offsetBy: offsetToRemove
        )
        newUnformattedString.remove(at: indexToRemove)

        let newFormattedString = format(newUnformattedString)

        let cursorPositionInNewFormattedString = Self.formattedPosition(
            unformattedString: newUnformattedString,
            positionInUnformattedString: cursorPositionInOldUnformattedString + cursorOffset,
            formattedString: newFormattedString
        ).lower

        return .init(
            formattedString: newFormattedString,
            cursorPosition: cursorPositionInNewFormattedString
        )
    }

    /// Insert a string, possibly an empty one, inside a selection.
    ///
    /// For example, imagine the formatter inserts a space between every pair of
    /// digits, so `1234` becomes `12 34`. If your cursor is at the end and you
    /// type a `5`, the new value should be `12 34 5`.
    ///
    /// - Parameter formattedString:
    /// The formatted string (`12 34` in the example above).
    /// - Parameter selectionStart:
    /// The start of the current selection.
    /// - Parameter selectionEnd:
    /// The end of the current selection. May be the same as `selectionStart`.
    /// - Parameter rawInsertion:
    /// The string to be inserted, possibly empty. Non-numbers are filtered.
    /// - Parameter maxDigits:
    /// The maximum number of digits. See earlier comments for details.
    /// - Parameter format:
    /// A function to format the string. See earlier comments for details.
    /// - Returns:
    /// The new formatted string and the new cursor position. If this action
    /// makes no change, `nil` is returned.
    static func insertOrReplace(
        formattedString: String,
        selectionStart: Int,
        selectionEnd: Int,
        rawInsertion: String,
        maxDigits: Int,
        format: (String) -> String
    ) -> OperationResult? {
        let insertion = rawInsertion.asciiDigitsOnly

        let selectionStartInOldUnformattedString = Self.unformattedPosition(
            formattedString: formattedString,
            positionInFormattedString: selectionStart
        )
        let selectionEndInOldUnformattedString = Self.unformattedPosition(
            formattedString: formattedString,
            positionInFormattedString: selectionEnd
        )
        let oldUnformattedString = formattedString.asciiDigitsOnly

        let newUnformattedString: String = {
            let prefix = oldUnformattedString.prefix(selectionStartInOldUnformattedString)

            let selectionEndIndex = oldUnformattedString.index(
                oldUnformattedString.startIndex,
                offsetBy: selectionEndInOldUnformattedString
            )
            let suffix = oldUnformattedString[selectionEndIndex...]

            return "\(prefix)\(insertion)\(suffix)"
        }()

        if oldUnformattedString == newUnformattedString {
            return nil
        }

        // The digit count can exceed the maximum under expected conditions.
        // This could happen if the field's text is programmatically changed or
        // if the maximum digit count is changed dynamically. Therefore, we only
        // prevent input if the change causes us to *further* exceed the limit.
        if newUnformattedString.count > oldUnformattedString.count, newUnformattedString.count > maxDigits {
            return nil
        }

        let newFormattedString = format(newUnformattedString)
        let cursorPositionInNewFormattedString = Self.formattedPosition(
            unformattedString: newUnformattedString,
            positionInUnformattedString: selectionStartInOldUnformattedString + insertion.count,
            formattedString: newFormattedString
        ).upper

        return .init(
            formattedString: newFormattedString,
            cursorPosition: cursorPositionInNewFormattedString
        )
    }
}
