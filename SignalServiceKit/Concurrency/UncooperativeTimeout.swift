//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct UncooperativeTimeoutError: Error {}

/// Invokes `operation` in a Task that's canceled after `seconds`.
///
/// This method should only be used with uncooperative code that does not
/// respect cancellation and should be considered a migratory bridge to
/// eventually reach use of `withCooperativeTimeout` everywhere instead of
/// using this method.
///
/// If a timeout occurs, an `UncooperativeTimeoutError` is thrown.
///
/// The outcome of this method is the earliest-occurring of: the return
/// value from invoking `operation`, the error thrown when invoking
/// `operation`, or the `UncooperativeTimeoutError` thrown after `seconds`.
///
/// > Important: This will leave uncleaned up Tasks running when it returns
/// and should therefore be used only for the purposes of migrating legacy
/// code. New coode should be written to respect Task cancellation and prefer
/// to use `withCooperativeTimeout`.
public func withUncooperativeTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    return try await withCheckedThrowingContinuation { continuation in
        let continuation = TSMutex<CheckedContinuation<T, any Error>?>(initialState: continuation)
        func takeContinuation() -> CheckedContinuation<T, any Error>? {
            return continuation.withLock { state in
                let continuation = state
                state = nil
                return continuation
            }
        }
        Task {
            do {
                let result = try await operation()
                takeContinuation()?.resume(returning: result)
            } catch {
                takeContinuation()?.resume(throwing: error)
            }
        }
        Task {
            try await Task.sleep(nanoseconds: UInt64(seconds * TimeInterval(NSEC_PER_SEC)))
            takeContinuation()?.resume(throwing: UncooperativeTimeoutError())
        }
    }
}
