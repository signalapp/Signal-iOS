//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

// MARK: - AttachmentBackfillInboundRequestRecord

struct AttachmentBackfillInboundRequestRecord: Codable, FetchableRecord, PersistableRecord {
    typealias IDType = Int64

    static let databaseTableName: String = "AttachmentBackfillInboundRequest"

    enum CodingKeys: String, CodingKey {
        case id
        case interactionId

        var column: Column {
            return Column(rawValue)
        }
    }

    let id: IDType
    let interactionId: Int64

    static func fetchAllAscending(tx: DBReadTransaction) -> [AttachmentBackfillInboundRequestRecord] {
        return failIfThrows {
            try AttachmentBackfillInboundRequestRecord
                .order(
                    AttachmentBackfillInboundRequestRecord.CodingKeys.id.column
                        .asc,
                )
                .fetchAll(tx.database)
        }
    }

    /// Fetch an existing record for the given interaction ID, if one exists.
    static func fetchRecord(
        interactionId: Int64,
        tx: DBReadTransaction,
    ) -> AttachmentBackfillInboundRequestRecord? {
        return failIfThrows {
            return try AttachmentBackfillInboundRequestRecord
                .filter(Column(CodingKeys.interactionId.rawValue) == interactionId)
                .fetchOne(tx.database)
        }
    }

    /// Inserts and returns a new record, or returns an existing record if one
    /// exists for the same interaction ID.
    static func fetchOrInsertRecord(
        interactionId: Int64,
        tx: DBWriteTransaction,
    ) -> AttachmentBackfillInboundRequestRecord {
        return failIfThrows {
            if let existingRecord = fetchRecord(interactionId: interactionId, tx: tx) {
                return existingRecord
            }

            return try AttachmentBackfillInboundRequestRecord.fetchOne(
                tx.database,
                sql: """
                INSERT INTO \(databaseTableName) (
                    \(CodingKeys.interactionId.rawValue)
                ) VALUES (?) RETURNING *
                """,
                arguments: [interactionId],
            )!
        }
    }
}
