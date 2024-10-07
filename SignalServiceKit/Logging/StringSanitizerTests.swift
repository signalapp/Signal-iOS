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
        let string = "abx̧c"
        let sanitized = StringSanitizer.sanitize(string)
        XCTAssertEqual(sanitized, string)
    }

    func testEmoji() {
        let string = "a👩🏿‍❤️‍💋‍👩🏻b"
        let sanitized = StringSanitizer.sanitize(string)
        XCTAssertEqual(sanitized, string)
    }

    func testZalgo() {
        let string = "x̸̢̧̛̙̝͈͈̖̳̗̰̆̈́̆̿̈́̅̽͆̈́̿̔͌̚͝abx̸̢̧̛̙̝͈͈̖̳̗̰̆̈́̆̿̈́̅̽͆̈́̿̔͌̚͝x̸̢̧̛̙̝͈͈̖̳̗̰̆̈́̆̿̈́̅̽͆̈́̿̔͌̚͝👩🏿‍❤️‍💋‍👩🏻cx̸̢̧̛̙̝͈͈̖̳̗̰̆̈́̆̿̈́̅̽͆̈́̿̔͌̚͝"
        let sanitized = StringSanitizer.sanitize(string)
        let expected = "�ab��👩🏿‍❤️‍💋‍👩🏻c�"
        XCTAssertEqual(sanitized, expected)
    }

    func testSingleZalgo() {
        let string = "x̸̢̧̛̙̝͈͈̖̳̗̰̆̈́̆̿̈́̅̽͆̈́̿̔͌̚͝"
        let sanitized = StringSanitizer.sanitize(string)
        let expected = "�"
        XCTAssertEqual(sanitized, expected)
    }

    func testTwoZalgo() {
        let string = "x̸̢̧̛̙̝͈͈̖̳̗̰̆̈́̆̿̈́̅̽͆̈́̿̔͌̚͝x̸̢̧̛̙̝͈͈̖̳̗̰̆̈́̆̿̈́̅̽͆̈́̿̔͌̚͝"
        let sanitized = StringSanitizer.sanitize(string)
        let expected = "��"
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
            "ab            cd ": "abcd"
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
            "ab  1 cd ": "abX X 1X cdX "
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
            "ab  1 ZcdX ": "  1 ZX "
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
