//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Testing
@testable import SignalServiceKit

struct StringSanitizerTests {
    @Test(arguments: [
        ("", nil),
        ("abc", nil),
        ("abx\u{327}c", nil),
        ("a\u{1f469}\u{1f3ff}\u{200d}\u{2764}\u{fe0f}\u{200d}\u{1f48b}\u{200d}\u{1f469}\u{1f3fb}b", nil),
        (
            "x\u{338}\u{306}\u{344}\u{31b}\u{306}\u{33f}\u{344}\u{31a}\u{305}\u{33d}\u{346}\u{35d}\u{344}\u{33f}\u{314}\u{34c}\u{319}\u{31d}\u{322}\u{348}\u{348}\u{316}\u{327}\u{333}\u{317}\u{330}abx\u{338}\u{306}\u{344}\u{31b}\u{306}\u{33f}\u{344}\u{31a}\u{305}\u{33d}\u{346}\u{35d}\u{344}\u{33f}\u{314}\u{34c}\u{319}\u{31d}\u{322}\u{348}\u{348}\u{316}\u{327}\u{333}\u{317}\u{330}x\u{338}\u{306}\u{344}\u{31b}\u{306}\u{33f}\u{344}\u{31a}\u{305}\u{33d}\u{346}\u{35d}\u{344}\u{33f}\u{314}\u{34c}\u{319}\u{31d}\u{322}\u{348}\u{348}\u{316}\u{327}\u{333}\u{317}\u{330}\u{1f469}\u{1f3ff}\u{200d}\u{2764}\u{fe0f}\u{200d}\u{1f48b}\u{200d}\u{1f469}\u{1f3fb}cx\u{338}\u{306}\u{344}\u{31b}\u{306}\u{33f}\u{344}\u{31a}\u{305}\u{33d}\u{346}\u{35d}\u{344}\u{33f}\u{314}\u{34c}\u{319}\u{31d}\u{322}\u{348}\u{348}\u{316}\u{327}\u{333}\u{317}\u{330}",
            "\u{fffd}ab\u{fffd}\u{fffd}\u{1f469}\u{1f3ff}\u{200d}\u{2764}\u{fe0f}\u{200d}\u{1f48b}\u{200d}\u{1f469}\u{1f3fb}c\u{fffd}",
        ),
        (
            "x\u{338}\u{306}\u{344}\u{31b}\u{306}\u{33f}\u{344}\u{31a}\u{305}\u{33d}\u{346}\u{35d}\u{344}\u{33f}\u{314}\u{34c}\u{319}\u{31d}\u{322}\u{348}\u{348}\u{316}\u{327}\u{333}\u{317}\u{330}",
            "\u{fffd}",
        ),
        (
            "x\u{338}\u{306}\u{344}\u{31b}\u{306}\u{33f}\u{344}\u{31a}\u{305}\u{33d}\u{346}\u{35d}\u{344}\u{33f}\u{314}\u{34c}\u{319}\u{31d}\u{322}\u{348}\u{348}\u{316}\u{327}\u{333}\u{317}\u{330}x\u{338}\u{306}\u{344}\u{31b}\u{306}\u{33f}\u{344}\u{31a}\u{305}\u{33d}\u{346}\u{35d}\u{344}\u{33f}\u{314}\u{34c}\u{319}\u{31d}\u{322}\u{348}\u{348}\u{316}\u{327}\u{333}\u{317}\u{330}",
            "\u{fffd}\u{fffd}",
        ),
    ])
    func testSanitize(testCase: (original: String, expected: String?)) {
        #expect(StringSanitizer.sanitize(testCase.original) == (testCase.expected ?? testCase.original))
    }
}

struct StringReplacementTests {
    @Test(arguments: [
        ("", "", true, ""),
        (" ", "", true, ""),
        ("         ", "", true, ""),
        ("a", "a", true, ""),
        ("abcd", "abcd", true, ""),
        (" abcd ", "abcd", true, ""),
        ("abcd ", "abcd", true, ""),
        (" abcd", "abcd", true, ""),
        ("ab cd", "abcd", true, ""),
        ("ab  1 cd ", "ab1cd", true, ""),
        ("ab            cd ", "abcd", true, ""),
        ("", "", true, "X "),
        ("abcd", "abcd", true, "X "),
        (" abcd ", "X abcdX ", true, "X "),
        ("abcd ", "abcdX ", true, "X "),
        (" abcd", "X abcd", true, "X "),
        ("ab cd", "abX cd", true, "X "),
        ("ab  1 cd ", "abX X 1X cdX ", true, "X "),
        ("", "", false, ""),
        ("abcd", "", false, ""),
        (" abcd ", "  ", false, ""),
        ("abcd ", " ", false, ""),
        (" abcd", " ", false, ""),
        ("ab cd", " ", false, ""),
        ("ab  1 cd ", "  1  ", false, ""),
        ("ab  1 ZcdX ", "  1 ZX ", false, ""),
    ])
    func testEquivalent(testCase: (original: String, expected: String, isWhitespacesAndNewlines: Bool, replacement: String)) {
        var characterSet: CharacterSet
        if testCase.isWhitespacesAndNewlines {
            characterSet = .whitespacesAndNewlines
        } else {
            characterSet = .punctuationCharacters
            characterSet.formUnion(.lowercaseLetters)
        }
        let result = testCase.original.replaceCharacters(characterSet: characterSet, replacement: testCase.replacement)
        #expect(result == testCase.expected)
    }
}
