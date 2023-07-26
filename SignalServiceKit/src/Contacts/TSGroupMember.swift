//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

@objc
public final class TSGroupMember: NSObject, SDSCodableModel, Decodable {
    public static let databaseTableName = "model_TSGroupMember"
    public static var recordType: UInt { SDSRecordType.groupMember.rawValue }
    public static var ftsIndexMode: TSFTSIndexMode { .manualUpdates }

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id
        case recordType
        case uniqueId
        case groupThreadId
        case phoneNumber
        case serviceId = "uuidString"
        case lastInteractionTimestamp
    }

    public var id: Int64?
    public let uniqueId: String
    public let serviceId: UntypedServiceId?
    public let phoneNumber: String?
    public let groupThreadId: String
    public private(set) var lastInteractionTimestamp: UInt64

    required public init(serviceId: UntypedServiceId?, phoneNumber: String?, groupThreadId: String, lastInteractionTimestamp: UInt64) {
        self.uniqueId = UUID().uuidString
        self.serviceId = serviceId
        self.phoneNumber = phoneNumber
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
        serviceId = try container.decodeIfPresent(UntypedServiceId.self, forKey: .serviceId)
        phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber)
        lastInteractionTimestamp = try container.decode(UInt64.self, forKey: .lastInteractionTimestamp)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(Self.recordType, forKey: .recordType)
        try container.encode(uniqueId, forKey: .uniqueId)
        try container.encode(groupThreadId, forKey: .groupThreadId)
        try container.encodeIfPresent(serviceId?.uuidValue, forKey: .serviceId)
        try container.encodeIfPresent(phoneNumber, forKey: .phoneNumber)
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
            WHERE (\(columnName(.serviceId)) = ? OR \(columnName(.serviceId)) IS NULL)
            AND (\(columnName(.phoneNumber)) = ? OR \(columnName(.phoneNumber)) IS NULL)
            AND NOT (\(columnName(.serviceId)) IS NULL AND \(columnName(.phoneNumber)) IS NULL)
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
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
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
            WHERE (\(columnName(.serviceId)) = ? OR \(columnName(.serviceId)) IS NULL)
            AND (\(columnName(.phoneNumber)) = ? OR \(columnName(.phoneNumber)) IS NULL)
            AND NOT (\(columnName(.serviceId)) IS NULL AND \(columnName(.phoneNumber)) IS NULL)
        """

        do {
            let cursor = try fetchCursor(
                transaction.unwrapGrdbRead.database,
                sql: sql,
                arguments: [address.uuidString, address.phoneNumber]
            )
            while let member = try cursor.next() {
                var stop: ObjCBool = false
                block(member, &stop)
                if stop.boolValue { break }
            }
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Failed to enumerate group membership.")
        }
    }

    @objc
    var addressComponentsDescription: String {
        SignalServiceAddress.addressComponentsDescription(
            uuidString: serviceId?.uuidValue.uuidString,
            phoneNumber: phoneNumber
        )
    }
}

// MARK: -

public extension TSGroupThread {
    @objc(groupThreadsWithAddress:transaction:)
    class func groupThreads(with address: SignalServiceAddress,
                            transaction: SDSAnyReadTransaction) -> [TSGroupThread] {
        let sql = """
            SELECT \(TSGroupMember.columnName(.groupThreadId)) FROM \(TSGroupMember.databaseTableName)
            WHERE (\(TSGroupMember.columnName(.serviceId)) = ? OR \(TSGroupMember.columnName(.serviceId)) IS NULL)
            AND (\(TSGroupMember.columnName(.phoneNumber)) = ? OR \(TSGroupMember.columnName(.phoneNumber)) IS NULL)
            AND NOT (\(TSGroupMember.columnName(.serviceId)) IS NULL AND \(TSGroupMember.columnName(.phoneNumber)) IS NULL)
            ORDER BY \(TSGroupMember.columnName(.lastInteractionTimestamp)) DESC
        """

        var groupThreads = [TSGroupThread]()

        do {
            let cursor = try String.fetchCursor(
                transaction.unwrapGrdbRead.database,
                sql: sql,
                arguments: [address.uuidString, address.phoneNumber]
            )

            while let groupThreadId = try cursor.next() {
                guard let groupThread = TSGroupThread.anyFetchGroupThread(uniqueId: groupThreadId,
                                                                          transaction: transaction) else {
                    owsFailDebug("Missing group thread")
                    continue
                }
                groupThreads.append(groupThread)
            }
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Failed to find group thread")
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
            WHERE (\(TSGroupMember.columnName(.serviceId)) = ? OR \(TSGroupMember.columnName(.serviceId)) IS NULL)
            AND (\(TSGroupMember.columnName(.phoneNumber)) = ? OR \(TSGroupMember.columnName(.phoneNumber)) IS NULL)
            AND NOT (\(TSGroupMember.columnName(.serviceId)) IS NULL AND \(TSGroupMember.columnName(.phoneNumber)) IS NULL)
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
            WHERE (\(TSGroupMember.columnName(.serviceId)) = ? OR \(TSGroupMember.columnName(.serviceId)) IS NULL)
            AND (\(TSGroupMember.columnName(.phoneNumber)) = ? OR \(TSGroupMember.columnName(.phoneNumber)) IS NULL)
            AND NOT (\(TSGroupMember.columnName(.serviceId)) IS NULL AND \(TSGroupMember.columnName(.phoneNumber)) IS NULL)
            ORDER BY \(TSGroupMember.columnName(.lastInteractionTimestamp)) DESC
        """

        return transaction.unwrapGrdbRead.database.strictRead { database in
            try String.fetchAll(database,
                                sql: sql,
                                arguments: [address.uuidString, address.phoneNumber])
        }
    }
}
