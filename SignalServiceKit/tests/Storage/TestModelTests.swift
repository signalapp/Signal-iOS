//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest
@testable import SignalServiceKit

class TestModelTests: SSKBaseTestSwift {

    func testTestModel() {

        self.write { transaction in
            let writeModel = TestModel()
            writeModel.anyInsert(transaction: transaction)

            let readModel = TestModel.anyFetch(uniqueId: writeModel.uniqueId, transaction: transaction)!
            XCTAssertFalse(writeModel === readModel)
            XCTAssertEqual(0, readModel.doubleValue)
            XCTAssertEqual(0, readModel.floatValue)
            XCTAssertEqual(0, readModel.uint64Value)
            XCTAssertEqual(0, readModel.int64Value)
            XCTAssertEqual(0, readModel.nsuIntegerValue)
            XCTAssertEqual(0, readModel.nsIntegerValue)
        }
    }
}
