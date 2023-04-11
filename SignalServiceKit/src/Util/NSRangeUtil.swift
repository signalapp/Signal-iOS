//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol NSRangeProviding {
    var range: NSRange { get }

    func copyWithNewRange(_ range: NSRange) -> Self
}

public class NSRangeUtil {

    /// Takes two sets of range-aware objects, sorted by start location and non-overlapping
    /// within themselves.
    /// Finds overlaps between the original and replacement sequence, preferring the
    /// replacement in all such cases, and preserving non-overlapping segments of
    /// the originals, including splitting up copies.
    /// For example, consider the following ranges, aligned vertically:
    /// original:            [   1   ]      [   2  ][        3         ]
    /// replacements:         [    a      ]             [  b  ]
    /// output:              [1][    a      ][2][3][  b  ][3]
    public static func replacingRanges<T: NSRangeProviding>(
        in originals: [T],
        withOverlapsIn replacements: [T]
    ) -> [T] {
        let maxUpperBoundInOriginls = originals.lazy.map(\.range.upperBound).max() ?? 0
        let maxUpperBoundInReplacements = replacements.lazy.map(\.range.upperBound).max() ?? 0
        let maxUpperBound = max(maxUpperBoundInOriginls, maxUpperBoundInReplacements)

        let string = NSMutableAttributedString(string: String(repeating: " ", count: maxUpperBound))
        let stringKey = NSAttributedString.Key(UUID().uuidString)

        originals.forEach {
            string.addAttributes([stringKey: $0], range: $0.range)
        }
        replacements.forEach {
            string.addAttributes([stringKey: $0], range: $0.range)
        }
        var final = [T]()
        string.enumerateAttributes(
            in: string.entireRange,
            using: { attributes, range, _ in
                guard let object = attributes[stringKey] as? T else {
                    return
                }
                final.append(object.copyWithNewRange(range))
            }
        )
        return final
    }
}
