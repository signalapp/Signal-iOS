//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient

/// Represents a full member of a group.
///
/// Importantly, this means that invited and requesting group members are
/// **not** represented by a ``TSGroupMember``. See the notes below for more
/// details.
///
/// - Note
/// A ``TSGroupMember`` stores both a serviceId and phone number. Full members
/// of a V2 group can only be represented by their ACI - so for V2 group
/// members the serviceId can be expected to be an ACI. However, phone
/// number-only members of legacy V1 groups may end up with a PNI; for example,
/// that phone-number-only member may become re-registered, and we may
/// subsequently learn about their PNI.
/// 
/// - Note
/// At the time of writing there exists a `UNIQUE INDEX` on the phone number and
/// group thread ID columns of this model. This is currently safe, as it's
/// impossible for a single phone number (a single account) to be in a group as
/// two different full members. However, it **is** possible for the same account
/// to be both an invited member (by their PNI) and a full member (by their
/// ACI). Take care if this model is ever extended to include invited members.
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
    public let serviceId: ServiceId?
    public let phoneNumber: String?
    public let groupThreadId: String
    public private(set) var lastInteractionTimestamp: UInt64

    required public init(
        address: NormalizedDatabaseRecordAddress,
        groupThreadId: String,
        lastInteractionTimestamp: UInt64
    ) {
        self.uniqueId = UUID().uuidString
        self.serviceId = address.serviceId
        self.phoneNumber = address.phoneNumber
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
        serviceId = try container.decodeIfPresent(String.self, forKey: .serviceId)
            .flatMap { try? ServiceId.parseFrom(serviceIdString: $0) }
        phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber)
        lastInteractionTimestamp = try container.decode(UInt64.self, forKey: .lastInteractionTimestamp)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(Self.recordType, forKey: .recordType)
        try container.encode(uniqueId, forKey: .uniqueId)
        try container.encode(groupThreadId, forKey: .groupThreadId)
        try container.encodeIfPresent(serviceId?.serviceIdUppercaseString, forKey: .serviceId)
        try container.encodeIfPresent(phoneNumber, forKey: .phoneNumber)
        try container.encode(lastInteractionTimestamp, forKey: .lastInteractionTimestamp)
    }

    // MARK: -

    public func updateWith(
        lastInteractionTimestamp: UInt64,
        transaction: SDSAnyWriteTransaction
    ) {
        anyUpdate(transaction: transaction) { groupMember in
            groupMember.lastInteractionTimestamp = lastInteractionTimestamp
        }
    }

    public class func groupMember(
        for address: SignalServiceAddress,
        in groupThreadId: String,
        transaction: SDSAnyReadTransaction
    ) -> TSGroupMember? {
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
                arguments: [address.serviceIdUppercaseString, address.phoneNumber, groupThreadId]
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
                arguments: [address.serviceIdUppercaseString, address.phoneNumber]
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
}

// MARK: -

public extension TSGroupThread {
    @objc(groupThreadsWithAddress:transaction:)
    class func groupThreads(
        with address: SignalServiceAddress,
        transaction: SDSAnyReadTransaction
    ) -> [TSGroupThread] {
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
                arguments: [address.serviceIdUppercaseString, address.phoneNumber]
            )

            while let groupThreadId = try cursor.next() {
                guard let groupThread = TSGroupThread.anyFetchGroupThread(
                    uniqueId: groupThreadId,
                    transaction: transaction
                ) else {
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
            arguments: [address.serviceIdUppercaseString, address.phoneNumber]
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

    class func groupThreadIds(
        with address: SignalServiceAddress,
        transaction: SDSAnyReadTransaction
    ) -> [String] {
        let sql = """
            SELECT \(TSGroupMember.columnName(.groupThreadId))
            FROM \(TSGroupMember.databaseTableName)
            WHERE (\(TSGroupMember.columnName(.serviceId)) = ? OR \(TSGroupMember.columnName(.serviceId)) IS NULL)
            AND (\(TSGroupMember.columnName(.phoneNumber)) = ? OR \(TSGroupMember.columnName(.phoneNumber)) IS NULL)
            AND NOT (\(TSGroupMember.columnName(.serviceId)) IS NULL AND \(TSGroupMember.columnName(.phoneNumber)) IS NULL)
            ORDER BY \(TSGroupMember.columnName(.lastInteractionTimestamp)) DESC
        """

        return transaction.unwrapGrdbRead.database.strictRead { database in
            try String.fetchAll(
                database,
                sql: sql,
                arguments: [address.serviceIdUppercaseString, address.phoneNumber]
            )
        }
    }
}
