//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import Signal

class FakeOutboundCallInitiator: OutboundCallInitiator {
    var passedRecipientId : String?

    override public func initiateCall(recipientId: String,
                                      isVideo: Bool) -> Bool {
        passedRecipientId = recipientId
        return true
    }
}

class OutboundCallInitiatorTest: SignalBaseTest {

    func testMissingCountryCode() {
        let testNumber = "5555555555"
        let fakeOutboundCallInitiator = FakeOutboundCallInitiator()
        fakeOutboundCallInitiator.initiateCall(handle: testNumber)
        XCTAssertNotNil(fakeOutboundCallInitiator.passedRecipientId)
        XCTAssertEqual(fakeOutboundCallInitiator.passedRecipientId, "+15555555555")
    }

    func testMissingCountryCodeWithFormat() {
        let testNumber = "(555) 555-5555"
        let fakeOutboundCallInitiator = FakeOutboundCallInitiator()
        fakeOutboundCallInitiator.initiateCall(handle: testNumber)
        XCTAssertNotNil(fakeOutboundCallInitiator.passedRecipientId)
        XCTAssertEqual(fakeOutboundCallInitiator.passedRecipientId, "+15555555555")
    }

    func testE164Number() {
        let testNumber = "+15555555555"
        let fakeOutboundCallInitiator = FakeOutboundCallInitiator()
        fakeOutboundCallInitiator.initiateCall(handle: testNumber)
        XCTAssertNotNil(fakeOutboundCallInitiator.passedRecipientId)
        XCTAssertEqual(fakeOutboundCallInitiator.passedRecipientId, testNumber)
    }

    func testE164BrazilNumber() {
        let testNumber = "+553212345678"
        let fakeOutboundCallInitiator = FakeOutboundCallInitiator()
        fakeOutboundCallInitiator.initiateCall(handle: testNumber)
        XCTAssertNotNil(fakeOutboundCallInitiator.passedRecipientId)
        XCTAssertEqual(fakeOutboundCallInitiator.passedRecipientId, testNumber)
    }

    func testFranceWithoutPlus() {
        let testNumber = "33 1 70 39 38 00"
        let fakeOutboundCallInitiator = FakeOutboundCallInitiator()
        fakeOutboundCallInitiator.initiateCall(handle: testNumber)
        XCTAssertNotNil(fakeOutboundCallInitiator.passedRecipientId)
        XCTAssertEqual(fakeOutboundCallInitiator.passedRecipientId, "+133170393800")
    }

    func testE164NumberWithFormat() {
        let testNumber = "+1 (555) 555-5555"
        let fakeOutboundCallInitiator = FakeOutboundCallInitiator()
        fakeOutboundCallInitiator.initiateCall(handle: testNumber)
        XCTAssertNotNil(fakeOutboundCallInitiator.passedRecipientId)
        XCTAssertEqual(fakeOutboundCallInitiator.passedRecipientId, "+15555555555")
    }
}
