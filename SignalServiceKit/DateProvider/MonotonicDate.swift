//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A Date-esque type that's not impacted by changes to the user's clock.
///
/// This type is and almost exclusively used for measuring durations.
///
/// A MonotonicDate is guaranteed to never decrease (but may remain the
/// same). Therefore, the following code will never underflow, though it may
/// output "0". (The same code with `Date`s could return negative values.)
///
/// ```
/// let a = MonotonicDate()
/// let b = MonotonicDate()
/// print(b - a)
/// ```
///
/// However, it's important to note that MonotonicDate is only valid within
/// a single process. You should NEVER persist one of them to disk. (When a
/// process relaunches, the device may have rebooted, and you can't
/// distinguish that case from the case where the user changed their clock.)
public struct MonotonicDate: Comparable {
    private let rawValue: UInt64

    private init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init() {
        let rawValue = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
        if rawValue == 0 {
            owsFail("Couldn't get monotonic time: \(errno)")
        }
        self.init(rawValue: rawValue)
    }

    public static let distantPast = MonotonicDate(rawValue: 0)

    public func adding(_ timeInterval: TimeInterval) -> MonotonicDate {
        return MonotonicDate(rawValue: self.rawValue + UInt64(timeInterval * TimeInterval(NSEC_PER_SEC)))
    }

    public static func < (lhs: MonotonicDate, rhs: MonotonicDate) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    public static func - (lhs: MonotonicDate, rhs: MonotonicDate) -> UInt64 {
        return lhs.rawValue - rhs.rawValue
    }
}
