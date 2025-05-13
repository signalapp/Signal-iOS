//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

/// Record type for BackupAttachmentUploadQueue rows.
///
/// The table is used only as an intermediary to ensure proper ordering. As we create (archive) a backup,
/// we insert attachments that need uploading into this table first. Once we are done archiving,
/// we walk over this table in reverse order and insert rows into the AttachmentUploadQueue table
/// for _actual_ uploading.
/// In this way we ensure proper upload ordering; AttachmentUploadQueue uploads FIFO,
/// but we want to upload things we archive in the backup in LIFO order (newest first). This table
/// allows us to do that reordering after we are done processing the backup in its normal order.
public struct QueuedBackupAttachmentUpload: Codable, FetchableRecord, MutablePersistableRecord, UInt64SafeRecord {

    public typealias IDType = Int64

    /// Sqlite row id
    public private(set) var id: IDType?

    /// Row id of the associated attachment (the one we want to upload) in the Attachments table.
    public let attachmentRowId: Attachment.IDType

    /// What type of owner owns this attachment (the "source" of the upload).
    /// Some sources are prioritized and uploaded first; thus used for sorting.
    public var sourceType: SourceType

    public enum SourceType {
        case threadWallpaper
        /// Timestamp of the newest message that owns this attachment.
        /// Used to determine priority of upload (ordering of the pop-off-queue query).
        case message(timestamp: UInt64)

        fileprivate var timestamp: UInt64? {
            switch self {
            case .threadWallpaper:
                return nil
            case .message(let timestamp):
                return timestamp
            }
        }
    }

    public init(
        id: Int64? = nil,
        attachmentRowId: Attachment.IDType,
        sourceType: SourceType
    ) {
        self.id = id
        self.attachmentRowId = attachmentRowId
        self.sourceType = sourceType
    }

    // MARK: FetchableRecord

    public static var databaseTableName: String { "BackupAttachmentUploadQueue" }

    // MARK: MutablePersistableRecord

    public mutating func didInsert(with rowID: Int64, for column: String?) {
        self.id = rowID
    }

    // MARK: - UInt64SafeRecord

    static var uint64Fields: [KeyPath<QueuedBackupAttachmentUpload, UInt64>] = []

    static var uint64OptionalFields: [KeyPath<QueuedBackupAttachmentUpload, UInt64?>] = [\.sourceType.timestamp]

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case attachmentRowId
        case sourceType
        case timestamp
    }

    /// Note the raw values. Leaving gaps as raw value influences sort order, and we may add a new
    /// type of attachment that should go before after or in between.
    private enum SourceTypeRaw: Int, Codable {
        case threadWallpaper = 100
        case message = 200
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int64.self, forKey: .id)
        self.attachmentRowId = try container.decode(Attachment.IDType.self, forKey: .attachmentRowId)
        let sourceTypeRaw = try container.decode(SourceTypeRaw.self, forKey: .sourceType)
        let timestamp = try container.decodeIfPresent(UInt64.self, forKey: .timestamp)
        switch sourceTypeRaw {
        case .threadWallpaper:
            self.sourceType = .threadWallpaper
        case .message:
            guard let timestamp else {
                throw OWSAssertionError("Message attachment upload without a timestamp!")
            }
            self.sourceType = .message(timestamp: timestamp)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(attachmentRowId, forKey: .attachmentRowId)
        switch sourceType {
        case .threadWallpaper:
            try container.encode(SourceTypeRaw.threadWallpaper, forKey: .sourceType)
        case .message(let timestamp):
            try container.encode(SourceTypeRaw.message, forKey: .sourceType)
            try container.encode(timestamp, forKey: .timestamp)
        }
    }
}
