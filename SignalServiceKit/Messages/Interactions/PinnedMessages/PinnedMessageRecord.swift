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
    public let expiresAt: Int64?

    static func insertRecord(
        interactionId: Int64,
        threadId: Int64,
        expiresAt: Int64? = nil,
        tx: DBWriteTransaction
    ) throws(GRDB.DatabaseError) -> Self {
        do {
            return try PinnedMessageRecord.fetchOne(
                tx.database,
                sql: """
                    INSERT INTO \(PinnedMessageRecord.databaseTableName) (
                        \(CodingKeys.interactionId.rawValue),
                        \(CodingKeys.threadId.rawValue),
                        \(CodingKeys.expiresAt.rawValue)
                    ) VALUES (?, ?, ?) RETURNING *
                    """,
                arguments: [
                    interactionId,
                    threadId,
                    expiresAt
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
    }

    enum Columns {
        static let id = Column(CodingKeys.id.rawValue)
        static let interactionId = Column(CodingKeys.interactionId.rawValue)
        static let threadId = Column(CodingKeys.threadId.rawValue)
        static let expiresAt = Column(CodingKeys.expiresAt.rawValue)
    }
}
