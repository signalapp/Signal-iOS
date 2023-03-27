//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

protocol GroupMemberDataStore {
    func insertGroupMember(_ groupMember: TSGroupMember, transaction: DBWriteTransaction)
    func updateGroupMember(_ groupMember: TSGroupMember, transaction: DBWriteTransaction)
    func removeGroupMember(_ groupMember: TSGroupMember, transaction: DBWriteTransaction)

    func sortedGroupMembers(in groupThreadId: String, transaction: DBReadTransaction) -> [TSGroupMember]
}

class GroupMemberDataStoreImpl: GroupMemberDataStore {
    func insertGroupMember(_ groupMember: TSGroupMember, transaction: DBWriteTransaction) {
        groupMember.anyInsert(transaction: SDSDB.shimOnlyBridge(transaction))
    }

    func updateGroupMember(_ groupMember: TSGroupMember, transaction: DBWriteTransaction) {
        groupMember.anyOverwritingUpdate(transaction: SDSDB.shimOnlyBridge(transaction))
    }

    func removeGroupMember(_ groupMember: TSGroupMember, transaction: DBWriteTransaction) {
        groupMember.anyRemove(transaction: SDSDB.shimOnlyBridge(transaction))
    }

    func sortedGroupMembers(in groupThreadId: String, transaction: DBReadTransaction) -> [TSGroupMember] {
        Self.sortedGroupMembers(in: groupThreadId, database: SDSDB.shimOnlyBridge(transaction).unwrapGrdbRead.database)
    }

    fileprivate static func sortedGroupMembers(in groupThreadId: String, database: Database) -> [TSGroupMember] {
        let sql = """
            SELECT * FROM \(TSGroupMember.databaseTableName)
            WHERE \(TSGroupMember.columnName(.groupThreadId)) = ?
            ORDER BY \(TSGroupMember.columnName(.lastInteractionTimestamp)) DESC
        """
        return database.strictRead { try TSGroupMember.fetchAll($0, sql: sql, arguments: [groupThreadId]) }
    }
}

#if TESTABLE_BUILD

class MockGroupMemberDataStore: GroupMemberDataStore {
    let inMemoryDatabase: DatabaseQueue = {
        let result = DatabaseQueue()
        let schemaUrl = Bundle(for: GRDBSchemaMigrator.self).url(forResource: "schema", withExtension: "sql")!
        try! result.write { try $0.execute(sql: try String(contentsOf: schemaUrl)) }
        return result
    }()

    func insertGroupMember(_ groupMember: TSGroupMember, transaction: DBWriteTransaction) {
        try! inMemoryDatabase.write { try groupMember.insert($0) }
    }

    func updateGroupMember(_ groupMember: TSGroupMember, transaction: DBWriteTransaction) {
        try! inMemoryDatabase.write { try groupMember.update($0) }
    }

    func removeGroupMember(_ groupMember: TSGroupMember, transaction: DBWriteTransaction) {
        try! inMemoryDatabase.write { _ = try groupMember.delete($0) }
    }

    func sortedGroupMembers(in groupThreadId: String, transaction: DBReadTransaction) -> [TSGroupMember] {
        try! inMemoryDatabase.read { GroupMemberDataStoreImpl.sortedGroupMembers(in: groupThreadId, database: $0) }
    }
}

#endif
