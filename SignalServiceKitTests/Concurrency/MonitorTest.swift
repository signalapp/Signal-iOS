//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

struct MonitorTest {
    private struct State {
        var isSatisfied = false
        var onSatisfied = [NSObject: Monitor.Continuation]()
    }

    private let state = AtomicValue(State(), lock: .init())

    private let satisfiedCondition = Monitor.Condition<State>(
        isSatisfied: { $0.isSatisfied },
        waiters: \.onSatisfied,
    )

    @Test
    func testWait() async throws {
        async let m1: Void = Monitor.waitForCondition(satisfiedCondition, in: state)
        async let m2: Void = Monitor.waitForCondition(satisfiedCondition, in: state)

        // An ugly polling loop to avoid polling everywhere else...
        while state.get().onSatisfied.count < 2 {
            try await Task.sleep(nanoseconds: NSEC_PER_USEC)
        }

        Monitor.updateAndNotify(
            in: state,
            block: { $0.isSatisfied = true },
            conditions: satisfiedCondition,
        )

        try await m1
        try await m2

        #expect(state.get().onSatisfied.isEmpty)
    }

    @Test
    func testAlreadySatisfied() async throws {
        state.update { $0.isSatisfied = true }
        try await Monitor.waitForCondition(satisfiedCondition, in: state)
        #expect(state.get().onSatisfied.isEmpty)
    }

    @Test
    func testCanceled() async throws {
        let waitTask = Task {
            try await Monitor.waitForCondition(satisfiedCondition, in: state)
        }
        waitTask.cancel()
        await #expect(throws: CancellationError.self, performing: { try await waitTask.value })
        #expect(state.get().onSatisfied.isEmpty)
    }

    private class QueueState {
        var isSatisfied = false
        var onSatisfied = [NSObject: Monitor.Continuation]()
    }

    private let queueSatisfiedCondition = Monitor.Condition<QueueState>(
        isSatisfied: { $0.isSatisfied },
        waiters: \.onSatisfied,
    )

    @Test
    func testWaitQueue() async throws {
        let queue = DispatchQueue(label: #fileID)
        let queueState = QueueState()
        func queueStateCount() async -> Int {
            await withCheckedContinuation { continuation in
                queue.async { continuation.resume(returning: queueState.onSatisfied.count) }
            }
        }
        async let m1: Void = Monitor.waitForCondition(self.queueSatisfiedCondition, in: queueState, on: queue)
        async let m2: Void = Monitor.waitForCondition(self.queueSatisfiedCondition, in: queueState, on: queue)
        // An ugly polling loop to avoid polling everywhere else...
        while await queueStateCount() < 2 {
            try await Task.sleep(nanoseconds: NSEC_PER_USEC)
        }
        queue.async {
            queueState.isSatisfied = true
            Monitor.notifyOnQueue(queue, state: queueState, conditions: self.queueSatisfiedCondition)
        }
        try await m1
        try await m2
        #expect(await queueStateCount() == 0)
    }
}
