//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct NSRangedValue<T> {
    public let range: NSRange
    public let value: T

    public init( _ value: T, range: NSRange) {
        self.range = range
        self.value = value
    }
}

extension NSRangedValue: Equatable where T: Equatable {}

extension NSRangedValue: Hashable where T: Hashable {}

extension NSRangedValue: Codable where T: Codable {}

extension NSRangedValue {

    enum Overlaps {
        /// There are no overlaps; new range can be applied directly.
        /// Provides index in the sorted array into which the new element can be inserted.
        case none(insertionIndex: Int)
        /// The input range falls entirely within an existing range at the provided index.
        case withinExistingRange(atIndex: Int)
        /// The input range lies across multiple existing ranges. There may be gaps
        /// between the ranges; if there are no gaps that means the ranges collectively cover
        /// the entire input range.
        case acrossExistingRanges(indexes: [Int], gaps: [NSRange])
    }

    /// Takes a sorted array of existing non-empty ranges and a single new range, and determines how
    /// the input range overlaps with the existing ranges that are "equal", for some provided
    /// definition of equal.
    /// The array is assumed to contain no overlaps between "equal" elements; if there are
    /// the results of this method are undetermined.
    static func overlaps<T>(
        of range: NSRangedValue<T>,
        in array: [NSRangedValue<T>],
        isEqual: (T, T) -> Bool
    ) -> Overlaps {
        var insertionIndex = 0
        var overlapIndexes = [Int]()
        var gaps = [NSRange]()
        for (i, existingRange) in array.enumerated() {
            if existingRange.range.location >= range.range.upperBound {
                // We are past the end, no need to check anymore.
                break
            }
            if existingRange.range.location < range.range.location {
                insertionIndex = i + 1
            }
            guard isEqual(existingRange.value, range.value) else {
                continue
            }
            guard let intersection = existingRange.range.intersection(range.range), intersection.length > 0 else {
                continue
            }
            if intersection == range.range {
                return .withinExistingRange(atIndex: i)
            }
            let lastOverlapIndex = overlapIndexes.last
            overlapIndexes.append(i)
            if let lastOverlapIndex {
                let lastOverlapRange = array[lastOverlapIndex]
                let gap = NSRange(
                    location: lastOverlapRange.range.upperBound,
                    length: existingRange.range.location - lastOverlapRange.range.upperBound
                )
                if gap.length > 0 {
                    gaps.append(gap)
                }
            }
        }
        if overlapIndexes.isEmpty {
            return .none(insertionIndex: insertionIndex)
        }
        return .acrossExistingRanges(indexes: overlapIndexes, gaps: gaps)
    }
}
