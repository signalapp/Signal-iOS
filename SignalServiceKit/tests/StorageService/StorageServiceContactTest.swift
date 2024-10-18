//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest
@testable import SignalServiceKit

class StorageServiceContactTest: XCTestCase {
    func testRegistrationStatus() throws {
        let now = Date()
        let nowMs = now.ows_millisecondsSince1970

        let testCases: [(UInt64?, StorageServiceContact.RegistrationStatus)] = [
            (nil, .registered),
            (nowMs, .unregisteredRecently),
            (nowMs, .unregisteredRecently),
            (nowMs - 44 * kDayInMs, .unregisteredRecently),
            (nowMs - 47 * kDayInMs, .unregisteredAWhileAgo),
            (nowMs + 100 * kDayInMs, .unregisteredRecently)
        ]

        for (unregisteredAtTimestamp, expectedValue) in testCases {
            let storageServiceContact = try XCTUnwrap(StorageServiceContact(
                aci: Aci.randomForTesting(),
                phoneNumber: nil,
                pni: nil,
                unregisteredAtTimestamp: unregisteredAtTimestamp
            ))
            let actualValue = storageServiceContact.registrationStatus(currentDate: now, remoteConfig: MockRemoteConfigProvider().currentConfig())
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
            (nowMs - 44 * kDayInMs, true),
            (nowMs + 100 * kDayInMs, true),
            (nowMs - 47 * kDayInMs, false)
        ]

        for (unregisteredAtTimestamp, expectedValue) in testCases {
            let storageServiceContact = try XCTUnwrap(StorageServiceContact(
                aci: Aci.randomForTesting(),
                phoneNumber: nil,
                pni: nil,
                unregisteredAtTimestamp: unregisteredAtTimestamp
            ))
            let actualValue = storageServiceContact.shouldBeInStorageService(currentDate: now, remoteConfig: MockRemoteConfigProvider().currentConfig())
            XCTAssertEqual(actualValue, expectedValue, String(describing: unregisteredAtTimestamp))
        }
    }
}
