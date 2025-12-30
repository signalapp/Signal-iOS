//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

public struct PinnedMessageRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName: String = "PinnedMessage"

    public let id: Int64
    public let interactionId: Int64
    public var threadId: Int64
    public let expiresAt: UInt64?
    public let sentTimestamp: UInt64
    public let receivedTimestamp: UInt64

    static func insertRecord(
        interactionId: Int64,
        threadId: Int64,
        expiresAt: UInt64? = nil,
        sentTimestamp: UInt64,
        receivedTimestamp: UInt64,
        tx: DBWriteTransaction,
    ) throws(GRDB.DatabaseError) -> Self {
        do {
            return try PinnedMessageRecord.fetchOne(
                tx.database,
                sql: """
                INSERT INTO \(PinnedMessageRecord.databaseTableName) (
                    \(CodingKeys.interactionId.rawValue),
                    \(CodingKeys.threadId.rawValue),
                    \(CodingKeys.expiresAt.rawValue),
                    \(CodingKeys.sentTimestamp.rawValue),
                    \(CodingKeys.receivedTimestamp.rawValue)
                ) VALUES (?, ?, ?, ?, ?) RETURNING *
                """,
                arguments: [
                    interactionId,
                    threadId,
                    expiresAt,
                    sentTimestamp,
                    receivedTimestamp,
                ],
            )!
        } catch {
            throw error.forceCastToDatabaseError()
        }
    }

    public enum CodingKeys: String, CodingKey {
        case id
        case interactionId
        case threadId
        case expiresAt
        case sentTimestamp
        case receivedTimestamp
    }

    enum Columns {
        static let id = Column(CodingKeys.id.rawValue)
        static let interactionId = Column(CodingKeys.interactionId.rawValue)
        static let threadId = Column(CodingKeys.threadId.rawValue)
        static let expiresAt = Column(CodingKeys.expiresAt.rawValue)
        static let sentTimestamp = Column(CodingKeys.sentTimestamp.rawValue)
        static let receivedTimestamp = Column(CodingKeys.receivedTimestamp.rawValue)
    }
}
