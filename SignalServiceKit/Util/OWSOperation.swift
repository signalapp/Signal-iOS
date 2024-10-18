//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

private enum OWSOperationState {
    case new
    case executing
    case finished
}

/// A base class for implementing retryable operations.
/// To utilize the retryable behavior:
/// Set remainingRetries to something greater than 0, and when you're reporting an error,
/// set `error.isRetryable = YES`.
/// If the failure is one that will not succeed upon retry, set `error.isFatal = YES`.
///
/// isRetryable and isFatal are opposites but not redundant.
///
/// If a group message send fails, the send will be retried if any of the errors were retryable UNLESS
/// any of the errors were fatal. Fatal errors trump retryable errors.
open class OWSOperation: Operation {
    public private(set) var failingError: Error?
    public private(set) var errorCount: UInt = 0
    /// Defaults to 0, set to greater than 0 in init if you'd like the operation to be retryable.
    @Atomic public var remainingRetries: UInt = 0
    private var operationState: AtomicValue<OWSOperationState>
    private var backgroundTask: OWSBackgroundTask
    /// This property should only be accessed on the main queue.
    private var retryTimer: Timer?

    public override init() {
        self.operationState = AtomicValue(.new, lock: UnfairLock())
        self.backgroundTask = OWSBackgroundTask(label: "[\(Self.self)]")
        super.init()
    }

    // MARK: - Mandatory Subclass Overrides

    /// Called every retry, this is where the bulk of the operation's work should go.
    open func run() {
        owsFail("Method needs to be implemented by subclasses.")
    }

    // MARK: - Optional Subclass Overrides

    /// Called at most one time.
    open func didSucceed() {}

    /// Called at most one time.
    open func didCancel() {}

    /// Called zero or more times, retry may be possible
    open func didReportError(_ error: Error) {}

    /// Called at most one time, once retry is no longer possible.
    open func didFail(error: Error) {}

    /// Called exactly once after operation has moved to OWSOperationStateFinished
    open func didComplete() {}

    /// How long to wait before retry, if possible
    open var retryInterval: TimeInterval {
        // Override in subclass if you want something more sophisticated, e.g. exponential backoff
        0.1
    }

    // MARK: - Operation Overrides

    /// Do not override this method in a subclass instead, override `run`
    public final override func main() {
        if let preconditionError = checkForPreconditionError() {
            failOperation(error: preconditionError)
            return
        }

        if isCancelled {
            reportCancelled()
            return
        }

        run()
    }

    // MARK: - Success/Error - Do Not Override

    /// Runs now if a retry timer has been set by a previous failure,
    /// otherwise assumes we're currently running and does nothing.
    internal func runAnyQueuedRetry() {
        DispatchQueue.main.async {
            let retryTimer = self.retryTimer
            self.retryTimer = nil
            if let retryTimer {
                retryTimer.invalidate()
                DispatchQueue.global().async {
                    self.run()
                }
            }
        }
    }

    /// Report that the operation completed successfully.
    ///
    /// Each invocation of `run` must make exactly one call to one of: `reportSuccess`, `reportCancelled`, or `reportError:`
    ///
    /// > Warning: This was labeled as not supposed to be overridden but DeviceTransferOperation did override it.
    open func reportSuccess() {
        didSucceed()
        markAsComplete()
    }

    /// Call this when you abort before completion due to being cancelled.
    ///
    /// Each invocation of `run` must make exactly one call to one of: `reportSuccess`, `reportCancelled`, or `reportError:`
    ///
    /// > Warning: This was labeled as not supposed to be overridden but DeviceTransferOperation did override it.
    open func reportCancelled() {
        didCancel()
        markAsComplete()
    }

    /// Report that the operation failed to complete due to an error.
    ///
    /// Each invocation of `run` must make exactly one call to one of: `reportSuccess`, `reportCancelled`, or `reportError:`
    /// You must ensure that `run` cannot succeed after calling `reportError`, e.g. generally you'll write something like
    /// this:
    ///
    ///     [self reportError:someError];
    ///     return;
    ///
    /// If the error is terminal, and you want to avoid retry, report an error with `error.isFatal = YES` otherwise the
    /// operation will retry if possible.
    private func __reportError(_ error: Error) {
        errorCount += 1
        didReportError(error)
        if error.isFatalError || !error.isRetryable || remainingRetries == 0 {
            failOperation(error: error)
            return
        }
        remainingRetries -= 1

        DispatchQueue.main.async {
            owsAssertDebug(self.retryTimer == nil)
            // this seems pointless if this is expected to be nil but this was in the objc code
            self.retryTimer?.invalidate()

            // The `scheduledTimerWith*` methods add the timer to the current thread's RunLoop.
            // Since Operations typically run on a background thread, that would mean the background
            // thread's RunLoop. However, the OS can spin down background threads if there's no work
            // being done, so we run the risk of the timer's RunLoop being deallocated before it's
            // fired.
            //
            // To ensure the timer's thread sticks around, we schedule it while on the main RunLoop.
            //
            // This comment seems incorrect but it's retained from the objc code.
            self.retryTimer = Timer.scheduledTimer(withTimeInterval: self.retryInterval, repeats: false, block: { [weak self] _ in
                guard let self else {
                    return
                }
                self.runAnyQueuedRetry()
            })
        }
    }

    /// The preferred error reporting mechanism, ensuring retry behavior has
    /// been specified. If your error has overridden errorUserInfo, be sure it
    /// includes has specified retry behavior using IsRetryableProvider or
    /// with(isRetryable:).
    public func reportError(_ error: Error,
                            file: String = #file,
                            function: String = #function,
                            line: Int = #line) {
        if !error.hasIsRetryable {
            let filename = (file as NSString).lastPathComponent
            let location = "[\(filename):\(line) \(function)]"
            Logger.warn("Error without isRetryable: \(type(of: error)) from: \(location)")
        }
        __reportError(error)
    }

    /// Use this if you've verified the error passed in has in fact defined retry behavior, or if you're
    /// comfortable potentially falling back to the default retry behavior (see `NSError.isRetryable`).
    ///
    /// @param `error` may or may not have defined it's retry behavior.
    public func reportError(withUndefinedRetry error: Error) {
        __reportError(error)
    }

    // MARK: - Life Cycle

    private func failOperation(error: Error) {
        failingError = error

        didFail(error: error)
        markAsComplete()
    }

    public final override var isExecuting: Bool {
        operationState.get() == .executing
    }

    public final override var isFinished: Bool {
        operationState.get() == .finished
    }

    public final override func start() {
        willChangeValue(forKey: #keyPath(isExecuting))
        operationState.set(.executing)
        didChangeValue(forKey: #keyPath(isExecuting))

        main()
    }

    public final func markAsComplete() {
        willChangeValue(forKey: #keyPath(isExecuting))
        willChangeValue(forKey: #keyPath(isFinished))

        // Ensure we call the success or failure handler exactly once.
        let oldOperationState = self.operationState.swap(.finished)
        owsAssertDebug(oldOperationState != .finished)

        didChangeValue(forKey: #keyPath(isExecuting))
        didChangeValue(forKey: #keyPath(isFinished))

        didComplete()
    }

    // MARK: - Private Methods

    /// Called one time only
    private func checkForPreconditionError() -> Error? {
        // OWSOperation have a notion of failure, which is inferred by the presence of a `failingError`.
        //
        // By default, any failing dependency cascades that failure to it's dependent.
        // If you'd like different behavior, override this method (`checkForPreconditionError`) without calling `super`.
        for dependency in dependencies {
            guard let dependentOperation = dependency as? OWSOperation else {
                // Native operations, like NSOperation and NSBlockOperation have no notion of "failure".
                // So there's no `failingError` to cascade.
                continue
            }

            // Don't proceed if dependency failed - surface the dependency's error.
            if let dependencyError = dependentOperation.failingError {
                return dependencyError
            }
        }

        return nil
    }

    // MARK: - Helper Methods

    public static func retryIntervalForExponentialBackoff(failureCount: UInt, maxBackoff: TimeInterval = 14.1 * kMinuteInterval) -> TimeInterval {
        // 110 retries will yield ~24 hours of retry.
        return min(maxBackoff, pow(2, Double(failureCount)))
    }

    public static func retryIntervalForExponentialBackoffNs(failureCount: Int, maxBackoff: TimeInterval = 14.1 * kMinuteInterval) -> UInt64 {
        return UInt64(retryIntervalForExponentialBackoff(failureCount: UInt(failureCount), maxBackoff: maxBackoff) * Double(NSEC_PER_SEC))
    }
}
