//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension OWSOperation {
    static func retryIntervalForExponentialBackoff(failureCount: UInt) -> TimeInterval {
        // Arbitrary backoff factor...
        // With backOffFactor of 1.9
        // retry 1 delay:  0.10s
        // retry 2 delay:  0.19s
        // ...
        // retry 5 delay:  1.30s
        // ...
        // retry 11 delay: 61.31s
        // ...
        // retry 15 delay: 15 minutes
        // retry 16 delay: 15 minutes
        //
        // 110 retries will yield ~24 hours of retry.
        let backoffFactor = 1.9
        let maxBackoff = 15 * kMinuteInterval

        let seconds = min(maxBackoff, 0.1 * pow(backoffFactor, Double(failureCount)))
        return seconds
    }
}
