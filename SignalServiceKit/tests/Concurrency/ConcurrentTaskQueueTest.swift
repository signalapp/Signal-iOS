//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

struct ConcurrentTaskQueueTest {
    /// Tests that two tasks can run simultaneously.
    @Test
    func testMultiple() async throws {
        let queue = ConcurrentTaskQueue(concurrentLimit: 2)
        try await queue.run {
            try await queue.run {
                // nothing
            }
        }
    }

    /// Tests that *something* will throw a CancellationError.
    @Test
    func testCancellation() async {
        let queue = ConcurrentTaskQueue(concurrentLimit: 2)
        let task = Task {
            try await queue.run {
                try await queue.run {
                    try await queue.run {}
                }
            }
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    /// Tests that cancellation doesn't wait for stuck tasks.
    @Test
    func testCancellationWhileStuck() async throws {
        let queue = ConcurrentTaskQueue(concurrentLimit: 1)
        try await queue.run {
            let task = Task {
                try await queue.run {}
            }
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }

    /// Tests that new work can be started after old work has completed.
    @Test
    func testSingle() async throws {
        let queue = ConcurrentTaskQueue(concurrentLimit: 1)
        try await queue.run {}
        try await queue.run {}
    }
}
