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
        var iterationCounter = 0
        while state.get().onSatisfied.count < 2 {
            try await Task.sleep(nanoseconds: NSEC_PER_USEC)
            iterationCounter += 1
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
}
