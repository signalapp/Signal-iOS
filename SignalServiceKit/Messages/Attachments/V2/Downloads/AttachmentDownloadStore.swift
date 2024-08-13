//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol AttachmentDownloadStore {

    func fetchRecord(
        id: QueuedAttachmentDownloadRecord.IDType,
        tx: DBReadTransaction
    ) throws -> QueuedAttachmentDownloadRecord?

    func enqueuedDownload(
        for id: Attachment.IDType,
        tx: DBReadTransaction
    ) throws -> QueuedAttachmentDownloadRecord?

    /// Fetch the next N highest priority downloads off the queue in FIFO order.
    func peek(
        count: UInt,
        tx: DBReadTransaction
    ) throws -> [QueuedAttachmentDownloadRecord]

    /// Return the lowest non-nil `minRetryTimestamp`.
    func nextRetryTimestamp(tx: DBReadTransaction) throws -> UInt64?

    /// Enqueues a target attachment (with a given source) for download at a given priority.
    ///
    /// If the attachment+source pair is already enqueued:
    /// * Does nothing if the existing one is at the same or higher priority
    /// * Replaces the existing one if the new one is at higher priority.
    ///
    /// Only allows 50 `default` priority attachments at a time; any more
    /// and it will remove existing ones from the queue (in FIFO order).
    ///
    /// Simply enqueues; wake up AttachmentDownloadManager to actually download off the queue.
    func enqueueDownloadOfAttachment(
        withId attachmentId: Attachment.IDType,
        source: QueuedAttachmentDownloadRecord.SourceType,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    ) throws

    func removeAttachmentFromQueue(
        withId attachmentId: Attachment.IDType,
        source: QueuedAttachmentDownloadRecord.SourceType,
        tx: DBWriteTransaction
    ) throws

    /// If the failure is permanent (no retry), use `removeAttachmentFromQueue` instead.
    func markQueuedDownloadFailed(
        withId id: QueuedAttachmentDownloadRecord.IDType,
        minRetryTimestamp: UInt64,
        tx: DBWriteTransaction
    ) throws

    /// Update all downloads with`minRetryTimestamp` past the current timestamp,
    /// marking them retryable.
    func updateRetryableDownloads(tx: DBWriteTransaction) throws
}
