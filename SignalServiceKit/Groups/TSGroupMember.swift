//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import GRDB
public import LibSignalClient

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

    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case recordType
        case uniqueId
        case threadUniqueId = "groupThreadId"
        case phoneNumber
        case serviceId = "uuidString"
        case lastInteractionTimestamp
    }

    public var id: Int64?
    public let uniqueId: String
    public let serviceId: ServiceId?
    public let phoneNumber: String?
    public let threadUniqueId: String
    public private(set) var lastInteractionTimestamp: UInt64

    public init(
        address: NormalizedDatabaseRecordAddress,
        threadUniqueId: String,
        lastInteractionTimestamp: UInt64,
    ) {
        self.uniqueId = UUID().uuidString
        self.serviceId = address.serviceId
        self.phoneNumber = address.phoneNumber
        self.threadUniqueId = threadUniqueId
        self.lastInteractionTimestamp = lastInteractionTimestamp
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(RowId.self, forKey: .id)
        uniqueId = try container.decode(String.self, forKey: .uniqueId)
        threadUniqueId = try container.decode(String.self, forKey: .threadUniqueId)
        serviceId = try container.decodeIfPresent(String.self, forKey: .serviceId)
            .flatMap { try? ServiceId.parseFrom(serviceIdString: $0) }
        phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber)
        lastInteractionTimestamp = try container.decode(UInt64.self, forKey: .lastInteractionTimestamp)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(0, forKey: .recordType)
        try container.encode(uniqueId, forKey: .uniqueId)
        try container.encode(threadUniqueId, forKey: .threadUniqueId)
        try container.encodeIfPresent(serviceId?.serviceIdUppercaseString, forKey: .serviceId)
        try container.encodeIfPresent(phoneNumber, forKey: .phoneNumber)
        try container.encode(lastInteractionTimestamp, forKey: .lastInteractionTimestamp)
    }

    // MARK: -

    public func anyUpdateWith(
        lastInteractionTimestamp: UInt64,
        transaction: DBWriteTransaction,
    ) {
        anyUpdate(transaction: transaction) { groupMember in
            groupMember.lastInteractionTimestamp = lastInteractionTimestamp
        }
    }

    public func updateWith(
        lastInteractionTimestamp: UInt64,
        tx: DBWriteTransaction,
    ) throws {
        self.lastInteractionTimestamp = lastInteractionTimestamp
        try self.update(tx.database)
    }

    public class func groupMember(
        for address: SignalServiceAddress,
        in groupThreadId: String,
        transaction: DBReadTransaction,
    ) -> TSGroupMember? {
        let sql = """
            SELECT * FROM \(databaseTableName)
            WHERE (\(columnName(.serviceId)) = ? OR \(columnName(.serviceId)) IS NULL)
            AND (\(columnName(.phoneNumber)) = ? OR \(columnName(.phoneNumber)) IS NULL)
            AND NOT (\(columnName(.serviceId)) IS NULL AND \(columnName(.phoneNumber)) IS NULL)
            AND \(columnName(.threadUniqueId)) = ?
            LIMIT 1
        """

        return failIfThrows {
            return try fetchOne(
                transaction.database,
                sql: sql,
                arguments: [address.serviceIdUppercaseString, address.phoneNumber, groupThreadId],
            )
        }
    }

    public class func groupMember(
        for aci: Aci,
        in groupThread: TSGroupThread,
        tx: DBReadTransaction,
    ) throws -> TSGroupMember? {
        return try TSGroupMember
            .filter(Column(CodingKeys.serviceId) == aci.serviceIdUppercaseString)
            .filter(Column(CodingKeys.threadUniqueId) == groupThread.uniqueId)
            .fetchOne(tx.database)
    }
}

// MARK: -

extension TSGroupThread {
    public static func groupThreads(
        withFullMember address: SignalServiceAddress,
        tx: DBReadTransaction,
    ) -> [TSGroupThread] {
        let uniqueIds = groupThreadUniqueIds(withFullMember: address, tx: tx)
        return groupThreads(forUniqueIds: uniqueIds, tx: tx)
    }

    public static func activeGroupThreads(
        withFullMember address: SignalServiceAddress,
        tx: DBReadTransaction,
    ) -> [TSGroupThread] {
        let uniqueIds = groupThreadUniqueIds(withFullMember: address, tx: tx)
        return activeGroupThreads(uniqueIds: uniqueIds, tx: tx)
    }

    public static func mutualGroupThreads(
        withFullMember address: SignalServiceAddress,
        tx: DBReadTransaction,
    ) -> [TSGroupThread] {
        let uniqueIds = groupThreadUniqueIds(withFullMember: address, tx: tx)
        return mutualGroupThreads(uniqueIds: uniqueIds, tx: tx)
    }

    public static func mutualVisibleGroupThreads(
        withFullMember address: SignalServiceAddress,
        tx: DBReadTransaction,
    ) -> [TSGroupThread] {
        let uniqueIds = groupThreadUniqueIds(withFullMember: address, tx: tx)
        return mutualVisibleGroupThreads(uniqueIds: uniqueIds, tx: tx)
    }

    public static func groupThreadUniqueIds(withFullMember address: SignalServiceAddress, tx: DBReadTransaction) -> [String] {
        let sql = """
            SELECT \(TSGroupMember.columnName(.threadUniqueId))
            FROM \(TSGroupMember.databaseTableName)
            WHERE (\(TSGroupMember.columnName(.serviceId)) = ? OR \(TSGroupMember.columnName(.serviceId)) IS NULL)
            AND (\(TSGroupMember.columnName(.phoneNumber)) = ? OR \(TSGroupMember.columnName(.phoneNumber)) IS NULL)
            AND NOT (\(TSGroupMember.columnName(.serviceId)) IS NULL AND \(TSGroupMember.columnName(.phoneNumber)) IS NULL)
            ORDER BY \(TSGroupMember.columnName(.lastInteractionTimestamp)) DESC
        """
        return failIfThrows {
            try String.fetchAll(
                tx.database,
                sql: sql,
                arguments: [address.serviceIdUppercaseString, address.phoneNumber],
            )
        }
    }

    public static func groupThreads(forUniqueIds uniqueIds: [String], tx: DBReadTransaction) -> [TSGroupThread] {
        return uniqueIds.compactMap {
            guard let groupThread = TSGroupThread.fetchViaCache(uniqueId: $0, transaction: tx) else {
                owsFailDebug("couldn't fetch group thread")
                return nil
            }
            return groupThread
        }
    }

    public static func activeGroupThreads(uniqueIds: [String], tx: DBReadTransaction) -> [TSGroupThread] {
        return groupThreads(forUniqueIds: uniqueIds, tx: tx).filter {
            return !$0.isTerminatedGroup
        }
    }

    public static func mutualGroupThreads(uniqueIds: [String], tx: DBReadTransaction) -> [TSGroupThread] {
        return activeGroupThreads(uniqueIds: uniqueIds, tx: tx).filter {
            return $0.groupModel.groupMembership.isLocalUserFullMember
        }
    }

    public static func mutualVisibleGroupThreads(uniqueIds: [String], tx: DBReadTransaction) -> [TSGroupThread] {
        return mutualGroupThreads(uniqueIds: uniqueIds, tx: tx).filter {
            return $0.shouldThreadBeVisible
        }
    }
}
