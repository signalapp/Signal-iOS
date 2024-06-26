//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Replaces extended grapheme clusters having too many combining marks with the unicode replacement character.
///
/// Example usage:
/// ```
/// let sanitizer = StringSanitizer("Jack said, “H̴̬̪̤̗̪̳̑̓e̵̱̗͇̰̽̊͛̿̒̚͠r̶̨̯̻̹̪̫̣̪̹͇̗̀͌̃̍̄͗̎͊͌ę̶̣͍̗̘̺̪̱̇̈́̈́͗͌̀̊̏ͅ'̷̧̧̭̜̱̜͉̟͇̣̉̃ͅs̸̪̻̯͔̤̣̱̾̽̌̇̃̒͋͂̈́̀͌̍̚ ̶͙́̓͊̈́̉̂͗̆͗̑͂̕J̵̨̧̧̠̩͈̹͈̦̩̣͙͐̿̇̈́̓ͅͅo̵̡̥̪͘h̵̡̧̢̘̟͓͖̤̼̟̺͓̰͈͓̎͋̎͝ņ̶̛͖̻̻̝͗̃͋͠n̶̮͈̯̩̘̠̻͔̈̌̐͘̚͝y̵̧̡̛͙͈̹̹̹̗̤̙͖̜̰̰͌͆̏̑͐̽̍͜!̸̡͈͔͆”)
/// if (sanitizer.needsSanitization) {
///     print(sanitizer.sanitized);  // Jack said, “��������������”
/// }
/// ```
@objc
public class StringSanitizer: NSObject {
    private static let maxCodePoints = 16
    private let string: String

    @objc(initWithString:)
    public init(_ string: String) {
        self.string = string
    }

    /// Indicates if the string needs to be modified. This is slightly cheaper than calling `sanitized`.
    @objc
    private(set) public lazy var needsSanitization: Bool = {
        return string.contains {
            $0.unicodeScalars.count > Self.maxCodePoints
        }
    }()

    /// Returns a modified version of the string if sanitization is needed, or the original string otherwise.
    @objc
    private(set) public lazy var sanitized: String = {
        if !needsSanitization {
            return string
        }
        precondition(!string.isEmpty)
        return sanitize(string)
    }()

    private func isBad(_ c: Character) -> Bool {
        return c.unicodeScalars.count > Self.maxCodePoints
    }

    private func sanitize(_ original: String) -> String {
        var remaining = original[...]
        var result = ""
        // An overestimate, because we will shorten at least one Character.
        result.reserveCapacity(original.utf8.count)
        while let nextBadCharIndex = remaining.firstIndex(where: isBad) {
            result.append(contentsOf: remaining[..<nextBadCharIndex])
            result.append("\u{FFFD}")
            remaining = remaining[nextBadCharIndex...].dropFirst()
        }
        result.append(contentsOf: remaining)
        return result
    }
}
