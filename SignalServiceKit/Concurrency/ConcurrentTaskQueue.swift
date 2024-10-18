//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A Task-based replacement for `OperationQueue.maxConcurrentOperationCount`.
///
/// A `ConcurrentTaskQueue` with `concurrentLimit` set to `1` ("CTQ1") is
/// similar to, but not identical to, a `SerialTaskQueue` ("STQ"). The
/// former will reuse the current Task, whereas the latter creates a new
/// Task for each block that's enqueued. A CTQ1 can be replaced anywhere it
/// appears with an STQ without impacting execution ordering guarantees.
/// However, SQTs can't (always) be replaced by CTQ1s because the former
/// supports bridging synchronous and asynchronous contexts.
public final actor ConcurrentTaskQueue {
    private var remainingCount: Int
    private var pendingContinuations = [CheckedContinuation<Void, Never>]()

    public init(concurrentLimit: Int) {
        self.remainingCount = concurrentLimit
    }

    public func run<T>(_ block: () async throws -> T) async rethrows -> T {
        if self.remainingCount > 0 {
            self.remainingCount -= 1
        } else {
            await withCheckedContinuation { continuation in
                self.pendingContinuations.append(continuation)
            }
        }
        defer {
            if let continuationToResume = self.pendingContinuations.first {
                self.pendingContinuations = Array(self.pendingContinuations.dropFirst())
                continuationToResume.resume()
            } else {
                self.remainingCount += 1
            }
        }
        return try await block()
    }
}
