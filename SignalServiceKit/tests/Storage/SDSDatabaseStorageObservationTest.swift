//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

class MockObserver: DatabaseChangeDelegate {
    var updateCount: UInt = 0
    var externalUpdateCount: UInt = 0
    var resetCount: UInt = 0
    var lastChange: DatabaseChanges?

    func clear() {
        updateCount = 0
        externalUpdateCount = 0
        resetCount = 0
        lastChange = nil
    }

    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        AssertIsOnMainThread()

        updateCount += 1
        lastChange = databaseChanges
    }

    func databaseChangesDidUpdateExternally() {
        AssertIsOnMainThread()

        externalUpdateCount += 1
    }

    func databaseChangesDidReset() {
        AssertIsOnMainThread()

        resetCount += 1
    }
}

// MARK: -

class SDSDatabaseStorageObservationTest: SSKBaseTestSwift {
    func testGRDBSyncWrite() {
        try! databaseStorage.grdbStorage.setupDatabaseChangeObserver()

        // Make sure there's already at least one thread.
        let someThread = self.write { transaction in
            let recipient = SignalServiceAddress(phoneNumber: "+1222333444")
            return TSContactThread.getOrCreateThread(withContactAddress: recipient, transaction: transaction)
        }
        waitForRunLoop()

        // Create the observer & confirm adding it doesn't send any updates.
        let mockObserver = MockObserver()
        databaseStorage.appendDatabaseChangeDelegate(mockObserver)
        XCTAssertEqual(0, mockObserver.updateCount)
        XCTAssertEqual(0, mockObserver.externalUpdateCount)
        XCTAssertEqual(0, mockObserver.resetCount)
        XCTAssertNil(mockObserver.lastChange)

        mockObserver.clear()

        let keyValueStore = SDSKeyValueStore(collection: "test")
        let otherKeyValueStore = SDSKeyValueStore(collection: "other")
        self.write { transaction in
            keyValueStore.setBool(true, key: "test", transaction: transaction)
        }
        waitForRunLoop()

        XCTAssertEqual(1, mockObserver.updateCount)
        XCTAssertEqual(0, mockObserver.externalUpdateCount)
        XCTAssertEqual(0, mockObserver.resetCount)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateInteractions, false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateThreads, false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateInteractionsOrThreads, false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateModel(collection: OWSDevice.collection()), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateModel(collection: "invalid collection name"), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(keyValueStore: keyValueStore), true)
        // Note: For GRDB, didUpdate(keyValueStore:) currently returns true if any key value stores was updated.
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(keyValueStore: otherKeyValueStore), true)

        mockObserver.clear()

        self.write { transaction in
            let recipient = SignalServiceAddress(phoneNumber: "+15551234567")
            _ = TSContactThread.getOrCreateThread(withContactAddress: recipient, transaction: transaction)
        }
        waitForRunLoop()

        XCTAssertEqual(1, mockObserver.updateCount)
        XCTAssertEqual(0, mockObserver.externalUpdateCount)
        XCTAssertEqual(0, mockObserver.resetCount)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateInteractions, false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateThreads, true)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateInteractionsOrThreads, true)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateModel(collection: OWSDevice.collection()), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateModel(collection: "invalid collection name"), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(keyValueStore: keyValueStore), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(keyValueStore: otherKeyValueStore), false)

        mockObserver.clear()

        let (lastMessage, unsavedMessage) = self.write { transaction in
            let recipient = SignalServiceAddress(phoneNumber: "+12345678900")
            let thread = TSContactThread.getOrCreateThread(withContactAddress: recipient, transaction: transaction)
            let message = TSOutgoingMessage(in: thread, messageBody: "Hello Alice", attachmentId: nil)
            message.anyInsert(transaction: transaction)
            message.anyReload(transaction: transaction)

            let unsavedMessage = TSOutgoingMessage(in: thread, messageBody: "Goodbyte Alice", attachmentId: nil)

            return (message, unsavedMessage)
        }
        waitForRunLoop()

        XCTAssertEqual(1, mockObserver.updateCount)
        XCTAssertEqual(0, mockObserver.externalUpdateCount)
        XCTAssertEqual(0, mockObserver.resetCount)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateInteractions, true)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateThreads, true)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateInteractionsOrThreads, true)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateModel(collection: OWSDevice.collection()), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateModel(collection: "invalid collection name"), false)
        // Note: For GRDB, didUpdate(keyValueStore:) currently returns true if any key value stores was updated.
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(keyValueStore: keyValueStore), true)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(keyValueStore: otherKeyValueStore), true)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(interaction: lastMessage), true)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(interaction: unsavedMessage), false)

        mockObserver.clear()

        self.write { transaction in
            self.databaseStorage.touch(thread: someThread, shouldReindex: true, transaction: transaction)
            Logger.verbose("Touch complete")
        }
        waitForRunLoop()

        XCTAssertEqual(1, mockObserver.updateCount)
        XCTAssertEqual(0, mockObserver.externalUpdateCount)
        XCTAssertEqual(0, mockObserver.resetCount)
        XCTAssertNotNil(mockObserver.lastChange)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateInteractions, false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateThreads, true)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateInteractionsOrThreads, true)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateModel(collection: OWSDevice.collection()), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateModel(collection: "invalid collection name"), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(keyValueStore: keyValueStore), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(keyValueStore: otherKeyValueStore), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(interaction: lastMessage), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(interaction: unsavedMessage), false)

        mockObserver.clear()

        self.write { transaction in
            self.databaseStorage.touch(interaction: lastMessage, shouldReindex: true, transaction: transaction)
            Logger.verbose("Touch complete")
        }
        waitForRunLoop()

        XCTAssertEqual(1, mockObserver.updateCount)
        XCTAssertEqual(0, mockObserver.externalUpdateCount)
        XCTAssertEqual(0, mockObserver.resetCount)
        XCTAssertNotNil(mockObserver.lastChange)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateInteractions, true)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateThreads, true)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateInteractionsOrThreads, true)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateModel(collection: OWSDevice.collection()), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateModel(collection: "invalid collection name"), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(keyValueStore: keyValueStore), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(keyValueStore: otherKeyValueStore), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(interaction: lastMessage), true)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(interaction: unsavedMessage), false)
    }

    private func waitForRunLoop() {
        let expectation = self.expectation(description: "waiting for run loop")
        DispatchQueue.main.async { expectation.fulfill() }
        waitForExpectations(timeout: 10)
    }
}
