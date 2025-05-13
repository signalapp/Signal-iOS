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
        let db = tx.database

        guard let sourceType = referencedAttachment.reference.owner.asUploadSourceType() else {
            throw OWSAssertionError("Enqueuing attachment that shouldn't be uploaded")
        }

        var newRecord = QueuedBackupAttachmentUpload(
            attachmentRowId: referencedAttachment.attachment.id,
            sourceType: sourceType
        )

        let existingRecord = try QueuedBackupAttachmentUpload
            .filter(Column(QueuedBackupAttachmentUpload.CodingKeys.attachmentRowId) == referencedAttachment.attachment.id)
            .fetchOne(db)

        guard var existingRecord else {
            // If there's no existing record, insert and we're done.
            try newRecord.insert(db)
            return
        }

        let needsUpdate = newRecord.sourceType.isHigherPriority(than: existingRecord.sourceType)

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
        let db = tx.database
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
        let db = tx.database
        try QueuedBackupAttachmentUpload
            .filter(Column(QueuedBackupAttachmentUpload.CodingKeys.attachmentRowId) == attachmentId)
            .deleteAll(db)
    }

    public func removeAll(tx: DBWriteTransaction) throws {
        try QueuedBackupAttachmentUpload.deleteAll(tx.database)
    }
}

extension AttachmentReference.Owner {

    public func asUploadSourceType() -> QueuedBackupAttachmentUpload.SourceType? {
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
            return nil
        }
    }
}

extension QueuedBackupAttachmentUpload.SourceType {

    public func isHigherPriority(than other: QueuedBackupAttachmentUpload.SourceType) -> Bool {
        switch (self, other) {

        // Thread wallpapers are higher priority, they always win.
        case (.threadWallpaper, _):
            return true
        case (.message(_), .threadWallpaper):
            return false

        case (.message(let selfTimestamp), .message(let otherTimestamp)):
            // Higher priority if more recent.
            return selfTimestamp > otherTimestamp
        }
    }
}
