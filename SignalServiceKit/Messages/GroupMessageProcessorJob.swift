//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

struct GroupMessageProcessorJob: Codable, PersistableRecord, FetchableRecord {
    static let databaseTableName: String = "model_IncomingGroupsV2MessageJob"

    let id: Int64
    let groupId: Data?
    let createdAt: Date
    let envelopeData: Data
    let plaintextData: Data? // optional for historical reasons
    let wasReceivedByUD: Bool
    let serverDeliveryTimestamp: UInt64

    private let recordType: Int64
    private let uniqueId: String

    enum CodingKeys: String, CodingKey {
        case id
        case recordType
        case uniqueId
        case groupId
        case createdAt
        case envelopeData
        case plaintextData
        case wasReceivedByUD
        case serverDeliveryTimestamp
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int64.self, forKey: .id)
        self.groupId = try container.decodeIfPresent(Data.self, forKey: .groupId)
        self.createdAt = Date(timeIntervalSince1970: try container.decode(TimeInterval.self, forKey: .createdAt))
        self.envelopeData = try container.decode(Data.self, forKey: .envelopeData)
        self.plaintextData = try container.decodeIfPresent(Data.self, forKey: .plaintextData)
        self.wasReceivedByUD = try container.decode(Bool.self, forKey: .wasReceivedByUD)
        self.serverDeliveryTimestamp = UInt64(bitPattern: try container.decode(Int64.self, forKey: .serverDeliveryTimestamp))
        self.recordType = try container.decode(Int64.self, forKey: .recordType)
        self.uniqueId = try container.decode(String.self, forKey: .uniqueId)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.groupId, forKey: .groupId)
        try container.encode(self.createdAt, forKey: .createdAt)
        try container.encode(self.envelopeData, forKey: .envelopeData)
        try container.encode(self.plaintextData, forKey: .plaintextData)
        try container.encode(self.wasReceivedByUD, forKey: .wasReceivedByUD)
        try container.encode(Int64(bitPattern: self.serverDeliveryTimestamp), forKey: .serverDeliveryTimestamp)
        try container.encode(self.recordType, forKey: .recordType)
        try container.encode(self.uniqueId, forKey: .uniqueId)
    }

    static func insertRecord(
        envelopeData: Data,
        plaintextData: Data,
        groupId: Data,
        wasReceivedByUD: Bool,
        serverDeliveryTimestamp: UInt64,
        tx: DBWriteTransaction,
    ) throws -> Self {
        do {
            return try Self.fetchOne(
                tx.database,
                sql: """
                INSERT INTO "model_IncomingGroupsV2MessageJob" (
                    "\(CodingKeys.groupId.rawValue)",
                    "\(CodingKeys.envelopeData.rawValue)",
                    "\(CodingKeys.plaintextData.rawValue)",
                    "\(CodingKeys.wasReceivedByUD.rawValue)",
                    "\(CodingKeys.serverDeliveryTimestamp.rawValue)",
                    "\(CodingKeys.createdAt.rawValue)",
                    "\(CodingKeys.recordType.rawValue)",
                    "\(CodingKeys.uniqueId.rawValue)"
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?) RETURNING *
                """,
                arguments: [
                    groupId,
                    envelopeData,
                    plaintextData,
                    wasReceivedByUD,
                    Int64(bitPattern: serverDeliveryTimestamp),
                    Date().timeIntervalSince1970,
                    SDSRecordType.incomingGroupsV2MessageJob.rawValue,
                    UUID().uuidString,
                ],
            )!
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    func parseEnvelope() throws -> SSKProtoEnvelope {
        return try SSKProtoEnvelope(serializedData: self.envelopeData)
    }
}
