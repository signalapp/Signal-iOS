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
                tx.database
            )
            let reference = try insertMessageAttachmentReferenceRecord(
                attachmentRowId: attachmentRecord.sqliteId!,
                messageRowId: messageRowId,
                threadRowId: threadRowId,
                timestamp: 1234,
                tx: tx
            )
            try store.enqueue(
                Attachment(record: attachmentRecord).asStream()!,
                owner: reference.owner.asEligibleUploadOwnerType,
                fullsize: true,
                tx: tx
            )

            // Ensure the row exists.
            let row = try QueuedBackupAttachmentUpload.fetchOne(tx.database)
            XCTAssertNotNil(row)
            XCTAssertEqual(row?.attachmentRowId, attachmentRecord.sqliteId)
            switch row!.highestPriorityOwnerType {
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
                Attachment(record: attachmentRecord).asStream()!,
                owner: reference.owner.asEligibleUploadOwnerType,
                fullsize: true,
                tx: tx
            )

            let row = try QueuedBackupAttachmentUpload.fetchOne(tx.database)
            XCTAssertNotNil(row)
            XCTAssertEqual(row?.attachmentRowId, attachmentRecord.sqliteId)
            switch row!.highestPriorityOwnerType {
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
            try referenceRecord.insert(tx.database)
            try store.enqueue(
                Attachment(record: attachmentRecord).asStream()!,
                owner: AttachmentReference(record: referenceRecord).owner.asEligibleUploadOwnerType,
                fullsize: true,
                tx: tx
            )

            let row = try QueuedBackupAttachmentUpload.fetchOne(tx.database)
            XCTAssertNotNil(row)
            XCTAssertEqual(row?.attachmentRowId, attachmentRecord.sqliteId)
            switch row!.highestPriorityOwnerType {
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
                Attachment(record: attachmentRecord).asStream()!,
                owner: reference.owner.asEligibleUploadOwnerType,
                fullsize: true,
                tx: tx
            )

            let row = try QueuedBackupAttachmentUpload.fetchOne(tx.database)
            XCTAssertNotNil(row)
            XCTAssertEqual(row?.attachmentRowId, attachmentRecord.sqliteId)
            // should not have overriden the nil timestamp
            switch row!.highestPriorityOwnerType {
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
                    tx.database
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
                        try referenceRecord.insert(tx.database)
                        return try AttachmentReference(record: referenceRecord)
                    }
                }()
                try store.enqueue(
                    Attachment(record: attachmentRecord).asStream()!,
                    owner: reference.owner.asEligibleUploadOwnerType,
                    fullsize: true,
                    tx: tx
                )
            }
        }

        var dequeuedRecords = [QueuedBackupAttachmentUpload]()
        try db.read { tx in
            XCTAssertEqual(
                timestamps.count,
                try QueuedBackupAttachmentUpload.fetchCount(tx.database)
            )

            dequeuedRecords = try store.fetchNextUploads(
                count: UInt(timestamps.count - 1),
                tx: tx
            )
        }

        let dequeuedTimestamps: [UInt64?] = dequeuedRecords.map {
            switch $0.highestPriorityOwnerType {
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
                    fullsize: true,
                    tx: tx
                )
            }
        }

        try db.read { tx in
            // all rows but one should be deleted.
            XCTAssertEqual(
                1,
                try QueuedBackupAttachmentUpload.fetchCount(tx.database)
            )
        }
    }

    func testDequeue_thumbnail() throws {
        let timestamps: [UInt64] = [1111, 4444, 3333, 2222]
        for timestamp in timestamps {
            var attachmentRecord = Attachment.Record(params: .mockStream())
            let (threadRowId, messageRowId) = insertThreadAndInteraction()

            try db.write { tx in
                try attachmentRecord.insert(
                    tx.database
                )
                let reference: AttachmentReference = try insertMessageAttachmentReferenceRecord(
                    attachmentRowId: attachmentRecord.sqliteId!,
                    messageRowId: messageRowId,
                    threadRowId: threadRowId,
                    timestamp: timestamp,
                    tx: tx
                )
                // Enqueue both fullsize and thumbnail
                try store.enqueue(
                    Attachment(record: attachmentRecord).asStream()!,
                    owner: reference.owner.asEligibleUploadOwnerType,
                    fullsize: true,
                    tx: tx
                )
                try store.enqueue(
                    Attachment(record: attachmentRecord).asStream()!,
                    owner: reference.owner.asEligibleUploadOwnerType,
                    fullsize: false,
                    tx: tx
                )
            }
        }

        var dequeuedRecords = [QueuedBackupAttachmentUpload]()
        try db.read { tx in
            XCTAssertEqual(
                timestamps.count * 2,
                try QueuedBackupAttachmentUpload.fetchCount(tx.database)
            )

            dequeuedRecords = try store.fetchNextUploads(
                count: UInt(timestamps.count * 2),
                tx: tx
            )
        }

        // We should get results in DESC order with thumbnails first.
        var index = 0
        for timestamp in timestamps.sorted().reversed() {
            XCTAssertEqual(dequeuedRecords[index].isFullsize, false)
            switch dequeuedRecords[index].highestPriorityOwnerType {
            case .threadWallpaper: XCTFail("Unexpected type")
            case .message(let recordTimestamp):
                XCTAssertEqual(timestamp, recordTimestamp)
            }
            index += 1
            XCTAssertEqual(dequeuedRecords[index].isFullsize, true)
            switch dequeuedRecords[index].highestPriorityOwnerType {
            case .threadWallpaper: XCTFail("Unexpected type")
            case .message(let recordTimestamp):
                XCTAssertEqual(timestamp, recordTimestamp)
            }
            index += 1
        }

        try db.write { tx in
            try dequeuedRecords.forEach { record in
                try store.removeQueuedUpload(
                    for: record.attachmentRowId,
                    fullsize: record.isFullsize,
                    tx: tx
                )
            }
        }

        try db.read { tx in
            // all rows should be deleted.
            XCTAssertEqual(
                0,
                try QueuedBackupAttachmentUpload.fetchCount(tx.database)
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

    private func insertThread(tx: DBWriteTransaction) -> TSThread {
        let thread = TSThread(uniqueId: UUID().uuidString)
        try! thread.asRecord().insert(tx.database)
        return thread
    }

    private func insertInteraction(thread: TSThread, tx: DBWriteTransaction) -> Int64 {
        let interaction = TSInteraction(timestamp: 0, receivedAtTimestamp: 0, thread: thread)
        try! interaction.asRecord().insert(tx.database)
        return interaction.sqliteRowId!
    }

    private func insertMessageAttachmentReferenceRecord(
        attachmentRowId: Int64,
        messageRowId: Int64,
        threadRowId: Int64,
        timestamp: UInt64,
        tx: DBWriteTransaction
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
        try record.insert(tx.database)
        return try AttachmentReference(record: record)
    }
}

fileprivate extension AttachmentReference.Owner {

    var asEligibleUploadOwnerType: QueuedBackupAttachmentUpload.OwnerType! {
        switch self {
        case .message(let messageSource):
            return .message(timestamp: messageSource.receivedAtTimestamp)
        case .thread(let threadSource):
            switch threadSource {
            case .threadWallpaperImage, .globalThreadWallpaperImage:
                return .threadWallpaper
            }
        case .storyMessage:
            return nil
        }
    }
}
