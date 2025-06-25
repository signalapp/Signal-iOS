//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// A wrapper around arbitrary state that asynchronously serializes access to
/// that state, allowing callers to perform async work while maintaining
/// exclusive access.
///
/// Callers should prefer this type over making themselves an `actor` if they
/// might need to perform async work while maintaining exclusive access to the
/// wrapped state.
public class AsyncAtomic<State> {
    private var state: State
    private let taskQueue: ConcurrentTaskQueue

    public init(_ wrapped: State) {
        self.state = wrapped
        self.taskQueue = ConcurrentTaskQueue(concurrentLimit: 1)
    }

    public func update<T>(_ block: (inout State) async -> T) async -> T {
        return await taskQueue.run {
            await block(&state)
        }
    }
}
