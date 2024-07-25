//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Generates timestamps for messages/envelopes.
@objc
public class MessageTimestampGenerator: NSObject {
    private let rangeToAvoid = AtomicValue<ClosedRange<UInt64>?>(nil, lock: .init())
    private let nowMs: () -> UInt64

    @objc
    public static let sharedInstance = MessageTimestampGenerator()

    public init(nowMs: @escaping () -> UInt64 = NSDate.ows_millisecondTimeStamp) {
        self.nowMs = nowMs
    }

    /// Generates a new timestamp from the device's local clock.
    ///
    /// Performs a few heuristics to try and avoid generating the same timestamp
    /// repeatedly when called in a tight loop.
    @objc
    public func generateTimestamp() -> UInt64 {
        let generatedTimestamp = max(nowMs(), 1)
        return rangeToAvoid.update { rangeToAvoid in
            let newRangeToAvoid = Self.avoidAndExtendRange(rangeToAvoid, proposedValue: generatedTimestamp)
            rangeToAvoid = newRangeToAvoid
            return newRangeToAvoid.upperBound
        }
    }

    private static func avoidAndExtendRange(
        _ oldRange: ClosedRange<UInt64>?,
        proposedValue: UInt64
    ) -> ClosedRange<UInt64> {
        if let oldRange, oldRange.contains(proposedValue) {
            // If we have a range from the last value, ensure that the new one is
            // higher. We track the range to handle cases where `generateTimestamp()`
            // is called twice for `t1` and then once for `t1 + 1`.
            return oldRange.lowerBound...(oldRange.upperBound + 1)
        } else {
            // Otherwise, we assume there's no conflict and return `proposedValue`.
            return proposedValue...proposedValue
        }
    }
}
