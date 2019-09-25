//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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

        let groupId = Randomness.generateRandomBytes(Int32(kGroupIdLength))
        let groupModel = TSGroupModel(title: "Test Group",
                                      members: [contactAddress],
                                      image: nil,
                                      groupId: groupId)
        let groupThread = TSGroupThread(groupModel: groupModel)

        storage.write { transaction in
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            groupThread.anyInsert(transaction: transaction)
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
            firstThread.update(withDraft: "Some draft", transaction: transaction)
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
