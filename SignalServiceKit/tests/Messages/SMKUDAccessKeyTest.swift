//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import XCTest

class SMKUDAccessKeyTest: XCTestCase {
    func testUDAccessKeyForProfileKey() {
        let profileKey = Aes256Key(data: Data(count: Int(Aes256Key.keyByteLength)))!
        let udAccessKey1 = SMKUDAccessKey(profileKey: profileKey)
        XCTAssertEqual(udAccessKey1.keyData.count, SMKUDAccessKey.kUDAccessKeyLength)

        let udAccessKey2 = SMKUDAccessKey(profileKey: profileKey)
        XCTAssertEqual(udAccessKey2.keyData.count, SMKUDAccessKey.kUDAccessKeyLength)

        XCTAssertEqual(udAccessKey1.keyData, udAccessKey2.keyData)
    }

    func testUDAccessKeyForProfileKey_badProfileKey() {
        let profileKey = Aes256Key(data: Data(count: Int(Aes256Key.keyByteLength - 1)))
        XCTAssertNil(profileKey)
    }
}
