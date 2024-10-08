//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
public import LibSignalClient

public protocol GroupMemberStore {
    func insert(fullGroupMember: TSGroupMember, tx: DBWriteTransaction)
    func update(fullGroupMember: TSGroupMember, tx: DBWriteTransaction)
    func remove(fullGroupMember: TSGroupMember, tx: DBWriteTransaction)

    func groupThreadIds(withFullMember serviceId: ServiceId, tx: DBReadTransaction) -> [String]
    func groupThreadIds(withFullMember phoneNumber: E164, tx: DBReadTransaction) -> [String]

    func sortedFullGroupMembers(in groupThreadId: String, tx: DBReadTransaction) -> [TSGroupMember]
}

class GroupMemberStoreImpl: GroupMemberStore {
    func insert(fullGroupMember groupMember: TSGroupMember, tx: DBWriteTransaction) {
        groupMember.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
    }

    func update(fullGroupMember groupMember: TSGroupMember, tx: DBWriteTransaction) {
        groupMember.anyOverwritingUpdate(transaction: SDSDB.shimOnlyBridge(tx))
    }

    func remove(fullGroupMember groupMember: TSGroupMember, tx: DBWriteTransaction) {
        groupMember.anyRemove(transaction: SDSDB.shimOnlyBridge(tx))
    }

    func groupThreadIds(withFullMember serviceId: ServiceId, tx: DBReadTransaction) -> [String] {
        Self.groupThreadIds(withFullMember: serviceId, tx: tx)
    }

    fileprivate static func groupThreadIds(withFullMember serviceId: ServiceId, tx: DBReadTransaction) -> [String] {
        let sql = """
            SELECT \(TSGroupMember.columnName(.groupThreadId))
            FROM \(TSGroupMember.databaseTableName)
            WHERE \(TSGroupMember.columnName(.serviceId)) = ?
        """
        return tx.databaseConnection.strictRead { try String.fetchAll($0, sql: sql, arguments: [serviceId.serviceIdUppercaseString]) }
    }

    func groupThreadIds(withFullMember phoneNumber: E164, tx: DBReadTransaction) -> [String] {
        Self.groupThreadIds(withFullMember: phoneNumber, tx: tx)
    }

    fileprivate static func groupThreadIds(withFullMember phoneNumber: E164, tx: DBReadTransaction) -> [String] {
        let sql = """
            SELECT \(TSGroupMember.columnName(.groupThreadId))
            FROM \(TSGroupMember.databaseTableName)
            WHERE \(TSGroupMember.columnName(.phoneNumber)) = ?
        """
        return tx.databaseConnection.strictRead { try String.fetchAll($0, sql: sql, arguments: [phoneNumber.stringValue]) }
    }

    func sortedFullGroupMembers(in groupThreadId: String, tx: DBReadTransaction) -> [TSGroupMember] {
        Self.sortedFullGroupMembers(in: groupThreadId, tx: tx)
    }

    fileprivate static func sortedFullGroupMembers(in groupThreadId: String, tx: DBReadTransaction) -> [TSGroupMember] {
        let sql = """
            SELECT * FROM \(TSGroupMember.databaseTableName)
            WHERE \(TSGroupMember.columnName(.groupThreadId)) = ?
            ORDER BY \(TSGroupMember.columnName(.lastInteractionTimestamp)) DESC
        """
        return tx.databaseConnection.strictRead { try TSGroupMember.fetchAll($0, sql: sql, arguments: [groupThreadId]) }
    }
}

#if TESTABLE_BUILD

class MockGroupMemberStore: GroupMemberStore {
    private let db = InMemoryDB()

    func insert(fullGroupMember groupMember: TSGroupMember, tx: DBWriteTransaction) {
        db.insert(record: groupMember)
    }

    func update(fullGroupMember groupMember: TSGroupMember, tx: DBWriteTransaction) {
        db.update(record: groupMember)
    }

    func remove(fullGroupMember groupMember: TSGroupMember, tx: DBWriteTransaction) {
        db.remove(model: groupMember)
    }

    func groupThreadIds(withFullMember serviceId: ServiceId, tx: DBReadTransaction) -> [String] {
        db.read { tx in
            GroupMemberStoreImpl.groupThreadIds(withFullMember: serviceId, tx: tx)
        }
    }

    func groupThreadIds(withFullMember phoneNumber: E164, tx: DBReadTransaction) -> [String] {
        db.read { tx in
            GroupMemberStoreImpl.groupThreadIds(withFullMember: phoneNumber, tx: tx)
        }
    }

    func sortedFullGroupMembers(in groupThreadId: String, tx: DBReadTransaction) -> [TSGroupMember] {
        db.read { tx in
            GroupMemberStoreImpl.sortedFullGroupMembers(in: groupThreadId, tx: tx)
        }
    }
}

#endif
