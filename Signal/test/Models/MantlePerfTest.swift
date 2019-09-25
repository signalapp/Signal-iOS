//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import SignalMessaging
@testable import SignalServiceKit

class MantlePerfTest: SignalBaseTest {

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testPerformanceExample() {
        let migration = OWS110SortIdMigration()

        self.measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            _ = OutgoingMessageFactory().create(count: 100)

            startMeasuring()

            let migrationCompleted = expectation(description: "migrationCompleted")
            migration.runUp(completion: migrationCompleted.fulfill)

            self.wait(for: [migrationCompleted], timeout: 10)

            stopMeasuring()

            self.write { transaction in
                TSInteraction.anyRemoveAllWithInstantation(transaction: transaction)
            }
        }
    }

}
