//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import XCTest
import SignalServiceKit

class OWSRequestFactoryTest: XCTestCase {
    func testGiftBadgePricesRequest() throws {
        let request = OWSRequestFactory.giftBadgePricesRequest()
        XCTAssertEqual(request.url?.path, "v1/subscription/boost/amounts/gift")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertTrue(request.parameters.isEmpty)
    }
}
