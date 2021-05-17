//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

public extension TSGroupMember {
    @objc(groupMemberForAddress:inGroupThreadId:transaction:)
    class func groupMember(for address: SignalServiceAddress, in groupThreadId: String, transaction: SDSAnyReadTransaction) -> TSGroupMember? {
        let sql = """
            SELECT * FROM \(GroupMemberRecord.databaseTableName)
            WHERE (\(groupMemberColumn: .uuidString) = ? OR \(groupMemberColumn: .uuidString) IS NULL)
            AND (\(groupMemberColumn: .phoneNumber) = ? OR \(groupMemberColumn: .phoneNumber) IS NULL)
            AND NOT (\(groupMemberColumn: .uuidString) IS NULL AND \(groupMemberColumn: .phoneNumber) IS NULL)
            AND \(groupMemberColumn: .groupThreadId) = ?
            LIMIT 1
        """

        return TSGroupMember.grdbFetchOne(
            sql: sql,
            arguments: [address.uuidString, address.phoneNumber, groupThreadId],
            transaction: transaction.unwrapGrdbRead
        )
    }

    @objc(groupMembersInGroupThreadId:transaction:)
    class func groupMembers(in groupThreadId: String, transaction: SDSAnyReadTransaction) -> [TSGroupMember] {
        let sql = """
            SELECT * FROM \(GroupMemberRecord.databaseTableName)
            WHERE \(groupMemberColumn: .groupThreadId) = ?
            ORDER BY \(groupMemberColumn: .lastInteractionTimestamp) DESC
        """
        let cursor = TSGroupMember.grdbFetchCursor(
            sql: sql,
            arguments: [groupThreadId],
            transaction: transaction.unwrapGrdbRead
        )
        var members = [TSGroupMember]()
        while let member = try! cursor.next() {
            members.append(member)
        }
        return members
    }
}

public extension TSGroupThread {
    @objc(groupThreadsWithAddress:transaction:)
    class func groupThreads(with address: SignalServiceAddress,
                            transaction: SDSAnyReadTransaction) -> [TSGroupThread] {
        let sql = """
            SELECT \(groupMemberColumn: .groupThreadId) FROM \(GroupMemberRecord.databaseTableName)
            WHERE (\(groupMemberColumn: .uuidString) = ? OR \(groupMemberColumn: .uuidString) IS NULL)
            AND (\(groupMemberColumn: .phoneNumber) = ? OR \(groupMemberColumn: .phoneNumber) IS NULL)
            AND NOT (\(groupMemberColumn: .uuidString) IS NULL AND \(groupMemberColumn: .phoneNumber) IS NULL)
            ORDER BY \(groupMemberColumn: .lastInteractionTimestamp) DESC
        """

        let cursor = try! String.fetchCursor(
            transaction.unwrapGrdbRead.database,
            sql: sql,
            arguments: [address.uuidString, address.phoneNumber]
        )

        var groupThreads = [TSGroupThread]()
        while let groupThreadId = try! cursor.next() {
            guard let groupThread = TSGroupThread.anyFetchGroupThread(uniqueId: groupThreadId,
                                                                      transaction: transaction) else {
                owsFailDebug("Missing group thread")
                continue
            }
            groupThreads.append(groupThread)
        }

        return groupThreads
    }

    class func enumerateGroupThreads(
        with address: SignalServiceAddress,
        transaction: SDSAnyReadTransaction,
        block: (TSGroupThread, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        let sql = """
            SELECT \(groupMemberColumn: .groupThreadId) FROM \(GroupMemberRecord.databaseTableName)
            WHERE (\(groupMemberColumn: .uuidString) = ? OR \(groupMemberColumn: .uuidString) IS NULL)
            AND (\(groupMemberColumn: .phoneNumber) = ? OR \(groupMemberColumn: .phoneNumber) IS NULL)
            AND NOT (\(groupMemberColumn: .uuidString) IS NULL AND \(groupMemberColumn: .phoneNumber) IS NULL)
            ORDER BY \(groupMemberColumn: .lastInteractionTimestamp) DESC
        """

        let cursor = try! String.fetchCursor(
            transaction.unwrapGrdbRead.database,
            sql: sql,
            arguments: [address.uuidString, address.phoneNumber]
        )

        while let groupThreadId = try! cursor.next() {
            guard let groupThread = TSGroupThread.anyFetchGroupThread(uniqueId: groupThreadId,
                                                                      transaction: transaction) else {
                owsFailDebug("Missing group thread")
                continue
            }
            var stop: ObjCBool = false
            block(groupThread, &stop)
            if stop.boolValue { return }
        }
    }

    @objc(groupThreadIdsWithAddress:transaction:)
    class func groupThreadIds(with address: SignalServiceAddress,
                              transaction: SDSAnyReadTransaction) -> [String] {
        let sql = """
            SELECT \(groupMemberColumn: .groupThreadId)
            FROM \(GroupMemberRecord.databaseTableName)
            WHERE (\(groupMemberColumn: .uuidString) = ? OR \(groupMemberColumn: .uuidString) IS NULL)
            AND (\(groupMemberColumn: .phoneNumber) = ? OR \(groupMemberColumn: .phoneNumber) IS NULL)
            AND NOT (\(groupMemberColumn: .uuidString) IS NULL AND \(groupMemberColumn: .phoneNumber) IS NULL)
            ORDER BY \(groupMemberColumn: .lastInteractionTimestamp) DESC
        """

        return transaction.unwrapGrdbRead.database.strictRead { database in
            try String.fetchAll(database,
                                sql: sql,
                                arguments: [address.uuidString, address.phoneNumber])
        }
    }
}
