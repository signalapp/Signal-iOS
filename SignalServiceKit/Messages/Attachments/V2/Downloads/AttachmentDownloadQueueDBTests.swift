//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import XCTest

@testable import SignalServiceKit

class AttachmentDownloadQueueDBTests: XCTestCase {

    private var db: InMemoryDB!

    private var attachmentStore: AttachmentStoreImpl!

    override func setUp() async throws {
        db = InMemoryDB()
        attachmentStore = AttachmentStoreImpl()
    }

    func testDeleteAttachment() async throws {
        // Create an attachment.
        let attachmentParams = Attachment.ConstructionParams.mockPointer()
        let referenceParams = AttachmentReference.ConstructionParams.mock(
            owner: .thread(.globalThreadWallpaperImage(creationTimestamp: Date().ows_millisecondsSince1970))
        )

        let attachmentRowId = try db.write { tx in
            try attachmentStore.insert(
                attachmentParams,
                reference: referenceParams,
                tx: tx
            )
            return try Int64.fetchOne(
                tx.db,
                sql: "SELECT \(Attachment.Record.CodingKeys.sqliteId.rawValue) from \(Attachment.Record.databaseTableName)"
            )!
        }

        // Create a download for the attachment.
        var download = QueuedAttachmentDownloadRecord.forNewDownload(
            ofAttachmentWithId: attachmentRowId,
            sourceType: .transitTier
        )
        try db.write { tx in
            try download.insert(tx.db)
        }

        // Now delete the attachment.
        try db.write { tx in
            try tx.db.execute(sql: "DELETE FROM \(Attachment.Record.databaseTableName)")
        }

        // The download should be deleted.
        try db.read { tx in
            XCTAssertNil(try QueuedAttachmentDownloadRecord
                .fetchOne(tx.db)
            )
        }

        // And there should be an orphan record.
        try db.read { tx in
            XCTAssertEqual(
                download.partialDownloadRelativeFilePath,
                try String.fetchOne(
                    tx.db,
                    sql: "SELECT \(OrphanedAttachmentRecord.CodingKeys.localRelativeFilePath.rawValue) FROM \(OrphanedAttachmentRecord.databaseTableName)"
                )
            )
        }
    }

    func testIndexes() throws {
        try db.read { tx in
            func getQueryPlan(sql: String) throws -> String {
                let queryPlan: String = try Row
                    .fetchAll(tx.db, sql: """
                        EXPLAIN QUERY PLAN \(sql)
                    """)
                    .map { row -> String in row["detail"] }
                    .joined()
                return queryPlan
            }

            // Look up by attachment id and source
            var queryPlan = try getQueryPlan(sql: """
                SELECT * FROM \(QueuedAttachmentDownloadRecord.databaseTableName)
                WHERE
                    \(QueuedAttachmentDownloadRecord.CodingKeys.attachmentId.rawValue) = 1
                    AND \(QueuedAttachmentDownloadRecord.CodingKeys.sourceType.rawValue) = 0
            """)
            XCTAssertEqual(
                queryPlan,
                "SEARCH \(QueuedAttachmentDownloadRecord.databaseTableName) "
                + "USING INDEX index_AttachmentDownloadQueue_on_attachmentId_and_sourceType "
                + "(\(QueuedAttachmentDownloadRecord.CodingKeys.attachmentId.rawValue)=? "
                + "AND \(QueuedAttachmentDownloadRecord.CodingKeys.sourceType.rawValue)=?)"
            )

            // Check priority count.
            queryPlan = try getQueryPlan(sql: """
                SELECT COUNT(id) FROM \(QueuedAttachmentDownloadRecord.databaseTableName)
                WHERE \(QueuedAttachmentDownloadRecord.CodingKeys.priority.rawValue) = 50
            """)
            XCTAssertEqual(
                queryPlan,
                "SEARCH \(QueuedAttachmentDownloadRecord.databaseTableName) "
                + "USING COVERING INDEX index_AttachmentDownloadQueue_on_priority "
                + "(\(QueuedAttachmentDownloadRecord.CodingKeys.priority.rawValue)=?)"
            )

            // Pop next off the queue
            queryPlan = try getQueryPlan(sql: """
                SELECT * FROM \(QueuedAttachmentDownloadRecord.databaseTableName)
                WHERE \(QueuedAttachmentDownloadRecord.CodingKeys.minRetryTimestamp.rawValue) IS NULL
                ORDER BY
                    \(QueuedAttachmentDownloadRecord.CodingKeys.priority.rawValue) DESC,
                    \(QueuedAttachmentDownloadRecord.CodingKeys.id.rawValue) ASC
                LIMIT 1;
            """)
            XCTAssertEqual(
                queryPlan,
                "SCAN \(QueuedAttachmentDownloadRecord.databaseTableName) "
                + "USING INDEX "
                + "partial_index_AttachmentDownloadQueue_on_priority_DESC_and_id_where_minRetryTimestamp_isNull"
            )

            // Find the next minimum retry timestamp
            queryPlan = try getQueryPlan(sql: """
                SELECT * FROM \(QueuedAttachmentDownloadRecord.databaseTableName)
                WHERE \(QueuedAttachmentDownloadRecord.CodingKeys.minRetryTimestamp.rawValue) IS NOT NULL
                ORDER BY \(QueuedAttachmentDownloadRecord.CodingKeys.minRetryTimestamp.rawValue) ASC
                LIMIT 1;
            """)
            XCTAssertEqual(
                queryPlan,
                "SEARCH \(QueuedAttachmentDownloadRecord.databaseTableName) "
                + "USING INDEX partial_index_AttachmentDownloadQueue_on_minRetryTimestamp_where_isNotNull "
                + "(\(QueuedAttachmentDownloadRecord.CodingKeys.minRetryTimestamp.rawValue)>?)"
            )
        }
    }
}
