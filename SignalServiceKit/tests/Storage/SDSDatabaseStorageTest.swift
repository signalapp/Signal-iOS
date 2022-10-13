//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable import SignalServiceKit

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

class SDSDatabaseStorageTest: SSKBaseTestSwift {

    // MARK: - Test Life Cycle

    override func setUp() {
        super.setUp()

        // ensure local client has necessary "registered" state
        let localE164Identifier = "+13235551234"
        let localUUID = UUID()
        tsAccountManager.registerForTests(withLocalNumber: localE164Identifier, uuid: localUUID)
    }

    // MARK: -

    func test_threads() {
        let storage = SDSDatabaseStorage.shared

        XCTAssertEqual(0, TSThread.anyFetchAll(databaseStorage: storage).count)

        let contactAddress = SignalServiceAddress(phoneNumber: "+13213214321")
        let contactThread = TSContactThread(contactAddress: contactAddress)

        storage.write { transaction in
            XCTAssertEqual(0, TSThread.anyFetchAll(transaction: transaction).count)
            contactThread.anyInsert(transaction: transaction)
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
        }

        XCTAssertEqual(1, TSThread.anyFetchAll(databaseStorage: storage).count)

        var groupThread: TSGroupThread!
        storage.write { transaction in
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)

            groupThread = try! GroupManager.createGroupForTests(members: [contactAddress],
                                                                name: "Test Group",
                                                                transaction: transaction)

            XCTAssertEqual(2, TSThread.anyFetchAll(transaction: transaction).count)
        }

        XCTAssertEqual(2, TSThread.anyFetchAll(databaseStorage: storage).count)

        storage.write { transaction in
            XCTAssertEqual(2, TSThread.anyFetchAll(transaction: transaction).count)
            contactThread.anyRemove(transaction: transaction)
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
        }

        XCTAssertEqual(1, TSThread.anyFetchAll(databaseStorage: storage).count)

        // Update
        storage.write { transaction in
            let threads = TSThread.anyFetchAll(transaction: transaction)
            guard let firstThread = threads.first else {
                XCTFail("Missing model.")
                return
            }
            XCTAssertNil(firstThread.messageDraft)
            firstThread.update(withDraft: MessageBody(text: "Some draft",
                                                      ranges: .empty),
                               replyInfo: nil,
                               transaction: transaction)
        }
        storage.read { transaction in
            let threads = TSThread.anyFetchAll(transaction: transaction)
            guard let firstThread = threads.first else {
                XCTFail("Missing model.")
                return
            }
            XCTAssertEqual(firstThread.messageDraft, "Some draft")
        }

        XCTAssertEqual(1, TSThread.anyFetchAll(databaseStorage: storage).count)

        storage.write { transaction in
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            groupThread.anyRemove(transaction: transaction)
            XCTAssertEqual(0, TSThread.anyFetchAll(transaction: transaction).count)
        }

        XCTAssertEqual(0, TSThread.anyFetchAll(databaseStorage: storage).count)
    }

    func test_interactions() {
        let storage = SDSDatabaseStorage.shared

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

        let message1 = TSOutgoingMessage(in: contactThread, messageBody: "message1", attachmentId: nil)

        storage.write { transaction in
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            XCTAssertEqual(0, TSInteraction.anyFetchAll(transaction: transaction).count)
            message1.anyInsert(transaction: transaction)
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            XCTAssertEqual(1, TSInteraction.anyFetchAll(transaction: transaction).count)
        }

        XCTAssertEqual(1, TSThread.anyFetchAll(databaseStorage: storage).count)
        XCTAssertEqual(1, TSInteraction.anyFetchAll(databaseStorage: storage).count)

        let message2 = TSOutgoingMessage(in: contactThread, messageBody: "message2", attachmentId: nil)

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
            message1.anyRemove(transaction: transaction)
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            XCTAssertEqual(1, TSInteraction.anyFetchAll(transaction: transaction).count)
        }

        XCTAssertEqual(1, TSThread.anyFetchAll(databaseStorage: storage).count)
        XCTAssertEqual(1, TSInteraction.anyFetchAll(databaseStorage: storage).count)

        storage.write { transaction in
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            XCTAssertEqual(1, TSInteraction.anyFetchAll(transaction: transaction).count)
            message2.anyRemove(transaction: transaction)
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            XCTAssertEqual(0, TSInteraction.anyFetchAll(transaction: transaction).count)
        }

        XCTAssertEqual(1, TSThread.anyFetchAll(databaseStorage: storage).count)
        XCTAssertEqual(0, TSInteraction.anyFetchAll(databaseStorage: storage).count)
    }
}
