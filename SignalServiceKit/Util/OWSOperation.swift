//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum OWSOperation {
    /// Computes an exponential retry delay with jitter.
    ///
    /// The "jitter" is 25% of the base value. For example, if `failureCount` is
    /// `4`, the base value is `16`, the jitter is ±4, and the value that's
    /// returned is in the range [12, 20]. (Jitter helps avoid resource
    /// contention, mitigate thundering herds, and spread out request spikes.)
    ///
    /// - Parameters:
    ///   - failureCount: The number of failures that have occurred/the number
    ///   of times we've backed off. This is the "n" in the "2^n" exponential
    ///   backoff formula used when computing the base value.
    ///
    ///   - maxAverageBackoff: The maximum base value (i.e., the largest value
    ///   used before computing the jitter). This method may return a value up
    ///   to 25% larger than `maxAverageBackoff`, but over many invocations, the
    ///   average of the returned values will be `maxAverageBackoff`. (For
    ///   example, if you want "one retry per day", specify `.day`. Some retries
    ///   will happen after only 18 hours (not 24 hours), but those will be
    ///   balanced by retries that wait 30 hours.)
    public static func retryIntervalForExponentialBackoff(
        failureCount: some FixedWidthInteger,
        minAverageBackoff: TimeInterval = 2,
        maxAverageBackoff: TimeInterval = .infinity,
    ) -> TimeInterval {
        let averageBackoff = min(maxAverageBackoff, pow(2, Double(failureCount)) * minAverageBackoff / 2)
        return averageBackoff * Double.random(in: 0.75..<1.25)
    }

    public static func formattedNs(_ nanoseconds: UInt64) -> String {
        return String(format: "%.1f", Double(nanoseconds) / Double(NSEC_PER_SEC))
    }
}
