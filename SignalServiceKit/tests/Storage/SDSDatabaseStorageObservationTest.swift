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
        updateCount += 1
        lastChange = databaseChanges
    }

    func databaseChangesDidUpdateExternally() {
        externalUpdateCount += 1
    }

    func databaseChangesDidReset() {
        resetCount += 1
    }
}

// MARK: -

class SDSDatabaseStorageObservationTest: SSKBaseTest {
    @MainActor
    func testGRDBSyncWrite() {
        // Make sure there's already at least one thread.
        let someThread = self.write { transaction in
            let recipient = SignalServiceAddress(phoneNumber: "+1222333444")
            return TSContactThread.getOrCreateThread(withContactAddress: recipient, transaction: transaction)
        }
        waitForRunLoop()

        // Create the observer & confirm adding it doesn't send any updates.
        let mockObserver = MockObserver()
        DependenciesBridge.shared.databaseChangeObserver.appendDatabaseChangeDelegate(mockObserver)
        XCTAssertEqual(0, mockObserver.updateCount)
        XCTAssertEqual(0, mockObserver.externalUpdateCount)
        XCTAssertEqual(0, mockObserver.resetCount)
        XCTAssertNil(mockObserver.lastChange)

        mockObserver.clear()

        let keyValueStore = KeyValueStore(collection: "test")
        self.write { transaction in
            keyValueStore.setBool(true, key: "test", transaction: transaction.asV2Write)
        }
        waitForRunLoop()

        XCTAssertEqual(1, mockObserver.updateCount)
        XCTAssertEqual(0, mockObserver.externalUpdateCount)
        XCTAssertEqual(0, mockObserver.resetCount)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateInteractions, false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateThreads, false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(tableName: OWSDevice.databaseTableName), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(tableName: "invalid table name"), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(tableName: KeyValueStore.tableName), true)

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
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(tableName: OWSDevice.databaseTableName), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(tableName: "invalid table name"), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(tableName: KeyValueStore.tableName), false)

        mockObserver.clear()

        let (lastMessage, unsavedMessage) = self.write { transaction in
            let recipient = SignalServiceAddress(phoneNumber: "+12345678900")
            let thread = TSContactThread.getOrCreateThread(withContactAddress: recipient, transaction: transaction)
            var message = TSOutgoingMessage(in: thread, messageBody: "Hello Alice")
            message.anyInsert(transaction: transaction)
            message = TSOutgoingMessage.anyFetchOutgoingMessage(uniqueId: message.uniqueId, transaction: transaction)!

            let unsavedMessage = TSOutgoingMessage(in: thread, messageBody: "Goodbyte Alice")

            return (message, unsavedMessage)
        }
        waitForRunLoop()

        XCTAssertEqual(1, mockObserver.updateCount)
        XCTAssertEqual(0, mockObserver.externalUpdateCount)
        XCTAssertEqual(0, mockObserver.resetCount)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateInteractions, true)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateThreads, true)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(tableName: OWSDevice.databaseTableName), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(tableName: "invalid table name"), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(tableName: KeyValueStore.tableName), true)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(interaction: lastMessage), true)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(interaction: unsavedMessage), false)

        mockObserver.clear()

        self.write { transaction in
            SSKEnvironment.shared.databaseStorageRef.touch(thread: someThread, shouldReindex: true, transaction: transaction)
        }
        waitForRunLoop()

        XCTAssertEqual(1, mockObserver.updateCount)
        XCTAssertEqual(0, mockObserver.externalUpdateCount)
        XCTAssertEqual(0, mockObserver.resetCount)
        XCTAssertNotNil(mockObserver.lastChange)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateInteractions, false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateThreads, true)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(tableName: OWSDevice.databaseTableName), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(tableName: "invalid table name"), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(tableName: KeyValueStore.tableName), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(interaction: lastMessage), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(interaction: unsavedMessage), false)

        mockObserver.clear()

        self.write { transaction in
            SSKEnvironment.shared.databaseStorageRef.touch(interaction: lastMessage, shouldReindex: true, transaction: transaction)
        }
        waitForRunLoop()

        XCTAssertEqual(1, mockObserver.updateCount)
        XCTAssertEqual(0, mockObserver.externalUpdateCount)
        XCTAssertEqual(0, mockObserver.resetCount)
        XCTAssertNotNil(mockObserver.lastChange)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateInteractions, true)
        XCTAssertEqual(mockObserver.lastChange?.didUpdateThreads, true)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(tableName: OWSDevice.databaseTableName), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(tableName: "invalid table name"), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(tableName: KeyValueStore.tableName), false)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(interaction: lastMessage), true)
        XCTAssertEqual(mockObserver.lastChange?.didUpdate(interaction: unsavedMessage), false)
    }

    private func waitForRunLoop() {
        let expectation = self.expectation(description: "waiting for run loop")
        DispatchQueue.main.async { expectation.fulfill() }
        waitForExpectations(timeout: 10)
    }
}

// MARK: -

private extension TSOutgoingMessage {
    convenience init(in thread: TSThread, messageBody: String) {
        let builder: TSOutgoingMessageBuilder = .withDefaultValues(thread: thread, messageBody: messageBody)
        self.init(outgoingMessageWith: builder, recipientAddressStates: [:])
    }
}
