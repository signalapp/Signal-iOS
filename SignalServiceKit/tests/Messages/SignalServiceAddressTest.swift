//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
@testable import SignalServiceKit
import XCTest

class SignalServiceAddressTest: SSKBaseTestSwift {

    var cache: SignalServiceAddressCache {
        return SSKEnvironment.shared.signalServiceAddressCache
    }

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
        cache.updateMapping(uuid: uuid1, phoneNumber: phoneNumber1)

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

        // Ignores phone number when UUIDs match.
        XCTAssertEqual(SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1),
                       SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber2))

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
                          SignalServiceAddress(uuid: uuid2, phoneNumber: phoneNumber2))
    }

    func test_mappingChanges() {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let phoneNumber1 = "+13213214321"
        let phoneNumber2 = "+13213214322"
        let phoneNumber3 = "+13213214323"

        autoreleasepool {
            let address1a = SignalServiceAddress(uuid: uuid1, phoneNumber: nil)
            let address1b = SignalServiceAddress(uuid: uuid1, phoneNumber: nil)
            let address1c = SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1)
            let address2a = SignalServiceAddress(uuid: uuid2, phoneNumber: nil)
            let address2b = SignalServiceAddress(uuid: uuid2, phoneNumber: phoneNumber2)

            // We use the "unresolved" accessors unresolvedUuid(), unresolvedPhoneNumber()
            // to avoid filling in the backing values.

            XCTAssertEqual(address1a.unresolvedUuid, uuid1)
            XCTAssertNil(address1a.unresolvedPhoneNumber)
            XCTAssertEqual(address1b.unresolvedUuid, uuid1)
            XCTAssertNil(address1b.unresolvedPhoneNumber)
            XCTAssertEqual(address1c.unresolvedUuid, uuid1)
            XCTAssertEqual(address1c.unresolvedPhoneNumber, phoneNumber1)
            XCTAssertEqual(address2a.unresolvedUuid, uuid2)
            XCTAssertNil(address2a.unresolvedPhoneNumber)
            XCTAssertEqual(address2b.unresolvedUuid, uuid2)
            XCTAssertEqual(address2b.unresolvedPhoneNumber, phoneNumber2)

            SSKEnvironment.shared.signalServiceAddressCache.updateMapping(uuid: uuid1, phoneNumber: phoneNumber1)

            XCTAssertEqual(address1a.unresolvedUuid, uuid1)
            XCTAssertEqual(address1a.unresolvedPhoneNumber, phoneNumber1)
            XCTAssertEqual(address1b.unresolvedUuid, uuid1)
            XCTAssertEqual(address1b.unresolvedPhoneNumber, phoneNumber1)
            XCTAssertEqual(address1c.unresolvedUuid, uuid1)
            XCTAssertEqual(address1c.unresolvedPhoneNumber, phoneNumber1)
            XCTAssertEqual(address2a.unresolvedUuid, uuid2)
            XCTAssertNil(address2a.unresolvedPhoneNumber)
            XCTAssertEqual(address2b.unresolvedUuid, uuid2)
            XCTAssertEqual(address2b.unresolvedPhoneNumber, phoneNumber2)

            SSKEnvironment.shared.signalServiceAddressCache.updateMapping(uuid: uuid1, phoneNumber: phoneNumber3)

            XCTAssertEqual(address1a.unresolvedUuid, uuid1)
            XCTAssertEqual(address1a.unresolvedPhoneNumber, phoneNumber3)
            XCTAssertEqual(address1b.unresolvedUuid, uuid1)
            XCTAssertEqual(address1b.unresolvedPhoneNumber, phoneNumber3)
            XCTAssertEqual(address1c.unresolvedUuid, uuid1)
            XCTAssertEqual(address1c.unresolvedPhoneNumber, phoneNumber3)
            XCTAssertEqual(address2a.unresolvedUuid, uuid2)
            XCTAssertNil(address2a.unresolvedPhoneNumber)
            XCTAssertEqual(address2b.unresolvedUuid, uuid2)
            XCTAssertEqual(address2b.unresolvedPhoneNumber, phoneNumber2)

            // MARK: - Resolved values

            XCTAssertEqual(address1a.uuid, uuid1)
            XCTAssertEqual(address1a.phoneNumber, phoneNumber3)
            XCTAssertEqual(address1b.uuid, uuid1)
            XCTAssertEqual(address1b.phoneNumber, phoneNumber3)
            XCTAssertEqual(address1c.uuid, uuid1)
            XCTAssertEqual(address1c.phoneNumber, phoneNumber3)
            XCTAssertEqual(address2a.uuid, uuid2)
            XCTAssertNil(address2a.phoneNumber)
            XCTAssertEqual(address2b.uuid, uuid2)
            XCTAssertEqual(address2b.phoneNumber, phoneNumber2)
        }
    }
}
