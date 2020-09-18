//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest

@testable import SignalServiceKit

class RemoteConfigManagerTests: SSKBaseTestSwift {
    func test_bucketCalculation() {
        let key = "research.megaphone.1"
        let uuid = UUID(uuidString: "15b9729c-51ea-4ddb-b516-652befe78062")!
        let bucketSize: UInt64 = 1_000_000

        let bucket = RemoteConfig.bucket(key: key, uuid: uuid, bucketSize: bucketSize)
        XCTAssertEqual(bucket, 243_315)
    }
}
