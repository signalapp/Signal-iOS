//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import XCTest

@testable import SignalServiceKit

class AttachmentDownloadStoreTests: XCTestCase {

    private var db: InMemoryDB!

    private var attachmentStore: AttachmentStoreImpl!
    private var downloadStore: AttachmentDownloadStoreImpl!

    private var now = Date()

    override func setUp() async throws {
        db = InMemoryDB()
        attachmentStore = AttachmentStoreImpl()
        downloadStore = AttachmentDownloadStoreImpl(
            dateProvider: { [weak self] in
                return self!.now
            }
        )
    }

    func testEnqueue() throws {
        let attachmentId = try insertAttachment()

        try db.write { tx in
            try downloadStore.enqueueDownloadOfAttachment(
                withId: attachmentId,
                source: .transitTier,
                priority: .default,
                tx: tx
            )
            let downloadId = tx.db.lastInsertedRowID
            var download = try downloadStore.fetchRecord(id: downloadId, tx: tx)
            XCTAssertNotNil(download)
            XCTAssertEqual(download?.attachmentId, attachmentId)

            // Re-enqueue at the same priority.
            try downloadStore.enqueueDownloadOfAttachment(
                withId: attachmentId,
                source: .transitTier,
                priority: .default,
                tx: tx
            )
            // It should've done nothing.
            XCTAssertEqual(tx.db.lastInsertedRowID, downloadId)
            download = try downloadStore.fetchRecord(id: downloadId, tx: tx)
            XCTAssertEqual(download?.priority, .default)

            // Re-enqueue at higher priority.
            try downloadStore.enqueueDownloadOfAttachment(
                withId: attachmentId,
                source: .transitTier,
                priority: .userInitiated,
                tx: tx
            )
            // It should've updated (no new row id) but at higher priority.
            XCTAssertEqual(tx.db.lastInsertedRowID, downloadId)
            download = try downloadStore.fetchRecord(id: downloadId, tx: tx)
            XCTAssertEqual(download?.priority, .userInitiated)
        }
    }

    func testEnqueue_defaultCountLimit() throws {
        try db.write { tx in
            let attachmentIds = try (0..<50).map { _ in
                try insertAttachment(tx: tx)
            }
            let extraAttachmentId = try insertAttachment(tx: tx)

            try attachmentIds.forEach { attachmentId in
                try downloadStore.enqueueDownloadOfAttachment(
                    withId: attachmentId,
                    source: .transitTier,
                    priority: .default,
                    tx: tx
                )
            }
            let downloadCount = try QueuedAttachmentDownloadRecord.fetchCount(tx.db)
            XCTAssertEqual(downloadCount, 50)

            // Enqueue one more, it should kick out the first.
            try downloadStore.enqueueDownloadOfAttachment(
                withId: extraAttachmentId,
                source: .transitTier,
                priority: .default,
                tx: tx
            )
            // It should've done nothing.
            let downloads = try QueuedAttachmentDownloadRecord.fetchAll(tx.db)
            XCTAssertEqual(downloads.count, 50)
            var expectedAttachmentIds = attachmentIds
            _ = expectedAttachmentIds.popFirst()
            expectedAttachmentIds.append(extraAttachmentId)
            XCTAssertEqual(expectedAttachmentIds, downloads.map(\.attachmentId))
        }
    }

    func testReEnqueue_userInitiatedIgnoresRetry() throws {
        let attachmentId = try insertAttachment()

        try db.write { tx in
            try downloadStore.enqueueDownloadOfAttachment(
                withId: attachmentId,
                source: .transitTier,
                priority: .default,
                tx: tx
            )
            let downloadId = tx.db.lastInsertedRowID
            var download = try downloadStore.fetchRecord(id: downloadId, tx: tx)
            XCTAssertNotNil(download)
            XCTAssertEqual(download?.attachmentId, attachmentId)

            // Mark it as failed.
            let retryTimestamp = self.now.addingTimeInterval(100).ows_millisecondsSince1970
            try downloadStore.markQueuedDownloadFailed(
                withId: downloadId,
                minRetryTimestamp: retryTimestamp,
                tx: tx
            )
            // Retry state updated
            download = try downloadStore.fetchRecord(id: downloadId, tx: tx)
            XCTAssertEqual(download?.minRetryTimestamp, retryTimestamp)
            XCTAssertEqual(download?.retryAttempts, 1)

            // Re-enqueue at user initiated priority.
            try downloadStore.enqueueDownloadOfAttachment(
                withId: attachmentId,
                source: .transitTier,
                priority: .userInitiated,
                tx: tx
            )
            // It should've updated (no new row id) but at higher priority
            // and ready to retry.
            XCTAssertEqual(tx.db.lastInsertedRowID, downloadId)
            download = try downloadStore.fetchRecord(id: downloadId, tx: tx)
            XCTAssertEqual(download?.priority, .userInitiated)
            XCTAssertNil(download!.minRetryTimestamp)
            XCTAssertEqual(download?.retryAttempts, 1)
        }
    }

    func testPeek() throws {
        try db.write { tx in
            let attachmentIds = try (0..<15).map { _ in
                try insertAttachment(tx: tx)
            }

            let downloadIds = try (0..<attachmentIds.count).map { i in
                let priority: AttachmentDownloadPriority
                if i < 5 {
                    priority = .default
                } else {
                    priority = .userInitiated
                }
                try downloadStore.enqueueDownloadOfAttachment(
                    withId: attachmentIds[i],
                    source: .transitTier,
                    priority: priority,
                    tx: tx
                )
                return tx.db.lastInsertedRowID
            }
            var peekResult = try downloadStore.peek(count: 5, tx: tx)
            // Should get the first five high priority items.
            XCTAssertEqual(peekResult.map(\.id), Array(downloadIds[5..<10]))

            // Mark those as failed.
            for i in 5..<10 {
                try downloadStore.markQueuedDownloadFailed(
                    withId: downloadIds[i],
                    minRetryTimestamp: now.ows_millisecondsSince1970 + 100,
                    tx: tx
                )
            }

            peekResult = try downloadStore.peek(count: 5, tx: tx)
            // Should get the next five high priority items.
            XCTAssertEqual(peekResult.map(\.id), Array(downloadIds[10..<15]))

            // Remove the next batch
            for i in 10..<15 {
                try downloadStore.removeAttachmentFromQueue(
                    withId: attachmentIds[i],
                    source: .transitTier,
                    tx: tx
                )
            }

            peekResult = try downloadStore.peek(count: 5, tx: tx)
            // Should get the five lower priority items.
            XCTAssertEqual(peekResult.map(\.id), Array(downloadIds[0..<5]))
        }
    }

    func testNextRetryTimestamp() throws {
        try db.write { tx in
            try (0..<10).forEach { index in
                try downloadStore.enqueueDownloadOfAttachment(
                    withId: try insertAttachment(tx: tx),
                    source: .transitTier,
                    priority: .default,
                    tx: tx
                )
                let downloadId = tx.db.lastInsertedRowID
                try downloadStore.markQueuedDownloadFailed(
                    withId: downloadId,
                    minRetryTimestamp: now.ows_millisecondsSince1970 + 100 - UInt64(index),
                    tx: tx
                )
            }
            let timestampResult = try downloadStore.nextRetryTimestamp(tx: tx)
            // Should get the first five high priority items.
            XCTAssertEqual(timestampResult, now.ows_millisecondsSince1970 + 100 - 9)
        }
    }

    func testUpdateRetryableDownloads() throws {
        self.now = Date(millisecondsSince1970: 0)
        try db.write { tx in
            try (0..<15).forEach { i in
                try downloadStore.enqueueDownloadOfAttachment(
                    withId: try insertAttachment(tx: tx),
                    source: .transitTier,
                    priority: .default,
                    tx: tx
                )
                try downloadStore.markQueuedDownloadFailed(
                    withId: tx.db.lastInsertedRowID,
                    minRetryTimestamp: UInt64(i + 1) * 100,
                    tx: tx
                )
            }

            func peekCount() -> Int {
                return try! downloadStore.peek(count: 15, tx: tx).count
            }
            // Everything retrying
            XCTAssertEqual(peekCount(), 0)

            // Update without moving time, nothing updates.
            try downloadStore.updateRetryableDownloads(tx: tx)
            XCTAssertEqual(peekCount(), 0)

            // Move time forward so one instance is ready.
            self.now = Date(millisecondsSince1970: 100)
            try downloadStore.updateRetryableDownloads(tx: tx)
            XCTAssertEqual(peekCount(), 1)

            // Move time forward again so more are ready.
            self.now = Date(millisecondsSince1970: 450)
            try downloadStore.updateRetryableDownloads(tx: tx)
            XCTAssertEqual(peekCount(), 4)
        }
    }

    // MARK: - Helpers

    private func insertAttachment() throws -> Attachment.IDType {
        return try db.write(block: insertAttachment(tx:))
    }

    private func insertAttachment(tx: InMemoryDB.WriteTransaction) throws -> Attachment.IDType {
        let thread = TSThread(uniqueId: UUID().uuidString)
        try thread.asRecord().insert(tx.db)
        let interaction = TSInteraction(timestamp: 0, receivedAtTimestamp: 0, thread: thread)
        try interaction.asRecord().insert(tx.db)

        let attachmentParams = Attachment.ConstructionParams.mockPointer()
        let referenceParams = AttachmentReference.ConstructionParams.mock(
            owner: .message(.bodyAttachment(.init(
                messageRowId: interaction.sqliteRowId!,
                receivedAtTimestamp: interaction.receivedAtTimestamp,
                threadRowId: thread.sqliteRowId!,
                contentType: nil,
                isPastEditRevision: false,
                caption: nil,
                renderingFlag: .default,
                orderInOwner: 0,
                idInOwner: nil,
                isViewOnce: false
            )))
        )
        try attachmentStore.insert(
            attachmentParams,
            reference: referenceParams,
            tx: tx
        )
        return tx.db.lastInsertedRowID
    }
}
