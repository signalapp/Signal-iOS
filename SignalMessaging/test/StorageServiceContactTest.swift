//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalMessaging

class StorageServiceContactTest: XCTestCase {
    func testRegistrationStatus() throws {
        let now = Date()
        let nowMs = now.ows_millisecondsSince1970

        let testCases: [(UInt64?, StorageServiceContact.RegistrationStatus)] = [
            (nil, .registered),
            (nowMs, .unregisteredRecently),
            (nowMs, .unregisteredRecently),
            (nowMs - 29 * kDayInMs, .unregisteredRecently),
            (nowMs - 32 * kDayInMs, .unregisteredMoreThanOneMonthAgo),
            (nowMs + 100 * kDayInMs, .unregisteredRecently)
        ]

        for (unregisteredAtTimestamp, expectedValue) in testCases {
            let storageServiceContact = try XCTUnwrap(StorageServiceContact(
                serviceId: UUID(),
                serviceE164: nil,
                unregisteredAtTimestamp: unregisteredAtTimestamp
            ))
            let actualValue = storageServiceContact.registrationStatus(currentDate: now)
            XCTAssertEqual(actualValue, expectedValue, String(describing: unregisteredAtTimestamp))
        }
    }

    func testShouldBeInStorageService() throws {
        let now = Date()
        let nowMs = now.ows_millisecondsSince1970

        let testCases: [(UInt64?, Bool)] = [
            (nil, true),
            (nowMs, true),
            (nowMs, true),
            (nowMs - 29 * kDayInMs, true),
            (nowMs + 100 * kDayInMs, true),
            (nowMs - 32 * kDayInMs, false)
        ]

        for (unregisteredAtTimestamp, expectedValue) in testCases {
            let storageServiceContact = try XCTUnwrap(StorageServiceContact(
                serviceId: UUID(),
                serviceE164: nil,
                unregisteredAtTimestamp: unregisteredAtTimestamp
            ))
            let actualValue = storageServiceContact.shouldBeInStorageService(currentDate: now)
            XCTAssertEqual(actualValue, expectedValue, String(describing: unregisteredAtTimestamp))
        }
    }
}
