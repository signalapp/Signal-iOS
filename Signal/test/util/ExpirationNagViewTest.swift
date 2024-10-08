//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import Signal
import SignalServiceKit

final class ExpirationNagViewTest: XCTestCase {
    private var date: Date!
    private var dateProvider: DateProvider { { self.date } }

    private var appExpiry: MockAppExpiry!

    override func setUp() {
        date = Date()
        appExpiry = MockAppExpiry()
        appExpiry.dateProvider = self.dateProvider
    }

    func testNoNag() {
        let nag = ExpirationNagView(
            dateProvider: dateProvider,
            appExpiry: appExpiry,
            osExpiry: OsExpiry(minimumIosMajorVersion: 2, enforcedAfter: date),
            device: MockDevice()
        )
        XCTAssertNil(nag.expirationMessage())
    }

    func testAppExpiry() {
        let nag = ExpirationNagView(
            dateProvider: dateProvider,
            appExpiry: appExpiry,
            osExpiry: OsExpiry(minimumIosMajorVersion: 2, enforcedAfter: date),
            device: MockDevice()
        )

        // Hidden with 12 days left.
        date = appExpiry.expirationDate.subtractingTimeInterval(12 * kDayInterval)
        XCTAssertNil(nag.expirationMessage())

        // Shown with nonempty text if 10 days or sooner.
        for dayCount in [10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0, -1, -99] {
            date = appExpiry.expirationDate.subtractingTimeInterval(
                TimeInterval(dayCount) * kDayInterval
            )
            nag.update()
            XCTAssertNotNil(nag.text.strippedOrNil)
            XCTAssertNotNil(nag.actionTitle)
            XCTAssertEqual(nag.urlToOpen, TSConstants.appStoreUrl)
            XCTAssertFalse(nag.isHidden)
        }

        // The text changes at different intervals.
        var texts = Set<String>()
        for dayCount in [2, 1, -1] {
            date = appExpiry.expirationDate.subtractingTimeInterval(
                TimeInterval(dayCount) * kDayInterval
            )
            nag.update()
            texts.insert(nag.text)
        }
        XCTAssertEqual(texts.count, 3)
    }

    func testOsExpiry() {
        let now = Date(timeIntervalSince1970: 1720000000)
        let osExpiration = Date(timeIntervalSince1970: 1727740800)
        let appExpiration1 = osExpiration.addingTimeInterval(-5 * kDayInterval)
        let appExpiration2 = osExpiration.addingTimeInterval(5 * kDayInterval)

        func d(_ offset: Int) -> Date {
            return now.addingTimeInterval(TimeInterval(offset) * kDayInterval)
        }

        let testCases: [(
            appExpiration: Date,
            timeToCheck: Int,
            expectedMessage: ExpirationNagView.ExpirationMessage?
        )] = [
            // The OS expires after the app.
            (appExpiration1, 10, .osWillExpireSoon(osExpiration, canUpgrade: true)),
            (appExpiration1, 80, .appWillExpireSoon(appExpiration1)),
            (appExpiration1, 84, .appWillExpireToday),
            (appExpiration1, 85, .appExpired),
            // If you wait long enough, the message will switch to OS expiration.
            (appExpiration1, 90, .osExpired(canUpgrade: true)),

            // The OS expires before the app.
            (appExpiration2, 10, .osWillExpireSoon(osExpiration, canUpgrade: true)),
            (appExpiration2, 89, .osWillExpireSoon(osExpiration, canUpgrade: true)),
            (appExpiration2, 90, .osExpired(canUpgrade: true)),
            (appExpiration2, 95, .osExpired(canUpgrade: true)),
            (appExpiration2, 99, .osExpired(canUpgrade: true)),
        ]
        for testCase in testCases {
            self.date = now.addingTimeInterval(TimeInterval(testCase.timeToCheck) * kDayInterval)
            self.appExpiry.expirationDate = testCase.appExpiration
            let nag = ExpirationNagView(
                dateProvider: dateProvider,
                appExpiry: appExpiry,
                osExpiry: OsExpiry(minimumIosMajorVersion: 3, enforcedAfter: osExpiration),
                device: MockDevice()
            )
            XCTAssertEqual(nag.expirationMessage(), testCase.expectedMessage, "\(testCase.timeToCheck)")
        }
    }

    func testOsExpirySoonToExpire() {
        let osExpirationDate = date.addingTimeInterval(5 * kDayInterval)

        let nag = ExpirationNagView(
            dateProvider: dateProvider,
            appExpiry: appExpiry,
            osExpiry: OsExpiry(minimumIosMajorVersion: 3, enforcedAfter: osExpirationDate),
            device: MockDevice()
        )

        XCTAssertFalse(nag.isHidden)
        XCTAssert(nag.text.contains(osExpirationDate.formatted))
    }

    func testOsExpired() {
        let osExpirationDate = date.subtractingTimeInterval(1)

        let nag = ExpirationNagView(
            dateProvider: dateProvider,
            appExpiry: appExpiry,
            osExpiry: OsExpiry(minimumIosMajorVersion: 3, enforcedAfter: osExpirationDate),
            device: MockDevice()
        )

        XCTAssertEqual(nag.expirationMessage(), .osExpired(canUpgrade: true))
    }
}

// MARK: - Test helpers device

private class MockDevice: UpgradableDevice {
    var iosMajorVersion = 2
    func canUpgrade(to iosMajorVersion: Int) -> Bool { iosMajorVersion < 4 }
}

fileprivate extension Date {
    func subtractingTimeInterval(_ timeInterval: TimeInterval) -> Date {
        return addingTimeInterval(-timeInterval)
    }

    var formatted: String {
        return DateFormatter.localizedString(from: self, dateStyle: .short, timeStyle: .none)
    }
}
