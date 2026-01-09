//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public enum Retry {

    // MARK: -

    /// Performs `block` repeatedly until `onError` throws an error (or until cancellation).
    public static func performRepeatedly<T, E>(block: () async throws(E) -> T, onError: (E, _ attemptCount: Int) async throws -> Void) async throws -> T {
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

    // MARK: -

    /// Performs `block` repeatedly with backoff.
    ///
    /// This method will invoke `block` at most `maxAttempts` times, propagating
    /// the error from the final attempt. If `block` throws an error where
    /// `isRetryable` returns false, that error will be propagated immediately.
    ///
    ///
    /// The backoff interval will be, at minimum, an exponential backoff
    /// determined by the `minAverageBackoff` and `maxAverageBackoff`
    /// parameters. Additionally, callers may use `preferredBackoffBlock` to ask
    /// for an error-specific backoff that will be respected if it is longer
    /// than the minimum; for example, to respect a Retry-After header.
    ///
    /// This method supports cancellation.
    ///
    /// - SeeAlso
    /// ``OWSOperation/retryIntervalForExponentialBackoff(failureCount:minAverageBackoff:maxAverageBackoff:)``.
    public static func performWithBackoff<T, E>(
        maxAttempts: Int,
        minAverageBackoff: TimeInterval = ExponentialBackoff.Defaults.minAverageBackoff,
        maxAverageBackoff: TimeInterval = ExponentialBackoff.Defaults.maxAverageBackoff,
        preferredBackoffBlock: (Error) -> TimeInterval? = { _ in nil },
        isRetryable: (E) -> Bool = { !$0.isFatalError && $0.isRetryable },
        block: () async throws(E) -> T,
    ) async throws -> T {
        return try await performRepeatedly(
            block: block,
            onError: { error, attemptCount in
                if attemptCount >= maxAttempts || !isRetryable(error) {
                    throw error
                }

                let exponentialRetryDelay = OWSOperation.retryIntervalForExponentialBackoff(
                    failureCount: attemptCount,
                    minAverageBackoff: minAverageBackoff,
                    maxAverageBackoff: maxAverageBackoff,
                )

                let retryDelay: TimeInterval
                if let preferredBackoff = preferredBackoffBlock(error) {
                    retryDelay = max(preferredBackoff, exponentialRetryDelay)
                } else {
                    retryDelay = exponentialRetryDelay
                }

                try await Task.sleep(nanoseconds: retryDelay.clampedNanoseconds)
            },
        )
    }
}
