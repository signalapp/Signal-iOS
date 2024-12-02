//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import XCTest

@testable import SignalServiceKit

class BackupAttachmentUploadStoreTests: XCTestCase {

    private var db: InMemoryDB!

    private var store: BackupAttachmentUploadStoreImpl!

    override func setUp() async throws {
        db = InMemoryDB()
        store = BackupAttachmentUploadStoreImpl()
    }

    func testEnqueue() throws {
        // Create an attachment and reference.
        var attachmentRecord = Attachment.Record(params: .mockStream())

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
            try store.enqueue(
                .init(
                    reference: reference,
                    attachmentStream: Attachment(record: attachmentRecord).asStream()!
                ),
                tx: tx
            )

            // Ensure the row exists.
            let row = try QueuedBackupAttachmentUpload.fetchOne(tx.db)
            XCTAssertNotNil(row)
            XCTAssertEqual(row?.attachmentRowId, attachmentRecord.sqliteId)
            switch row!.sourceType {
            case .threadWallpaper:
                XCTFail("unexpected type")
            case .message(let timestamp):
                XCTAssertEqual(timestamp, 1234)
            }
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
            try store.enqueue(
                .init(
                    reference: reference,
                    attachmentStream: Attachment(record: attachmentRecord).asStream()!
                ),
                tx: tx
            )

            let row = try QueuedBackupAttachmentUpload.fetchOne(tx.db)
            XCTAssertNotNil(row)
            XCTAssertEqual(row?.attachmentRowId, attachmentRecord.sqliteId)
            switch row!.sourceType {
            case .threadWallpaper:
                XCTFail("unexpected type")
            case .message(let timestamp):
                XCTAssertEqual(timestamp, 5678)
            }
        }

        // Re enqueue with a nil timestamp
        try db.write { tx in
            let referenceRecord = AttachmentReference.ThreadAttachmentReferenceRecord.init(
                attachmentRowId: attachmentRecord.sqliteId!,
                // Confusingly, this owner _has_ a timestamp; we just don't use it
                // for the backup attachment upload queue.
                threadSource: .globalThreadWallpaperImage(creationTimestamp: 1)
            )
            try referenceRecord.insert(tx.db)
            try store.enqueue(
                .init(
                    reference: AttachmentReference(record: referenceRecord),
                    attachmentStream: Attachment(record: attachmentRecord).asStream()!
                ),
                tx: tx
            )

            let row = try QueuedBackupAttachmentUpload.fetchOne(tx.db)
            XCTAssertNotNil(row)
            XCTAssertEqual(row?.attachmentRowId, attachmentRecord.sqliteId)
            switch row!.sourceType {
            case .threadWallpaper:
                break
            case .message:
                XCTFail("unexpected type")
            }
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
            try store.enqueue(
                .init(
                    reference: reference,
                    attachmentStream: Attachment(record: attachmentRecord).asStream()!
                ),
                tx: tx
            )

            let row = try QueuedBackupAttachmentUpload.fetchOne(tx.db)
            XCTAssertNotNil(row)
            XCTAssertEqual(row?.attachmentRowId, attachmentRecord.sqliteId)
            // should not have overriden the nil timestamp
            switch row!.sourceType {
            case .threadWallpaper:
                break
            case .message:
                XCTFail("unexpected type")
            }
        }
    }

    func testDequeue() throws {
        let timestamps: [UInt64?] = [1111, nil, 4444, 3333, 2222]
        for timestamp in timestamps {
            var attachmentRecord = Attachment.Record(params: .mockStream())
            let (threadRowId, messageRowId) = insertThreadAndInteraction()

            try db.write { tx in
                try attachmentRecord.insert(
                    tx.db
                )
                let reference: AttachmentReference = try {
                    if let timestamp {
                        return try insertMessageAttachmentReferenceRecord(
                            attachmentRowId: attachmentRecord.sqliteId!,
                            messageRowId: messageRowId,
                            threadRowId: threadRowId,
                            timestamp: timestamp,
                            tx: tx
                        )
                    } else {
                        let referenceRecord = AttachmentReference.ThreadAttachmentReferenceRecord.init(
                            attachmentRowId: attachmentRecord.sqliteId!,
                            // Confusingly, this owner _has_ a timestamp; we just don't use it
                            // for the backup attachment upload queue.
                            threadSource: .globalThreadWallpaperImage(creationTimestamp: 1)
                        )
                        try referenceRecord.insert(tx.db)
                        return try AttachmentReference(record: referenceRecord)
                    }
                }()
                try store.enqueue(
                    .init(
                        reference: reference,
                        attachmentStream: Attachment(record: attachmentRecord).asStream()!
                    ),
                    tx: tx
                )
            }
        }

        var dequeuedRecords = [QueuedBackupAttachmentUpload]()
        try db.read { tx in
            XCTAssertEqual(
                timestamps.count,
                try QueuedBackupAttachmentUpload.fetchCount(tx.db)
            )

            dequeuedRecords = try store.fetchNextUploads(
                count: UInt(timestamps.count - 1),
                tx: tx
            )
        }

        let dequeuedTimestamps: [UInt64?] = dequeuedRecords.map {
            switch $0.sourceType {
            case .threadWallpaper: return nil
            case .message(let timestamp): return timestamp
            }
        }
        let sortedTimestamps = timestamps.sorted(by: { lhs, rhs in
            return (lhs ?? .max) > (rhs ?? .max)
        })

        // We should have gotten entries in timestamp order
        XCTAssertEqual(dequeuedTimestamps, Array(sortedTimestamps.prefix(sortedTimestamps.count - 1)))

        try db.write { tx in
            try dequeuedRecords.forEach { record in
                try store.removeQueuedUpload(
                    for: record.attachmentRowId,
                    tx: tx
                )
            }
        }

        try db.read { tx in
            // all rows but one should be deleted.
            XCTAssertEqual(
                1,
                try QueuedBackupAttachmentUpload.fetchCount(tx.db)
            )
        }
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
