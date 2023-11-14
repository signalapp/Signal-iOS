//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalUI

final class FormattedNumberFieldTest: XCTestCase {
    /// A helper that makes it easy to express test cases with concise strings.
    struct TestState: Equatable, ExpressibleByStringLiteral, CustomDebugStringConvertible {
        public let formattedString: String
        public let selectionStart: Int
        public let selectionEnd: Int

        public var debugDescription: String {
            if selectionStart == selectionEnd {
                return formattedString.inserted("|", at: selectionStart)
            } else {
                return formattedString.inserted("]", at: selectionEnd).inserted("[", at: selectionStart)
            }
        }

        public init(formattedString: String, selectionStart: Int, selectionEnd: Int) {
            self.formattedString = formattedString
            self.selectionStart = selectionStart
            self.selectionEnd = selectionEnd
        }

        public init(stringLiteral string: String) {
            self.formattedString = string
                .replacingOccurrences(of: "|", with: "")
                .replacingOccurrences(of: "[", with: "")
                .replacingOccurrences(of: "]", with: "")

            if let pipeIndex = string.firstIndex(of: "|") {
                let pipeDistance = string.distance(to: pipeIndex)
                self.selectionStart = pipeDistance
                self.selectionEnd = pipeDistance
            } else if let startIndex = string.firstIndex(of: "["), let endIndex = string.lastIndex(of: "]") {
                self.selectionStart = string.distance(to: startIndex)
                self.selectionEnd = string.distance(to: endIndex) - 1
            } else {
                fatalError("Test was not set up correctly. String was badly formatted: \(string)")
            }
        }
    }

    private func testFormat(_ str: String) -> String {
        var result = [Character]()
        var charactersInGroup: UInt8 = 0
        for character in str {
            result.append(character)
            charactersInGroup += 1
            if charactersInGroup == 4 {
                result.append(" ")
                charactersInGroup = 0
            }
        }
        return String(result)
    }

    func testSingleDelete() {
        let noopCases: [(TestState, FormattedNumberField.SingleDeletionDirection)] = [
            ("|", .backward),
            ("|123", .backward),
            ("|1234 ", .backward),
            ("|", .forward),
            ("123|", .forward),
            ("1234| ", .forward),
            ("1234 |", .forward)
        ]
        for (inputState, deletionDirection) in noopCases {
            let result = FormattedNumberField.singleDelete(
                formattedString: inputState.formattedString,
                allowedCharacters: .numbers,
                cursorPosition: inputState.selectionStart,
                direction: deletionDirection,
                format: testFormat
            )
            XCTAssertNil(result, "\(inputState) \(deletionDirection)")
        }

        let deletionCases: [(TestState, FormattedNumberField.SingleDeletionDirection, TestState)] = [
            ("1|", .backward, "|"),
            ("1234| ", .backward, "123|"),
            ("1234 |", .backward, "123|"),
            ("12|34 567", .backward, "1|345 67"),
            ("1234| 567", .backward, "123|5 67"),
            ("1234 |567", .backward, "123|5 67"),
            ("12|39 9999 9999 9999 9999 ", .backward, "1|399 9999 9999 9999 999"),
            ("|1", .forward, "|"),
            ("12|34 567", .forward, "12|45 67"),
            ("1234| 56", .forward, "1234| 6"),
            ("1234 |56", .forward, "1234| 6"),
            ("12|39 9999 9999 9999 9999 ", .forward, "12|99 9999 9999 9999 999")
        ]
        for (inputState, deletionDirection, expectedOutputState) in deletionCases {
            let result = FormattedNumberField.singleDelete(
                formattedString: inputState.formattedString,
                allowedCharacters: .numbers,
                cursorPosition: inputState.selectionStart,
                direction: deletionDirection,
                format: testFormat
            )
            XCTAssertEqual(result?.asTestState, expectedOutputState, "\(inputState) \(deletionDirection)")
        }
    }

    func testNumericInsert() {
        let noopCases: [(TestState, String)] = [
          ("|", ""),
          ("|", "x"),
          ("123|", "x"),
          ("1234567890|", "1"),
          ("1234|567890", "1"),
          ("123456789|", "123")
        ]
        for (inputState, insertion) in noopCases {
            let result = FormattedNumberField.insertOrReplace(
                formattedString: inputState.formattedString,
                allowedCharacters: .numbers,
                selectionStart: inputState.selectionStart,
                selectionEnd: inputState.selectionEnd,
                rawInsertion: insertion,
                maxCharacters: 10,
                format: testFormat
            )
            XCTAssertNil(result, "\(inputState) \(insertion)")
        }

        let testCases: [(TestState, String, TestState)] = [
          ("|", "1", "1|"),
          ("|", "123", "123|"),
          ("|", "123x", "123|"),

          ("|", "1234", "1234 |"),
          ("123|", "4", "1234 |"),

          ("12|3", "9", "129|3 "),
          ("12|34 ", "9", "129|3 4"),
          ("1234| ", "5", "1234 5|"),
          ("1234 |", "5", "1234 5|"),

          ("[123]", "9", "9|"),
          ("[1234] ", "9", "9|"),
          ("[1234] 5678 ", "9", "9|567 8"),
          ("[1234] 5678 ", "9", "9|567 8"),
          ("12[34 56]78 ", "9", "129|7 8"),
          ("12[34 56]78 ", "000", "1200 0|78"),
          ("12[34 56]78 ", "0000", "1200 00|78 "),
          ("12[34 56]78 ", "", "12|78 "),
          ("12[34 56]78 ", "x", "12|78 "),
          ("12[34 56]78 ", "0x9", "1209 |78"),

          ("[1234 5678 9012 34]", "", "|"),
          ("[1234 5678 9012 34]", "987", "987|"),
          ("1234 5678 9012 3[4]", "", "1234 5678 9012 3|")
        ]

        for (inputState, insertion, expectedOutputState) in testCases {
            let result = FormattedNumberField.insertOrReplace(
                formattedString: inputState.formattedString,
                allowedCharacters: .numbers,
                selectionStart: inputState.selectionStart,
                selectionEnd: inputState.selectionEnd,
                rawInsertion: insertion,
                maxCharacters: 10,
                format: testFormat
            )
            XCTAssertEqual(result?.asTestState, expectedOutputState, "\(inputState) \(insertion)")
        }
    }

    func testAlphanumericInsert() {
        let noopCases: [(TestState, String)] = [
            ("|", ""),
            ("|", "."),
            ("AT123|", "."),
            ("BE1234567890|", "1"),
            ("HR1234|567890", "1"),
            ("EE123456789|", "123")
        ]
        for (inputState, insertion) in noopCases {
            let result = FormattedNumberField.insertOrReplace(
                formattedString: inputState.formattedString,
                allowedCharacters: .alphanumeric,
                selectionStart: inputState.selectionStart,
                selectionEnd: inputState.selectionEnd,
                rawInsertion: insertion,
                maxCharacters: 12,
                format: testFormat
            )
            XCTAssertNil(result, "\(inputState) \(insertion)")
        }

        let testCases: [(TestState, String, TestState)] = [
          ("|", "A", "A|"),
          ("|", "ABC", "ABC|"),
          ("|", "ABC.", "ABC|"),

          ("|", "ABCD", "ABCD |"),
          ("FI2|", "1", "FI21 |"),

          ("AB|3", "9", "AB9|3 "),
          ("AB|34 ", "9", "AB9|3 4"),
          ("AB34| ", "E", "AB34 E|"),
          ("AB34 |", "E", "AB34 E|"),

          ("[AB3]", "9", "9|"),
          ("[AB34] ", "9", "9|"),
          ("[AB34] E678 ", "9", "9|E67 8"),
          ("[AB34] E678 ", "9", "9|E67 8"),
          ("AB[34 E6]78 ", "9", "AB9|7 8"),
          ("AB[34 E6]78 ", "000", "AB00 0|78"),
          ("AB[34 E6]78 ", "0000", "AB00 00|78 "),
          ("AB[34 E6]78 ", "", "AB|78 "),
          ("AB[34 E6]78 ", ".", "AB|78 "),

          ("[AB34 E678 90AB 34]", "", "|"),
          ("[AB34 E678 90AB 34]", "987", "987|"),
          ("AB34 E678 90AB 3[4]", "", "AB34 E678 90AB 3|")
        ]

        for (inputState, insertion, expectedOutputState) in testCases {
            let result = FormattedNumberField.insertOrReplace(
                formattedString: inputState.formattedString,
                allowedCharacters: .alphanumeric,
                selectionStart: inputState.selectionStart,
                selectionEnd: inputState.selectionEnd,
                rawInsertion: insertion,
                maxCharacters: 10,
                format: testFormat
            )
            XCTAssertEqual(result?.asTestState, expectedOutputState, "\(inputState) \(insertion)")
        }
    }
}

fileprivate extension String {
    func inserted(_ newElement: Character, at offset: Int) -> String {
        var result = self
        result.insert(newElement, at: index(result.startIndex, offsetBy: offset))
        return result
    }

    func distance(to end: String.Index) -> Int {
        distance(from: startIndex, to: end)
    }
}

fileprivate extension FormattedNumberField.OperationResult {
    var asTestState: FormattedNumberFieldTest.TestState {
        .init(
            formattedString: formattedString,
            selectionStart: cursorPosition,
            selectionEnd: cursorPosition
        )
    }
}
