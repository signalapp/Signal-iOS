//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest
@testable import SignalServiceKit

class SDSDatabaseStorageTest: SSKBaseTestSwift {

    func test_simple2() {
    }

    func test_simple() {
        let storage = try! SDSDatabaseStorage(adapter: SDSDatabaseStorage.createGrdbStorage(), raisingErrors: ())

        XCTAssertEqual(0, TSThread.anyFetchAll(databaseStorage: storage).count)

        let contactId = "+13213214321"
        let contactThread = TSContactThread(contactId: contactId)

        try! storage.write { (transaction) in
            XCTAssertEqual(0, TSThread.anyFetchAll(transaction: transaction).count)
            contactThread.anySave(transaction: transaction)
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
        }

        XCTAssertEqual(1, TSThread.anyFetchAll(databaseStorage: storage).count)

        let groupId = Randomness.generateRandomBytes(Int32(kGroupIdLength))!
        let groupModel = TSGroupModel(title: "Test Group",
                                      memberIds: [contactId ],
                                      image: nil,
                                      groupId: groupId)
        let groupThread = TSGroupThread(groupModel: groupModel)

        try! storage.write { (transaction) in
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            groupThread.anySave(transaction: transaction)
            XCTAssertEqual(2, TSThread.anyFetchAll(transaction: transaction).count)
        }

        XCTAssertEqual(2, TSThread.anyFetchAll(databaseStorage: storage).count)

        try! storage.write { (transaction) in
            XCTAssertEqual(2, TSThread.anyFetchAll(transaction: transaction).count)
            contactThread.anyRemove(transaction: transaction)
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
        }

        XCTAssertEqual(1, TSThread.anyFetchAll(databaseStorage: storage).count)

        try! storage.write { (transaction) in
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            groupThread.anyRemove(transaction: transaction)
            XCTAssertEqual(0, TSThread.anyFetchAll(transaction: transaction).count)
        }

        XCTAssertEqual(0, TSThread.anyFetchAll(databaseStorage: storage).count)
    }
}
