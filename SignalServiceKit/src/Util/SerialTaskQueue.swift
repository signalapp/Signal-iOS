//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A queue which takes Sendable async closures and executes them in serial in the order they
/// were enqueued.
///
/// Each closure is wrapped in a Task and returned; callers can await the result of that Task to
/// get the result when it runs after any other Tasks in the queue.
public actor SerialTaskQueue {

    private struct IdentifiedTask {
        let id: Int
        let task: AnyTask
    }

    private var isRunningTask = false
    private var queue: [IdentifiedTask] = []

    public init() {}

    deinit {
        for task in queue {
            task.task.cancel()
        }
    }

    /// Returns when the closure's Task has been enqueued, but the task may not necessarily have begin (let alone finished)
    /// execution.
    @discardableResult
    public func enqueue<T>(operation: @escaping @Sendable () async throws -> T) -> Task<T, Error> {
        let previousTask = queue.last
        let newTaskIdParams = (previousTask?.id ?? 0).addingReportingOverflow(1)
        let newTaskId = newTaskIdParams.overflow ? 1 : newTaskIdParams.partialValue

        let task = Task { [weak self] in
            try Task.checkCancellation()
            await previousTask?.task.await()
            try Task.checkCancellation()
            let value = try await operation()

            await self?.cleanUpQueue(upToId: newTaskId)

            return value
        }

        queue.append(.init(id: newTaskId, task: task))
        return task
    }

    /// Like enqueue, but cancels all previous tasks.
    @discardableResult
    public func enqueueCancellingPrevious<T>(
        operation: @escaping @Sendable () async throws -> T
    ) async -> Task<T, Error> {
        await cancelAll()
        return enqueue(operation: operation)
    }

    /// Note that it is up to each task to respect its cancellation and yield; cancelling does not
    /// guarantee they will cease execution.
    public func cancelAll() async {
        queue.forEach { $0.task.cancel() }
        queue = []
    }

    private func cleanUpQueue(upToId: Int) async {
        queue = queue.filter { $0.id > upToId }
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
