//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import SignalServiceKit
import XCTest

class OWSDeviceManagerTest: XCTestCase {
    private let db: DB = MockDB()
    private var deviceManager: OWSDeviceManager!

    override func setUp() {
        deviceManager = OWSDeviceManagerImpl(
            databaseStorage: db,
            keyValueStoreFactory: InMemoryKeyValueStoreFactory()
        )
    }

    func testHasReceivedSyncMessage() {
        XCTAssertFalse(deviceManager.hasReceivedSyncMessage(
            inLastSeconds: 60
        ))

        db.write { transaction in
            deviceManager.setHasReceivedSyncMessage(
                lastReceivedAt: Date().addingTimeInterval(-5),
                transaction: transaction
            )
        }

        XCTAssertFalse(deviceManager.hasReceivedSyncMessage(
            inLastSeconds: 4
        ))

        XCTAssertTrue(deviceManager.hasReceivedSyncMessage(
            inLastSeconds: 6
        ))
    }

    func testMayHaveLinkedDevices() {
        db.write { transaction in
            XCTAssertTrue(deviceManager.mightHaveUnknownLinkedDevice(transaction: transaction))

            deviceManager.setMightHaveUnknownLinkedDevice(false, transaction: transaction)
            XCTAssertFalse(deviceManager.mightHaveUnknownLinkedDevice(transaction: transaction))

            deviceManager.setMightHaveUnknownLinkedDevice(true, transaction: transaction)
            XCTAssertTrue(deviceManager.mightHaveUnknownLinkedDevice(transaction: transaction))
        }
    }
}
