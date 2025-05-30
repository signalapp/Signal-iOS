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
    let results = await _withCooperativeRace(operations: [
        { () async throws -> T? in
            try await operation()
        },
        { () async throws -> T? in
            do {
                try await Task.sleep(nanoseconds: seconds.clampedNanoseconds)
            } catch {
                // If the timeout Task's sleep call throws an error, it's almost certainly
                // a CancellationError. Per the documentation, though, we can't rethrow
                // this error because it's neither a CooperativeTimeoutError nor an error
                // produced from invoking operation().
                return nil
            }
            throw CooperativeTimeoutError()
        },
    ])
    for result in results {
        if let operationResult = try result.get() {
            return operationResult
        }
    }
    // There are always two results. If at least one of them throws an Error,
    // that error will be re-thrown above, and we can't reach this code. If
    // neither of them throws an Error, the result from invoking operation()
    // will be nonnil, it will be returned above, and we can't reach this code.
    owsFail("Can't reach this code.")
}

/// Invokes `operation` & `operations`, passing through the earliest result.
///
/// This method doesn't return until `operation` and every element of
/// `operations` returns. In other words, every operation must cooperate
/// with the cancellation request.
///
/// The `operation` and `operations` parameters are separated in the
/// function signature to require callers to provide at least one operation.
/// This provides compile-time safety for the `.first!` forced unwrap.
public func withCooperativeRace<T>(
    _ operation: @escaping () async throws -> T,
    _ operations: (() async throws -> T)...,
) async throws -> T {
    return try await _withCooperativeRace(operations: [operation] + operations).first!.get()
}

private func _withCooperativeRace<T>(operations: [() async throws -> T]) async -> [Result<T, any Error>] {
    return await withThrowingTaskGroup { taskGroup in
        for operation in operations {
            taskGroup.addTask {
                return try await operation()
            }
        }
        var results = [Result<T, any Error>]()
        if let firstResult = await taskGroup.nextResult() {
            results.append(firstResult)
            // Cancel everything else as soon as anything wins the race.
            taskGroup.cancelAll()
            // This is cooperative, so even though we canceled all the other
            // operations, they may still produce meaningful results.
            while let otherResult = await taskGroup.nextResult() {
                results.append(otherResult)
            }
        }
        return results
    }
}
