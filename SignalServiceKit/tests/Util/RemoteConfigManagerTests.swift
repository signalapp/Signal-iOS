//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

class RemoteConfigManagerTests: SSKBaseTestSwift {
    func test_bucketCalculation() {
        let testCases: [(String, String, UInt64, UInt64)] = [
            ("research.megaphone.1", "15b9729c-51ea-4ddb-b516-652befe78062", 1_000_000, 243_315),
            ("research.megaphone.2", "15b9729c-51ea-4ddb-b516-652befe78062", 1_000_000, 551_742),
            ("research.megaphone.1", "5f5b28bb-f485-4a0a-a85c-13fc047524b1", 1_000_000, 365_381),
            ("research.megaphone.1", "15b9729c-51ea-4ddb-b516-652befe78062", 100_000, 43_315)
        ]
        for (key, uuidString, bucketSize, expectedBucket) in testCases {
            let actualBucket = RemoteConfig.bucket(key: key, uuid: UUID(uuidString: uuidString)!, bucketSize: bucketSize)
            XCTAssertEqual(actualBucket, expectedBucket)
        }
    }
}
