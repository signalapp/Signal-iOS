//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

class OWSDeviceManagerTest: XCTestCase {
    private let db: any DB = InMemoryDB()
    private var deviceManager: OWSDeviceManager!

    override func setUp() {
        deviceManager = OWSDeviceManagerImpl()
    }

    func testHasReceivedSyncMessage() {
        db.read { tx in
            XCTAssertFalse(deviceManager.hasReceivedSyncMessage(
                inLastSeconds: 60,
                transaction: tx,
            ))
        }

        db.write { transaction in
            deviceManager.setHasReceivedSyncMessage(
                lastReceivedAt: Date().addingTimeInterval(-5),
                transaction: transaction,
            )
        }

        db.read { tx in
            XCTAssertFalse(deviceManager.hasReceivedSyncMessage(
                inLastSeconds: 4,
                transaction: tx,
            ))
        }

        db.read { tx in
            XCTAssertTrue(deviceManager.hasReceivedSyncMessage(
                inLastSeconds: 6,
                transaction: tx,
            ))
        }
    }
}
