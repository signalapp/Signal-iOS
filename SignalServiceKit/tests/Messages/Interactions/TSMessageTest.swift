//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

@testable import SignalServiceKit
import XCTest

class TSMessageTest: SSKBaseTestSwift {
    private var thread: TSThread!

    override func setUp() {
        super.setUp()

        self.thread = TSContactThread.getOrCreateThread(contactAddress: SignalServiceAddress(phoneNumber: "fake-thread-id"))
    }

    func testExpiresAtWithoutStartedTimer() {
        let builder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: self.thread, messageBody: "foo")
        builder.timestamp = 1
        builder.expiresInSeconds = 100

        let message = builder.buildWithSneakyTransaction()
        XCTAssertEqual(0, message.expiresAt)
    }

    func testExpiresAtWithStartedTimer() {
        let now = Date.ows_millisecondTimestamp()
        let expirationSeconds: UInt32 = 10

        let builder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: self.thread, messageBody: "foo")
        builder.timestamp = 1
        builder.expiresInSeconds = expirationSeconds
        builder.expireStartedAt = now

        let message = builder.buildWithSneakyTransaction()
        XCTAssertEqual(now + UInt64(expirationSeconds * 1000), message.expiresAt)
    }
}
