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
        databaseStorage.readSwallowingErrors { (transaction) in
            result += anyFetchAll(transaction: transaction)
        }
        return result
    }

    @objc
    public class func anyFetchAll(transaction: SDSAnyReadTransaction) -> [TSThread] {
        var result = [TSThread]()
        switch transaction.readTransaction {
        case .yapRead(let ydbTransaction):
            TSThread.enumerateCollectionObjects(with: ydbTransaction) { (object, _) in
                guard let model = object as? TSThread else {
                    owsFailDebug("unexpected object: \(type(of: object))")
                    return
                }
                result.append(model)
            }
        case .grdbRead(let grdbTransaction):
            let columnNames: [String] = TSThreadSerializer.table.selectColumnNames
            let columnsSQL: String = columnNames.map { $0.quotedDatabaseIdentifier }.joined(separator: ", ")
            let tableName: String = TSThreadSerializer.table.tableName
            // TODO: Add ORDER by clause.
            let sql: String = "SELECT \(columnsSQL) FROM \(tableName.quotedDatabaseIdentifier)"
            do {
                result += try grdbFetchCursor(sql: sql, arguments: nil, transaction: grdbTransaction).all()
            } catch let error {
                // TODO:
                owsFail("Read failed: \(error)")
            }
        }
        return result
    }
}

// MARK: -

extension TSInteraction {
    @objc
    public class func anyFetchAll(databaseStorage: SDSDatabaseStorage) -> [TSInteraction] {
        var result = [TSInteraction]()
        databaseStorage.readSwallowingErrors { (transaction) in
            result += anyFetchAll(transaction: transaction)
        }
        return result
    }

    @objc
    public class func anyFetchAll(transaction: SDSAnyReadTransaction) -> [TSInteraction] {
        var result = [TSInteraction]()
        switch transaction.readTransaction {
        case .yapRead(let ydbTransaction):
            TSInteraction.enumerateCollectionObjects(with: ydbTransaction) { (object, _) in
                guard let model = object as? TSInteraction else {
                    owsFailDebug("unexpected object: \(type(of: object))")
                    return
                }
                result.append(model)
            }
        case .grdbRead(let grdbTransaction):
            let columnNames: [String] = TSInteractionSerializer.table.selectColumnNames
            let columnsSQL: String = columnNames.map { $0.quotedDatabaseIdentifier }.joined(separator: ", ")
            let tableName: String = TSInteractionSerializer.table.tableName
            // TODO: Add ORDER by clause.
            let sql: String = "SELECT \(columnsSQL) FROM \(tableName.quotedDatabaseIdentifier)"
            do {
                result += try grdbFetchCursor(sql: sql, arguments: nil, transaction: grdbTransaction).all()
            } catch let error {
                // TODO:
                owsFail("Read failed: \(error)")
            }
        }
        return result
    }
}

// MARK: -

class SDSDatabaseStorageTest: SSKBaseTestSwift {

    func test_threads() {
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

    func test_interactions() {
        let storage = try! SDSDatabaseStorage(adapter: SDSDatabaseStorage.createGrdbStorage(), raisingErrors: ())

        XCTAssertEqual(0, TSInteraction.anyFetchAll(databaseStorage: storage).count)

        let contactId = "+13213214321"
        let contactThread = TSContactThread(contactId: contactId)

        try! storage.write { (transaction) in
            XCTAssertEqual(0, TSThread.anyFetchAll(transaction: transaction).count)
            contactThread.anySave(transaction: transaction)
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
        }

        XCTAssertEqual(1, TSThread.anyFetchAll(databaseStorage: storage).count)
        XCTAssertEqual(0, TSInteraction.anyFetchAll(databaseStorage: storage).count)

        let message1 = TSOutgoingMessage(in: contactThread, messageBody: "message1", attachmentId: nil)

        try! storage.write { (transaction) in
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            XCTAssertEqual(0, TSInteraction.anyFetchAll(transaction: transaction).count)
            message1.anySave(transaction: transaction)
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            XCTAssertEqual(1, TSInteraction.anyFetchAll(transaction: transaction).count)
        }

        XCTAssertEqual(1, TSThread.anyFetchAll(databaseStorage: storage).count)
        XCTAssertEqual(1, TSInteraction.anyFetchAll(databaseStorage: storage).count)

        let message2 = TSOutgoingMessage(in: contactThread, messageBody: "message2", attachmentId: nil)

        try! storage.write { (transaction) in
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            XCTAssertEqual(1, TSInteraction.anyFetchAll(transaction: transaction).count)
            message2.anySave(transaction: transaction)
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            XCTAssertEqual(2, TSInteraction.anyFetchAll(transaction: transaction).count)
        }

        XCTAssertEqual(1, TSThread.anyFetchAll(databaseStorage: storage).count)
        XCTAssertEqual(2, TSInteraction.anyFetchAll(databaseStorage: storage).count)

        // Re-saving a model should have no effect.
        try! storage.write { (transaction) in
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            XCTAssertEqual(2, TSInteraction.anyFetchAll(transaction: transaction).count)
            message2.anySave(transaction: transaction)
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            XCTAssertEqual(2, TSInteraction.anyFetchAll(transaction: transaction).count)
        }

        XCTAssertEqual(1, TSThread.anyFetchAll(databaseStorage: storage).count)
        XCTAssertEqual(2, TSInteraction.anyFetchAll(databaseStorage: storage).count)

        try! storage.write { (transaction) in
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            XCTAssertEqual(2, TSInteraction.anyFetchAll(transaction: transaction).count)
            message1.anyRemove(transaction: transaction)
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            XCTAssertEqual(1, TSInteraction.anyFetchAll(transaction: transaction).count)
        }

        XCTAssertEqual(1, TSThread.anyFetchAll(databaseStorage: storage).count)
        XCTAssertEqual(1, TSInteraction.anyFetchAll(databaseStorage: storage).count)

        try! storage.write { (transaction) in
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
