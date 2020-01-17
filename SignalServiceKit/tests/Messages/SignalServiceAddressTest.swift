//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
@testable import SignalServiceKit
import XCTest

class SignalServiceAddressTest: SSKBaseTestSwift {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func test_isEqualPermissive() {
        let phoneNumber1 = "+13213214321"
        let phoneNumber2 = "+13213214322"
        let uuid1 = UUID()
        let uuid2 = UUID()

        // Double match
        XCTAssertEqual(SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1),
                       SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1))

        // Single match works, ignores single missing.
        //
        // SignalServiceAddress's getters use a cache to fill in the blanks.
        XCTAssertEqual(SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber1),
                       SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1))
        XCTAssertEqual(SignalServiceAddress(uuid: uuid1),
                       SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1))
        XCTAssertEqual(SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1),
                       SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber1))
        XCTAssertEqual(SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1),
                       SignalServiceAddress(uuid: uuid1))

        // Single match works, ignores double missing.
        XCTAssertEqual(SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber1),
                       SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber1))
        XCTAssertEqual(SignalServiceAddress(uuid: uuid1),
                       SignalServiceAddress(uuid: uuid1))

        // Match fails if no common value.
        XCTAssertEqual(SignalServiceAddress(uuid: uuid1),
                       SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber1))

        // Match fails if either value doesn't match.
        XCTAssertNotEqual(SignalServiceAddress(uuid: uuid1),
                          SignalServiceAddress(uuid: uuid2))
        XCTAssertNotEqual(SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber1),
                          SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber2))
        XCTAssertNotEqual(SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1),
                          SignalServiceAddress(uuid: uuid2))
        XCTAssertNotEqual(SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1),
                          SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber2))
        XCTAssertNotEqual(SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1),
                          SignalServiceAddress(uuid: uuid2, phoneNumber: phoneNumber1))
        XCTAssertNotEqual(SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1),
                          SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber2))
        XCTAssertNotEqual(SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1),
                          SignalServiceAddress(uuid: uuid2, phoneNumber: phoneNumber2))
    }
}
