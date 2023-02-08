//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension Usernames {
    /// Provides validation for "nicknames", i.e. the user-generated portion of
    /// a username (without the numeric discriminator).
    struct NicknameValidator {
        public enum ValidationResult {
            case tooShort
            case tooLong
            case invalidCharacters
            case success
        }

        /// A regex to check the validity of a nickname. The first character may be
        /// in [_a-zA-Z], and all subsequent characters may also be decimal digits.
        private static let nicknameValidityRegex: NSRegularExpression = try! .init(pattern: "^[_a-zA-Z][_a-zA-Z0-9]*$")

        /// Minimum number of Unicode codepoints for a nickname.
        private let minCodepoints: UInt

        /// Maximum number of Unicode codepoints for a nickname.
        private let maxCodepoints: UInt

        public init(minCodepoints: UInt, maxCodepoints: UInt) {
            self.minCodepoints = minCodepoints
            self.maxCodepoints = maxCodepoints
        }

        /// Performs limited client-side validation on the given nickname. Any
        /// normalization should be performed prior to calling this method.
        public func validate(desiredNickname nickname: String) -> ValidationResult {
            let unicodePointsCount = nickname.unicodeScalars.count

            guard unicodePointsCount >= minCodepoints else {
                return .tooShort
            }

            guard unicodePointsCount <= maxCodepoints else {
                return .tooLong
            }

            guard Self.nicknameValidityRegex.hasMatch(input: nickname) else {
                return .invalidCharacters
            }

            return .success
        }
    }
}
