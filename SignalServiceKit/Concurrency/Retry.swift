//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum Retry {
    /// Performs `block` repeatedly until `onError` throws an error (or until cancellation).
    public static func performRepeatedly<T>(block: () async throws -> T, onError: (any Error, _ attemptCount: Int) async throws -> Void) async throws -> T {
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
    /// the error from the final attempt. If `block` throws an error where
    /// `isRetryable` returns false, that error will be propagated immediately.
    /// This method supports cancellation.
    public static func performWithBackoff<T>(maxAttempts: Int, isRetryable: (any Error) -> Bool, block: () async throws -> T) async throws -> T {
        return try await performRepeatedly(
            block: block,
            onError: { error, attemptCount in
                if attemptCount >= maxAttempts || !isRetryable(error) {
                    throw error
                }
                let retryDelayNs = OWSOperation.retryIntervalForExponentialBackoffNs(failureCount: attemptCount)
                try await Task.sleep(nanoseconds: retryDelayNs)
            }
        )
    }

    /// Performs `block` repeatedly with exponential backoff.
    ///
    /// This method will invoke `block` at most `maxAttempts` times, propagating
    /// the error from the final attempt. If `block` throws a fatal error or
    /// non-retryable error on an earlier attempt, that error will be propagated
    /// immediately. This method supports cancellation.
    public static func performWithBackoff<T>(maxAttempts: Int, block: () async throws -> T) async throws -> T {
        return try await performWithBackoff(
            maxAttempts: maxAttempts,
            isRetryable: { !$0.isFatalError && $0.isRetryable },
            block: block
        )
    }
}
