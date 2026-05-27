//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

class StringSanitizerTests: XCTestCase {
    func testEmpty() {
        let string = ""
        let sanitized = StringSanitizer.sanitize(string)
        XCTAssertEqual(sanitized, string)
    }

    func testASCII() {
        let string = "abc"
        let sanitized = StringSanitizer.sanitize(string)
        XCTAssertEqual(sanitized, string)
    }

    func testCombiningMarks() {
        let string = "abx\u{327}c"
        let sanitized = StringSanitizer.sanitize(string)
        XCTAssertEqual(sanitized, string)
    }

    func testEmoji() {
        let string = "a\u{1f469}\u{1f3ff}\u{200d}\u{2764}\u{fe0f}\u{200d}\u{1f48b}\u{200d}\u{1f469}\u{1f3fb}b"
        let sanitized = StringSanitizer.sanitize(string)
        XCTAssertEqual(sanitized, string)
    }

    func testZalgo() {
        let string = "x\u{338}\u{306}\u{344}\u{31b}\u{306}\u{33f}\u{344}\u{31a}\u{305}\u{33d}\u{346}\u{35d}\u{344}\u{33f}\u{314}\u{34c}\u{319}\u{31d}\u{322}\u{348}\u{348}\u{316}\u{327}\u{333}\u{317}\u{330}abx\u{338}\u{306}\u{344}\u{31b}\u{306}\u{33f}\u{344}\u{31a}\u{305}\u{33d}\u{346}\u{35d}\u{344}\u{33f}\u{314}\u{34c}\u{319}\u{31d}\u{322}\u{348}\u{348}\u{316}\u{327}\u{333}\u{317}\u{330}x\u{338}\u{306}\u{344}\u{31b}\u{306}\u{33f}\u{344}\u{31a}\u{305}\u{33d}\u{346}\u{35d}\u{344}\u{33f}\u{314}\u{34c}\u{319}\u{31d}\u{322}\u{348}\u{348}\u{316}\u{327}\u{333}\u{317}\u{330}\u{1f469}\u{1f3ff}\u{200d}\u{2764}\u{fe0f}\u{200d}\u{1f48b}\u{200d}\u{1f469}\u{1f3fb}cx\u{338}\u{306}\u{344}\u{31b}\u{306}\u{33f}\u{344}\u{31a}\u{305}\u{33d}\u{346}\u{35d}\u{344}\u{33f}\u{314}\u{34c}\u{319}\u{31d}\u{322}\u{348}\u{348}\u{316}\u{327}\u{333}\u{317}\u{330}"
        let sanitized = StringSanitizer.sanitize(string)
        let expected = "\u{fffd}ab\u{fffd}\u{fffd}\u{1f469}\u{1f3ff}\u{200d}\u{2764}\u{fe0f}\u{200d}\u{1f48b}\u{200d}\u{1f469}\u{1f3fb}c\u{fffd}"
        XCTAssertEqual(sanitized, expected)
    }

    func testSingleZalgo() {
        let string = "x\u{338}\u{306}\u{344}\u{31b}\u{306}\u{33f}\u{344}\u{31a}\u{305}\u{33d}\u{346}\u{35d}\u{344}\u{33f}\u{314}\u{34c}\u{319}\u{31d}\u{322}\u{348}\u{348}\u{316}\u{327}\u{333}\u{317}\u{330}"
        let sanitized = StringSanitizer.sanitize(string)
        let expected = "\u{fffd}"
        XCTAssertEqual(sanitized, expected)
    }

    func testTwoZalgo() {
        let string = "x\u{338}\u{306}\u{344}\u{31b}\u{306}\u{33f}\u{344}\u{31a}\u{305}\u{33d}\u{346}\u{35d}\u{344}\u{33f}\u{314}\u{34c}\u{319}\u{31d}\u{322}\u{348}\u{348}\u{316}\u{327}\u{333}\u{317}\u{330}x\u{338}\u{306}\u{344}\u{31b}\u{306}\u{33f}\u{344}\u{31a}\u{305}\u{33d}\u{346}\u{35d}\u{344}\u{33f}\u{314}\u{34c}\u{319}\u{31d}\u{322}\u{348}\u{348}\u{316}\u{327}\u{333}\u{317}\u{330}"
        let sanitized = StringSanitizer.sanitize(string)
        let expected = "\u{fffd}\u{fffd}"
        XCTAssertEqual(sanitized, expected)
    }
}

class StringReplacementTests: XCTestCase {

    func testEquivalent() {

        let testCases: [String: String] = [
            "": "",
            " ": "",
            "         ": "",
            "a": "a",
            "abcd": "abcd",
            " abcd ": "abcd",
            "abcd ": "abcd",
            " abcd": "abcd",
            "ab cd": "abcd",
            "ab  1 cd ": "ab1cd",
            "ab            cd ": "abcd",
        ]

        for key in testCases.keys {
            let expectedResult = testCases[key]

            let result = key.replaceCharacters(characterSet: .whitespacesAndNewlines, replacement: "")

            XCTAssertEqual(result, expectedResult)
        }
    }

    func testEquivalent2() {

        let testCases: [String: String] = [
            "": "",
            "abcd": "abcd",
            " abcd ": "X abcdX ",
            "abcd ": "abcdX ",
            " abcd": "X abcd",
            "ab cd": "abX cd",
            "ab  1 cd ": "abX X 1X cdX ",
        ]

        for key in testCases.keys {
            let expectedResult = testCases[key]

            let result = key.replaceCharacters(characterSet: .whitespacesAndNewlines, replacement: "X ")

            XCTAssertEqual(result, expectedResult)
        }
    }

    func testEquivalent3() {

        let testCases: [String: String] = [
            "": "",
            "abcd": "",
            " abcd ": "  ",
            "abcd ": " ",
            " abcd": " ",
            "ab cd": " ",
            "ab  1 cd ": "  1  ",
            "ab  1 ZcdX ": "  1 ZX ",
        ]

        for key in testCases.keys {
            let expectedResult = testCases[key]

            var characterSetUnion = CharacterSet.punctuationCharacters
            characterSetUnion.formUnion(.lowercaseLetters)

            let result = key.replaceCharacters(characterSet: characterSetUnion, replacement: "")

            XCTAssertEqual(result, expectedResult)
        }
    }
}
