//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public protocol BackupAttachmentUploadStore {

    /// "Enqueue" an attachment from a backup for upload.
    ///
    /// If the same attachment is already enqueued, updates it to the greater of the old and new timestamp.
    ///
    /// Doesn't actually trigger an upload; callers must later call `fetchNextUpload`, complete the upload of
    /// both the fullsize and thumbnail as needed, and then call `removeQueuedUpload` once finished.
    /// Note that the upload operation can (and will) be separately durably enqueued in AttachmentUploadQueue,
    /// that's fine and doesn't change how this queue works.
    func enqueue(
        _ referencedAttachment: ReferencedAttachmentStream,
        tx: DBWriteTransaction
    ) throws

    /// Read the next highest priority uploads off the queue, up to count.
    /// Returns an empty array if nothing is left to upload.
    func fetchNextUploads(
        count: UInt,
        tx: DBReadTransaction
    ) throws -> [QueuedBackupAttachmentUpload]

    /// Remove the upload from the queue. Should be called once uploaded (or permanently failed).
    func removeQueuedUpload(
        for attachmentId: Attachment.IDType,
        tx: DBWriteTransaction
    ) throws

    /// Remove all enqueued uploads from the able.
    func removeAll(tx: DBWriteTransaction) throws
}

public class BackupAttachmentUploadStoreImpl: BackupAttachmentUploadStore {

    public init() {}

    public func enqueue(
        _ referencedAttachment: ReferencedAttachmentStream,
        tx: DBWriteTransaction
    ) throws {
        let db = databaseConnection(tx)
        var newRecord = QueuedBackupAttachmentUpload(
            attachmentRowId: referencedAttachment.attachment.id,
            sourceType: try referencedAttachment.reference.owner.asUploadSourceType()
        )

        let existingRecord = try QueuedBackupAttachmentUpload
            .filter(Column(QueuedBackupAttachmentUpload.CodingKeys.attachmentRowId) == referencedAttachment.attachment.id)
            .fetchOne(db)

        guard var existingRecord else {
            // If there's no existing record, insert and we're done.
            try newRecord.insert(db)
            return
        }

        let needsUpdate: Bool = {
            switch (existingRecord.sourceType, newRecord.sourceType) {

            // Thread wallpapers are higher priority, they always win.
            case (.threadWallpaper, _):
                return false
            case (.message(_), .threadWallpaper):
                return true

            case (.message(let oldTimestamp), .message(let newTimestamp)):
                // Replace if more recent.
                return newTimestamp > oldTimestamp
            }
        }()

        guard needsUpdate else {
            return
        }

        existingRecord.sourceType = newRecord.sourceType
        try existingRecord.update(db)
    }

    public func fetchNextUploads(
        count: UInt,
        tx: DBReadTransaction
    ) throws -> [QueuedBackupAttachmentUpload] {
        let db = databaseConnection(tx)
        return try QueuedBackupAttachmentUpload
            .order([
                Column(QueuedBackupAttachmentUpload.CodingKeys.sourceType).asc,
                Column(QueuedBackupAttachmentUpload.CodingKeys.timestamp).desc
            ])
            .limit(Int(count))
            .fetchAll(db)
    }

    public func removeQueuedUpload(
        for attachmentId: Attachment.IDType,
        tx: DBWriteTransaction
    ) throws {
        let db = databaseConnection(tx)
        try QueuedBackupAttachmentUpload
            .filter(Column(QueuedBackupAttachmentUpload.CodingKeys.attachmentRowId) == attachmentId)
            .deleteAll(db)
    }

    public func removeAll(tx: DBWriteTransaction) throws {
        try QueuedBackupAttachmentUpload.deleteAll(databaseConnection(tx))
    }
}

extension AttachmentReference.Owner {

    fileprivate func asUploadSourceType() throws -> QueuedBackupAttachmentUpload.SourceType {
        switch self {
        case .message(let messageSource):
            return .message(timestamp: {
                switch messageSource {
                case .bodyAttachment(let metadata):
                    return metadata.receivedAtTimestamp
                case .oversizeText(let metadata):
                    return metadata.receivedAtTimestamp
                case .linkPreview(let metadata):
                    return metadata.receivedAtTimestamp
                case .quotedReply(let metadata):
                    return metadata.receivedAtTimestamp
                case .sticker(let metadata):
                    return metadata.receivedAtTimestamp
                case .contactAvatar(let metadata):
                    return metadata.receivedAtTimestamp
                }
            }())
        case .thread(let threadSource):
            switch threadSource {
            case .threadWallpaperImage, .globalThreadWallpaperImage:
                return .threadWallpaper
            }
        case .storyMessage:
            throw OWSAssertionError("Story message attachments shouldn't be uploaded")
        }
    }
}

#if TESTABLE_BUILD

open class BackupAttachmentUploadStoreMock: BackupAttachmentUploadStore {

    public init() {}

    var nextId: Int64 = 1
    open var queue = [QueuedBackupAttachmentUpload]()

    public func enqueue(
        _ referencedAttachment: ReferencedAttachmentStream,
        tx: DBWriteTransaction
    ) throws {
        queue.append(.init(
            id: nextId,
            attachmentRowId: referencedAttachment.attachment.id,
            sourceType: try referencedAttachment.reference.owner.asUploadSourceType())
        )
    }

    public func fetchNextUploads(
        count: UInt,
        tx: DBReadTransaction
    ) throws -> [QueuedBackupAttachmentUpload] {
        return Array(queue.prefix(Int(count)))
    }

    public func removeQueuedUpload(
        for attachmentId: Attachment.IDType,
        tx: DBWriteTransaction
    ) throws {
        queue.removeAll(where: { $0.attachmentRowId == attachmentId })
    }

    public func removeAll(tx: DBWriteTransaction) throws {
        queue.removeAll()
    }
}

#endif
