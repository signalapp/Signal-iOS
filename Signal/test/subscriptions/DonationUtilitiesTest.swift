//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalMessaging

final class DonationUtilitiesTest: XCTestCase {
    func testChooseDefaultCurrency() throws {
        let foundResult = DonationUtilities.chooseDefaultCurrency(
            preferred: ["AUD", "GBP", nil, "USD", "XYZ"],
            supported: ["USD"]
        )
        XCTAssertEqual(foundResult, "USD")

        let noResult = DonationUtilities.chooseDefaultCurrency(
            preferred: ["AUD", "GBP", "USD"],
            supported: ["XYZ"]
        )
        XCTAssertNil(noResult)
    }
}
