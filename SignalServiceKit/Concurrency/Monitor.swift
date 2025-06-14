//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// The Monitor methods help build logic that waits for specific conditions.
enum Monitor {
    struct Continuation {
        fileprivate let continuation: CancellableContinuation<Void>
        fileprivate init(_ continuation: CancellableContinuation<Void>) {
            self.continuation = continuation
        }
    }

    struct Condition<State> {
        var isSatisfied: (State) -> Bool
        var waiters: WritableKeyPath<State, [NSObject: Continuation]>
    }

    /// Returns when `condition` is satisfied.
    ///
    /// - Warning: Callers must update `state` using `updateAndNotify`, and they
    /// must pass the same `condition` to that method.
    ///
    /// - Parameter condition: If `condition.isSatisfied(_:)` returns true, this
    /// method returns immediately. If `condition.isSatisfied(_:)` returns
    /// false, this method adds a continuation to `condition.waiters` that's
    /// resumed by a call to `updateAndNotify`.
    static func waitForCondition<State>(
        _ condition: Condition<State>,
        in state: AtomicValue<State>,
    ) async throws(CancellationError) {
        let cancellationToken = NSObject()
        let cancellableContinuation = CancellableContinuation<Void>()
        state.update {
            if condition.isSatisfied($0) {
                cancellableContinuation.resume(with: .success(()))
            } else {
                $0[keyPath: condition.waiters][cancellationToken] = Continuation(cancellableContinuation)
            }
        }
        do {
            try await withTaskCancellationHandler(
                operation: cancellableContinuation.wait,
                onCancel: {
                    // Don't cancel because CancellableContinuation does that.
                    // We just clean up the state so that we don't leak memory.
                    state.update { _ = $0[keyPath: condition.waiters].removeValue(forKey: cancellationToken) }
                }
            )
        } catch let error as CancellationError {
            throw error
        } catch {
            // The CancellableContinuation is used properly by this type, and it's not
            // accessible outside of this file, so it's impossible for it to throw
            // other types of errors.
            owsFail("Impossible.")
        }
    }

    /// Executes `block` and notifies `waiters` whose `condition` is now true.
    ///
    /// - Warning: Callers must provide the same `condition` to the
    /// `waitForCondition` method to ensure correct behavior.
    ///
    /// - Parameter conditions: Every provided `condition` will be checked; if
    /// satisfied, its `waiters` will be resumed.
    static func updateAndNotify<State, Result>(
        in state: AtomicValue<State>,
        block: (inout State) -> Result,
        conditions: Condition<State>...,
    ) -> Result {
        let result: Result
        let waitersToResume: [Continuation]
        (result, waitersToResume) = state.update {
            let result = block(&$0)
            var waitersToResume = [Continuation]()
            for condition in conditions {
                if condition.isSatisfied($0) {
                    waitersToResume.append(contentsOf: $0[keyPath: condition.waiters].values)
                    $0[keyPath: condition.waiters] = [:]
                }
            }
            return (result, waitersToResume)
        }
        waitersToResume.forEach { $0.continuation.resume(with: .success(())) }
        return result
    }
}
