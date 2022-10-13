//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

class OWSDeviceProvisioningURLParserTest: XCTestCase {
    func testValid() {
        func isValid(_ provisioningURL: String) -> Bool {
            OWSDeviceProvisioningURLParser(provisioningURL: provisioningURL).isValid
        }

        XCTAssertFalse(isValid(""))
        XCTAssertFalse(isValid("ts:/?uuid=MTIz"))
        XCTAssertFalse(isValid("ts:/?pub_key=MTIz"))
        XCTAssertFalse(isValid("ts:/uuid=asd&pub_key=MTIz"))

        XCTAssertTrue(isValid("ts:/?uuid=asd&pub_key=MTIz"))
    }

    func testPublicKey() {
        let parser = OWSDeviceProvisioningURLParser(provisioningURL: "ts:/?uuid=asd&pub_key=MTIz")

        XCTAssertEqual(parser.publicKey?.base64EncodedString(), "MTIz")
    }

    func testEphemeralDeviceId() {
        let parser = OWSDeviceProvisioningURLParser(provisioningURL: "ts:/?uuid=asd&pub_key=MTIz")

        XCTAssertEqual(parser.ephemeralDeviceId, "asd")
    }
}
