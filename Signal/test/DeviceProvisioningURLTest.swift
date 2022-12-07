//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import Signal

class DeviceProvisioningURLTest: XCTestCase {
    func testValid() {
        func isValid(_ provisioningURL: String) -> Bool {
            DeviceProvisioningURL(urlString: provisioningURL) != nil
        }

        XCTAssertFalse(isValid(""))
        XCTAssertFalse(isValid("ts:/?uuid=MTIz"))
        XCTAssertFalse(isValid("ts:/?pub_key=MTIz"))
        XCTAssertFalse(isValid("ts:/uuid=asd&pub_key=MTIz"))

        XCTAssertTrue(isValid("ts:/?uuid=asd&pub_key=MTIz"))
    }

    func testPublicKey() throws {
        let url = try XCTUnwrap(DeviceProvisioningURL(urlString: "ts:/?uuid=asd&pub_key=MTIz"))

        XCTAssertEqual(url.publicKey, "123".data(using: .utf8))
    }

    func testEphemeralDeviceId() throws {
        let url = try XCTUnwrap(DeviceProvisioningURL(urlString: "ts:/?uuid=asd&pub_key=MTIz"))

        XCTAssertEqual(url.ephemeralDeviceId, "asd")
    }
}
