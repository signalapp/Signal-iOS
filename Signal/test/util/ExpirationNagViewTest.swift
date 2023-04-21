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
    }

    func testNoNag() {
        let nag = ExpirationNagView(
            dateProvider: dateProvider,
            appExpiry: appExpiry,
            osExpiry: OsExpiry(minimumIosMajorVersion: 2, enforcedAfter: date),
            device: MockDevice()
        )
        XCTAssertTrue(nag.isHidden)
    }

    func testAppExpiry() {
        let nag = ExpirationNagView(
            dateProvider: dateProvider,
            appExpiry: appExpiry,
            osExpiry: OsExpiry(minimumIosMajorVersion: 2, enforcedAfter: date),
            device: MockDevice()
        )

        // Hidden with 11 days left.
        date = appExpiry.expirationDate.subtractingTimeInterval(11 * kDayInterval)
        nag.update()
        XCTAssertTrue(nag.isHidden)

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

        XCTAssertFalse(nag.isHidden)
        XCTAssertFalse(nag.text.contains(osExpirationDate.formatted))
    }

    func testOsExpiryPicksEarlierExpirationDate() {
        let osExpirationDate = date.addingTimeInterval(5 * kDayInterval)
        appExpiry.expirationDate = date.subtractingTimeInterval(1)

        let nag = ExpirationNagView(
            dateProvider: dateProvider,
            appExpiry: appExpiry,
            osExpiry: OsExpiry(minimumIosMajorVersion: 3, enforcedAfter: osExpirationDate),
            device: MockDevice()
        )

        XCTAssertFalse(nag.isHidden)
        XCTAssertFalse(nag.text.contains(osExpirationDate.formatted))
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
