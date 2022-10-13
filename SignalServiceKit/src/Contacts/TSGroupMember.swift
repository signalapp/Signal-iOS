//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

@objc
public final class TSGroupMember: NSObject, SDSCodableModel {
    public static let databaseTableName = "model_TSGroupMember"
    public static var recordType: UInt { SDSRecordType.groupMember.rawValue }
    public static var ftsIndexMode: TSFTSIndexMode { .manualUpdates }

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id
        case recordType
        case uniqueId
        case groupThreadId
        case phoneNumber
        case uuidString
        case lastInteractionTimestamp
    }

    public var id: Int64?
    @objc
    public let uniqueId: String

    @objc
    public let address: SignalServiceAddress
    @objc
    public let groupThreadId: String
    @objc
    public private(set) var lastInteractionTimestamp: UInt64

    @objc
    required public init(address: SignalServiceAddress, groupThreadId: String, lastInteractionTimestamp: UInt64) {
        self.uniqueId = UUID().uuidString
        self.address = address
        self.groupThreadId = groupThreadId
        self.lastInteractionTimestamp = lastInteractionTimestamp
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedRecordType = try container.decode(Int.self, forKey: .recordType)
        owsAssertDebug(decodedRecordType == Self.recordType, "Unexpectedly decoded record with wrong type.")

        id = try container.decodeIfPresent(RowId.self, forKey: .id)
        uniqueId = try container.decode(String.self, forKey: .uniqueId)

        groupThreadId = try container.decode(String.self, forKey: .groupThreadId)

        let uuid = try container.decodeIfPresent(UUID.self, forKey: .uuidString)
        let phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber)
        address = SignalServiceAddress(uuid: uuid, phoneNumber: phoneNumber)

        lastInteractionTimestamp = try container.decode(UInt64.self, forKey: .lastInteractionTimestamp)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try id.map { try container.encode($0, forKey: .id) }
        try container.encode(recordType, forKey: .recordType)
        try container.encode(uniqueId, forKey: .uniqueId)

        try container.encode(groupThreadId, forKey: .groupThreadId)

        try address.uuid.map { try container.encode($0, forKey: .uuidString) }
        try address.phoneNumber.map { try container.encode($0, forKey: .phoneNumber) }

        try container.encode(lastInteractionTimestamp, forKey: .lastInteractionTimestamp)
    }

    // MARK: -

    @objc
    public func updateWithLastInteractionTimestamp(_ lastInteractionTimestamp: UInt64, transaction: SDSAnyWriteTransaction) {
        anyUpdate(transaction: transaction) { groupMember in
            groupMember.lastInteractionTimestamp = lastInteractionTimestamp
        }
    }

    @objc(groupMemberForAddress:inGroupThreadId:transaction:)
    public class func groupMember(for address: SignalServiceAddress, in groupThreadId: String, transaction: SDSAnyReadTransaction) -> TSGroupMember? {
        let sql = """
            SELECT * FROM \(databaseTableName)
            WHERE (\(columnName(.uuidString)) = ? OR \(columnName(.uuidString)) IS NULL)
            AND (\(columnName(.phoneNumber)) = ? OR \(columnName(.phoneNumber)) IS NULL)
            AND NOT (\(columnName(.uuidString)) IS NULL AND \(columnName(.phoneNumber)) IS NULL)
            AND \(columnName(.groupThreadId)) = ?
            LIMIT 1
        """

        do {
            return try fetchOne(
                transaction.unwrapGrdbRead.database,
                sql: sql,
                arguments: [address.uuidString, address.phoneNumber, groupThreadId]
            )
        } catch {
            owsFailDebug("Failed to fetch group member \(error)")
            return nil
        }
    }

    @objc(enumerateGroupMembersForAddress:withTransaction:block:)
    public class func enumerateGroupMembers(
        for address: SignalServiceAddress,
        transaction: SDSAnyReadTransaction,
        block: @escaping (TSGroupMember, UnsafeMutablePointer<ObjCBool>
    ) -> Void) {
        let sql = """
            SELECT * FROM \(databaseTableName)
            WHERE (\(columnName(.uuidString)) = ? OR \(columnName(.uuidString)) IS NULL)
            AND (\(columnName(.phoneNumber)) = ? OR \(columnName(.phoneNumber)) IS NULL)
            AND NOT (\(columnName(.uuidString)) IS NULL AND \(columnName(.phoneNumber)) IS NULL)
        """

        let cursor = try! fetchCursor(
            transaction.unwrapGrdbRead.database,
            sql: sql,
            arguments: [address.uuidString, address.phoneNumber]
        )
        while let member = try! cursor.next() {
            var stop: ObjCBool = false
            block(member, &stop)
            if stop.boolValue { break }
        }
    }

    @objc(groupMembersInGroupThreadId:transaction:)
    public class func groupMembers(in groupThreadId: String, transaction: SDSAnyReadTransaction) -> [TSGroupMember] {
        let sql = """
            SELECT * FROM \(databaseTableName)
            WHERE \(columnName(.groupThreadId)) = ?
            ORDER BY \(columnName(.lastInteractionTimestamp)) DESC
        """
        let cursor = try! fetchCursor(
            transaction.unwrapGrdbRead.database,
            sql: sql,
            arguments: [groupThreadId]
        )
        var members = [TSGroupMember]()
        while let member = try! cursor.next() {
            members.append(member)
        }
        return members
    }

    @objc
    var addressComponentsDescription: String {
        SignalServiceAddress.addressComponentsDescription(uuidString: address.uuidString,
                                                          phoneNumber: address.phoneNumber)
    }
}

// MARK: -

public extension TSGroupThread {
    @objc(groupThreadsWithAddress:transaction:)
    class func groupThreads(with address: SignalServiceAddress,
                            transaction: SDSAnyReadTransaction) -> [TSGroupThread] {
        let sql = """
            SELECT \(TSGroupMember.columnName(.groupThreadId)) FROM \(TSGroupMember.databaseTableName)
            WHERE (\(TSGroupMember.columnName(.uuidString)) = ? OR \(TSGroupMember.columnName(.uuidString)) IS NULL)
            AND (\(TSGroupMember.columnName(.phoneNumber)) = ? OR \(TSGroupMember.columnName(.phoneNumber)) IS NULL)
            AND NOT (\(TSGroupMember.columnName(.uuidString)) IS NULL AND \(TSGroupMember.columnName(.phoneNumber)) IS NULL)
            ORDER BY \(TSGroupMember.columnName(.lastInteractionTimestamp)) DESC
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

    @objc(enumerateGroupThreadsWithAddress:transaction:block:)
    class func enumerateGroupThreads(
        with address: SignalServiceAddress,
        transaction: SDSAnyReadTransaction,
        block: (TSGroupThread, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        let sql = """
            SELECT \(TSGroupMember.columnName(.groupThreadId)) FROM \(TSGroupMember.databaseTableName)
            WHERE (\(TSGroupMember.columnName(.uuidString)) = ? OR \(TSGroupMember.columnName(.uuidString)) IS NULL)
            AND (\(TSGroupMember.columnName(.phoneNumber)) = ? OR \(TSGroupMember.columnName(.phoneNumber)) IS NULL)
            AND NOT (\(TSGroupMember.columnName(.uuidString)) IS NULL AND \(TSGroupMember.columnName(.phoneNumber)) IS NULL)
            ORDER BY \(TSGroupMember.columnName(.lastInteractionTimestamp)) DESC
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
            SELECT \(TSGroupMember.columnName(.groupThreadId))
            FROM \(TSGroupMember.databaseTableName)
            WHERE (\(TSGroupMember.columnName(.uuidString)) = ? OR \(TSGroupMember.columnName(.uuidString)) IS NULL)
            AND (\(TSGroupMember.columnName(.phoneNumber)) = ? OR \(TSGroupMember.columnName(.phoneNumber)) IS NULL)
            AND NOT (\(TSGroupMember.columnName(.uuidString)) IS NULL AND \(TSGroupMember.columnName(.phoneNumber)) IS NULL)
            ORDER BY \(TSGroupMember.columnName(.lastInteractionTimestamp)) DESC
        """

        return transaction.unwrapGrdbRead.database.strictRead { database in
            try String.fetchAll(database,
                                sql: sql,
                                arguments: [address.uuidString, address.phoneNumber])
        }
    }
}
