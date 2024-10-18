//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A queue which takes Sendable async closures and executes them in serial
/// in the order they were enqueued.
///
/// Each closure is wrapped in a Task and returned; callers can await the
/// result of that Task to get the result when it runs after any other Tasks
/// in the queue.
public final class SerialTaskQueue {

    private let queue = AtomicValue<[AnyTask]>([], lock: .init())

    public init() {}

    deinit {
        for task in queue.get() {
            task.cancel()
        }
    }

    /// Returns when the closure's Task has been enqueued, but the task may not
    /// necessarily have begin (let alone finished) execution.
    @discardableResult
    public func enqueue<T>(operation: @escaping @Sendable () async throws -> T) -> Task<T, Error> {
        return queue.update {
            let oldTask = $0.last
            let newTask = Task { [queue] in
                await oldTask?.await()
                defer {
                    queue.update { _ = $0.remove(at: 0) }
                }
                try Task.checkCancellation()
                return try await operation()
            }
            $0.append(newTask)
            return newTask
        }
    }

    /// Like enqueue, but cancels all previous tasks.
    @discardableResult
    public func enqueueCancellingPrevious<T>(
        operation: @escaping @Sendable () async throws -> T
    ) -> Task<T, Error> {
        cancelAll()
        return enqueue(operation: operation)
    }

    /// Note that it is up to each task to respect its cancellation and yield;
    /// cancelling does not guarantee they will cease execution.
    public func cancelAll() {
        for task in queue.get() {
            task.cancel()
        }
    }
}

private protocol AnyTask {
    func cancel()
    func await() async
}

extension Task: AnyTask {
    func await() async {
        _ = await self.result
    }
}
