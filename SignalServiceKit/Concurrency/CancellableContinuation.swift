//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A container that immediately resumes when canceled.
///
/// This is useful when there is no operation that needs to be canceled. For
/// example, when waiting for an event to occur, "cancellation" means "stop
/// waiting for the event to occur" and not "stop the event from occurring".
class CancellableContinuation<T> {
    private struct State {
        var continuation: CheckedContinuation<T, Error>?
        var result: Result<T, Error>?
    }
    private let state = AtomicValue<State>(State(), lock: .init())

    func cancel() {
        self.resume(with: .failure(CancellationError()))
    }

    /// Resumes the continuation with `result`.
    ///
    /// It's safe (and harmless) to call `resume` multiple times; redundant
    /// invocations are ignored.
    func resume(with result: Result<T, Error>) {
        let continuation = self.state.update { state -> CheckedContinuation<T, Error>? in
            if let continuation = state.continuation {
                state.continuation = nil
                return continuation
            }
            if state.result == nil {
                state.result = result
            }
            return nil
        }
        if let continuation {
            continuation.resume(with: result)
        }
    }

    func wait() async throws -> T {
        try await withTaskCancellationHandler(
            operation: {
                return try await withCheckedThrowingContinuation { continuation in
                    let result = self.state.update { state -> Result<T, Error>? in
                        if let result = state.result {
                            state.result = nil
                            return result
                        }
                        state.continuation = continuation
                        return nil
                    }
                    if let result {
                        continuation.resume(with: result)
                    }
                }
            },
            onCancel: { self.cancel() }
        )
    }
}
