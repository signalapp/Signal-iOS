//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum OWSOperation {
    public static func retryIntervalForExponentialBackoff(failureCount: UInt, maxBackoff: TimeInterval = 14.1 * kMinuteInterval) -> TimeInterval {
        // 110 retries will yield ~24 hours of retry.
        let averageBackoff = min(maxBackoff, pow(2, Double(failureCount)))
        return averageBackoff * Double.random(in: 0.75..<1.25)
    }

    public static func retryIntervalForExponentialBackoffNs(failureCount: Int, maxBackoff: TimeInterval = 14.1 * kMinuteInterval) -> UInt64 {
        return UInt64(retryIntervalForExponentialBackoff(failureCount: UInt(failureCount), maxBackoff: maxBackoff) * Double(NSEC_PER_SEC))
    }

    public static func formattedNs(_ nanoseconds: UInt64) -> String {
        return String(format: "%.1f", Double(nanoseconds) / Double(NSEC_PER_SEC))
    }
}
