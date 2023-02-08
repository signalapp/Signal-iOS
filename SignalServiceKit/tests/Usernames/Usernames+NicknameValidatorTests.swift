//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import Signal

final class UsernamesNicknameValidatorTests: XCTestCase {
    private typealias NicknameValidator = Usernames.NicknameValidator

    private static let usernameTestCases: [(String, NicknameValidator.ValidationResult)] = [
        // MARK: Too short

        ("", .tooShort),
        ("a", .tooShort),
        ("ab", .tooShort),

        // MARK: Too long

        ("longlonglonglonglonglonglonglonglonglonglonglonglonglonglonglong", .tooLong),

        // MARK: Invalid characters

        ("abcdef" + "👀", .invalidCharacters),
        ("abcdef" + "⼉", .invalidCharacters),
        ("abcdef" + "é", .invalidCharacters),
        ("abcdef" + "+", .invalidCharacters),
        ("abcdef" + "-", .invalidCharacters),
        ("abcdef" + "=", .invalidCharacters),
        ("abcdef" + ",", .invalidCharacters),
        ("abcdef" + ".", .invalidCharacters),
        ("abcdef" + "{", .invalidCharacters),
        ("abcdef" + "}", .invalidCharacters),
        ("abcdef" + "[", .invalidCharacters),
        ("abcdef" + "]", .invalidCharacters),
        ("abcdef" + "\\", .invalidCharacters),
        ("abcdef" + "\"", .invalidCharacters),
        ("abcdef" + "\'", .invalidCharacters),

        (.init(repeating: "👀", count: 100), .tooLong),

        // MARK: Invalid first character

        ("0" + "abcdef", .invalidCharacters),

        // MARK: Valid

        ("abc", .success),
        ("abc123", .success),
        ("_abc", .success),
        ("abc_", .success),
        ("abc_123", .success),
        ("abc_cba321", .success)
    ]

    func testUsernames() {
        let validator = NicknameValidator(minCodepoints: 3, maxCodepoints: 32)

        for testCase in Self.usernameTestCases {
            let (username, expectedResult) = testCase

            let actualResult = validator.validate(desiredNickname: username)

            XCTAssertEqual(
                actualResult,
                expectedResult,
                "Username \(username) should have been reported as \(expectedResult), but instead reported as \(actualResult)."
            )
        }
    }
}
