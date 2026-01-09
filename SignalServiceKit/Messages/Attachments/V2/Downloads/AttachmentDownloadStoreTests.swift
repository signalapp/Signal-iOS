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

    private var attachmentStore: AttachmentStore!
    private var downloadStore: AttachmentDownloadStore!

    private var now = Date()

    override func setUp() async throws {
        db = InMemoryDB()
        attachmentStore = AttachmentStore()
        downloadStore = AttachmentDownloadStore(
            dateProvider: { [weak self] in
                return self!.now
            },
        )
    }

    func testEnqueue() {
        let attachmentId = insertAttachment()

        db.write { tx in
            downloadStore.enqueueDownloadOfAttachment(
                withId: attachmentId,
                source: .transitTier,
                priority: .default,
                tx: tx,
            )
            let downloadId = tx.database.lastInsertedRowID
            var download = downloadStore.fetchRecord(id: downloadId, tx: tx)
            XCTAssertNotNil(download)
            XCTAssertEqual(download?.attachmentId, attachmentId)

            // Re-enqueue at the same priority.
            downloadStore.enqueueDownloadOfAttachment(
                withId: attachmentId,
                source: .transitTier,
                priority: .default,
                tx: tx,
            )
            // It should've done nothing.
            XCTAssertEqual(tx.database.lastInsertedRowID, downloadId)
            download = downloadStore.fetchRecord(id: downloadId, tx: tx)
            XCTAssertEqual(download?.priority, .default)

            // Re-enqueue at higher priority.
            downloadStore.enqueueDownloadOfAttachment(
                withId: attachmentId,
                source: .transitTier,
                priority: .userInitiated,
                tx: tx,
            )
            // It should've updated (no new row id) but at higher priority.
            XCTAssertEqual(tx.database.lastInsertedRowID, downloadId)
            download = downloadStore.fetchRecord(id: downloadId, tx: tx)
            XCTAssertEqual(download?.priority, .userInitiated)
        }
    }

    func testEnqueue_defaultCountLimit() {
        db.write { tx in
            let attachmentIds = (0..<50).map { _ in
                insertAttachment(tx: tx)
            }
            let extraAttachmentId = insertAttachment(tx: tx)

            attachmentIds.forEach { attachmentId in
                downloadStore.enqueueDownloadOfAttachment(
                    withId: attachmentId,
                    source: .transitTier,
                    priority: .default,
                    tx: tx,
                )
            }
            let downloadCount = try! QueuedAttachmentDownloadRecord.fetchCount(tx.database)
            XCTAssertEqual(downloadCount, 50)

            // Enqueue one more, it should kick out the first.
            downloadStore.enqueueDownloadOfAttachment(
                withId: extraAttachmentId,
                source: .transitTier,
                priority: .default,
                tx: tx,
            )
            // It should've done nothing.
            let downloads = try! QueuedAttachmentDownloadRecord.fetchAll(tx.database)
            XCTAssertEqual(downloads.count, 50)
            var expectedAttachmentIds = attachmentIds
            _ = expectedAttachmentIds.popFirst()
            expectedAttachmentIds.append(extraAttachmentId)
            XCTAssertEqual(expectedAttachmentIds, downloads.map(\.attachmentId))
        }
    }

    func testReEnqueue_userInitiatedIgnoresRetry() {
        let attachmentId = insertAttachment()

        db.write { tx in
            downloadStore.enqueueDownloadOfAttachment(
                withId: attachmentId,
                source: .transitTier,
                priority: .default,
                tx: tx,
            )
            let downloadId = tx.database.lastInsertedRowID
            var download = downloadStore.fetchRecord(id: downloadId, tx: tx)
            XCTAssertNotNil(download)
            XCTAssertEqual(download?.attachmentId, attachmentId)

            // Mark it as failed.
            let retryTimestamp = self.now.addingTimeInterval(100).ows_millisecondsSince1970
            downloadStore.markQueuedDownloadFailed(
                withId: downloadId,
                minRetryTimestamp: retryTimestamp,
                tx: tx,
            )
            // Retry state updated
            download = downloadStore.fetchRecord(id: downloadId, tx: tx)
            XCTAssertEqual(download?.minRetryTimestamp, retryTimestamp)
            XCTAssertEqual(download?.retryAttempts, 1)

            // Re-enqueue at user initiated priority.
            downloadStore.enqueueDownloadOfAttachment(
                withId: attachmentId,
                source: .transitTier,
                priority: .userInitiated,
                tx: tx,
            )
            // It should've updated (no new row id) but at higher priority
            // and ready to retry.
            XCTAssertEqual(tx.database.lastInsertedRowID, downloadId)
            download = downloadStore.fetchRecord(id: downloadId, tx: tx)
            XCTAssertEqual(download?.priority, .userInitiated)
            XCTAssertNil(download!.minRetryTimestamp)
            XCTAssertEqual(download?.retryAttempts, 1)
        }
    }

    func testPeek() {
        db.write { tx in
            let attachmentIds = (0..<15).map { _ in
                insertAttachment(tx: tx)
            }

            let downloadIds = (0..<attachmentIds.count).map { i in
                let priority: AttachmentDownloadPriority
                if i < 5 {
                    priority = .default
                } else {
                    priority = .userInitiated
                }
                downloadStore.enqueueDownloadOfAttachment(
                    withId: attachmentIds[i],
                    source: .transitTier,
                    priority: priority,
                    tx: tx,
                )
                return tx.database.lastInsertedRowID
            }
            var peekResult = downloadStore.peek(count: 5, tx: tx)
            // Should get the first five high priority items.
            XCTAssertEqual(peekResult.map(\.id), Array(downloadIds[5..<10]))

            // Mark those as failed.
            for i in 5..<10 {
                downloadStore.markQueuedDownloadFailed(
                    withId: downloadIds[i],
                    minRetryTimestamp: now.ows_millisecondsSince1970 + 100,
                    tx: tx,
                )
            }

            peekResult = downloadStore.peek(count: 5, tx: tx)
            // Should get the next five high priority items.
            XCTAssertEqual(peekResult.map(\.id), Array(downloadIds[10..<15]))

            // Remove the next batch
            for i in 10..<15 {
                downloadStore.removeAttachmentFromQueue(
                    withId: attachmentIds[i],
                    source: .transitTier,
                    tx: tx,
                )
            }

            peekResult = downloadStore.peek(count: 5, tx: tx)
            // Should get the five lower priority items.
            XCTAssertEqual(peekResult.map(\.id), Array(downloadIds[0..<5]))
        }
    }

    func testNextRetryTimestamp() {
        db.write { tx in
            (0..<10).forEach { index in
                downloadStore.enqueueDownloadOfAttachment(
                    withId: insertAttachment(tx: tx),
                    source: .transitTier,
                    priority: .default,
                    tx: tx,
                )
                let downloadId = tx.database.lastInsertedRowID
                downloadStore.markQueuedDownloadFailed(
                    withId: downloadId,
                    minRetryTimestamp: now.ows_millisecondsSince1970 + 100 - UInt64(index),
                    tx: tx,
                )
            }
            let timestampResult = downloadStore.nextRetryTimestamp(tx: tx)
            // Should get the first five high priority items.
            XCTAssertEqual(timestampResult, now.ows_millisecondsSince1970 + 100 - 9)
        }
    }

    func testUpdateRetryableDownloads() {
        self.now = Date(millisecondsSince1970: 0)
        db.write { tx in
            (0..<15).forEach { i in
                downloadStore.enqueueDownloadOfAttachment(
                    withId: insertAttachment(tx: tx),
                    source: .transitTier,
                    priority: .default,
                    tx: tx,
                )
                downloadStore.markQueuedDownloadFailed(
                    withId: tx.database.lastInsertedRowID,
                    minRetryTimestamp: UInt64(i + 1) * 100,
                    tx: tx,
                )
            }

            func peekCount() -> Int {
                return downloadStore.peek(count: 15, tx: tx).count
            }
            // Everything retrying
            XCTAssertEqual(peekCount(), 0)

            // Update without moving time, nothing updates.
            downloadStore.updateRetryableDownloads(tx: tx)
            XCTAssertEqual(peekCount(), 0)

            // Move time forward so one instance is ready.
            self.now = Date(millisecondsSince1970: 100)
            downloadStore.updateRetryableDownloads(tx: tx)
            XCTAssertEqual(peekCount(), 1)

            // Move time forward again so more are ready.
            self.now = Date(millisecondsSince1970: 450)
            downloadStore.updateRetryableDownloads(tx: tx)
            XCTAssertEqual(peekCount(), 4)
        }
    }

    // MARK: - Helpers

    private func insertAttachment() -> Attachment.IDType {
        return db.write(block: insertAttachment(tx:))
    }

    private func insertAttachment(tx: DBWriteTransaction) -> Attachment.IDType {
        let thread = TSThread(uniqueId: UUID().uuidString)
        try! thread.asRecord().insert(tx.database)
        let interaction = TSInteraction(timestamp: 0, receivedAtTimestamp: 0, thread: thread)
        try! interaction.asRecord().insert(tx.database)

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
                orderInMessage: 0,
                idInOwner: nil,
                isViewOnce: false,
            ))),
        )
        try! attachmentStore.insert(
            attachmentParams,
            reference: referenceParams,
            tx: tx,
        )
        return tx.database.lastInsertedRowID
    }
}
