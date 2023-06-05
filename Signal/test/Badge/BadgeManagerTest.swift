//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import Signal
@testable import SignalServiceKit

class BadgeManagerTest: XCTestCase {
    private class MockBadgeObserver: BadgeObserver {
        var badgeValues = [UInt]()
        func didUpdateBadgeValue(_ badgeManager: BadgeManager, badgeValue: UInt) {
            badgeValues.append(badgeValue)
        }
    }

    func testMultipleRequestsReuseResults() {
        let scheduler = TestScheduler()
        var fetchCount: UInt = 0
        let badgeManager = BadgeManager(
            mainScheduler: scheduler,
            serialScheduler: scheduler,
            fetchBadgeValue: {
                fetchCount += 1
                return fetchCount
            }
        )

        let observer1 = MockBadgeObserver()
        badgeManager.addObserver(observer1)
        let observer2 = MockBadgeObserver()
        badgeManager.addObserver(observer2)
        scheduler.runUntilIdle()
        XCTAssertEqual(observer1.badgeValues, [1])
        XCTAssertEqual(observer2.badgeValues, [1])
        XCTAssertEqual(fetchCount, 1)

        let observer3 = MockBadgeObserver()
        badgeManager.addObserver(observer3)
        scheduler.runUntilIdle()
        XCTAssertEqual(observer1.badgeValues, [1])
        XCTAssertEqual(observer2.badgeValues, [1])
        XCTAssertEqual(observer3.badgeValues, [1])
        XCTAssertEqual(fetchCount, 1)
    }

    func testPendingRequestsCoalesce() {
        let mainScheduler = TestScheduler()
        let serialScheduler = TestScheduler()
        var fetchCount: UInt = 0
        let badgeManager = BadgeManager(
            mainScheduler: mainScheduler,
            serialScheduler: serialScheduler,
            fetchBadgeValue: {
                fetchCount += 1
                return fetchCount
            }
        )

        serialScheduler.start()

        let observer = MockBadgeObserver()
        badgeManager.addObserver(observer)
        mainScheduler.runUntilIdle()
        XCTAssertEqual(observer.badgeValues, [1])

        badgeManager.invalidateBadgeValue()
        badgeManager.invalidateBadgeValue()
        badgeManager.invalidateBadgeValue()

        mainScheduler.runUntilIdle()

        XCTAssertEqual(observer.badgeValues, [1, 2, 3])
        XCTAssertEqual(fetchCount, 3)
    }
}
