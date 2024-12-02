//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import XCTest

@testable import SignalServiceKit

class BackupAttachmentDownloadStoreTests: XCTestCase {

    private var db: InMemoryDB!

    private var store: BackupAttachmentDownloadStoreImpl!

    override func setUp() async throws {
        db = InMemoryDB()
        store = BackupAttachmentDownloadStoreImpl()
    }

    func testEnqueue() throws {
        // Create an attachment and reference.
        var attachmentRecord = Attachment.Record(params: .mockPointer())

        let (threadRowId, messageRowId) = insertThreadAndInteraction()

        try db.write { tx in
            try attachmentRecord.insert(
                tx.db
            )
            let reference = try insertMessageAttachmentReferenceRecord(
                attachmentRowId: attachmentRecord.sqliteId!,
                messageRowId: messageRowId,
                threadRowId: threadRowId,
                timestamp: 1234,
                tx: tx
            )
            try store.enqueue(reference, tx: tx)

            // Ensure the row exists.
            let row = try QueuedBackupAttachmentDownload.fetchOne(tx.db)
            XCTAssertNotNil(row)
            XCTAssertEqual(row?.attachmentRowId, attachmentRecord.sqliteId)
            XCTAssertEqual(row?.timestamp, 1234)
        }

        // Re enqueue at a higher timestamp.
        try db.write { tx in
            let reference = try insertMessageAttachmentReferenceRecord(
                attachmentRowId: attachmentRecord.sqliteId!,
                messageRowId: messageRowId,
                threadRowId: threadRowId,
                timestamp: 5678,
                tx: tx
            )
            try store.enqueue(reference, tx: tx)

            let row = try QueuedBackupAttachmentDownload.fetchOne(tx.db)
            XCTAssertNotNil(row)
            XCTAssertEqual(row?.attachmentRowId, attachmentRecord.sqliteId)
            XCTAssertEqual(row?.timestamp, 5678)
        }

        // Re enqueue with a nil timestamp
        try db.write { tx in
            let referenceRecord = AttachmentReference.ThreadAttachmentReferenceRecord.init(
                attachmentRowId: attachmentRecord.sqliteId!,
                // Confusingly, this owner _has_ a timestamp; we just don't use it
                // for the backup attachment download queue.
                threadSource: .globalThreadWallpaperImage(creationTimestamp: 1)
            )
            try referenceRecord.insert(tx.db)
            try store.enqueue(
                try AttachmentReference(record: referenceRecord),
                tx: tx
            )

            let row = try QueuedBackupAttachmentDownload.fetchOne(tx.db)
            XCTAssertNotNil(row)
            XCTAssertEqual(row?.attachmentRowId, attachmentRecord.sqliteId)
            XCTAssertNil(row?.timestamp)
        }

        // Re enqueue at an even higher timestamp.
        try db.write { tx in
            let reference = try insertMessageAttachmentReferenceRecord(
                attachmentRowId: attachmentRecord.sqliteId!,
                messageRowId: messageRowId,
                threadRowId: threadRowId,
                timestamp: 9999,
                tx: tx
            )
            try store.enqueue(reference, tx: tx)

            let row = try QueuedBackupAttachmentDownload.fetchOne(tx.db)
            XCTAssertNotNil(row)
            XCTAssertEqual(row?.attachmentRowId, attachmentRecord.sqliteId)
            // should not have overriden the nil timestamp
            XCTAssertNil(row?.timestamp)
        }
    }

    func testPeek() throws {
        let timestamps: [UInt64] = [1111, 4444, 3333, 2222]
        for timestamp in timestamps {
            var attachmentRecord = Attachment.Record(params: .mockPointer())
            let (threadRowId, messageRowId) = insertThreadAndInteraction()

            try db.write { tx in
                try attachmentRecord.insert(
                    tx.db
                )
                let reference = try insertMessageAttachmentReferenceRecord(
                    attachmentRowId: attachmentRecord.sqliteId!,
                    messageRowId: messageRowId,
                    threadRowId: threadRowId,
                    timestamp: timestamp,
                    tx: tx
                )
                try store.enqueue(reference, tx: tx)
            }
        }

        try db.read { tx in
            XCTAssertEqual(
                timestamps.count,
                try QueuedBackupAttachmentDownload.fetchCount(tx.db)
            )
        }

        var dequeuedTimestamps = [UInt64]()
        try db.write { tx in
            var lastRecordId = Int64.max
            let records = try store.peek(
                count: UInt(timestamps.count - 1),
                tx: tx
            )
            for record in records {
                XCTAssert(record.id! < lastRecordId)
                lastRecordId = record.id!
                dequeuedTimestamps.append(record.timestamp!)
            }
        }

        // We should have gotten entries in reverse order to insertion order,
        // regardless of timestamps.
        XCTAssertEqual(dequeuedTimestamps, Array(timestamps.reversed().prefix(timestamps.count - 1)))
    }

    // MARK: - Helpers

    private func insertThreadAndInteraction() -> (threadRowId: Int64, interactionRowId: Int64) {
        return db.write { tx in
            let thread = insertThread(tx: tx)
            let interactionRowId = insertInteraction(thread: thread, tx: tx)
            return (thread.sqliteRowId!, interactionRowId)
        }
    }

    private func insertThread(tx: InMemoryDB.WriteTransaction) -> TSThread {
        let thread = TSThread(uniqueId: UUID().uuidString)
        try! thread.asRecord().insert(tx.db)
        return thread
    }

    private func insertInteraction(thread: TSThread, tx: InMemoryDB.WriteTransaction) -> Int64 {
        let interaction = TSInteraction(timestamp: 0, receivedAtTimestamp: 0, thread: thread)
        try! interaction.asRecord().insert(tx.db)
        return interaction.sqliteRowId!
    }

    private func insertMessageAttachmentReferenceRecord(
        attachmentRowId: Int64,
        messageRowId: Int64,
        threadRowId: Int64,
        timestamp: UInt64,
        tx: InMemoryDB.WriteTransaction
    ) throws -> AttachmentReference {
        let record = AttachmentReference.MessageAttachmentReferenceRecord.init(
            attachmentRowId: attachmentRowId,
            sourceFilename: nil,
            sourceUnencryptedByteCount: nil,
            sourceMediaSizePixels: nil,
            messageSource: .linkPreview(.init(
                messageRowId: messageRowId,
                receivedAtTimestamp: timestamp,
                threadRowId: threadRowId,
                contentType: nil,
                isPastEditRevision: false
            ))
        )
        try record.insert(tx.db)
        return try AttachmentReference(record: record)
    }
}
