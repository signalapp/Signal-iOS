//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class AccountAttributesTest: XCTestCase {
    func testCapabilitiesRequestParameters() {
        let capabilities = AccountAttributes.Capabilities(hasSVRBackups: true)
        let requestParameters = capabilities.requestParameters
        // All we care about is that the prior line didn't crash.
        XCTAssertGreaterThanOrEqual(requestParameters.count, 0)
    }
}
