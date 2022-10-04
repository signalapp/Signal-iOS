//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import XCTest
import SignalServiceKit
import SignalCoreKit

class SMKUDAccessKeyTest: XCTestCase {
    func testUDAccessKeyForProfileKey() {
        let profileKey = Data(count: Int(kAES256_KeyByteLength))
        let udAccessKey1 = try! SMKUDAccessKey(profileKey: profileKey)
        XCTAssertEqual(udAccessKey1.keyData.count, SMKUDAccessKey.kUDAccessKeyLength)

        let udAccessKey2 = try! SMKUDAccessKey(profileKey: profileKey)
        XCTAssertEqual(udAccessKey2.keyData.count, SMKUDAccessKey.kUDAccessKeyLength)

        XCTAssertEqual(udAccessKey1, udAccessKey2)
    }

    func testUDAccessKeyForProfileKey_badProfileKey() {
        let profileKey = Data(count: Int(kAES256_KeyByteLength - 1))
        XCTAssertThrowsError(try SMKUDAccessKey(profileKey: profileKey))
    }
}
