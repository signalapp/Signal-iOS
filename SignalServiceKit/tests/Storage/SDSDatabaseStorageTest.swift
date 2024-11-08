//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable public import SignalServiceKit

extension TSThread {
    @objc
    public class func anyFetchAll(databaseStorage: SDSDatabaseStorage) -> [TSThread] {
        var result = [TSThread]()
        databaseStorage.read { transaction in
            result += anyFetchAll(transaction: transaction)
        }
        return result
    }
}

// MARK: -

extension TSInteraction {
    @objc
    public class func anyFetchAll(databaseStorage: SDSDatabaseStorage) -> [TSInteraction] {
        var result = [TSInteraction]()
        databaseStorage.read { transaction in
            result += anyFetchAll(transaction: transaction)
        }
        return result
    }
}

// MARK: -

class SDSDatabaseStorageTest: SSKBaseTest {

    // MARK: - Test Life Cycle

    override func setUp() {
        super.setUp()

        SSKEnvironment.shared.databaseStorageRef.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .forUnitTests,
                tx: tx.asV2Write
            )
        }
    }

    // MARK: -

    func test_threads() {
        let storage = SSKEnvironment.shared.databaseStorageRef

        XCTAssertEqual(0, TSThread.anyFetchAll(databaseStorage: storage).count)

        let contactAddress = SignalServiceAddress(phoneNumber: "+13213214321")
        let contactThread = TSContactThread(contactAddress: contactAddress)

        storage.write { transaction in
            XCTAssertEqual(0, TSThread.anyFetchAll(transaction: transaction).count)
            contactThread.anyInsert(transaction: transaction)
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
        }

        XCTAssertEqual(1, TSThread.anyFetchAll(databaseStorage: storage).count)

        storage.write { transaction in
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            _ = try! GroupManager.createGroupForTests(members: [contactAddress], name: "Test Group", transaction: transaction)
            XCTAssertEqual(2, TSThread.anyFetchAll(transaction: transaction).count)
        }

        XCTAssertEqual(2, TSThread.anyFetchAll(databaseStorage: storage).count)

        // Update
        storage.write { transaction in
            let threads = TSThread.anyFetchAll(transaction: transaction)
            guard let firstThread = threads.first else {
                XCTFail("Missing model.")
                return
            }
            XCTAssertNil(firstThread.messageDraft)
            firstThread.updateWithDraft(
                draftMessageBody: MessageBody(text: "Some draft", ranges: .empty),
                replyInfo: nil,
                editTargetTimestamp: nil,
                transaction: transaction
            )
        }
        storage.read { transaction in
            let threads = TSThread.anyFetchAll(transaction: transaction)
            guard let firstThread = threads.first else {
                XCTFail("Missing model.")
                return
            }
            XCTAssertEqual(firstThread.messageDraft, "Some draft")
        }
    }

    func test_interactions() {
        let storage = SSKEnvironment.shared.databaseStorageRef

        XCTAssertEqual(0, TSInteraction.anyFetchAll(databaseStorage: storage).count)

        let contactAddress = SignalServiceAddress(phoneNumber: "+13213214321")
        let contactThread = TSContactThread(contactAddress: contactAddress)

        storage.write { transaction in
            XCTAssertEqual(0, TSThread.anyFetchAll(transaction: transaction).count)
            contactThread.anyInsert(transaction: transaction)
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
        }

        XCTAssertEqual(1, TSThread.anyFetchAll(databaseStorage: storage).count)
        XCTAssertEqual(0, TSInteraction.anyFetchAll(databaseStorage: storage).count)

        let message1 = TSOutgoingMessage(in: contactThread, messageBody: "message1")

        storage.write { transaction in
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            XCTAssertEqual(0, TSInteraction.anyFetchAll(transaction: transaction).count)
            message1.anyInsert(transaction: transaction)
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            XCTAssertEqual(1, TSInteraction.anyFetchAll(transaction: transaction).count)
        }

        XCTAssertEqual(1, TSThread.anyFetchAll(databaseStorage: storage).count)
        XCTAssertEqual(1, TSInteraction.anyFetchAll(databaseStorage: storage).count)

        let message2 = TSOutgoingMessage(in: contactThread, messageBody: "message2")

        storage.write { transaction in
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            XCTAssertEqual(1, TSInteraction.anyFetchAll(transaction: transaction).count)
            message2.anyInsert(transaction: transaction)
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            XCTAssertEqual(2, TSInteraction.anyFetchAll(transaction: transaction).count)
        }

        XCTAssertEqual(1, TSThread.anyFetchAll(databaseStorage: storage).count)
        XCTAssertEqual(2, TSInteraction.anyFetchAll(databaseStorage: storage).count)

        storage.write { transaction in
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            XCTAssertEqual(2, TSInteraction.anyFetchAll(transaction: transaction).count)
            DependenciesBridge.shared.interactionDeleteManager.delete(message1, sideEffects: .default(), tx: transaction.asV2Write)
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            XCTAssertEqual(1, TSInteraction.anyFetchAll(transaction: transaction).count)
        }

        XCTAssertEqual(1, TSThread.anyFetchAll(databaseStorage: storage).count)
        XCTAssertEqual(1, TSInteraction.anyFetchAll(databaseStorage: storage).count)

        storage.write { transaction in
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            XCTAssertEqual(1, TSInteraction.anyFetchAll(transaction: transaction).count)
            DependenciesBridge.shared.interactionDeleteManager.delete(message2, sideEffects: .default(), tx: transaction.asV2Write)
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            XCTAssertEqual(0, TSInteraction.anyFetchAll(transaction: transaction).count)
        }

        XCTAssertEqual(1, TSThread.anyFetchAll(databaseStorage: storage).count)
        XCTAssertEqual(0, TSInteraction.anyFetchAll(databaseStorage: storage).count)
    }
}

// MARK: -

private extension TSOutgoingMessage {
    convenience init(in thread: TSThread, messageBody: String) {
        let builder: TSOutgoingMessageBuilder = .withDefaultValues(thread: thread, messageBody: messageBody)
        self.init(outgoingMessageWith: builder, recipientAddressStates: [:])
    }
}
