//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import SignalServiceKit
import XCTest

class InactivePrimaryDeviceStoreTest: XCTestCase {
    private let db: any DB = InMemoryDB()
    private var inactivePrimaryDeviceStore: InactivePrimaryDeviceStore!

    override func setUp() {
        inactivePrimaryDeviceStore = InactivePrimaryDeviceStore()
    }

    func testSetIdlePrimaryDevice() {
        db.read { tx in
            XCTAssertFalse(inactivePrimaryDeviceStore.valueForInactivePrimaryDeviceAlert(transaction: tx))
        }

        db.write { tx in
            inactivePrimaryDeviceStore.setValueForInactivePrimaryDeviceAlert(value: true, transaction: tx)
        }

        db.read { tx in
            XCTAssertTrue(inactivePrimaryDeviceStore.valueForInactivePrimaryDeviceAlert(transaction: tx))
        }

        db.write { tx in
            inactivePrimaryDeviceStore.setValueForInactivePrimaryDeviceAlert(value: false, transaction: tx)
        }

        db.read { tx in
            XCTAssertFalse(inactivePrimaryDeviceStore.valueForInactivePrimaryDeviceAlert(transaction: tx))
        }
    }
}
