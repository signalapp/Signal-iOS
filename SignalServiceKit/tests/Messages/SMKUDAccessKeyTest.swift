//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

class SMKUDAccessKeyTest: XCTestCase {
    func testUDAccessKeyForProfileKey() {
        let profileKey = Data(count: Int(Aes256Key.keyByteLength))
        let udAccessKey1 = try! SMKUDAccessKey(profileKey: profileKey)
        XCTAssertEqual(udAccessKey1.keyData.count, SMKUDAccessKey.kUDAccessKeyLength)

        let udAccessKey2 = try! SMKUDAccessKey(profileKey: profileKey)
        XCTAssertEqual(udAccessKey2.keyData.count, SMKUDAccessKey.kUDAccessKeyLength)

        XCTAssertEqual(udAccessKey1.keyData, udAccessKey2.keyData)
    }

    func testUDAccessKeyForProfileKey_badProfileKey() {
        let profileKey = Data(count: Int(Aes256Key.keyByteLength - 1))
        XCTAssertThrowsError(try SMKUDAccessKey(profileKey: profileKey))
    }
}
