//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

/// Manages connection retry logic with exponential backoff for device transfers.
/// Extracted into a separate class for testability.
class ConnectionRetryManager {

    // MARK: - Configuration

    struct Configuration {
        /// Maximum number of retry attempts before giving up.
        let maxRetries: Int

        /// Base delay in seconds for the first retry (doubles with each subsequent attempt).
        let baseDelaySeconds: TimeInterval

        static let `default` = Configuration(
            maxRetries: 3,
            baseDelaySeconds: 2.0
        )
    }

    // MARK: - Properties

    let configuration: Configuration
    private(set) var retryCount: Int = 0
    private var retryTask: Task<Void, Never>?

    /// Callback invoked when a retry should be attempted.
    /// The closure receives the retry number (1-indexed) and should return true if retry was initiated.
    var onRetry: ((Int) -> Void)?

    /// Callback invoked when all retries are exhausted.
    var onRetriesExhausted: (() -> Void)?

    // MARK: - Initialization

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    // MARK: - Public Methods

    /// Calculates the delay for a given retry attempt using exponential backoff.
    /// - Parameter attempt: The retry attempt number (1-indexed).
    /// - Returns: The delay in seconds before this retry should be attempted.
    func delayForRetry(attempt: Int) -> TimeInterval {
        return configuration.baseDelaySeconds * pow(2.0, Double(attempt - 1))
    }

    /// Checks if more retries are available.
    var canRetry: Bool {
        return retryCount < configuration.maxRetries
    }

    /// The number of remaining retry attempts.
    var remainingRetries: Int {
        return max(0, configuration.maxRetries - retryCount)
    }

    /// Attempts to schedule a retry.
    /// - Returns: `true` if a retry was scheduled, `false` if retries are exhausted.
    @discardableResult
    func attemptRetry() -> Bool {
        guard canRetry else {
            Logger.warn("Connection retry limit reached (\(configuration.maxRetries))")
            onRetriesExhausted?()
            return false
        }

        retryCount += 1
        let currentRetry = retryCount
        let delay = delayForRetry(attempt: currentRetry)

        Logger.info("Scheduling connection retry \(currentRetry)/\(configuration.maxRetries) in \(delay)s")

        retryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                // Task was cancelled
                return
            }

            guard let self else { return }

            Logger.info("Executing connection retry \(currentRetry)")
            self.onRetry?(currentRetry)
        }

        return true
    }

    /// Resets the retry count and cancels any pending retry.
    func reset() {
        retryCount = 0
        cancelPendingRetry()
    }

    /// Cancels any pending retry task without resetting the count.
    func cancelPendingRetry() {
        retryTask?.cancel()
        retryTask = nil
    }

    /// Records a successful connection, resetting the retry count.
    func recordSuccessfulConnection() {
        Logger.info("Connection successful, resetting retry count")
        reset()
    }
}

// MARK: - Testing Support

#if TESTABLE_BUILD
extension ConnectionRetryManager {
    /// Synchronously calculates what the next delay would be without actually scheduling.
    var nextRetryDelay: TimeInterval? {
        guard canRetry else { return nil }
        return delayForRetry(attempt: retryCount + 1)
    }

    /// For testing: immediately execute the retry callback without delay.
    func executeRetryImmediately() {
        guard canRetry else {
            onRetriesExhausted?()
            return
        }

        retryCount += 1
        onRetry?(retryCount)
    }
}
#endif
