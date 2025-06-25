//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A Task-based replacement for `OperationQueue.maxConcurrentOperationCount`.
///
/// A `ConcurrentTaskQueue` with `concurrentLimit` set to `1` ("CTQ1") is
/// similar to, but not identical to, a `SerialTaskQueue` ("STQ"). The
/// former will reuse the current Task, whereas the latter creates a new
/// Task for each block that's enqueued. A CTQ1 can be replaced anywhere it
/// appears with an STQ without impacting execution ordering guarantees.
/// However, SQTs can't (always) be replaced by CTQ1s because the former
/// supports bridging synchronous and asynchronous contexts.
///
/// A ConcurrentTaskQueue is intended to be (somewhat) "invisible to the
/// caller", meaning that it doesn't violate the caller's expectations. For
/// example, ConcurrentTaskQueue supports cooperative cancellation, so it's
/// safe to use in methods intended to be cancellable. (This is different
/// than STQs -- those break the "chain of cancellation", and that might be
/// surprising to async callers of an async method.)
///
/// A ConcurrentTaskQueue serves as a suspension point/cancellation check.
/// This is different than invoking `block` directly (it's not "invisible"),
/// but it's roughly equivalent to calling `Task.checkCancellation()` just
/// prior to invoking `block`. Various other APIs -- `Task.sleep`, network
/// requests, Monitors -- similarly serve as cancellation points.
///
/// A ConcurrentTaskQueue doesn't "slow down" the reaction speed for
/// cancellations. If a block is executing when it's canceled, the reaction
/// speed will match that of the block that's executing. If a block hasn't
/// started executing, cancellation is immediate.
public final actor ConcurrentTaskQueue {
    private var remainingCount: Int
    private var pendingContinuations = [Int: CheckedContinuation<Bool, Never>]()

    private var pendingContinuationIndex = 0
    private var resumedContinuationIndex = 0

    public init(concurrentLimit: Int) {
        self.remainingCount = concurrentLimit
    }

    /// Executes `block` when fewer than `concurrentLimit` blocks are running.
    ///
    /// This method doesn't check for cancellation while waiting.
    public func runWithoutTaskCancellationHandler<T, E>(_ block: () async throws(E) -> T) async throws(E) -> T {
        let result: Result<T, E>
        do throws(CancellationError) {
            result = try await _run(isCancellable: false, block)
        } catch {
            owsFail("Can't throw an error when isCancellable is false.")
        }
        return try result.get()
    }

    /// Executes `block` when fewer than `concurrentLimit` blocks are running.
    ///
    /// This method throws a `CancellationError` immediately (i.e., out of
    /// "order") if canceled while waiting.
    ///
    /// From a cancellation perspective, its behavior is an efficient
    /// implementation (i.e., without polling) of the following code:
    ///
    ///     while runningBlocks >= concurrentLimit {
    ///         try Task.checkCancellation()
    ///         await Task.yield()
    ///     }
    ///     return try await block()
    ///
    /// - Throws: An error thrown from `block` or a `CancellationError`.
    public func run<T>(_ block: () async throws -> T) async throws -> T {
        return try await _run(isCancellable: true, block).get()
    }

    /// This throws a CancellationError and returns a Result to aid in compiler
    /// enforcement for the implementation of the two public-facing methods.
    private func _run<T, E>(
        isCancellable: Bool,
        _ block: () async throws(E) -> T,
    ) async throws(CancellationError) -> Result<T, E> {
        if self.remainingCount > 0 {
            self.remainingCount -= 1
        } else {
            let continuationIndex = self.pendingContinuationIndex
            self.pendingContinuationIndex += 1
            let isCanceled = await withTaskCancellationHandler(
                operation: {
                    return await withCheckedContinuation { continuation in
                        self.pendingContinuations[continuationIndex] = continuation
                    }
                },
                onCancel: {
                    if isCancellable {
                        Task { await self.cancelContinuation(continuationIndex: continuationIndex) }
                    }
                },
            )
            if isCanceled {
                throw CancellationError()
            }
        }
        defer {
            self.remainingCount += 1
            while resumedContinuationIndex < pendingContinuationIndex {
                let continuationToResume = self.pendingContinuations.removeValue(forKey: resumedContinuationIndex)
                resumedContinuationIndex += 1
                if let continuationToResume {
                    self.remainingCount -= 1
                    continuationToResume.resume(returning: false)
                    break
                }
            }
        }
        return await Result(catching: { () async throws(E) in try await block() })
    }

    private func cancelContinuation(continuationIndex: Int) {
        self.pendingContinuations.removeValue(forKey: continuationIndex)?.resume(returning: true)
    }
}
