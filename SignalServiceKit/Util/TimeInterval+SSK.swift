//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension TimeInterval {

    /// An approximate time interval for a single second.
    ///
    /// > Warning: These approximations should never be used for strict date/time calcuations.
    public static let second: TimeInterval = 1

    /// An approximate time interval for a single minute.
    ///
    /// > Warning: These approximations should never be used for strict date/time calcuations.
    public static let minute: TimeInterval = 60

    /// An approximate time interval for a single hour.
    ///
    /// > Warning: These approximations should never be used for strict date/time calcuations.
    public static let hour: TimeInterval = 60 * .minute

    /// An approximate time interval for a single day.
    ///
    /// > Warning: These approximations should never be used for strict date/time calcuations.
    public static let day: TimeInterval = 24 * .hour

    /// An approximate time interval for a single week.
    ///
    /// > Warning: These approximations should never be used for strict date/time calcuations.
    public static let week: TimeInterval = 7 * .day

    /// An approximate time interval for a 30 day month.
    ///
    /// > Warning: These approximations should never be used for strict date/time calcuations.
    public static let month: TimeInterval = 30 * .day

    /// An approximate time interval for a 365 day year.
    ///
    /// > Warning: These approximations should never be used for strict date/time calcuations.
    public static let year: TimeInterval = 365 * .day

    /// The time interval as nanoseconds clamped to [0, Int64.max].
    ///
    /// If the value is NaN, 0 is returned.
    public var clampedNanoseconds: UInt64 {
        let actualValue = UInt64(exactly: floor(max(0, self) * TimeInterval(NSEC_PER_SEC))) ?? .max
        // Values larger than Int64.max are intereted as "don't sleep" by
        // Task.sleep(nanoseconds:). (They are probably being coerced to Int64s and
        // then interpreted as negative values.)
        return min(actualValue, UInt64(Int64.max))
    }
}

@objcMembers
@available(swift, obsoleted: 1)
final public class NSTimeIntervalConstants: NSObject {
    public static let second: TimeInterval = .second
    public static let minute: TimeInterval = .minute
    public static let hour: TimeInterval = .hour
    public static let day: TimeInterval = .day
    public static let week: TimeInterval = .week
    public static let month: TimeInterval = .month
    public static let year: TimeInterval = .year
}
