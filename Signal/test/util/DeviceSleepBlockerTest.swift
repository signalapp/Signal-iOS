//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing
@testable import Signal
@testable import SignalServiceKit

@MainActor
struct DeviceSleepBlockerTest {
    private let deviceSleepManager = DeviceSleepManagerMock()

    @Test
    func testToggling() {
        let blocker = DeviceSleepBlocker(
            blockReason: "test",
            maxBlockDuration: .infinity,
            deviceSleepManager: deviceSleepManager,
        )

        blocker.setShouldBlock(true)
        #expect(deviceSleepManager.blockObjects.count == 1)

        blocker.setShouldBlock(true)
        #expect(deviceSleepManager.blockObjects.count == 1)

        blocker.setShouldBlock(false)
        #expect(deviceSleepManager.blockObjects.isEmpty)

        blocker.setShouldBlock(false)
        #expect(deviceSleepManager.blockObjects.isEmpty)
    }

    @Test
    func testExpiration() async {
        let blocker = DeviceSleepBlocker(
            blockReason: "test",
            maxBlockDuration: .minute,
            deviceSleepManager: deviceSleepManager,
            sleepFn: { _ in },
        )

        blocker.setShouldBlock(true)
        #expect(deviceSleepManager.blockObjects.count == 1)
        await blocker.expirationTaskForTesting!.value
        #expect(deviceSleepManager.blockObjects.isEmpty)

        // Stays expired...
        blocker.setShouldBlock(true)
        #expect(deviceSleepManager.blockObjects.isEmpty)

        // ...until toggled off and back on.
        blocker.setShouldBlock(false)
        blocker.setShouldBlock(true)
        #expect(deviceSleepManager.blockObjects.count == 1)
        await blocker.expirationTaskForTesting!.value
        #expect(deviceSleepManager.blockObjects.isEmpty)
    }

    @Test
    func testCancelledExpirationDoesNotAffectNewBlock() async {
        let blocker = DeviceSleepBlocker(
            blockReason: "test",
            maxBlockDuration: .infinity,
            deviceSleepManager: deviceSleepManager,
        )

        blocker.setShouldBlock(true)
        let firstExpirationTask = blocker.expirationTaskForTesting!

        blocker.setShouldBlock(false)
        blocker.setShouldBlock(true)
        let secondBlockObject = deviceSleepManager.blockObjects.first

        await firstExpirationTask.value
        #expect(deviceSleepManager.blockObjects.count == 1)
        #expect(deviceSleepManager.blockObjects.first === secondBlockObject)
    }
}
