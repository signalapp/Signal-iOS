//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public typealias DateProviderMonotonic = () -> MonotonicDate

extension MonotonicDate {
    public static var provider: DateProviderMonotonic {
        { MonotonicDate() }
    }
}

// MARK: -

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

    public func adding(_ timeInterval: TimeInterval) -> MonotonicDate {
        return MonotonicDate(rawValue: self.rawValue + timeInterval.clampedNanoseconds)
    }

    public static func <(lhs: MonotonicDate, rhs: MonotonicDate) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    /// - Important
    /// The given date must not be after this date!
    public static func -(lhs: MonotonicDate, rhs: MonotonicDate) -> MonotonicDuration {
        return MonotonicDuration(nanoseconds: lhs.rawValue - rhs.rawValue)
    }
}

public struct MonotonicDuration: Comparable, CustomDebugStringConvertible {
    public let nanoseconds: UInt64

    public init(nanoseconds: UInt64) {
        self.nanoseconds = nanoseconds
    }

    public init(milliseconds: UInt64) {
        self.nanoseconds = milliseconds * NSEC_PER_MSEC
    }

    public init(clampingSeconds seconds: TimeInterval) {
        self.nanoseconds = seconds.clampedNanoseconds
    }

    /// The duration as milliseconds.
    ///
    /// - Warning: The value is rounded down to the nearest millisecond, so
    /// nanoseconds greater than 0 but less than 1ms will return 0. (Therefore,
    /// it is plausible that `a != b` but `(a - b).milliseconds == 0`.)
    public var milliseconds: UInt64 {
        return self.nanoseconds / NSEC_PER_MSEC
    }

    /// The duration as seconds.
    public var seconds: TimeInterval {
        return TimeInterval(self.nanoseconds) / TimeInterval(NSEC_PER_SEC)
    }

    public static func <(lhs: MonotonicDuration, rhs: MonotonicDuration) -> Bool {
        return lhs.nanoseconds < rhs.nanoseconds
    }

    public var debugDescription: String {
        if self.nanoseconds < NSEC_PER_MSEC {
            return "\(self.nanoseconds)ns"
        }
        return "\(self.milliseconds)ms"
    }
}
