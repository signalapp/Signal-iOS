//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import XCTest
import SignalServiceKit

final class ProtoParsingTest: XCTestCase {
    func testProtoParsingInvalid() throws {
        XCTAssertThrowsError(try SSKProtoEnvelope(serializedData: Data()))
        XCTAssertThrowsError(try SSKProtoEnvelope(serializedData: Data([1, 2, 3])))
    }
}
