//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum OWSOperation {
    public static func retryIntervalForExponentialBackoff(failureCount: UInt, maxBackoff: TimeInterval = 14.1 * kMinuteInterval) -> TimeInterval {
        // 110 retries will yield ~24 hours of retry.
        return min(maxBackoff, pow(2, Double(failureCount)))
    }

    public static func retryIntervalForExponentialBackoffNs(failureCount: Int, maxBackoff: TimeInterval = 14.1 * kMinuteInterval) -> UInt64 {
        return UInt64(retryIntervalForExponentialBackoff(failureCount: UInt(failureCount), maxBackoff: maxBackoff) * Double(NSEC_PER_SEC))
    }
}
