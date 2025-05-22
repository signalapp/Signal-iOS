//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Wraps an asynchronous block that might be invoked multiple times, allowing
/// callers to avoid having multiple instances of the block running at once.
///
/// For example, imagine the block does N seconds of work. If `.run()` is called,
/// then is called again within N seconds, the second call will return the
/// `Task` started by the first call, instead of starting a new `Task`. A later
/// call to `.run()` after N seconds will start a new `Task`.
///
/// - Important
/// Cancellations do not pass through to the async block underlying a
/// `DebouncedTask`. For example, running
/// ```swift
/// let debouncedTask = DebouncedTask { ... }
/// let wrapperTask = Task { try await debouncedTask.run() }
/// wrapperTask.cancel()
/// ```
/// will not automatically pass the cancellation through to the block being run
/// by the `DebouncedTask`.
public struct DebouncedTask<Value> {
    private struct State {
        var task: Task<Value, Error>?
    }

    private let block: () async throws -> Value
    private let state: AtomicValue<State>

    public init(block: @escaping () async throws -> Value) {
        self.block = block
        self.state = AtomicValue(State(), lock: .init())
    }

    /// Returns the currently-running `Task`, if present.
    public func isCurrentlyRunning() -> Task<Value, Error>? {
        return state.get().task
    }

    /// Returns a `Task` running the block, or an actively-running `Task` from
    /// an earlier call to this method.
    public func run() -> Task<Value, Error> {
        return state.update { _state -> Task<Value, Error> in
            if let task = _state.task {
                return task
            }

            _state.task = Task {
                defer {
                    state.update { $0.task = nil }
                }

                return try await block()
            }
            return _state.task!
        }
    }
}
