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
        func didUpdateBadgeCount(_ badgeManager: BadgeManager, badgeCount: BadgeCount) {
            badgeValues.append(badgeCount.unreadChatCount)
        }
    }

    @MainActor
    func testMultipleRequestsReuseResults() async {
        var fetchCount: UInt = 0
        let badgeManager = BadgeManager(
            fetchIntBadgeValue: {
                fetchCount += 1
                return fetchCount
            }
        )

        let observer1 = MockBadgeObserver()
        badgeManager.addObserver(observer1)
        let observer2 = MockBadgeObserver()
        badgeManager.addObserver(observer2)
        await badgeManager.flush()
        XCTAssertEqual(observer1.badgeValues, [1])
        XCTAssertEqual(observer2.badgeValues, [1])
        XCTAssertEqual(fetchCount, 1)

        let observer3 = MockBadgeObserver()
        badgeManager.addObserver(observer3)
        await badgeManager.flush()
        XCTAssertEqual(observer1.badgeValues, [1])
        XCTAssertEqual(observer2.badgeValues, [1])
        XCTAssertEqual(observer3.badgeValues, [1])
        XCTAssertEqual(fetchCount, 1)
    }

    @MainActor
    func testPendingRequestsCoalesce() async {
        var fetchCount: UInt = 0
        let badgeManager = BadgeManager(
            fetchIntBadgeValue: {
                fetchCount += 1
                return fetchCount
            }
        )

        let observer = MockBadgeObserver()
        badgeManager.addObserver(observer)
        await badgeManager.flush()
        XCTAssertEqual(observer.badgeValues, [1])

        badgeManager.serialQueue.sync {
            badgeManager.invalidateBadgeValue()
            badgeManager.invalidateBadgeValue()
            badgeManager.invalidateBadgeValue()
        }

        await badgeManager.flush()
        await badgeManager.flush()

        XCTAssertEqual(observer.badgeValues, [1, 2, 3])
        XCTAssertEqual(fetchCount, 3)
    }
}

private extension BadgeManager {
    convenience init(
        fetchIntBadgeValue: @escaping () -> UInt
    ) {
        self.init(
            fetchBadgeCountBlock: { BadgeCount(unreadChatCount: fetchIntBadgeValue(), unreadCallsCount: 0) }
        )
    }

    func flush() async {
        await withCheckedContinuation { continuation in
            self.serialQueue.async {
                DispatchQueue.main.async {
                    continuation.resume()
                }
            }
        }
    }
}
