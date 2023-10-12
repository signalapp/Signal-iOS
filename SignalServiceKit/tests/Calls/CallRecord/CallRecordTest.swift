//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class CallRecordTest: XCTestCase {
    func testNoOverlapBetweenStatuses() {
        let allIndividualStatusRawValues = CallRecord.CallStatus.IndividualCallStatus.allCases.map { $0.rawValue }
        let allGroupStatusRawValues = CallRecord.CallStatus.GroupCallStatus.allCases.map { $0.rawValue }

        XCTAssertFalse(
            Set(allIndividualStatusRawValues).intersects(Set(allGroupStatusRawValues))
        )
    }
}
