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

    private var store: BackupAttachmentDownloadStore!

    override func setUp() async throws {
        db = InMemoryDB()
        store = BackupAttachmentDownloadStore()
    }

    func testEnqueue() throws {
        // Create an attachment and reference.
        var attachmentRecord = Attachment.Record(params: .mockPointer())

        let (threadRowId, messageRowId) = insertThreadAndInteraction()

        db.write { tx in
            try! attachmentRecord.insert(
                tx.database,
            )
            let attachment = try! Attachment(record: attachmentRecord)
            let reference = insertMessageAttachmentReferenceRecord(
                attachmentRowId: attachmentRecord.sqliteId!,
                messageRowId: messageRowId,
                threadRowId: threadRowId,
                timestamp: 1234,
                tx: tx,
            )
            store.enqueue(
                ReferencedAttachment(reference: reference, attachment: attachment),
                thumbnail: false,
                canDownloadFromMediaTier: true,
                state: .ready,
                currentTimestamp: Date().ows_millisecondsSince1970,
                tx: tx,
            )

            // Ensure the row exists.
            let row = try! QueuedBackupAttachmentDownload.fetchOne(tx.database)
            XCTAssertNotNil(row)
            XCTAssertEqual(row?.attachmentRowId, attachmentRecord.sqliteId)
            XCTAssertEqual(row?.maxOwnerTimestamp, 1234)
        }

        // Re enqueue at a higher timestamp.
        try db.write { tx in
            let attachment = try! Attachment(record: attachmentRecord)
            let reference = insertMessageAttachmentReferenceRecord(
                attachmentRowId: attachmentRecord.sqliteId!,
                messageRowId: messageRowId,
                threadRowId: threadRowId,
                timestamp: 5678,
                tx: tx,
            )
            store.enqueue(
                ReferencedAttachment(reference: reference, attachment: attachment),
                thumbnail: false,
                canDownloadFromMediaTier: true,
                state: .ready,
                currentTimestamp: Date().ows_millisecondsSince1970,
                tx: tx,
            )

            let row = try QueuedBackupAttachmentDownload.fetchOne(tx.database)
            XCTAssertNotNil(row)
            XCTAssertEqual(row?.attachmentRowId, attachmentRecord.sqliteId)
            XCTAssertEqual(row?.maxOwnerTimestamp, 5678)
        }

        // Re enqueue with a nil timestamp
        try db.write { tx in
            let referenceRecord = AttachmentReference.ThreadAttachmentReferenceRecord(
                attachmentRowId: attachmentRecord.sqliteId!,
                // Confusingly, this owner _has_ a timestamp; we just don't use it
                // for the backup attachment download queue.
                threadSource: .globalThreadWallpaperImage(creationTimestamp: 1),
            )
            try referenceRecord.insert(tx.database)

            let attachment = try Attachment(record: attachmentRecord)
            let reference = try AttachmentReference(record: referenceRecord)

            store.enqueue(
                ReferencedAttachment(reference: reference, attachment: attachment),
                thumbnail: false,
                canDownloadFromMediaTier: true,
                state: .ready,
                currentTimestamp: Date().ows_millisecondsSince1970,
                tx: tx,
            )

            let row = try QueuedBackupAttachmentDownload.fetchOne(tx.database)
            XCTAssertNotNil(row)
            XCTAssertEqual(row?.attachmentRowId, attachmentRecord.sqliteId)
            XCTAssertNil(row?.maxOwnerTimestamp)
        }

        // Re enqueue at an even higher timestamp.
        try db.write { tx in
            let attachment = try! Attachment(record: attachmentRecord)
            let reference = insertMessageAttachmentReferenceRecord(
                attachmentRowId: attachmentRecord.sqliteId!,
                messageRowId: messageRowId,
                threadRowId: threadRowId,
                timestamp: 9999,
                tx: tx,
            )

            store.enqueue(
                ReferencedAttachment(reference: reference, attachment: attachment),
                thumbnail: false,
                canDownloadFromMediaTier: true,
                state: .ready,
                currentTimestamp: Date().ows_millisecondsSince1970,
                tx: tx,
            )

            let row = try QueuedBackupAttachmentDownload.fetchOne(tx.database)
            XCTAssertNotNil(row)
            XCTAssertEqual(row?.attachmentRowId, attachmentRecord.sqliteId)
            // should not have overriden the nil timestamp
            XCTAssertNil(row?.maxOwnerTimestamp)
        }
    }

    func testPeek() throws {
        let nowTimestamp = Date().ows_millisecondsSince1970

        let thumbnailTimestamps: [UInt64] = [
            nowTimestamp - 4,
            nowTimestamp,
            nowTimestamp - 6,
            nowTimestamp - 2,
        ]
        let fullsizeTimestamps: [UInt64] = [
            nowTimestamp - 7,
            nowTimestamp - 1,
            nowTimestamp - 3,
            nowTimestamp - 5,
        ]
        for (isThumbnail, timestamps) in [(true, thumbnailTimestamps), (false, fullsizeTimestamps)] {
            for timestamp in timestamps {
                var attachmentRecord = Attachment.Record(params: .mockPointer())
                let (threadRowId, messageRowId) = insertThreadAndInteraction()

                try db.write { tx in
                    try attachmentRecord.insert(
                        tx.database,
                    )
                    let attachment = try! Attachment(record: attachmentRecord)
                    let reference = insertMessageAttachmentReferenceRecord(
                        attachmentRowId: attachmentRecord.sqliteId!,
                        messageRowId: messageRowId,
                        threadRowId: threadRowId,
                        timestamp: timestamp,
                        tx: tx,
                    )
                    store.enqueue(
                        ReferencedAttachment(reference: reference, attachment: attachment),
                        thumbnail: isThumbnail,
                        canDownloadFromMediaTier: true,
                        state: .ready,
                        currentTimestamp: nowTimestamp,
                        tx: tx,
                    )
                }
            }
        }

        // Add a bunch of very recent ineligible and done rows
        // that should be skipped in peek.
        for i: UInt64 in 1...10 {
            var attachmentRecord = Attachment.Record(params: .mockPointer())
            let (threadRowId, messageRowId) = insertThreadAndInteraction()
            try db.write { tx in
                try attachmentRecord.insert(
                    tx.database,
                )
                let attachment = try! Attachment(record: attachmentRecord)
                let reference = insertMessageAttachmentReferenceRecord(
                    attachmentRowId: attachmentRecord.sqliteId!,
                    messageRowId: messageRowId,
                    threadRowId: threadRowId,
                    timestamp: nowTimestamp - i,
                    tx: tx,
                )
                store.enqueue(
                    ReferencedAttachment(reference: reference, attachment: attachment),
                    thumbnail: i % 2 == 0,
                    canDownloadFromMediaTier: true,
                    state: i % 3 == 1 ? .ineligible : .done,
                    currentTimestamp: nowTimestamp,
                    tx: tx,
                )
            }
        }

        try db.read { tx in
            XCTAssertEqual(
                thumbnailTimestamps.count + fullsizeTimestamps.count + 10,
                try QueuedBackupAttachmentDownload.fetchCount(tx.database),
            )
        }

        let thumbnailRecords = try db.read { tx in
            try store.peek(
                count: 7,
                isThumbnail: true,
                tx: tx,
            )
        }
        let fullsizeRecords = try db.read { tx in
            try store.peek(
                count: 7,
                isThumbnail: false,
                tx: tx,
            )
        }

        XCTAssert(thumbnailRecords.anySatisfy(\.isThumbnail))
        XCTAssert(fullsizeRecords.anySatisfy(\.isThumbnail.negated))
        XCTAssertEqual(
            thumbnailRecords.map(\.maxOwnerTimestamp),
            thumbnailTimestamps.sorted().reversed(),
        )
        XCTAssertEqual(
            fullsizeRecords.map(\.maxOwnerTimestamp),
            fullsizeTimestamps.sorted().reversed(),
        )
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
        tx: DBWriteTransaction,
    ) -> AttachmentReference {
        let record = AttachmentReference.MessageAttachmentReferenceRecord(
            attachmentRowId: attachmentRowId,
            sourceFilename: nil,
            sourceUnencryptedByteCount: nil,
            sourceMediaSizePixels: nil,
            messageSource: .linkPreview(.init(
                messageRowId: messageRowId,
                receivedAtTimestamp: timestamp,
                threadRowId: threadRowId,
                contentType: nil,
                isPastEditRevision: false,
            )),
        )
        try! record.insert(tx.database)
        return try! AttachmentReference(record: record)
    }
}
