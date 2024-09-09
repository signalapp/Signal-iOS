//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import SignalServiceKit
import XCTest

final class StringExtensionTests: XCTestCase {

    func testBalancedBidiControlCharacters() throws {
        let scalarBidiLeftToRightIsolate: Unicode.Scalar = "\u{2066}"
        let scalarBidiRightToLeftIsolate: Unicode.Scalar = "\u{2067}"
        let scalarBidiFirstStrongIsolate: Unicode.Scalar = "\u{2068}"
        let scalarBidiLeftToRightEmbedding: Unicode.Scalar = "\u{202A}"
        let scalarBidiRightToLeftEmbedding: Unicode.Scalar = "\u{202B}"
        let scalarBidiLeftToRightOverride: Unicode.Scalar = "\u{202D}"
        let scalarBidiRightToLeftOverride: Unicode.Scalar = "\u{202E}"
        let scalarBidiPopDirectionalFormatting: Unicode.Scalar = "\u{202C}"
        let scalarBidiPopDirectionalIsolate: Unicode.Scalar = "\u{2069}"

        let bidiLeftToRightIsolate = Character(scalarBidiLeftToRightIsolate)
        let bidiRightToLeftIsolate = Character(scalarBidiRightToLeftIsolate)
        let bidiFirstStrongIsolate = Character(scalarBidiFirstStrongIsolate)
        let bidiLeftToRightEmbedding = Character(scalarBidiLeftToRightEmbedding)
        let bidiRightToLeftEmbedding = Character(scalarBidiRightToLeftEmbedding)
        let bidiLeftToRightOverride = Character(scalarBidiLeftToRightOverride)
        let bidiRightToLeftOverride = Character(scalarBidiRightToLeftOverride)
        let bidiPopDirectionalFormatting = Character(scalarBidiPopDirectionalFormatting)
        let bidiPopDirectionalIsolate = Character(scalarBidiPopDirectionalIsolate)

        XCTAssertEqual("A", "A".ensureBalancedBidiControlCharacters())

        // If we have too many isolate starts, append PDI to balance
        let string1 = "ABC\(bidiLeftToRightIsolate)"
        XCTAssertEqual("\(string1)\(bidiPopDirectionalIsolate)", string1.ensureBalancedBidiControlCharacters())

        // Control characters interspersed with printing characters.
        let string2 = "ABC\(bidiLeftToRightIsolate)E\(bidiLeftToRightIsolate)"
        XCTAssertEqual("\(string2)\(bidiPopDirectionalIsolate)\(bidiPopDirectionalIsolate)", string2.ensureBalancedBidiControlCharacters())

        // Various kinds of isolate starts.
        let string3 = "ABC\(bidiLeftToRightIsolate)E\(bidiRightToLeftIsolate)E\(bidiFirstStrongIsolate)"
        XCTAssertEqual("\(string3)\(bidiPopDirectionalIsolate)\(bidiPopDirectionalIsolate)\(bidiPopDirectionalIsolate)", string3.ensureBalancedBidiControlCharacters())

        // If we have too many isolate pops, prepend FSI to balance
        // Various kinds of isolate starts.
        let string4 = "ABC\(bidiPopDirectionalIsolate)E\(bidiPopDirectionalIsolate)E\(bidiPopDirectionalIsolate)"
        XCTAssertEqual("\(bidiFirstStrongIsolate)\(bidiFirstStrongIsolate)\(bidiFirstStrongIsolate)\(string4)", string4.ensureBalancedBidiControlCharacters())

        // If we have too many formatting starts, append PDF to balance
        let string5 = "ABC\(bidiLeftToRightEmbedding)E\(bidiRightToLeftEmbedding)E\(bidiLeftToRightOverride)E\(bidiRightToLeftOverride)"
        XCTAssertEqual("\(string5)\(bidiPopDirectionalFormatting)\(bidiPopDirectionalFormatting)\(bidiPopDirectionalFormatting)\(bidiPopDirectionalFormatting)", string5.ensureBalancedBidiControlCharacters())

        // If we have too many formatting pops, prepend LRE to balance
        let string6 = "ABC\(bidiPopDirectionalFormatting)E\(bidiPopDirectionalFormatting)E\(bidiPopDirectionalFormatting)E\(bidiPopDirectionalFormatting)"
        XCTAssertEqual("\(bidiLeftToRightEmbedding)\(bidiLeftToRightEmbedding)\(bidiLeftToRightEmbedding)\(bidiLeftToRightEmbedding)\(string6)", string6.ensureBalancedBidiControlCharacters())
    }

    func testfilterUnsafeFilenameCharacters() throws {
        XCTAssertEqual("1", "1".filterUnsafeFilenameCharacters())
        XCTAssertEqual("alice\u{FFFD}bob", "alice\u{202D}bob".filterUnsafeFilenameCharacters())
        XCTAssertEqual("\u{FFFD}alicebob", "\u{202D}alicebob".filterUnsafeFilenameCharacters())
        XCTAssertEqual("alicebob\u{FFFD}", "alicebob\u{202D}".filterUnsafeFilenameCharacters())
        XCTAssertEqual("alice\u{FFFD}bob", "alice\u{202E}bob".filterUnsafeFilenameCharacters())
        XCTAssertEqual("\u{FFFD}alicebob", "\u{202E}alicebob".filterUnsafeFilenameCharacters())
        XCTAssertEqual("alicebob\u{FFFD}", "alicebob\u{202E}".filterUnsafeFilenameCharacters())
        XCTAssertEqual("alice\u{FFFD}bobalice\u{FFFD}bob", "alice\u{202D}bobalice\u{202E}bob".filterUnsafeFilenameCharacters())
    }
}
