//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import XCTest

final class TSThreadTests: XCTestCase {
    func testInitCallsDesignatedInit() throws {
        let thread = TSThread()
        XCTAssertEqual(thread.conversationColorNameObsolete, "Obsolete")
        XCTAssertNil(thread.messageDraft)
        let now = Date()
        let creationDate = try XCTUnwrap(thread.creationDate)
        XCTAssertEqual(creationDate.timeIntervalSinceReferenceDate, now.timeIntervalSinceReferenceDate, accuracy: 0.01 /* 10 ms */)
    }
}
