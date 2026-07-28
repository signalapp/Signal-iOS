//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension NSRange {
    public func offset(by offset: Int) -> Self {
        return NSRange(
            location: self.location + offset,
            length: self.length,
        )
    }

    /// Returns the "gaps" between ranges.
    ///
    /// If `ranges` contains `[1, 3), [5, 7), [7, 8)`, this method returns `[3,
    /// 5), [7, 7)`. (It returns the gap between `3` and `5` and the empty gap
    /// between `7` and `7`.)
    ///
    /// Callers may wish to filter to non-empty gaps.
    static func gapsBetweenNonOverlappingSortedRanges(_ ranges: [NSRange]) -> [NSRange] {
        return zip(ranges, ranges.dropFirst()).map({ (r1, r2) in
            owsAssertDebug(r1.upperBound <= r2.location)
            return NSRange(location: r1.upperBound, length: r2.location - r1.upperBound)
        })
    }
}
