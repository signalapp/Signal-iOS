//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct CooperativeTimeoutError: Error {}

/// Invokes `operation` in a Task that's canceled after `seconds`.
///
/// This method doesn't return until `operation` returns. In other words,
/// `operation` must cooperate with the cancellation request.
///
/// If a timeout occurs, a `CooperativeTimeoutError` is thrown. The error is
/// thrown even if `operation` ignores the cancellation and returns a value.
///
/// The outcome of this method is the earliest-occurring of: the return
/// value from invoking `operation`, the error thrown when invoking
/// `operation`, or the `CooperativeTimeoutError` thrown after `seconds`.
public func withCooperativeTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    return try await withThrowingTaskGroup(of: T.self) { taskGroup in
        taskGroup.addTask {
            return try await operation()
        }
        taskGroup.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * TimeInterval(NSEC_PER_SEC)))
            throw CooperativeTimeoutError()
        }
        let result = try await taskGroup.next()!
        // If the first child Task to finish throws an error, that error will be
        // rethrown on the prior line. When `withThrowingTaskGroup` throws an error
        // from its body, it cancels all the other child Tasks. If, however, the
        // first child Task to finish doesn't throw an error, we must cancel the
        // other one to avoid waiting for it to time out.
        taskGroup.cancelAll()
        return result
    }
}
