//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum StringSanitizer {
    private static let maxCodePoints = 16

    public static func isExtremelyLongGraphemeCluster(_ c: Character) -> Bool {
        return c.unicodeScalars.count > Self.maxCodePoints
    }

    /// Replaces extended grapheme clusters having too many combining marks with the unicode replacement character.
    ///
    /// Example usage:
    /// ```swift
    /// let sanitized = StringSanitizer.sanitize("Jack said, "H̴̬̪̤̗̪̳̑̓e̵̱̗͇̰̽̊͛̿̒̚͠r̶̨̯̻̹̪̫̣̪̹͇̗̀͌̃̍̄͗̎͊͌ę̶̣͍̗̘̺̪̱̇̈́̈́͗͌̀̊̏ͅ'̷̧̧̭̜̱̜͉̟͇̣̉̃ͅs̸̪̻̯͔̤̣̱̾̽̌̇̃̒͋͂̈́̀͌̍̚ ̶͙́̓͊̈́̉̂͗̆͗̑͂̕J̵̨̧̧̠̩͈̹͈̦̩̣͙͐̿̇̈́̓ͅͅo̵̡̥̪͘h̵̡̧̢̘̟͓͖̤̼̟̺͓̰͈͓̎͋̎͝ņ̶̛͖̻̻̝͗̃͋͠n̶̮͈̯̩̘̠̻͔̈̌̐͘̚͝y̵̧̡̛͙͈̹̹̹̗̤̙͖̜̰̰͌͆̏̑͐̽̍͜!̸̡͈͔͆")
    /// print(sanitized)  // Jack said, "��������������"
    /// ```
    public static func sanitize(_ original: String, shouldRemove: (Character) -> Bool = isExtremelyLongGraphemeCluster) -> String {
        guard original.contains(where: shouldRemove) else {
            return original
        }
        var remaining = original[...]
        var result = ""
        // An overestimate, because we will shorten at least one Character.
        result.reserveCapacity(original.utf8.count)
        while let nextBadCharIndex = remaining.firstIndex(where: shouldRemove) {
            result.append(contentsOf: remaining[..<nextBadCharIndex])
            result.append("\u{FFFD}")
            remaining = remaining[nextBadCharIndex...].dropFirst()
        }
        result.append(contentsOf: remaining)
        return result
    }
}
