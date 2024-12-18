//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

enum Retry {
    /// Performs `block` repeatedly until `onError` throws an error (or until cancellation).
    static func performRepeatedly<T>(block: () async throws -> T, onError: (any Error, _ attemptCount: Int) async throws -> Void) async throws -> T {
        var attemptCount = 0
        while true {
            try Task.checkCancellation()
            do {
                attemptCount += 1
                return try await block()
            } catch {
                try await onError(error, attemptCount)
            }
        }
    }

    /// Performs `block` repeatedly with exponential backoff.
    ///
    /// This method will invoke `block` at most `maxAttempts` times, propagating
    /// the error from the final attempt. If `block` throws a fatal error or
    /// non-retryable error on an earlier attempt, that error will be propagated
    /// immediately. This method supports cancellation.
    static func performWithBackoff<T>(maxAttempts: Int, block: () async throws -> T) async throws -> T {
        return try await performRepeatedly(
            block: block,
            onError: { error, attemptCount in
                if error.isFatalError || !error.isRetryable || attemptCount >= maxAttempts {
                    throw error
                }
                let retryDelayNs = OWSOperation.retryIntervalForExponentialBackoffNs(failureCount: attemptCount)
                try await Task.sleep(nanoseconds: retryDelayNs)
            }
        )
    }
}
