//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
@testable import SignalServiceKit
public import XCTest

public class AttachmentV2MigrationTest: XCTestCase {

    private var dbFileURL: URL!
    private var db: SDSDatabaseStorage!

    override public func setUp() async throws {
        self.dbFileURL = OWSFileSystem.temporaryFileUrl()
        self.db = try SDSDatabaseStorage(
            appReadiness: AppReadinessMock(),
            databaseFileUrl: dbFileURL,
            keychainStorage: MockKeychainStorage()
        )
    }

    override public func tearDown() {
        try! OWSFileSystem.deleteFile(url: dbFileURL)
    }

    // MARK: - Tests

    func testInsert() throws {
        try runMigration()

        try db.write { tx in
            let threadId1 = try insertThread(tx: tx)
            let messageId = try insertMessage(tx: tx)

            let attachmentId1 = try insertAttachment(tx: tx)
            try insertMessageAttachmentReference(
                threadId: threadId1,
                messageId: messageId,
                attachmentId: attachmentId1,
                tx: tx
            )

            XCTAssertNotNil(try fetchAttachment(id: attachmentId1, tx: tx))
            XCTAssertEqual([messageId], try fetchMessageAttachmentReferences(attachmentId: attachmentId1, tx: tx).map { $0["ownerRowId"] })
            XCTAssertEqual([attachmentId1], try fetchMessageAttachmentReferences(messageId: messageId, tx: tx).map { $0["attachmentRowId"] })

            let storyMessageId = try insertStoryMessage(tx: tx)

            let attachmentId2 = try insertAttachment(tx: tx)
            try insertStoryMessageAttachmentReference(
                storyMessageId: storyMessageId,
                attachmentId: attachmentId2,
                tx: tx
            )

            XCTAssertNotNil(try fetchAttachment(id: attachmentId2, tx: tx))
            XCTAssertEqual([storyMessageId], try fetchStoryMessageAttachmentReferences(attachmentId: attachmentId2, tx: tx).map { $0["ownerRowId"] })
            XCTAssertEqual(
                [attachmentId2],
                try fetchStoryMessageAttachmentReferences(storyMessageId: storyMessageId, tx: tx).map { $0["attachmentRowId"] }
            )

            let threadId2 = try insertThread(tx: tx)

            let attachmentId3 = try insertAttachment(tx: tx)
            try insertThreadAttachmentReference(
                threadId: threadId2,
                attachmentId: attachmentId3,
                tx: tx
            )

            XCTAssertNotNil(try fetchAttachment(id: attachmentId3, tx: tx))
            XCTAssertEqual([threadId2], try fetchThreadAttachmentReferences(attachmentId: attachmentId3, tx: tx).map { $0["ownerRowId"] })
            XCTAssertEqual([attachmentId3], try fetchThreadAttachmentReferences(threadId: threadId2, tx: tx).map { $0["attachmentRowId"] })
        }
    }

    func testContentTypeMirroring() throws {
        try runMigration()

        try db.write { tx in
            let threadId = try insertThread(tx: tx)
            let messageId1 = try insertMessage(tx: tx)
            let messageId2 = try insertMessage(tx: tx)

            let attachmentId = try insertAttachment(
                contentType: 1,
                tx: tx
            )
            try insertMessageAttachmentReference(
                threadId: threadId,
                messageId: messageId1,
                attachmentId: attachmentId,
                contentType: 1,
                tx: tx
            )
            try insertMessageAttachmentReference(
                threadId: threadId,
                messageId: messageId2,
                attachmentId: attachmentId,
                contentType: 1,
                tx: tx
            )

            // Ensure the content type is set.
            XCTAssertEqual(1, try fetchAttachment(id: attachmentId, tx: tx)?["contentType"])
            var references = try fetchMessageAttachmentReferences(attachmentId: attachmentId, tx: tx)
            XCTAssertEqual([1, 1], references.map { $0["contentType"] })

            // Set a new content type on the attachment.
            try tx.unwrapGrdbWrite.database.execute(
                sql: """
                    UPDATE Attachment SET contentType = ? WHERE id = ?
                """,
                arguments: [3, attachmentId]
            )

            // Ensure the content type is set back on the references, too.
            XCTAssertEqual(3, try fetchAttachment(id: attachmentId, tx: tx)?["contentType"])
            references = try fetchMessageAttachmentReferences(attachmentId: attachmentId, tx: tx)
            XCTAssertEqual([3, 3], references.map { $0["contentType"] })
        }
    }

    // MARK: - Deletion triggers

    func testCascadingDelete_Single() throws {
        try runMigration()

        try db.write { tx in
            let threadId1 = try insertThread(tx: tx)
            let messageId1 = try insertMessage(tx: tx)

            let attachmentId1 = try insertAttachment(tx: tx)
            try insertMessageAttachmentReference(
                threadId: threadId1,
                messageId: messageId1,
                attachmentId: attachmentId1,
                tx: tx
            )

            // Delete the thread; deletion should cascade to attachments.
            try deleteThread(id: threadId1, tx: tx)

            XCTAssertNil(try fetchAttachment(id: attachmentId1, tx: tx))
            XCTAssertEqual(0, try fetchMessageAttachmentReferences(attachmentId: attachmentId1, tx: tx).count)
            XCTAssertEqual(0, try fetchMessageAttachmentReferences(messageId: messageId1, tx: tx).count)

            // Do the same thing, but delete the message this time.
            let threadId2 = try insertThread(tx: tx)
            let messageId2 = try insertMessage(tx: tx)

            let attachmentId2 = try insertAttachment(tx: tx)
            try insertMessageAttachmentReference(
                threadId: threadId2,
                messageId: messageId2,
                attachmentId: attachmentId2,
                tx: tx
            )

            // Delete the message; deletion should cascade to attachments.
            try deleteMessage(id: messageId2, tx: tx)

            XCTAssertNil(try fetchAttachment(id: attachmentId2, tx: tx))
            XCTAssertEqual(0, try fetchMessageAttachmentReferences(attachmentId: attachmentId2, tx: tx).count)
            XCTAssertEqual(0, try fetchMessageAttachmentReferences(messageId: messageId2, tx: tx).count)

            // Again, with story message.
            let storyMessageId = try insertStoryMessage(tx: tx)

            let attachmentId3 = try insertAttachment(tx: tx)
            try insertStoryMessageAttachmentReference(
                storyMessageId: storyMessageId,
                attachmentId: attachmentId3,
                tx: tx
            )

            // Delete the story message; deletion should cascade to attachments.
            try deleteStoryMessage(id: storyMessageId, tx: tx)

            XCTAssertNil(try fetchAttachment(id: attachmentId3, tx: tx))
            XCTAssertEqual(0, try fetchStoryMessageAttachmentReferences(attachmentId: attachmentId3, tx: tx).count)
            XCTAssertEqual(0, try fetchStoryMessageAttachmentReferences(storyMessageId: storyMessageId, tx: tx).count)

            // Lastly, with thread.
            let threadId3 = try insertThread(tx: tx)

            let attachmentId4 = try insertAttachment(tx: tx)
            try insertThreadAttachmentReference(
                threadId: threadId3,
                attachmentId: attachmentId4,
                tx: tx
            )

            // Delete the thread; deletion should cascade to attachments.
            try deleteThread(id: threadId3, tx: tx)

            XCTAssertNil(try fetchAttachment(id: attachmentId4, tx: tx))
            XCTAssertEqual(0, try fetchThreadAttachmentReferences(attachmentId: attachmentId4, tx: tx).count)
            XCTAssertEqual(0, try fetchThreadAttachmentReferences(threadId: threadId3, tx: tx).count)
        }
    }

    func testCascadingDelete_MultipleReferences() throws {
        try runMigration()

        try db.write { tx in
            // Create 2 messages, 1 story and 1 thread and make all owners of a single attachment.
            // Delete them one by one. The references will delete as we go, but the attachment
            // won't get deleted until every owner has been deleted.

            let messageThreadId = try insertThread(tx: tx)
            let messageId1 = try insertMessage(tx: tx)
            let messageId2 = try insertMessage(tx: tx)
            let storyMessageId = try insertStoryMessage(tx: tx)
            let threadId = try insertThread(tx: tx)

            let attachmentId = try insertAttachment(tx: tx)
            try insertMessageAttachmentReference(
                threadId: messageThreadId,
                messageId: messageId1,
                attachmentId: attachmentId,
                tx: tx
            )
            try insertMessageAttachmentReference(
                threadId: messageThreadId,
                messageId: messageId2,
                attachmentId: attachmentId,
                tx: tx
            )
            try insertStoryMessageAttachmentReference(
                storyMessageId: storyMessageId,
                attachmentId: attachmentId,
                tx: tx
            )
            try insertThreadAttachmentReference(
                threadId: threadId,
                attachmentId: attachmentId,
                tx: tx
            )

            // Delete the thread.
            try deleteThread(id: threadId, tx: tx)
            // The references should be deleted by cascade rule.
            XCTAssertEqual(0, try fetchThreadAttachmentReferences(attachmentId: attachmentId, tx: tx).count)
            XCTAssertEqual(0, try fetchThreadAttachmentReferences(threadId: threadId, tx: tx).count)
            // But there are other owner references so the attachment shouldn't be deleted.
            XCTAssertNotNil(try fetchAttachment(id: attachmentId, tx: tx))

            // Delete the story message.
            try deleteStoryMessage(id: storyMessageId, tx: tx)
            // The references should be deleted by cascade rule.
            XCTAssertEqual(0, try fetchStoryMessageAttachmentReferences(attachmentId: attachmentId, tx: tx).count)
            XCTAssertEqual(0, try fetchStoryMessageAttachmentReferences(storyMessageId: storyMessageId, tx: tx).count)
            // But there are other owner references so the attachment shouldn't be deleted.
            XCTAssertNotNil(try fetchAttachment(id: attachmentId, tx: tx))

            // Delete the first message.
            try deleteMessage(id: messageId1, tx: tx)
            // The references should be deleted by cascade rule.
            XCTAssertEqual(1, try fetchMessageAttachmentReferences(attachmentId: attachmentId, tx: tx).count)
            XCTAssertEqual(0, try fetchMessageAttachmentReferences(messageId: messageId1, tx: tx).count)
            // But there are other owner references so the attachment shouldn't be deleted.
            XCTAssertNotNil(try fetchAttachment(id: attachmentId, tx: tx))

            // Finally delete the final message.
            try deleteMessage(id: messageId2, tx: tx)
            // The references should be deleted by cascade rule.
            XCTAssertEqual(0, try fetchMessageAttachmentReferences(attachmentId: attachmentId, tx: tx).count)
            XCTAssertEqual(0, try fetchMessageAttachmentReferences(messageId: messageId2, tx: tx).count)
            // Now the attachment should be deleted.
            XCTAssertNil(try fetchAttachment(id: attachmentId, tx: tx))
        }
    }

    // MARK: - Orphaning

    func testOrphanedTableInsert() throws {
        try runMigration()

        try db.write { tx in
            let threadId = try insertThread(tx: tx)
            let messageId = try insertMessage(tx: tx)

            let filepath = UUID().uuidString
            let attachmentId = try insertAttachment(filepath: filepath, tx: tx)
            _ = try insertMessageAttachmentReference(
                threadId: threadId,
                messageId: messageId,
                attachmentId: attachmentId,
                tx: tx
            )

            // Delete the message; deletion should cascade to attachment.
            try deleteMessage(id: messageId, tx: tx)

            XCTAssertNil(try fetchAttachment(id: attachmentId, tx: tx))

            // Check that a row was inserted into the orphan table.
            let orphanAttachments = try fetchOrphanAttachments(tx: tx)
            XCTAssertEqual([filepath], orphanAttachments.map { $0["localRelativeFilePath"] })
        }
    }

    // MARK: - OriginalAttachmentIdForQuotedReply

    func testOriginalAttachmentIdForQuotedReplyForeignKey() throws {
        try runMigration()
        try runOriginalAttachmentIdForQuotedReplyMigration()

        try db.write { tx in
            // Create 2 attachments, 1 a regular attachment and one with
            // an attachment that references the first attachment.
            let originalAttachmentId = try insertAttachment(tx: tx)
            let replyAttachmentId = try insertQuotedReplyAttachment(
                originalAttachmentIdForQuotedReply: originalAttachmentId,
                tx: tx
            )

            // Fetch the second by the first attachment's ID.
            var replyAttachment = try Row.fetchOne(
                tx.unwrapGrdbRead.database,
                sql: """
                    SELECT * FROM Attachment WHERE originalAttachmentIdForQuotedReply = ?;
                """,
                arguments: [originalAttachmentId]
            )
            XCTAssertEqual(replyAttachment?["id"], replyAttachmentId)

            // Delete the first attachment.
            try tx.unwrapGrdbWrite.database.execute(
                sql: """
                    DELETE FROM Attachment WHERE id = ?;
                """,
                arguments: [originalAttachmentId]
            )

            // Should not be able to find the second attachment by the original's id now.
            replyAttachment = try Row.fetchOne(
                tx.unwrapGrdbRead.database,
                sql: """
                    SELECT * FROM Attachment WHERE originalAttachmentIdForQuotedReply = ?;
                """,
                arguments: [originalAttachmentId]
            )
            XCTAssertNil(replyAttachment)

            // But we can fetch it by its id.
            replyAttachment = try Row.fetchOne(
                tx.unwrapGrdbRead.database,
                sql: """
                    SELECT * FROM Attachment WHERE id = ?;
                """,
                arguments: [replyAttachmentId]
            )
            XCTAssertNotNil(replyAttachment)
            XCTAssertNil(replyAttachment?["originalAttachmentIdForQuotedReply"])
        }
    }

    // MARK: - Indexes

    func testIndexes() throws {
        try runMigration()

        try db.read { tx in
            func assertUsesIndex(sql: String) throws {
                try self.assertUsesIndex(sql: sql, tx: tx)
            }

            // Common attachment lookups.
            try assertUsesIndex(sql: "SELECT 0 FROM Attachment WHERE sha256ContentHash = '123'")
            try assertUsesIndex(sql: "SELECT 0 FROM Attachment WHERE mediaName = '123'")
            try assertUsesIndex(sql: "SELECT 0 FROM Attachment WHERE contentType = 1 AND mimeType = 'image/png'")

            // Message reference lookups in both directions: by attachment and owner.
            try assertUsesIndex(sql: "SELECT 0 FROM MessageAttachmentReference WHERE attachmentRowId = 1")
            try assertUsesIndex(sql: "SELECT 0 FROM MessageAttachmentReference WHERE ownerType = 1 AND ownerRowId = 1")

            // Find a given attachment by id on its owning message.
            try assertUsesIndex(sql: "SELECT 0 FROM MessageAttachmentReference WHERE ownerRowId = 1 AND idInMessage = 1")

            // Find a given sticker.
            try assertUsesIndex(sql: "SELECT 0 FROM MessageAttachmentReference WHERE stickerPackId = 1 AND stickerId = 1")

            // What we need to drive media gallery, including filtering and ordering.
            try assertUsesIndex(sql: """
                SELECT receivedAtTimestamp FROM MessageAttachmentReference
                WHERE
                    threadRowId = 1
                    AND ownerType = 1
                    AND contentType = 1
                    AND renderingFlag = 1
                ORDER BY
                    receivedAtTimestamp
                    ,ownerRowId
                    ,orderInMessage
            """)

            // Story message reference lookups in both directions: by attachment and owner.
            try assertUsesIndex(sql: "SELECT 0 FROM StoryMessageAttachmentReference WHERE attachmentRowId = 1")
            try assertUsesIndex(sql: "SELECT 0 FROM StoryMessageAttachmentReference WHERE ownerType = 1 AND ownerRowId = 1")

            // Thread reference lookups in both directions: by attachment and owner.
            try assertUsesIndex(sql: "SELECT 0 FROM ThreadAttachmentReference WHERE attachmentRowId = 1")
            try assertUsesIndex(sql: "SELECT 0 FROM ThreadAttachmentReference WHERE ownerRowId = 1")
        }
    }

    func testOriginalAttachmentIdForQuotedReplyIndex() throws {
        try runMigration()
        try runOriginalAttachmentIdForQuotedReplyMigration()

        try db.read { tx in
            try assertUsesIndex(sql: "SELECT 0 FROM Attachment WHERE originalAttachmentIdForQuotedReply = 1", tx: tx)
        }
    }

    // MARK: - Helpers

    private func runMigration() throws {
        try db.write { tx in
            let tx = tx.unwrapGrdbWrite

            // We need a messages and threads table for the foreign keys in
            // the attachments tables.
            // But only create a very minimal table, we don't need other fields
            // to test attachments stuff.
            try tx.database.execute(sql: """
                CREATE TABLE IF NOT EXISTS "model_TSThread" (
                    "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                );
            """)
            try tx.database.execute(sql: """
                CREATE TABLE IF NOT EXISTS "model_TSInteraction" (
                    "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                );
            """)
            try tx.database.execute(sql: """
                CREATE TABLE IF NOT EXISTS "model_StoryMessage" (
                    "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                );
            """)

            // Create the attachment tables, indexes, triggers.
            _ = try GRDBSchemaMigrator.createV2AttachmentTables(tx)
        }
    }

    private func runOriginalAttachmentIdForQuotedReplyMigration() throws {
        try db.write { tx in
            let tx = tx.unwrapGrdbWrite

            // Create the attachment tables, indexes, triggers.
            _ = try GRDBSchemaMigrator.addOriginalAttachmentIdForQuotedReplyColumn(tx)
        }
    }

    private func assertUsesIndex(sql: String, tx: SDSAnyReadTransaction) throws {
        let queryPlan: String = try Row.fetchOne(tx.unwrapGrdbRead.database, sql: """
            EXPLAIN QUERY PLAN \(sql)
        """)!["detail"]
        XCTAssert(queryPlan.contains("USING COVERING INDEX"))
    }

    // MARK: Inserts

    private func insertAttachment(
        filepath: String = UUID().uuidString,
        contentType: Int64 = 0,
        tx: SDSAnyWriteTransaction
    ) throws -> Int64 {
        // Only set columns which are relevant to the SQL constraints + triggers.
        // Irrelevant columns with NOT NULL are set to arbitrary values.
        // Other columns that aren't NOT NULL are ignored for this test.
        try tx.unwrapGrdbWrite.database.execute(
            sql: """
                INSERT INTO Attachment (
                    mimeType
                    ,encryptionKey
                    ,localRelativeFilePath
                    ,contentType
                ) VALUES (
                    'image/png'
                    ,x'1234'
                    ,?
                    ,?
                );
            """,
            arguments: [
                filepath,
                contentType
            ]
        )
        return tx.unwrapGrdbWrite.database.lastInsertedRowID
    }

    private func insertQuotedReplyAttachment(
        filepath: String = UUID().uuidString,
        originalAttachmentIdForQuotedReply: Attachment.IDType,
        tx: SDSAnyWriteTransaction
    ) throws -> Int64 {
        // Only set columns which are relevant to the SQL constraints + triggers.
        // Irrelevant columns with NOT NULL are set to arbitrary values.
        // Other columns that aren't NOT NULL are ignored for this test.
        try tx.unwrapGrdbWrite.database.execute(
            sql: """
                INSERT INTO Attachment (
                    mimeType
                    ,encryptionKey
                    ,localRelativeFilePath
                    ,contentType
                    ,originalAttachmentIdForQuotedReply
                ) VALUES (
                    'image/png'
                    ,x'1234'
                    ,?
                    ,0
                    ,?
                );
            """,
            arguments: [
                filepath,
                originalAttachmentIdForQuotedReply
            ]
        )
        return tx.unwrapGrdbWrite.database.lastInsertedRowID
    }

    private func insertMessageAttachmentReference(
        threadId: Int64,
        messageId: Int64,
        attachmentId: Int64,
        contentType: Int64 = 0,
        tx: SDSAnyWriteTransaction
    ) throws {
        // Only set columns which are relevant to the SQL constraints + triggers.
        // Irrelevant columns with NOT NULL are set to arbitrary values.
        // Other columns that aren't NOT NULL are ignored for this test.
        try tx.unwrapGrdbWrite.database.execute(
            sql: """
                INSERT INTO MessageAttachmentReference (
                    ownerType
                    ,ownerRowId
                    ,attachmentRowId
                    ,receivedAtTimestamp
                    ,contentType
                    ,renderingFlag
                    ,threadRowId
                ) VALUES (
                    0
                    ,?
                    ,?
                    ,1000000
                    ,?
                    ,0
                    ,?
                );
            """,
            arguments: [
                messageId,
                attachmentId,
                contentType,
                threadId
            ]
        )
    }

    private func insertStoryMessageAttachmentReference(
        storyMessageId: Int64,
        attachmentId: Int64,
        tx: SDSAnyWriteTransaction
    ) throws {
        // Only set columns which are relevant to the SQL constraints + triggers.
        // Irrelevant columns with NOT NULL are set to arbitrary values.
        // Other columns that aren't NOT NULL are ignored for this test.
        try tx.unwrapGrdbWrite.database.execute(
            sql: """
                INSERT INTO StoryMessageAttachmentReference (
                    ownerType
                    ,ownerRowId
                    ,attachmentRowId
                    ,shouldLoop
                ) VALUES (
                    0
                    ,?
                    ,?
                    ,0
                );
            """,
            arguments: [
                storyMessageId,
                attachmentId
            ]
        )
    }

    private func insertThreadAttachmentReference(
        threadId: Int64,
        attachmentId: Int64,
        tx: SDSAnyWriteTransaction
    ) throws {
        // Only set columns which are relevant to the SQL constraints + triggers.
        // Irrelevant columns with NOT NULL are set to arbitrary values.
        // Other columns that aren't NOT NULL are ignored for this test.
        try tx.unwrapGrdbWrite.database.execute(
            sql: """
                INSERT INTO ThreadAttachmentReference (
                    ownerRowId
                    ,attachmentRowId
                    ,creationTimestamp
                ) VALUES (
                    ?
                    ,?
                    ,1234
                );
            """,
            arguments: [
                threadId,
                attachmentId
            ]
        )
    }

    // MARK: Fetches

    private func fetchAttachment(id: Int64, tx: SDSAnyReadTransaction) throws -> Row? {
        return try Row.fetchOne(
            tx.unwrapGrdbRead.database,
            sql: """
                SELECT * FROM Attachment WHERE id = ?;
            """,
            arguments: [id]
        )
    }

    private func fetchOrphanAttachments(tx: SDSAnyReadTransaction) throws -> [Row] {
        return try Row.fetchAll(
            tx.unwrapGrdbRead.database,
            sql: """
                SELECT * FROM OrphanedAttachment;
            """
        )
    }

    private func fetchMessageAttachmentReferences(
        attachmentId: Int64,
        tx: SDSAnyReadTransaction
    ) throws -> [Row] {
        return try Row.fetchAll(
            tx.unwrapGrdbRead.database,
            sql: """
                SELECT * FROM MessageAttachmentReference WHERE attachmentRowId = ?;
            """,
            arguments: [attachmentId]
        )
    }

    private func fetchMessageAttachmentReferences(
        messageId: Int64,
        tx: SDSAnyReadTransaction
    ) throws -> [Row] {
        return try Row.fetchAll(
            tx.unwrapGrdbRead.database,
            sql: """
                SELECT * FROM MessageAttachmentReference WHERE ownerRowId = ?;
            """,
            arguments: [messageId]
        )
    }

    private func fetchStoryMessageAttachmentReferences(
        attachmentId: Int64,
        tx: SDSAnyReadTransaction
    ) throws -> [Row] {
        return try Row.fetchAll(
            tx.unwrapGrdbRead.database,
            sql: """
                SELECT * FROM StoryMessageAttachmentReference WHERE attachmentRowId = ?;
            """,
            arguments: [attachmentId]
        )
    }

    private func fetchStoryMessageAttachmentReferences(
        storyMessageId: Int64,
        tx: SDSAnyReadTransaction
    ) throws -> [Row] {
        return try Row.fetchAll(
            tx.unwrapGrdbRead.database,
            sql: """
                SELECT * FROM StoryMessageAttachmentReference WHERE ownerRowId = ?;
            """,
            arguments: [storyMessageId]
        )
    }

    private func fetchThreadAttachmentReferences(
        attachmentId: Int64,
        tx: SDSAnyReadTransaction
    ) throws -> [Row] {
        return try Row.fetchAll(
            tx.unwrapGrdbRead.database,
            sql: """
                SELECT * FROM ThreadAttachmentReference WHERE attachmentRowId = ?;
            """,
            arguments: [attachmentId]
        )
    }

    private func fetchThreadAttachmentReferences(
        threadId: Int64,
        tx: SDSAnyReadTransaction
    ) throws -> [Row] {
        return try Row.fetchAll(
            tx.unwrapGrdbRead.database,
            sql: """
                SELECT * FROM ThreadAttachmentReference WHERE ownerRowId = ?;
            """,
            arguments: [threadId]
        )
    }

    // MARK: Referenced non-attachment types

    private func insertThread(tx: SDSAnyWriteTransaction) throws -> Int64 {
        try tx.unwrapGrdbWrite.database.execute(sql: """
          INSERT INTO model_TSThread DEFAULT VALUES;
        """)
        return tx.unwrapGrdbWrite.database.lastInsertedRowID
    }

    private func deleteThread(id: Int64, tx: SDSAnyWriteTransaction) throws {
        try tx.unwrapGrdbWrite.database.execute(
            sql: """
                DELETE FROM model_TSThread WHERE id = ?;
            """,
            arguments: [id]
        )
    }

    private func insertMessage(tx: SDSAnyWriteTransaction) throws -> Int64 {
        try tx.unwrapGrdbWrite.database.execute(sql: """
          INSERT INTO model_TSInteraction DEFAULT VALUES;
        """)
        return tx.unwrapGrdbWrite.database.lastInsertedRowID
    }

    private func deleteMessage(id: Int64, tx: SDSAnyWriteTransaction) throws {
        try tx.unwrapGrdbWrite.database.execute(
            sql: """
                DELETE FROM model_TSInteraction WHERE id = ?;
            """,
            arguments: [id]
        )
    }

    private func insertStoryMessage(tx: SDSAnyWriteTransaction) throws -> Int64 {
        try tx.unwrapGrdbWrite.database.execute(sql: """
          INSERT INTO model_StoryMessage DEFAULT VALUES;
        """)
        return tx.unwrapGrdbWrite.database.lastInsertedRowID
    }

    private func deleteStoryMessage(id: Int64, tx: SDSAnyWriteTransaction) throws {
        try tx.unwrapGrdbWrite.database.execute(
            sql: """
                DELETE FROM model_StoryMessage WHERE id = ?;
            """,
            arguments: [id]
        )
    }
}
