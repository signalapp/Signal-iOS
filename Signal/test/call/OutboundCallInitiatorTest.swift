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
        let fakeOutboundCallInitiator = FakeOutboundCallInitiator()
        fakeOutboundCallInitiator.initiateCall(handle: "555555555")
        XCTAssertNotNil(fakeOutboundCallInitiator.passedRecipientId)
    }
    
    func testE164Number() {
        let fakeOutboundCallInitiator = FakeOutboundCallInitiator()
        fakeOutboundCallInitiator.initiateCall(handle: "+1555555555")
        XCTAssertNotNil(fakeOutboundCallInitiator.passedRecipientId)
    }
    
}
