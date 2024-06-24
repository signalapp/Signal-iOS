//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

open class AttachmentDownloadStoreMock: AttachmentDownloadStore {

    private let dateProvider: DateProvider

    public init(dateProvider: @escaping DateProvider) {
        self.dateProvider = dateProvider
    }

    public var nextId: QueuedAttachmentDownloadRecord.IDType = 1
    public var queue = [QueuedAttachmentDownloadRecord]()

    open func fetchRecord(
        id: QueuedAttachmentDownloadRecord.IDType,
        tx: DBReadTransaction
    ) throws -> QueuedAttachmentDownloadRecord? {
        return queue.first(where: { $0.id == id })
    }

    open func isAttachmentEnqueuedForDownload(
        id: Attachment.IDType,
        tx: DBReadTransaction
    ) throws -> Bool {
        return queue.contains(where: { $0.attachmentId == id })
    }

    open func peek(
        count: UInt,
        tx: DBReadTransaction
    ) throws -> [QueuedAttachmentDownloadRecord] {
        return Array(queue.lazy
            .sorted(by: { $0.priority.rawValue > $1.priority.rawValue })
            .prefix(Int(count)))
    }

    open func nextRetryTimestamp(tx: DBReadTransaction) throws -> UInt64? {
        return queue.lazy.compactMap(\.minRetryTimestamp).min()
    }

    open func enqueueDownloadOfAttachment(
        withId attachmentId: Attachment.IDType,
        source: QueuedAttachmentDownloadRecord.SourceType,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    ) throws {
        var newRecord = QueuedAttachmentDownloadRecord.forNewDownload(
            ofAttachmentWithId: attachmentId,
            priority: priority,
            sourceType: source
        )
        newRecord.id = nextId
        nextId += 1
        queue.append(newRecord)
    }

    open func removeAttachmentFromQueue(
        withId attachmentId: Attachment.IDType,
        source: QueuedAttachmentDownloadRecord.SourceType,
        tx: DBWriteTransaction
    ) throws {
        queue.removeAll(where: {
            $0.attachmentId == attachmentId && $0.sourceType == source
        })
    }

    open func markQueuedDownloadFailed(
        withId id: QueuedAttachmentDownloadRecord.IDType,
        minRetryTimestamp: UInt64,
        tx: DBWriteTransaction
    ) throws {
        guard let index = queue.firstIndex(where: { $0.id == id }) else {
            return
        }
        var record = queue[index]
        record.minRetryTimestamp = minRetryTimestamp
        record.retryAttempts += 1
        queue[index] = record
    }

    open func updateRetryableDownloads(tx: DBWriteTransaction) throws {
        for i in 0..<queue.count {
            var record = queue[i]
            guard
                let minRetryTimestamp = record.minRetryTimestamp,
                minRetryTimestamp <= dateProvider().ows_millisecondsSince1970
            else {
                continue
            }
            record.minRetryTimestamp = nil
            queue[i] = record
        }
    }
}

#endif
