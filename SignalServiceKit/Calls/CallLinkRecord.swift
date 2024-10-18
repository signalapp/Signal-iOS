//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB
public import SignalRingRTC

public struct CallLinkRecord: Codable, PersistableRecord, FetchableRecord {
    public static let databaseTableName: String = "CallLink"

    public let id: Int64
    public let roomId: Data
    public let rootKey: CallLinkRootKey
    public var adminPasskey: Data?
    private(set) public var adminDeletedAtTimestampMs: UInt64?
    public var activeCallId: UInt64?
    private(set) public var pendingFetchCounter: Int64
    private(set) public var isUpcoming: Bool?
    private(set) public var name: String?
    private(set) public var restrictions: Restrictions?
    private(set) public var revoked: Bool?
    private(set) public var expiration: Int64?

    init(
        id: Int64,
        roomId: Data,
        rootKey: CallLinkRootKey,
        adminPasskey: Data?,
        adminDeletedAtTimestampMs: UInt64?,
        activeCallId: UInt64?,
        pendingFetchCounter: Int64,
        isUpcoming: Bool?,
        name: String?,
        restrictions: Restrictions?,
        revoked: Bool?,
        expiration: Int64?
    ) {
        self.id = id
        self.roomId = roomId
        self.rootKey = rootKey
        self.adminPasskey = adminPasskey
        self.adminDeletedAtTimestampMs = adminDeletedAtTimestampMs
        self.activeCallId = activeCallId
        self.pendingFetchCounter = pendingFetchCounter
        self.isUpcoming = isUpcoming
        self.name = name
        self.restrictions = restrictions
        self.revoked = revoked
        self.expiration = expiration
    }

    enum CodingKeys: String, CodingKey {
        case id
        case roomId
        case rootKey
        case adminPasskey
        case adminDeletedAtTimestampMs
        case activeCallId
        case pendingFetchCounter = "pendingActionCounter"
        case isUpcoming
        case name
        case restrictions
        case revoked
        case expiration
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.roomId, forKey: .roomId)
        try container.encode(self.rootKey.bytes, forKey: .rootKey)
        try container.encodeIfPresent(self.adminPasskey, forKey: .adminPasskey)
        try container.encodeIfPresent(self.adminDeletedAtTimestampMs.map(Int64.init(bitPattern:)), forKey: .adminDeletedAtTimestampMs)
        try container.encodeIfPresent(self.activeCallId.map(Int64.init(bitPattern:)), forKey: .activeCallId)
        try container.encode(self.pendingFetchCounter, forKey: .pendingFetchCounter)
        try container.encodeIfPresent(self.isUpcoming, forKey: .isUpcoming)
        try container.encodeIfPresent(self.name, forKey: .name)
        try container.encodeIfPresent(self.restrictions?.rawValue, forKey: .restrictions)
        try container.encodeIfPresent(self.revoked, forKey: .revoked)
        try container.encodeIfPresent(self.expiration, forKey: .expiration)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int64.self, forKey: .id)
        self.roomId = try container.decode(Data.self, forKey: .roomId)
        self.rootKey = try CallLinkRootKey(container.decode(Data.self, forKey: .rootKey))
        self.adminPasskey = try container.decodeIfPresent(Data.self, forKey: .adminPasskey)
        self.adminDeletedAtTimestampMs = try container.decodeIfPresent(Int64.self, forKey: .adminDeletedAtTimestampMs).map(UInt64.init(bitPattern:))
        self.activeCallId = try container.decodeIfPresent(Int64.self, forKey: .activeCallId).map(UInt64.init(bitPattern:))
        self.pendingFetchCounter = try container.decode(Int64.self, forKey: .pendingFetchCounter)
        self.isUpcoming = try container.decodeIfPresent(Bool.self, forKey: .isUpcoming)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.restrictions = try container.decodeIfPresent(Int.self, forKey: .restrictions).map { rawValue in
            guard let result = Restrictions(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(forKey: .restrictions, in: container, debugDescription: "")
            }
            return result
        }
        self.revoked = try container.decodeIfPresent(Bool.self, forKey: .revoked)
        self.expiration = try container.decodeIfPresent(Int64.self, forKey: .expiration)
    }

    static func insertRecord(rootKey: CallLinkRootKey, tx: DBWriteTransaction) throws -> CallLinkRecord {
        do {
            return try CallLinkRecord.fetchOne(
                tx.databaseConnection,
                sql: """
                INSERT INTO "CallLink" ("roomId", "rootKey") VALUES (?, ?) RETURNING *
                """,
                arguments: [rootKey.deriveRoomId(), rootKey.bytes]
            )!
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    public mutating func clearNeedsFetch() {
        self.pendingFetchCounter = 0
    }

    public mutating func setNeedsFetch() {
        self.pendingFetchCounter += 1
    }

    // This is currently an enum, but depending on what restrictions are added
    // in the future, it seems like it may need to become an OptionSet. By
    // using `1` here, this could be trivially switched to being interpreted as
    // an OptionSet in the future.
    public enum Restrictions: Int {
        case none = 0
        case adminApproval = 1
    }

    public mutating func updateState(_ callLinkState: CallLinkState) {
        self.name = callLinkState.name
        self.restrictions = .some(callLinkState.requiresAdminApproval ? .adminApproval : .none)
        self.revoked = callLinkState.revoked
        self.expiration = Int64(callLinkState.expiration.timeIntervalSince1970)
        self.didUpdateState()
    }

    public var state: CallLinkState? {
        if let restrictions, let revoked, let expiration {
            return CallLinkState(
                name: self.name,
                requiresAdminApproval: restrictions == .adminApproval,
                revoked: revoked,
                expiration: Date(timeIntervalSince1970: TimeInterval(expiration))
            )
        }
        return nil
    }

    private mutating func didUpdateState() {
        // If we haven't used the link & we're an admin, mark it as upcoming.
        self.isUpcoming = self.isUpcoming ?? (self.adminPasskey != nil)
    }

    mutating func didInsertCallRecord() {
        self.isUpcoming = false
    }

    public var isDeleted: Bool {
        return self.adminDeletedAtTimestampMs != nil
    }

    public mutating func markDeleted(atTimestampMs timestampMs: UInt64) {
        self.adminPasskey = nil
        self.adminDeletedAtTimestampMs = timestampMs
        self.name = nil
        self.restrictions = nil
        self.revoked = nil
        self.expiration = nil
        self.pendingFetchCounter = 0
        self.isUpcoming = false
    }
}
