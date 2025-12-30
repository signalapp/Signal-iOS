//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A [Key: ConcurrentTaskQueue] that prunes empty task queues.
///
/// This type is useful, for example, when you want to limit the number of
/// concurrent operations per ServiceId.
///
/// (This type could be expanded to allow, for example, "no more than 2
/// concurrent tasks per key and no more than 8 concurrent tasks total").
public actor KeyedConcurrentTaskQueue<KeyType: Hashable> {
    private let concurrentLimitPerKey: Int
    private var taskQueues = [KeyType: ReferenceCounted<ConcurrentTaskQueue>]()

    public init(concurrentLimitPerKey: Int) {
        self.concurrentLimitPerKey = concurrentLimitPerKey
    }

    private func buildTaskQueue() -> ReferenceCounted<ConcurrentTaskQueue> {
        return ReferenceCounted(wrappedValue: ConcurrentTaskQueue(concurrentLimit: concurrentLimitPerKey))
    }

    /// See the corresponding ConcurrentTaskQueue method.
    public func runWithoutTaskCancellationHandler<T, E>(forKey key: KeyType, _ block: () async throws(E) -> T) async throws(E) -> T {
        return try await withTaskQueue(forKey: key) { taskQueue async throws(E) in
            return try await taskQueue.runWithoutTaskCancellationHandler(block)
        }
    }

    /// See the corresponding ConcurrentTaskQueue method.
    public func run<T>(forKey key: KeyType, _ block: () async throws -> T) async throws -> T {
        return try await withTaskQueue(forKey: key) { taskQueue async throws in
            return try await taskQueue.run(block)
        }
    }

    /// See the corresponding ConcurrentTaskQueue method.
    public func run<T>(forKey key: KeyType, _ block: () async -> T) async throws(CancellationError) -> T {
        return try await withTaskQueue(forKey: key) { taskQueue async throws(CancellationError) in
            return try await taskQueue.run(block)
        }
    }

    private func withTaskQueue<T, E>(forKey key: KeyType, run block: (_ taskQueue: ConcurrentTaskQueue) async throws(E) -> T) async throws(E) -> T {
        // The increment and decrement both run on this actor, so they are mutually
        // exclusive. We only remove from `taskQueues` when everything is done.
        let taskQueue = taskQueues[key, default: buildTaskQueue()].increment()
        defer {
            // The value must exist in the Dictionary because we own our own reference
            // count and haven't yet decremented it.
            if taskQueues[key]!.decrement() {
                taskQueues.removeValue(forKey: key)
            }
        }
        return try await block(taskQueue)
    }
}

private struct ReferenceCounted<T> {
    var referenceCount = 0
    var wrappedValue: T

    mutating func increment() -> T {
        referenceCount += 1
        return wrappedValue
    }

    mutating func decrement() -> Bool {
        referenceCount -= 1
        return referenceCount == 0
    }
}
