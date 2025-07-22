//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// A wrapper around arbitrary state that asynchronously serializes access to
/// that state, allowing callers to perform async work while maintaining
/// exclusive access.
public class SeriallyAccessedState<State> {
    private var state: State
    private let updatesQueue: SerialTaskQueue

    public init(_ initialState: State) {
        self.state = initialState
        self.updatesQueue = SerialTaskQueue()
    }

    public func enqueueUpdate(_ update: @escaping (inout State) async -> Void) {
        updatesQueue.enqueue { [self] in
            await update(&state)
        }
    }

    public func awaitUpdate<T>(_ update: @escaping (inout State) async -> T) async throws(CancellationError) -> T {
        do {
            return try await updatesQueue.enqueue { [self] in
                return await update(&state)
            }.value
        } catch let cancellationError as CancellationError {
            throw cancellationError
        } catch {
            owsFail("Unexpected error from enqueued task with non-throwing block! \(error)")
        }
    }
}
