//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

private let bidiLeftToRightIsolate: Unicode.Scalar = "\u{2066}"
private let bidiRightToLeftIsolate: Unicode.Scalar = "\u{2067}"
private let bidiFirstStrongIsolate: Unicode.Scalar = "\u{2068}"
private let bidiLeftToRightEmbedding: Unicode.Scalar = "\u{202A}"
private let bidiRightToLeftEmbedding: Unicode.Scalar = "\u{202B}"
private let bidiLeftToRightOverride: Unicode.Scalar = "\u{202D}"
private let bidiRightToLeftOverride: Unicode.Scalar = "\u{202E}"
private let bidiPopDirectionalFormatting: Unicode.Scalar = "\u{202C}"
private let bidiPopDirectionalIsolate: Unicode.Scalar = "\u{2069}"
private let bidiControlCharacterSet: CharacterSet = [
    bidiLeftToRightIsolate,
    bidiRightToLeftIsolate,
    bidiFirstStrongIsolate,
    bidiLeftToRightEmbedding,
    bidiRightToLeftEmbedding,
    bidiLeftToRightOverride,
    bidiRightToLeftOverride,
    bidiPopDirectionalFormatting,
    bidiPopDirectionalIsolate,
]

private let nonPrintingCharacterSet = {
    var characterSet = CharacterSet.whitespacesAndNewlines
    characterSet.formUnion(CharacterSet.controlCharacters)
    characterSet.formUnion(bidiControlCharacterSet)
    // Left-to-right and Right-to-left marks.
    characterSet.insert(charactersIn: "\u{200E}\u{200F}")
    return characterSet
}()

// 0x202D and 0x202E are the unicode ordering letters
// and can be used to control the rendering of text.
// They could be used to construct misleading attachment
// filenames that appear to have a different file extension,
// for example.
private let unsafeFilenameCharacterSet: CharacterSet = [bidiLeftToRightOverride, bidiRightToLeftOverride]

extension String {

    private func sanitized() -> String {
        // There was a sanitizer cache in the objc code. This should be linear in the length
        // of the string so unless we're calling this over and over and over again for the
        // same strings the cache doesn't seem very useful and the right place to fix things
        // is to not call this over and over again.
        StringSanitizer.sanitize(self)
    }

    /// - Warning: Only exposed for testing. Do not use.
    internal func filterUnsafeFilenameCharacters() -> String {
        StringSanitizer.sanitize(self) { c in
            c.unicodeScalars.contains { s in
                unsafeFilenameCharacterSet.contains(s)
            }
        }
    }

    public func ows_stripped() -> String {
        if unicodeScalars.allSatisfy(nonPrintingCharacterSet.contains) {
            // If string has no printing characters, consider it empty.
            return ""
        } else {
            return trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// A version of the string that only contains digits.
    ///
    /// Handles non-ASCII digits. If you only want ASCII digits, see `asciiDigitsOnly`.
    ///
    /// ```
    /// "1x2x3".digitsOnly
    /// // => "123"
    /// "١23".digitsOnly
    /// // => "١23"
    /// "1️⃣23".digitsOnly
    /// // => "123"
    /// ```
    public func digitsOnly() -> String {
        String(unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) })
    }

    public func hasAnyASCII() -> Bool {
        contains(where: \.isASCII)
    }

    public func isOnlyASCII() -> Bool {
        allSatisfy(\.isASCII)
    }

    /// Trims and filters a string for display
    public func filterStringForDisplay() -> String {
        ows_stripped().sanitized().ensureBalancedBidiControlCharacters()
    }

    public func filterFilename() -> String {
        ows_stripped().sanitized().filterUnsafeFilenameCharacters()
    }

    public func withoutBidiControlCharacters() -> String {
        // TODO: This may not be the right behavior. Investigate if it's supposed to remove all or just trim.
        trimmingCharacters(in: bidiControlCharacterSet)
    }

    public func ensureBalancedBidiControlCharacters() -> String {
        var isolateStartsCount = 0
        var isolatePopCount = 0
        var formattingStartsCount = 0
        var formattingPopCount = 0

        for c in unicodeScalars {
            switch c {
            case bidiLeftToRightIsolate, bidiRightToLeftIsolate, bidiFirstStrongIsolate:
                isolateStartsCount += 1
            case bidiPopDirectionalIsolate:
                isolatePopCount += 1
            case bidiLeftToRightEmbedding, bidiRightToLeftEmbedding, bidiLeftToRightOverride, bidiRightToLeftOverride:
                formattingStartsCount += 1
            case bidiPopDirectionalFormatting:
                formattingPopCount += 1
            default:
                break
            }
        }

        if (isolateStartsCount == isolatePopCount && formattingStartsCount == formattingPopCount) {
            return self
        }

        var balancedString = ""

        // If we have too many isolate pops, prepend FSI to balance
        while isolatePopCount > isolateStartsCount {
            balancedString += String(bidiFirstStrongIsolate)
            isolateStartsCount += 1
        }

        // If we have too many formatting pops, prepend LRE to balance
        while formattingPopCount > formattingStartsCount {
            balancedString += String(bidiLeftToRightEmbedding)
            formattingStartsCount += 1
        }

        balancedString += self

        // If we have too many formatting starts, append PDF to balance
        while formattingStartsCount > formattingPopCount {
            balancedString += String(bidiPopDirectionalFormatting)
            formattingPopCount += 1
        }

        // If we have too many isolate starts, append PDI to balance
        while isolateStartsCount > isolatePopCount {
            balancedString += String(bidiPopDirectionalIsolate)
            isolatePopCount += 1
        }

        return balancedString
    }

    public func bidirectionallyBalancedAndIsolated() -> String {
        // We're already isolated, nothing to do here.
        if let first = unicodeScalars.first, let last = unicodeScalars.last, first == bidiFirstStrongIsolate && last == bidiPopDirectionalIsolate {
            return self
        }

        return String(bidiFirstStrongIsolate) + ensureBalancedBidiControlCharacters() + String(bidiPopDirectionalIsolate)
    }
}
