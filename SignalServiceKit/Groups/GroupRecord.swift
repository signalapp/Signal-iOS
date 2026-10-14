//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation
public import GRDB
import LibSignalClient

public struct GroupRecord: Codable, FetchableRecord, PersistableRecord {
    // This table has a "Record" suffix to avoid the SQL "GROUP" keyword.
    public static let databaseTableName: String = "GroupRecord"

    enum Constants {
        /// How frequently groups should be automatically refreshed.
        static let refreshInterval: TimeInterval = .week
        static let refreshJitter: TimeInterval = refreshInterval / 7

        /// How frequently groups should be refreshed via a snapshot. (This is a
        /// fallback and shouldn't be load bearing in practice.)
        static let snapshotInterval: TimeInterval = 45 * .day
        static let snapshotJitter: TimeInterval = snapshotInterval / 15

        /// This should be bumped whenever changeProtoEpoch changes (which happens
        /// automatically due to its inclusion in this value), but it can also be
        /// bumped manually by incrementing snapshotVersionCounter.
        static let snapshotVersion: Int64 = Int64(safeCast: GroupManager.changeProtoEpoch) + snapshotVersionCounter
        private static let snapshotVersionCounter: Int64 = 0
    }

    enum Status: Int64, Codable {
        case unspecified = 0
        case whitelisted = 1
        case blocked = 2
    }

    public typealias RowId = Int64
    public typealias ThreadId = TSThread.RowId

    let rowId: RowId

    /// Might be 16 bytes (GV1) or 32 bytes (GV2).
    public let groupId: Data
    public var groupIdObj: AnyGroupIdentifier {
        get throws { try AnyGroupIdentifier.parseFrom(self.groupId) }
    }

    /// Might not exist. Perhaps the group hasn't been restored yet or the
    /// thread has been deleted.
    public private(set) var threadId: ThreadId?

    /// Missing for GV1 groups; potentially missing for GV2 groups you've left.
    private(set) var masterKey: GroupMasterKey?

    /// The timestamp when the group was most recently auto-refreshed.
    private(set) var refreshedAt: Int64

    var refreshedAtDate: Date {
        return Date(timeIntervalSince1970: TimeInterval(self.refreshedAt))
    }

    // The last group name that was set by the local user.
    // Nil if it has never been set by the local user.
    private(set) var lastVerifiedGroupNameHash: Data?

    private(set) var status: Status
    public private(set) var blockedAt: BlockedTimestamp

    private(set) var lastSnapshotAt: Int64

    var lastSnapshotAtDate: Date {
        return Date(timeIntervalSince1970: TimeInterval(self.lastSnapshotAt))
    }

    private(set) var lastSnapshotVersion: Int64

    enum CodingKeys: String, CodingKey {
        case rowId
        case groupId
        case threadId
        case masterKey
        case refreshedAt
        case lastVerifiedGroupNameHash
        case status
        case blockedAt = "blockedAtMs"
        case lastSnapshotAt
        case lastSnapshotVersion
    }

    enum Columns {
        static let rowId = Column(CodingKeys.rowId.rawValue)
        static let groupId = Column(CodingKeys.groupId.rawValue)
        static let threadId = Column(CodingKeys.threadId.rawValue)
        static let masterKey = Column(CodingKeys.masterKey.rawValue)
        static let refreshedAt = Column(CodingKeys.refreshedAt.rawValue)
        static let lastVerifiedGroupNameHash = Column(CodingKeys.lastVerifiedGroupNameHash.rawValue)
        static let status = Column(CodingKeys.status.rawValue)
        static let blockedAt = Column(CodingKeys.blockedAt.rawValue)
        static let lastSnapshotAt = Column(CodingKeys.lastSnapshotAt.rawValue)
        static let lastSnapshotVersion = Column(CodingKeys.lastSnapshotVersion.rawValue)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.rowId = try container.decode(RowId.self, forKey: .rowId)
        self.groupId = try container.decode(Data.self, forKey: .groupId)
        self.threadId = try container.decodeIfPresent(ThreadId.self, forKey: .threadId)
        self.masterKey = try container.decodeIfPresent(Data.self, forKey: .masterKey).map(GroupMasterKey.init(contents:))
        self.refreshedAt = try container.decode(Int64.self, forKey: .refreshedAt)
        self.lastVerifiedGroupNameHash = try container.decodeIfPresent(Data.self, forKey: .lastVerifiedGroupNameHash)
        self.status = try container.decode(Status.self, forKey: .status)
        self.blockedAt = try container.decode(BlockedTimestamp.self, forKey: .blockedAt)
        self.lastSnapshotAt = try container.decode(Int64.self, forKey: .lastSnapshotAt)
        self.lastSnapshotVersion = try container.decode(Int64.self, forKey: .lastSnapshotVersion)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.rowId, forKey: .rowId)
        try container.encode(self.groupId, forKey: .groupId)
        try container.encode(self.threadId, forKey: .threadId)
        try container.encode(self.masterKey?.serialize(), forKey: .masterKey)
        try container.encode(self.refreshedAt, forKey: .refreshedAt)
        try container.encode(self.lastVerifiedGroupNameHash, forKey: .lastVerifiedGroupNameHash)
        try container.encode(self.status, forKey: .status)
        try container.encode(self.blockedAt, forKey: .blockedAt)
        try container.encode(self.lastSnapshotAt, forKey: .lastSnapshotAt)
        try container.encode(self.lastSnapshotVersion, forKey: .lastSnapshotVersion)
    }

    static func insertRecord(
        groupId: Data,
        threadId: TSThread.RowId?,
        masterKey: GroupMasterKey?,
        refreshedAt: Date,
        status: Status = .unspecified,
        blockedAt: BlockedTimestamp = .unspecified,
        tx: DBWriteTransaction,
    ) -> Self {
        return failIfThrows {
            return try Self.fetchOne(
                tx.database,
                sql: """
                INSERT INTO \(GroupRecord.databaseTableName) (
                    \(Columns.groupId.name),
                    \(Columns.threadId.name),
                    \(Columns.masterKey.name),
                    \(Columns.refreshedAt.name),
                    \(Columns.status.name),
                    \(Columns.blockedAt.name)
                ) VALUES (?, ?, ?, ?, ?, ?) RETURNING *
                """,
                arguments: [
                    groupId,
                    threadId,
                    masterKey?.serialize(),
                    Int64(refreshedAt.timeIntervalSince1970),
                    status.rawValue,
                    blockedAt.rawValue,
                ],
            ).owsFailUnwrap("must return value or error")
        }
    }

    mutating func setMasterKey(secretParams: GroupSecretParams, tx: DBWriteTransaction) {
        let groupId = failIfThrows { try secretParams.getPublicParams().getGroupIdentifier() }
        owsPrecondition(groupId.serialize() == self.groupId, "can't change ID for a group")
        self.masterKey = failIfThrows { try secretParams.getMasterKey() }
        failIfThrows { try self.update(tx.database) }
    }

    func deriveSecretParams() -> GroupSecretParams? {
        return failIfThrows {
            return try self.masterKey.map {
                return try GroupSecretParams.deriveFromMasterKey(groupMasterKey: $0)
            }
        }
    }

    mutating func setThreadId(_ threadId: ThreadId, tx: DBWriteTransaction) {
        self.threadId = threadId
        failIfThrows { try self.update(tx.database) }
    }

    mutating func clearThreadId() {
        self.threadId = nil
    }

    mutating func setRefreshedAt(_ refreshedAt: Date, tx: DBWriteTransaction) {
        self.refreshedAt = Int64(refreshedAt.timeIntervalSince1970)
        failIfThrows { try self.update(tx.database) }
    }

    public static func addingRefreshJitter(toDate date: Date) -> Date {
        let jitter = TimeInterval.random(in: -Constants.refreshJitter...Constants.refreshJitter)
        return date.addingTimeInterval(jitter)
    }

    mutating func setLastSnapshotAt(_ lastSnapshotAt: Date, tx: DBWriteTransaction) {
        self.lastSnapshotAt = Int64(lastSnapshotAt.timeIntervalSince1970)
        self.lastSnapshotVersion = Constants.snapshotVersion
        failIfThrows { try self.update(tx.database) }
    }

    public static func addingSnapshotJitter(toDate date: Date) -> Date {
        let jitter = TimeInterval.random(in: -Constants.snapshotJitter...Constants.snapshotJitter)
        return date.addingTimeInterval(jitter)
    }

    /// True if we should fetch a snapshot instead of change actions.
    ///
    /// There may be other reasons (e.g., we were just added to a group) that
    /// also necessitate fetching change actions.
    func shouldFetchSnapshot(now: Date = Date()) -> Bool {
        if self.lastSnapshotVersion != Constants.snapshotVersion {
            return true
        }
        if abs(now.timeIntervalSince(self.lastSnapshotAtDate)) > Constants.snapshotInterval {
            return true
        }
        return false
    }

    mutating func setLastVerifiedGroupNameHash(_ lastVerifiedGroupNameHash: Data?, tx: DBWriteTransaction) {
        self.lastVerifiedGroupNameHash = lastVerifiedGroupNameHash
        failIfThrows { try self.update(tx.database) }
    }

    static func groupNameVerificationHash(groupName: String) -> Data {
        var sha = SHA256()
        sha.update(data: Data(groupName.utf8))
        return Data(sha.finalize())
    }

    public func isGroupNameVerified(groupName: String) -> Bool {
        return self.lastVerifiedGroupNameHash == Self.groupNameVerificationHash(groupName: groupName)
    }

    var isBlocked: Bool {
        switch self.status {
        case .blocked:
            return true
        case .unspecified, .whitelisted:
            return false
        }
    }

    mutating func setBlocked(_ isBlocked: Bool, tx: DBWriteTransaction) {
        if isBlocked {
            self.status = .blocked
        } else if self.status == .blocked {
            self.status = .unspecified
            self.blockedAt = .unspecified
        }
        failIfThrows { try self.update(tx.database) }
    }

    mutating func setBlockedAt(_ blockedAt: BlockedTimestamp, tx: DBWriteTransaction) {
        guard self.status == .blocked else {
            owsFailDebug("can't set blockedAt unless blocked")
            return
        }
        self.blockedAt = blockedAt
        failIfThrows { try self.update(tx.database) }
    }

    var isWhitelisted: Bool {
        switch self.status {
        case .whitelisted:
            return true
        case .unspecified, .blocked:
            return false
        }
    }

    mutating func setWhitelisted(_ isWhitelisted: Bool, tx: DBWriteTransaction) {
        switch self.status {
        case .blocked:
            return
        case .whitelisted, .unspecified:
            self.status = isWhitelisted ? .whitelisted : .unspecified
        }
        failIfThrows { try self.update(tx.database) }
    }
}
