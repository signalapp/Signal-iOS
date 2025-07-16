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
/// Debounced callers of `.run()` will all be returned the same `Task` instance.
/// That means that if any caller cancels that `Task`, it will be canceled for
/// all callers.
public struct DebouncedTask<Value> {
    private struct State {
        var task: Task<Value, Never>?
    }

    private let block: () async -> Value
    private let state: AtomicValue<State>

    public init(block: @escaping () async -> Value) {
        self.block = block
        self.state = AtomicValue(State(), lock: .init())
    }

    /// Returns a `Task` running the block, or an actively-running `Task` from
    /// an earlier call to this method.
    public func run() -> Task<Value, Never> {
        return state.update { _state -> Task<Value, Never> in
            if let task = _state.task {
                return task
            }

            _state.task = Task {
                defer {
                    state.update { $0.task = nil }
                }

                return await block()
            }
            return _state.task!
        }
    }
}
