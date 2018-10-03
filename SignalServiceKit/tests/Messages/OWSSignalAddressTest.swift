//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import XCTest

class OWSSignalAddressTest: SSKBaseTestSwift {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testInitializer() {
        let recipientId = "+13213214321"
        let deviceId: UInt = 1
        let address = try! OWSSignalAddress(recipientId: recipientId, deviceId: deviceId)
        XCTAssertEqual(address.recipientId, recipientId)
        XCTAssertEqual(address.deviceId, deviceId)
    }

    func testInitializer_badRecipientId() {
        let recipientId = ""
        let deviceId: UInt = 1
        XCTAssertThrowsError(try OWSSignalAddress(recipientId: recipientId, deviceId: deviceId))
    }

    func testInitializer_badDeviceId() {
        let recipientId = "+13213214321"
        let deviceId: UInt = 0
        XCTAssertThrowsError(try OWSSignalAddress(recipientId: recipientId, deviceId: deviceId))
    }
}
