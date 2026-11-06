//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

struct NotificationPreconditionTest {
    let notificationName: Notification.Name = Notification.Name(UUID().uuidString)

    @Test
    func testSynchronous() async {
        let precondition = NotificationPrecondition(notificationName: notificationName, isSatisfied: { true })
        let waitResult = await precondition.waitUntilSatisfied()
        #expect(waitResult == .satisfiedImmediately)
    }

    @Test
    func testCanceled() async {
        let precondition = NotificationPrecondition(notificationName: notificationName, isSatisfied: { false })
        let waitTask = Task { await precondition.waitUntilSatisfied() }
        waitTask.cancel()
        let waitResult = await waitTask.value
        #expect(waitResult == .canceled)
    }

    @Test
    func testRaceCondition() async {
        let checkCount = AtomicValue(0, lock: .init())
        let isSatisfied: @Sendable () -> Bool = {
            let checkCountValue = checkCount.update { $0 += 1; return $0 }
            if checkCountValue == 1 {
                // Simulate the flag changing & the notification being posted while the
                // result is still being returned to the caller. The test code is
                // contrived, but it illustrates a real race condition.
                NotificationCenter.default.post(name: notificationName, object: nil)
                return false
            }
            if checkCountValue == 2 {
                return true
            }
            fatalError()
        }
        let precondition = NotificationPrecondition(notificationName: notificationName, isSatisfied: isSatisfied)
        let waitResult = await precondition.waitUntilSatisfied()
        #expect(waitResult == .wasNotSatisfiedButIsNow)
    }
}
