//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// PendingTasks are used to wait for outstanding work.
///
/// They don't have any side effects/dependencies. Notably, this means that
/// they don't interface with OWSBackgroundTask/UIBackgroundTask.
///
/// For example, in the Notification Service, we want to wait for ACKs,
/// receipts, and messages to be sent for any messages we receive. When
/// those operations start, they create a `PendingTask`. The Notification
/// Service can then wait for any outstanding `PendingTask`s.
///
/// This type pre-dates structured concurrency/Swift Concurrency, and there
/// may be better approaches in a Swift Concurrency-exclusive world.
public class PendingTasks {
    private let pendingTasks = AtomicValue<[Int: PendingTask]>([:], lock: .init())

    public init() {
    }

    public func waitForPendingTasks() async throws {
        // This promise blocks on all pending tasks already in flight,
        // but will not block on new tasks added after this promise
        // is created. This is intentional.
        let pendingTasks = self.pendingTasks.update { $0.values }
        // It's fine to wait on these sequentially because the underlying
        // operations are already running concurrently.
        for pendingTask in pendingTasks {
            try await pendingTask.wait()
        }
    }

    public func buildPendingTask() -> PendingTask {
        let pendingTask = PendingTask(pendingTasks: self)
        pendingTasks.update { $0[pendingTask.id] = pendingTask }
        return pendingTask
    }

    fileprivate func removePendingTask(_ pendingTask: PendingTask) {
        pendingTasks.update { $0.removeValue(forKey: pendingTask.id) }
    }
}

// MARK: -

public class PendingTask {
    private static let idCounter = AtomicValue<Int>(0, lock: .init())
    fileprivate let id = PendingTask.idCounter.update { $0 += 1; return $0 }

    private weak var pendingTasks: PendingTasks?

    private struct State {
        var isComplete = false
        var continuations = [CancellableContinuation<Void>]()
    }

    private let state = AtomicValue<State>(State(), lock: .init())

    init(pendingTasks: PendingTasks) {
        self.pendingTasks = pendingTasks
    }

    fileprivate func wait() async throws {
        try await self.state.update { mutableState -> CancellableContinuation<Void>? in
            if mutableState.isComplete {
                return nil
            } else {
                let continuation = CancellableContinuation<Void>()
                mutableState.continuations.append(continuation)
                return continuation
            }
        }?.wait()
    }

    public func complete() {
        self.state.update { mutableState -> [CancellableContinuation<Void>] in
            mutableState.isComplete = true
            let continuations = mutableState.continuations
            mutableState.continuations = []
            return continuations
        }.forEach {
            $0.resume(with: .success(()))
        }
        // If nobody cares about `pendingTasks`, we don't need to worry about
        // removing it, so it's fine for this to be a no-op.
        pendingTasks?.removePendingTask(self)
    }
}
