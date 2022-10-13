//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

final class ProtoParsingTest: XCTestCase {
    func testProtoParsingInvalid() throws {
        XCTAssertThrowsError(try SSKProtoEnvelope(serializedData: Data()))
        XCTAssertThrowsError(try SSKProtoEnvelope(serializedData: Data([1, 2, 3])))
    }
}
