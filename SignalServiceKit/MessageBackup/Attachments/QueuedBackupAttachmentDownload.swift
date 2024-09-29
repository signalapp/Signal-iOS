//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

/// Record type for BackupAttachmentDownloadQueue rows.
///
/// The table is used only as an intermediary to ensure proper ordering. As we restore a backup,
/// we insert attachments that need downloading into this table first. Once we are done restoring,
/// we walk over this table in reverse order and insert rows into the AttachmentDownloadQueue table
/// for _actual_ downloading.
/// In this way we ensure proper download ordering; AttachmentDownloadQueue downloads FIFO,
/// but we want to download things we see in the backup in LIFO order. This table allows us to
/// do that reordering after we are done processing the backup in its normal order.
public struct QueuedBackupAttachmentDownload: Codable, FetchableRecord, MutablePersistableRecord, UInt64SafeRecord {

    public typealias IDType = Int64

    /// Sqlite row id
    public private(set) var id: IDType?

    /// Row id of the associated attachment (the one we want to download) in the Attachments table.
    public let attachmentRowId: Int64

    /// Timestamp of the newest message that owns this attachment (or nil if non-message attachment).
    /// Used to determine priority and whether to download fullsize or thumbnail. NOT used for sorting.
    public private(set) var timestamp: UInt64?

    // MARK: - API

    public init(
        id: Int64? = nil,
        attachmentRowId: Int64,
        timestamp: UInt64?
    ) {
        self.id = id
        self.attachmentRowId = attachmentRowId
        self.timestamp = timestamp
    }

    public mutating func updateWithTimestamp(_ timestamp: UInt64) {
        self.timestamp = timestamp
    }

    // MARK: FetchableRecord

    public static var databaseTableName: String { "BackupAttachmentDownloadQueue" }

    // MARK: MutablePersistableRecord

    public mutating func didInsert(with rowID: Int64, for column: String?) {
        self.id = rowID
    }

    // MARK: - UInt64SafeRecord

    static var uint64Fields: [KeyPath<QueuedBackupAttachmentDownload, UInt64>] = []

    static var uint64OptionalFields: [KeyPath<QueuedBackupAttachmentDownload, UInt64?>] = [\.timestamp]

    // MARK: Codable

    public enum CodingKeys: String, CodingKey {
        case id
        case attachmentRowId
        case timestamp
    }
}
